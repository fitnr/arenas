KMLEXPORT = https://tools.wmflabs.org/kmlexport/

STATES_WITH_ARENA = 04 06 06 08 11 12 \
	13 17 18 20 22 \
	24 25 26 27 29 \
	36 37 39 40 41 \
	42 47 48 49 53 55

TSRS = -t_srs EPSG:4326

# todo: radii in city center

CITIES = $(shell cut -d, -f2 citycenters.txt | sed 's/ /_/g')

all: $(addsuffix .svg,$(addprefix svg/,$(CITIES)))

# Maps

GEO = GENZ2014/shp/cb_2014_us_state_5m.shp \
	TIGER2015/UAC/tl_2015_us_uac10.shp \
	TIGER2015/places.shp \
	wiki/National_Hockey_League.shp \
	wiki/National_Football_League.shp \
	wiki/Major_League_Baseball.shp \
	wiki/National_Basketball_Association.shp

svg/%.svg: styles.css bounds/% $(GEO) buffer/%.shp | svg
	xargs -J % svgis draw -j local -x -f 100 -c $< -p 100 --bounds % <bounds/$* \
	$(filter %.shp,$^) -o $@

# Buffers
buffer/%.shp: buffer/%_25mi.shp buffer/%_20mi.shp buffer/%_15mi.shp buffer/%_10mi.shp
	ogr2ogr -overwrite $@ buffer/$*_25mi.shp -nln buffer 
	ogr2ogr -update $@ buffer/$*_20mi.shp -append
	ogr2ogr -update $@ buffer/$*_15mi.shp -append
	ogr2ogr -update $@ buffer/$*_10mi.shp -append

buffer/%_10mi.shp: buffer/%_0.shp
	ogr2ogr -overwrite $@ $< $(TSRS) -dialect sqlite -sql 'SELECT Buffer(Geometry, 16093.4) Geometry, 10 mi FROM "$*_0"'

buffer/%_15mi.shp: buffer/%_0.shp
	ogr2ogr -overwrite $@ $< $(TSRS) -dialect sqlite -sql 'SELECT Buffer(Geometry, 24140.2) Geometry, 15 mi FROM "$*_0"'

buffer/%_20mi.shp: buffer/%_0.shp
	ogr2ogr -overwrite $@ $< $(TSRS) -dialect sqlite -sql 'SELECT Buffer(Geometry, 32186.9) Geometry, 20 mi FROM "$*_0"'

buffer/%_25mi.shp: buffer/%_0.shp
	ogr2ogr -overwrite $@ $< $(TSRS) -dialect sqlite -sql 'SELECT Buffer(Geometry, 40233.6) Geometry, 25 mi FROM "$*_0"'

# Can't fucking quote in xargs properly WTF
buffer/%_0.shp: bounds/% city/centers.shp | buffer
	PROJ=$$(xargs -J % svgis project -j utm % <$<); \
	ogr2ogr -overwrite $@ city/centers.shp -where "name='$*'" -t_srs "$${PROJ}"

bounds/%: city/bounds.csv | bounds
	grep $* $< | cut -d, -f2 > $@

bounds buffer svg:; mkdir -p $@

# Geocoding
# set google key in vars
GOOGLEKEY ?=
GOOGLEAPI = https://maps.googleapis.com/maps/api/geocode/json -d key=$(GOOGLEKEY)

city/bounds.csv: city/envelope.shp
	@rm -f $@
	ogr2ogr -f CSV $@ $< -dialect sqlite \
	-sql "SELECT name, MbrMinX(Geometry) || ' ' || \
	MbrMinY(Geometry) || ' ' || MbrMaxX(Geometry) || ' ' || \
	MbrMaxY(Geometry) bounds FROM envelope"

city/envelope.shp: GENZ2014/shp/cb_2014_us_cbsa_20m.shp city/centers.shp
	 ogr2ogr -overwrite $@ $< $(TSRS) -dialect sqlite \
	 -sql "SELECT Envelope(a.Geometry) Geometry, a.GEOID, b.name \
	 FROM 'city/centers.shp'.centers b, $(basename $(<F)) a WHERE Within(b.Geometry, a.Geometry)"

city/centers.shp: city/centers.csv
	ogr2ogr -overwrite -f 'ESRI Shapefile' $@ $< \
	-s_srs EPSG:4326 $(TSRS) \
	-dialect sqlite -sql "SELECT MakePoint(CAST(x as REAL), CAST(y as REAL)) Geometry, CAST(x as REAL) x, CAST(y as REAL) y, REPLACE(REPLACE(name, 'Old Toronto', 'Toronto'), ' ', '_') name FROM centers"

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
.PRECIOUS: %.zip

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

TIGER2015/%.zip:
	@mkdir -p $(@D)
	curl -so $@ ftp://ftp2.census.gov/geo/tiger/$@

GENZ2014/shp/%.shp: GENZ2014/shp/%.zip
	ogr2ogr $@ /vsizip/$</$(@F) $(TSRS)

GENZ2014/shp/%.zip: | GENZ2014/shp
	curl -so $@ http://www2.census.gov/geo/tiger/$@

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

wiki/%.shp: wiki/%.kml
	@rm -f $@
	ogr2ogr $@ $< -nln $*

wiki/%.kml: | wiki
	curl -Gso $@ $(KMLEXPORT) -d article=$* -d section=$($*_section)

wiki: ; mkdir -p $@
