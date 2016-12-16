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

.SECONDARY:

all: $(addsuffix .svg,$(addprefix svg/,$(SIMPLE_CITIES) $(JOINED_CITIES)))

# Maps

ARENAS = wiki/List_of_National_Hockey_League_arenas.geojson \
	wiki/National_Football_League.geojson \
	wiki/Major_League_Baseball.geojson \
	wiki/National_Basketball_Association.geojson

GEO = states \
	urban \
	places \
	roads \
	arenas \
	buffer

svg/%.svg: styles.css $(foreach g,$(GEO),city/%/$(g).shp) | svg
	svgis draw -j local -xl -f 100 -c $< -p 100 -a mi,league -s 50 $(filter %.geojson %.shp,$^) -o $@

# clipped layers
CLIP = -clipsrc city/$* -clipsrclayer bufferwgs84 -skipfailures

# Local Arenas

city/%/arenas.shp: city/%/bufferwgs84.shp $(ARENAS)
	ogr2ogr -overwrite $@ wiki/List_of_National_Hockey_League_arenas.geojson $(CLIP) -nlt POINT \
		-sql "SELECT Name, 'nhl' league FROM OGRGeoJSON"
	ogr2ogr -update -append $@ wiki/National_Football_League.geojson $(CLIP) \
		-sql "SELECT Name, 'nfl' league FROM OGRGeoJSON"
	ogr2ogr -update -append $@ wiki/Major_League_Baseball.geojson $(CLIP) \
		-sql "SELECT Name, 'mlb' league FROM OGRGeoJSON"
	ogr2ogr -update -append $@ wiki/National_Basketball_Association.geojson $(CLIP) \
		-sql "SELECT Name, 'nba' league FROM OGRGeoJSON"

city/%/roads.shp: TIGER2016/prisecroads.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ $< -overwrite $(CLIP) -nlt LINESTRING -select FULLNAME

city/%/water.shp: TIGER2016/water.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ $< -overwrite $(CLIP) -nlt POLYGON

city/%/places.shp: GENZ2015/places.shp can/places.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ $< -overwrite $(CLIP) -nlt POLYGON
	ogr2ogr $@ can places -update -append $(CLIP)

city/%/urban.shp: GENZ2015/shp/cb_2015_us_ua10_500k.zip city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp -overwrite -nlt POLYGON $(TSRS) $(CLIP) -select GEOID10,NAME10

city/%/states.shp: GENZ2015/shp/cb_2015_us_state_500k.zip can/provinces.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp -overwrite -nlt POLYGON $(TSRS) $(CLIP) -select GEOID,NAME
	ogr2ogr $@ can provinces -update -append $(CLIP)

# Buffers

city/%/bufferwgs84.shp: city/%/buffer.shp
	ogr2ogr $@ $< $(TSRS) -where mi=30

city/Bay_Area/buffer.shp: $(foreach x,Oakland San_Jose San_Francisco,city/$x/buffer.shp) | city/Bay_Area
	ogr2ogr $@ $(<D) -overwrite -dialect sqlite -sql "SELECT \
	ST_union(c.Geometry, ST_union(a.Geometry, b.Geometry)) Geometry, mi \
	FROM 'city/San_Jose'.buffer a \
	LEFT JOIN 'city/San_Francisco'.buffer b USING (mi) \
	LEFT JOIN buffer c USING (mi)"

city/Dallas_Ft_Worth/buffer.shp: city/Dallas/buffer.shp city/Fort_Worth/buffer.shp | city/Dallas_Ft_Worth
	ogr2ogr $@ $< -overwrite -dialect sqlite -sql "SELECT \
	ST_union(a.Geometry, b.Geometry) Geometry, mi \
	FROM 'city/Fort_Worth'.buffer a \
	LEFT JOIN buffer b USING (mi)"

city/Minneapolis_St_Paul/buffer.shp: city/Minneapolis/buffer.shp city/Saint_Paul/buffer.shp | city/Minneapolis_St_Paul
	ogr2ogr $@ $< -overwrite -dialect sqlite -sql "SELECT \
	ST_union(a.Geometry, b.Geometry) Geometry, mi \
	FROM 'city/Saint_Paul'.buffer a \
	LEFT JOIN buffer b USING (mi)"

city/Tampa_Bay/buffer.shp: city/Tampa/buffer.shp city/Saint_Petersburg/buffer.shp | city/Tampa_Bay
	ogr2ogr $@ $< -overwrite -dialect sqlite -sql "SELECT \
	ST_union(a.Geometry, b.Geometry) Geometry, mi \
	FROM 'city/Saint_Petersburg'.buffer a \
	LEFT JOIN buffer b USING (mi)"

city/%/buffer.shp: city/%/center.shp
	ogr2ogr $@ $< -overwrite -dialect sqlite \
		-sql 'WITH RECURSIVE cnt(mi) AS (SELECT 10 UNION ALL SELECT mi+5 FROM cnt LIMIT 5) \
		SELECT Buffer(Geometry, mi * 1609.34) Geometry, mi, 'y' ring FROM $(basename $(<F)), cnt'

