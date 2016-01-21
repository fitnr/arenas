CENSUS = ftp://ftp2.census.gov/geo/tiger
STATCAN = http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/files-fichiers
OPENCAN = http://ftp2.cits.rncan.gc.ca/pub/geobase/official/muni/shp_eng
KMLEXPORT = https://tools.wmflabs.org/kmlexport/

STATES_WITH_ARENA = 04 06 06 08 11 12 \
	13 17 18 20 22 \
	24 25 26 27 29 34 \
	36 37 39 40 41 \
	42 47 48 49 53 55

TSRS = -t_srs EPSG:4326

CITIES = $(shell cut -d, -f2 citycenters.txt | sed 's/ /_/g')

COMPLEX_CITIES = Dallas \
	Fort_Worth \
	Minneapolis \
	Saint_Paul \
	Oakland \
	San_Jose \
	San_Francisco \
	Saint_Petersburg \
	Tampa

JOINED_CITIES = Dallas_Ft_Worth \
	Minneapolis_St_Paul \
	Bay_Area \
	Tampa_Bay

SIMPLE_CITIES = $(filter-out $(COMPLEX_CITIES),$(CITIES))

all: $(addsuffix .svg,$(addprefix svg/,$(SIMPLE_CITIES) $(JOINED_CITIES)))

# Maps

GEO = GENZ2014/shp/cb_2014_us_state_5m.shp \
	can/provinces.shp \
	TIGER2015/UAC/tl_2015_us_uac10.shp \
	TIGER2015/places.shp \
	can/places.shp \
	TIGER2014/prisecroads.shp \
	wiki/National_Hockey_League.shp \
	wiki/National_Football_League.shp \
	wiki/Major_League_Baseball.shp \
	wiki/National_Basketball_Association.shp

svg/%.svg: styles.css bounds/% $(GEO) buffer/%.shp | svg
	xargs -J % svgis draw -j local -x -f 100 -c $< -p 100 --bounds % < bounds/$* \
	$(filter %.shp,$^) -o $@

# bounds
bounds/%: buffer/%.shp | bounds
	@rm -f $@
	ogr2ogr -f CSV /dev/stdout $< -dialect sqlite \
	-sql "SELECT MbrMinX(Geometry) || ' ' || MbrMinY(Geometry) || ' ' || \
	MbrMaxX(Geometry) || ' ' || MbrMaxY(Geometry) bounds FROM $* WHERE mi=25" | \
	grep -v bounds > $@

# Buffers

buffer/Bay_Area.shp: buffer/Oakland.shp buffer/San_Jose.shp buffer/San_Francisco.shp | buffer
	ogr2ogr $@ $< -overwrite -dialect sqlite -sql "SELECT \
	ST_union(c.Geometry, ST_union(a.Geometry, b.Geometry)) Geometry, mi \
	FROM 'buffer/San_Jose.shp'.San_Jose a \
	LEFT JOIN 'buffer/San_Francisco.shp'.San_Francisco b USING (mi) \
	LEFT JOIN Oakland c USING (mi)"

buffer/Dallas_Ft_Worth.shp: buffer/Dallas.shp buffer/Fort_Worth.shp | buffer
	ogr2ogr $@ $< -overwrite -dialect sqlite -sql "SELECT \
	ST_union(a.Geometry, b.Geometry) Geometry, mi \
	FROM 'buffer/Fort_Worth.shp'.Fort_Worth a \
	LEFT JOIN Dallas b USING (mi)"

buffer/Minneapolis_St_Paul.shp: buffer/Minneapolis.shp buffer/Saint_Paul.shp | buffer
	ogr2ogr $@ $< -overwrite -dialect sqlite -sql "SELECT \
	ST_union(a.Geometry, b.Geometry) Geometry, mi \
	FROM 'buffer/Saint_Paul.shp'.Saint_Paul a \
	LEFT JOIN Minneapolis b USING (mi)"

buffer/Tampa_Bay.shp: buffer/Tampa.shp buffer/Saint_Petersburg.shp | buffer
	ogr2ogr $@ $< -overwrite -dialect sqlite -sql "SELECT \
	ST_union(a.Geometry, b.Geometry) Geometry, mi \
	FROM 'buffer/Saint_Petersburg.shp'.Saint_Petersburg a \
	LEFT JOIN Tampa b USING (mi)"

buffer/%.shp: buffer/%_utm.shp
	ogr2ogr $@ $< $(TSRS) -overwrite -dialect sqlite -sql 'SELECT Buffer(Geometry, 48280.2) Geometry, 30 mi FROM "$(basename $(<F))"'
	ogr2ogr $@ $< $(TSRS) -update -append -dialect sqlite -sql 'SELECT Buffer(Geometry, 40233.6) Geometry, 25 mi FROM "$(basename $(<F))"'
	ogr2ogr $@ $< $(TSRS) -update -append -dialect sqlite -sql 'SELECT Buffer(Geometry, 32186.9) Geometry, 20 mi FROM "$(basename $(<F))"'
	ogr2ogr $@ $< $(TSRS) -update -append -dialect sqlite -sql 'SELECT Buffer(Geometry, 24140.2) Geometry, 15 mi FROM "$(basename $(<F))"'
	ogr2ogr $@ $< $(TSRS) -update -append -dialect sqlite -sql 'SELECT Buffer(Geometry, 16093.4) Geometry, 10 mi FROM "$(basename $(<F))"'

