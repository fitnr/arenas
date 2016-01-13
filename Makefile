KMLEXPORT = https://tools.wmflabs.org/kmlexport/

STATES_WITH_ARENA = 04 06 06 08 11 12 \
	13 17 18 20 22 \
	24 25 26 27 29 \
	36 37 39 40 41 \
	42 47 48 49 53 55

TSRS = -t_srs EPSG:4326

# todo: major city outline
# todo: urban areas
# todo: city centers and boundaries
# todo: radii in city center

all: 

# Geocoding
# set google key in vars
GOOGLEKEY ?=
GOOGLEAPI = https://maps.googleapis.com/maps/api/geocode/json -d key=$(GOOGLEKEY)

city/bounds.csv: city/envelope.shp
	ogr2ogr -f CSV $@ $< -dialect sqlite \
	-sql "SELECT name, MbrMinX(Geometry) || ' ' || \
	MbrMinY(Geometry) || ' ' || MbrMaxX(Geometry) || ' ' || \
	MbrMaxY(Geometry) bounds FROM envelope"

city/envelope.shp: TIGER2015/UAC/tl_2015_us_uac10.shp city/centers.geojson
	 ogr2ogr $@ $< $(TSRS) -dialect sqlite -sql "SELECT Envelope(a.Geometry) Geometry, a.GEOID10 GEOID10, a.NAME10 NAME10, b.name FROM '$(filter %.geojson,$^)'.OGRGeoJSON b, $(basename $(<F)) a WHERE Within(b.Geometry, a.Geometry)"

city/centers.shp: city/centers.csv
	ogr2ogr -f 'ESRI Shapefile' $@ $< \
	-s_srs EPSG:4326 $(TSRS) \
	-dialect sqlite -sql "SELECT MakePoint(CAST(x as REAL), CAST(y as REAL)) Geometry, CAST(x as REAL) x, CAST(y as REAL) y, REPLACE(REPLACE('Old Toronto', 'Toronto', name), ' ', '_') name FROM centers"

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

city: ; mkdir -p $@

# Census

TIGER2015/places.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2015/PLACE/tl_2015_$x_place.shp)
	for f in $^; do \
		ogr2ogr -update -append $@ $$f; \
	done;

TIGER2015/PLACE/tl_2015_%_place.shp: TIGER2015/PLACE/tl_2015_%_place.zip
	ogr2ogr $@ /vsizip/$</$(@F) \
	$(TSRS) -select GEOID,NAME -where "PCICBSA='Y'"

TIGER2015/UAC/tl_2015_us_uac10.shp: TIGER2015/UAC/tl_2015_us_uac10.zip
	ogr2ogr $@ /vsizip/$</$(@F) \
	$(TSRS) -select GEOID10,NAME10

TIGER2015/%.zip:
	@mkdir -p $(@D)
	curl -so $@ ftp://ftp2.census.gov/geo/tiger/$@

GENZ2014/shp/cb_2014_us_nation_5m.shp: GENZ2014/shp/cb_2014_us_nation_5m.zip
	ogr2ogr $@ /vsizip/$</$(@F) $(TSRS)

GENZ2014/shp/cb_2014_us_nation_5m.zip: | GENZ2014/shp
	curl -o $@ -s http://www2.census.gov/geo/tiger/$@

GENZ2014/shp:; mkdir -p $@

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

wiki/%.geojson: wiki/%.kml
	@rm -f $@
	ogr2ogr -f GeoJSON $@ $<

wiki/%.kml: | wiki
	curl -Gso $@ $(KMLEXPORT) -d article=$* -d section=$($*_section)

wiki: ; mkdir -p $@
