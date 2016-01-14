CENSUS = ftp://ftp2.census.gov/geo/tiger
STATCAN = http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/files-fichiers
OPENCAN = http://ftp2.cits.rncan.gc.ca/pub/geobase/official/muni/shp_eng
KMLEXPORT = https://tools.wmflabs.org/kmlexport/

STATES_WITH_ARENA = 04 06 06 08 11 12 \
	13 17 18 20 22 \
	24 25 26 27 29 \
	36 37 39 40 41 \
	42 47 48 49 53 55

TSRS = -t_srs EPSG:4326

CITIES = $(shell cut -d, -f2 citycenters.txt | sed 's/ /_/g')

all: $(addsuffix .svg,$(addprefix svg/,$(CITIES)))

# Maps

GEO = GENZ2014/shp/cb_2014_us_state_5m.shp \
	can/provinces.shp \
	TIGER2015/UAC/tl_2015_us_uac10.shp \
	TIGER2015/places.shp \
	can/places.shp \
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

bounds buffer svg:; mkdir -p $@

# Geocoding

# set google key in vars
GOOGLEKEY ?=
GOOGLEAPI = https://maps.googleapis.com/maps/api/geocode/json -d key=$(GOOGLEKEY)

city/centers.shp: city/centers.csv
	ogr2ogr -overwrite -f 'ESRI Shapefile' $@ $< -s_srs EPSG:4326 $(TSRS) \
	-dialect sqlite -sql "SELECT MakePoint(CAST(x as REAL), CAST(y as REAL)) Geometry, \
	CAST(x as REAL) x, CAST(y as REAL) y, \
	REPLACE(REPLACE(name, 'Old Toronto', 'Toronto'), ' ', '_') name FROM centers"

.SECONDARY: city/centers.csv
city/centers.csv: citycenters.txt | city
	echo x,y,name > $@
	sed 's/ /%20/g;s/,/%2C/g' $< | \
	xargs -I% curl -Gs $(GOOGLEAPI) -d address=% | \
	jq -r '.results[0] | \
		[(.geometry.location.lng), (.geometry.location.lat), \
			 [(.address_components[] | select( .types | contains(["locality", "political"])) | .long_name )][0] \
			 +" "+ \
			 [(.address_components[] | select( .types | contains(["administrative_area_level_1"])) | .short_name )][0] \
		] | @csv' >> $@

# Census
.SECONDARY: GENZ2014/shp/cb_2014_us_state_5m.zip GENZ2014/shp/cb_2014_us_state_5m.shp

TIGER2015/places.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2015/PLACE/tl_2015_$x_place.shp)
	for f in $^; do \
		ogr2ogr -update -append $@ $$f; \
	done;

TIGER2015/PLACE/tl_2015_%_place.shp: TIGER2015/PLACE/tl_2015_%_place.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(@F) \
	$(TSRS) -select GEOID,NAME -where "PCICBSA='Y'"

TIGER2015/UAC/tl_2015_us_uac10.shp: TIGER2015/UAC/tl_2015_us_uac10.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(@F) \
	$(TSRS) -select GEOID10,NAME10

GENZ2014/shp/%.shp: GENZ2014/shp/%.zip
	ogr2ogr $@ /vsizip/$</$(@F) $(TSRS)

can/provinces.shp: can/gpr_000b11a_e.zip
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp $(TSRS)

# Montreal, Ottawa, Toronto, Edmonton, Calgary, vancouver
can/places.shp: can/lcsd000a15a_e.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(basename $(<F)).shp $(TSRS) \
	-where "CSDUID IN ('2466023', '3506008', '3520005', '4811061', '4806016', '5915022')"

can/local_area_boundary_shp.zip:
	curl -so $@ ftp://webftp.vancouver.ca/OpenData/shape/$(@F)

can/gpr_000b11a_e.zip can/lcsd000a15a_e.zip: | can
	curl -so $@ $(STATCAN)/$(@F)

TIGER2015/%.zip GENZ2014/shp/%.zip:
	@mkdir -p $(@D)
	curl -so $@ $(CENSUS)/$@

city can:; mkdir -p $@

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