# Can't fucking quote in xargs properly WTF
# Point of this file is that it's in UTM so we can make proper circles
buffer/%_utm.shp: buffer/%.utm city/centers.shp
	ogr2ogr -overwrite $@ $(filter %.shp,$^) -where "name='$*'" -t_srs "$$(cat $<)"

# Small file containing the UTM Proj.4 string.
# Can't get xargs to work properly with ogr2ogr.
$(addsuffix .utm,$(addprefix buffer/,$(CITIES))): buffer/%.utm: city/centers.csv | buffer
	grep "$(subst _, ,$*)" $< | \
	cut -d, -f1-2 | \
	sed -E 's/,/ /g;s/(-?[0-9.]+) (-?[0-9.]+)/\1 \2 \1 \2/' | \
	xargs svgis project -j utm > $@

# Geocoding

# set google key in vars
GOOGLEKEY ?=
GOOGLEAPI = https://maps.googleapis.com/maps/api/geocode/json -d key=$(GOOGLEKEY)

city/centers.shp: city/centers.csv
	ogr2ogr -overwrite -f 'ESRI Shapefile' $@ $< -s_srs EPSG:4326 $(TSRS) \
	-dialect sqlite -sql "SELECT MakePoint(CAST(x as REAL), CAST(y as REAL)) Geometry, \
	CAST(x as REAL) x, CAST(y as REAL) y, \
	REPLACE(name, ' ', '_') name FROM centers"

.SECONDARY: city/centers.csv
city/centers.csv: citycenters.txt | city
	echo x,y,name > $@
	sed 's/ /%20/g;s/,/%2C/g' $< | \
	xargs -I% curl -Gs $(GOOGLEAPI) -d address=% | \
	jq -r '.results[0] | \
		[(.geometry.location.lng), (.geometry.location.lat), \
			 [(.address_components[] | select( .types | contains(["locality", "political"])) | .long_name )][0] \
		] | @csv' | \
	sed 's/Old Toronto/Toronto/g' >> $@

# Census
.INTERMEDIATE:

TIGER2014/prisecroads.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2014/PRISECROADS/tl_2014_$x_prisecroads.shp)
	for f in $^; do \
		ogr2ogr -update -append -nlt LINESTRING $@ $$f; \
	done;

TIGER2014/PRISECROADS/tl_2014_%_prisecroads.shp: TIGER2014/PRISECROADS/tl_2014_%_prisecroads.zip | TIGER2014/PRISECROADS
	ogr2ogr -overwrite $@ /vsizip/$</$(@F) $(TSRS) -where "MTFCC='S1100'"

TIGER2015/places.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2015/PLACE/tl_2015_$x_place.shp)
	for f in $^; do \
		ogr2ogr -update -append -nlt POLYGON $@ $$f; \
	done;

TIGER2015/PLACE/tl_2015_%_place.shp: TIGER2015/PLACE/tl_2015_%_place.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(@F) $(TSRS) -select GEOID,NAME -where "PCICBSA='Y'"

TIGER2015/UAC/tl_2015_us_uac10.shp: TIGER2015/UAC/tl_2015_us_uac10.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(@F) $(TSRS) -select GEOID10,NAME10

GENZ2014/shp/%.shp: GENZ2014/shp/%.zip
	ogr2ogr $@ /vsizip/$</$(@F) $(TSRS)

can/provinces.shp: can/gpr_000b11a_e.zip
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp $(TSRS)

# Montreal, Ottawa, Toronto, Edmonton, Calgary, vancouver
can/places.shp: can/lcsd000a15a_e.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(basename $(<F)).shp $(TSRS) \
	-where "CSDUID IN ('2466023', '3506008', '3520005', '4811061', '4806016', '5915022')"

can/gpr_000b11a_e.zip can/lcsd000a15a_e.zip: | can
	curl -so $@ $(STATCAN)/$(@F)

.SECONDEXPANSION:
TIGER2014/%.zip TIGER2015/%.zip GENZ2014/shp/%.zip: | $$(@D)
	curl -so $@ $(CENSUS)/$@

TIGER2014/PRISECROADS TIGER2015/PLACE TIGER2015/UAC GENZ2014/shp city can bounds buffer svg:; mkdir -p $@

# Stadia

National_Hockey_League_section = List_of_teams
National_Football_League_section = Clubs
Major_League_Baseball_section = Current_teams
National_Basketball_Association_section = Teams

.PHONY: arenas
arenas: wiki/National_Hockey_League.geojson \
	wiki/National_Football_League.geojson \
	wiki/Major_League_Baseball.geojson \
	wiki/National_Basketball_Association.geojson

wiki/%.shp: wiki/%.kml
	@rm -f $@
	ogr2ogr $@ $< -nln $*

wiki/%.kml: | wiki
	curl -Gso $@ $(KMLEXPORT) -d article=$* -d section=$($*_section)

wiki: ; mkdir -p $@