# Can't fucking quote in xargs properly WTF
# Point of this file is that it's in UTM so we can make proper circles
city/%/center.shp: city/%/utm.wkt city/centers.geojson | city/%
	ogr2ogr $@ $(filter %.geojson,$^) -where "name='$*'" -t_srs $< -overwrite

city/Bay_Area/utm.wkt: city/Oakland/utm.wkt; cp $< $@
city/Dallas_Ft_Worth/utm.wkt: city/Dallas/utm.wkt; cp $< $@
city/Minneapolis_St_Paul/utm.wkt: city/Minneapolis/utm.wkt; cp $< $@
city/Tampa_Bay/utm.wkt: city/Tampa/utm.wkt; cp $< $@

%.wkt: %.prj; gdalsrsinfo -o wkt $< > $@

# Small file containing the UTM Proj.4 string.
$(foreach x,$(CITIES),city/$x/utm.prj): city/%/utm.prj: citycenters.csv | city/%
	grep "$(subst _, ,$*)" $< | \
	cut -d, -f1-2 | \
	tr , ' ' | \
	xargs svgis project -m utm -- > $@

$(addprefix city/,$(CITIES) $(JOINED_CITIES)):; mkdir -p $@

# Geocoding

# set google key in vars
GOOGLEKEY ?=
GOOGLEAPI = https://maps.googleapis.com/maps/api/geocode/json -d key=$(GOOGLEKEY)

city/centers.geojson: citycenters.csv
	@rm -f $@
	ogr2ogr $@ $< -f GeoJSON -s_srs EPSG:4326 $(TSRS) \
	-dialect sqlite -sql "SELECT MakePoint(CAST(x as REAL), CAST(y as REAL)) Geometry, \
	CAST(x as REAL) x, CAST(y as REAL) y, \
	REPLACE(name, ' ', '_') name FROM $(basename $(<F))"

citycenters.csv: citycenters.txt | city
	echo x,y,name > $@
	sed 's/ /%20/g;s/,/%2C/g' $< | \
	xargs -I% curl -Gs $(GOOGLEAPI) -d address=% | \
	jq -r '.results[0] | \
		[(.geometry.location.lng), (.geometry.location.lat), \
			 [(.address_components[] | select( .types | contains(["locality", "political"])) | .long_name )][0] \
		] | @csv' | \
	sed 's/Old Toronto/Toronto/g; s/Ville-Marie/Montreal/g; s/St. /St /g; s/Manhattan/New York/g' >> $@

# Census
TIGER2016/prisecroads.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2016/PRISECROADS/tl_2014_$x_prisecroads.zip)
	@rm -f $@
	for f in $(basename $(^F)); do \
		ogr2ogr $@ /vsizip/$$f.zip $$f -update -append -nlt LINESTRING $(TSRS) -where "MTFCC='S1100'"; \
	done;

TIGER2016/water.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2016/AREAWATER/tl_2016_$x_areawater.zip)

GENZ2015/places.shp: $(foreach x,$(STATES_WITH_ARENA),GENZ2015/shp/cb_2015_$x_place_500k.zip)
	@rm -f $@
	for f in $(basename $(^F)); do \
		ogr2ogr $@ /vsizip/$$f.zip $$f -update -append $(TSRS) -nlt POLYGON -select GEOID,NAME -where "PCICBSA='Y'";\
	done;

can/provinces.shp: can/gpr_000b11a_e.zip
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp $(TSRS)

# Montreal, Ottawa, Toronto, Edmonton, Calgary, vancouver
can/places.shp: can/lcsd000a15a_e.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(basename $(<F)).shp $(TSRS) \
		-where "CSDUID IN ('2466023', '3506008', '3520005', '4811061', '4806016', '5915022')"

can/gpr_000b11a_e.zip can/lcsd000a15a_e.zip: | can
	curl -o $@ $(STATCAN)/$(@F)

.SECONDEXPANSION:
TIGER2016/%.zip GENZ2015/shp/%.zip: | $$(@D)
	curl -o $@ $(CENSUS)/$@

TIGER2016/PRISECROADS TIGER2015/PLACE TIGER2015/UAC GENZ2015/shp city can bounds buffer png svg:; mkdir -p $@

# Stadia

National_Hockey_League_section = Teams
List_of_National_Hockey_League_arenas_section = Current_arenas
Major_League_Baseball_section = Teams
National_Basketball_Association_section = Teams

.PHONY: arenas
arenas: $(ARENAS)

wiki/%.geojson: kml/%.kml | wiki
	@rm -f $@
	ogr2ogr $@ $< -f GeoJSON -nln $*

kml/%.kml: | kml
	curl -Gso $@ $(KMLEXPORT) -d article=$* -d section=$($*_section)

kml wiki: ; mkdir -p $@
