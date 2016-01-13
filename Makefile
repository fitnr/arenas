KMLEXPORT = https://tools.wmflabs.org/kmlexport/

STATES_WITH_ARENA = 04 06 06 08 11 12 \
	13 17 18 20 22 \
	24 25 26 27 29 \
	36 37 39 40 41 \
	42 47 48 49 53 55

# todo: major city outline
# todo: urban areas
# todo: city centers and boundaries
# todo: radii in city center

all: 

# Census

TIGER2015/places.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2015/PLACE/tl_2015_$x_place.shp)
	for f in $^; do \
		ogr2ogr -update -append $@ $$f; \
	done;

TIGER2015/PLACE/tl_2015_%_place.shp: TIGER2015/PLACE/tl_2015_%_place.zip
	ogr2ogr $@ /vsizip/$</$(@F) \
	-t_srs EPSG:4326 -select GEOID,NAME -where "PCICBSA='Y'"

TIGER2015/UAC/tl_2015_us_uac10.shp: TIGER2015/UAC/tl_2015_us_uac10.zip
	ogr2ogr $@ /vsizip/$</$(@F) \
	-t_srs EPSG:4326 -select GEOID10,NAME10

TIGER2015/%.zip:
	@mkdir -p $(@D)
	curl -so $@ ftp://ftp2.census.gov/geo/tiger/$@

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
