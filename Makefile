CENSUS = ftp://ftp2.census.gov/geo/tiger
STATCAN = http://www12.statcan.gc.ca/census-recensement/2011/geo/bound-limit/files-fichiers
UTLIBRARY = http://data.library.utoronto.ca/datapub/cc11/geo/cbf/mapinfo
OPENCAN = http://ftp2.cits.rncan.gc.ca/pub/geobase/official/muni/shp_eng
KMLEXPORT = https://tools.wmflabs.org/kmlexport/

STATES_WITH_ARENA = 04 06 06 08 11 12 \
	13 17 18 20 22 \
	24 25 26 27 29 34 \
	36 37 39 40 41 \
	42 47 48 49 53 55

ARENAS = wiki/List_of_National_Hockey_League_arenas.geojson \
	wiki/National_Football_League.geojson \
	wiki/Major_League_Baseball.geojson \
	wiki/National_Basketball_Association.geojson \
	wiki/List_of_Major_League_Soccer_stadiums.geojson

GEO = bufferwgs84 \
	states \
	urban \
	water \
	places \
	roads \
	arenas \
	buffer

PLACES = 0455000 0653000 0664000 0666000 0668000 0667000 0644000 0820000 1150000 \
	1271000 1235000 1245000 1304000 1714000 1836003 2036000 2255000 2404000 2507000 \
	2622000 2743000 2758000 2938000 2965000 3651000 3611000 3712000 3916000 3918000 \
	3915000 4055000 4075000 4159000 4261000 4260000 4752006 4748000 4819000 4827000 \
	4865000 4805000 4835000 4967000 5363000 5553000 5531000 1263000 3755000

, = ,

TSRS = -t_srs EPSG:4326

CITIES = $(shell cut -d, -f2 citycenters.txt | sed 's/ /_/g; s/\.//g')

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

CANADIAN_CITIES = Calgary Edmonton Toronto Vancouver

.SECONDARY:

all: $(addsuffix .svg,$(addprefix svg/,$(SIMPLE_CITIES) $(JOINED_CITIES))) \
     $(addsuffix .png,$(addprefix png/,$(SIMPLE_CITIES) $(JOINED_CITIES)))

# Maps

png/%.png: svg/%.svg | png
	convert -density 150x150 $< $@

svg/%.svg: styles.css $(foreach g,$(GEO),city/%/$(g).shp) | svg
	svgis draw -j local -xl -f 100 -c $< -p 100 -i Name -a mi,league -s 50 $(filter %.geojson %.shp,$^) -o $@

# clipped layers
CLIP = -clipdst city/$* -clipdstlayer bufferwgs84 -skipfailures

# Local Arenas

city/%/arenas.shp: city/%/bufferwgs84.shp $(ARENAS)
	ogr2ogr -overwrite $@ wiki/Major_League_Baseball.geojson $(CLIP)
	ogr2ogr -update -append $@ wiki/National_Basketball_Association.geojson $(CLIP)
	ogr2ogr -update -append $@ wiki/List_of_National_Hockey_League_arenas.geojson $(CLIP)
	ogr2ogr -update -append $@ wiki/National_Football_League.geojson $(CLIP)
	ogr2ogr -update -append $@ wiki/List_of_Major_League_Soccer_stadiums.geojson $(CLIP)

city/%/roads.shp: TIGER2014/prisecroads.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ $< -overwrite $(CLIP) -nlt LINESTRING -select FULLNAME

$(foreach x,$(CANADIAN_CITIES),city/$x/water.shp): city/%/water.shp: can/ghy_000c11m_e can/ghy_000h11m_e city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ $< -overwrite $(CLIP) -nlt POLYGON
	ogr2ogr $@ can/ghy_000h11m_e -update -append $(CLIP)

$(foreach x,$(filter-out $(CANADIAN_CITIES),$(CITIES)),city/$x/water.shp): city/%/water.shp: TIGER2016/water.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ $< -overwrite $(CLIP) -nlt POLYGON

city/%/places.shp: GENZ2015/places.shp can/places.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ $< -overwrite $(CLIP) -nlt POLYGON
	ogr2ogr $@ can places -update -append $(CLIP)

city/%/urban.shp: GENZ2015/shp/cb_2015_us_ua10_500k.zip can/gpc_000b11m_e city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp -overwrite -nlt POLYGON $(TSRS) $(CLIP) -select GEOID10
	ogr2ogr $@ can/gpc_000b11m_e -update -append $(TSRS) $(CLIP)

city/%/states.shp: GENZ2015/shp/cb_2015_us_state_500k.zip can/provinces.shp city/%/bufferwgs84.shp | city/%
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp -overwrite -nlt POLYGON $(TSRS) $(CLIP) -select GEOID
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
TIGER2014/prisecroads.shp: $(foreach x,$(STATES_WITH_ARENA),TIGER2014/PRISECROADS/tl_2014_$x_prisecroads.zip)
	@rm -f $@
	for f in $(basename $(^F)); do \
		ogr2ogr $@ /vsizip/$(<D)/$$f.zip $$f -update -append -nlt LINESTRING $(TSRS) -where "MTFCC='S1100'"; \
	done;
	ogrinfo $@ -sql 'CREATE SPATIAL INDEX ON $(@F)'

GENZ2015/places.shp: $(foreach x,$(STATES_WITH_ARENA),GENZ2015/shp/cb_2015_$x_place_500k.zip)
	@rm -f $@
	for f in $(basename $(^F)); do \
		ogr2ogr $@ /vsizip/$(<D)/$$f.zip $$f -update -append $(TSRS) -nlt POLYGON -select GEOID,NAME \
		-where "GEOID IN ('$(subst $() $(),'$(,) ',$(PLACES))')";\
	done;
	ogrinfo $(@D) -sql 'CREATE SPATIAL INDEX ON $(basename $(@F))'

# Counties

COUNTIES = $(shell cat counties.txt)

TIGER2016/water.shp: $(foreach x,$(COUNTIES),TIGER2016/AREAWATER/tl_2016_$x_areawater.zip)
	@rm -f $@
	for f in $(COUNTIES); do \
		ogr2ogr $@ /vsizip/$(<D)/tl_2016_$${f}_areawater.zip tl_2016_$${f}_areawater \
		-nlt POLYGON $(TSRS) -update -append \
		-select FULLNAME -where "AWATER > 12000 AND MTFCC IN ('H2030', 'H2040', 'H2051', 'H2053', 'H3010', 'H3020')"; \
	done;
	ogrinfo $(@D) -sql 'CREATE SPATIAL INDEX ON $(basename $(@F))'

# Filter out Whatcom, WA (only intersects Canada)
counties.txt: GENZ2015/county.csv
	tail -n+2 $< | \
	cut -d, -f 1 | \
	grep -v 53073 | \
	sort | xargs |\
	fold -sw 80 > $@

GENZ2015/county.csv: GENZ2015/shp/cb_2015_us_county_500k.shp city/buffers.shp
	@rm -f $@
	ogr2ogr -f CSV $@ $(<D) -dialect sqlite \
		-sql "WITH b AS (SELECT ST_Union(Geometry) Buffer FROM 'city'.buffers) \
		SELECT GEOID, NAME FROM $(basename $(<F)) a, b WHERE ST_Intersects(a.Geometry, b.Buffer)"

city/buffers.shp: $(foreach x,$(JOINED_CITIES) $(SIMPLE_CITIES),city/$x/bufferwgs84.shp)
	@rm -f $@
	for d in $(basename $(^D)); do \
		ogr2ogr $@ $$d $(basename $(<F)) -update -append -nlt POLYGON; \
	done;
	ogrinfo $(@D) -sql 'CREATE SPATIAL INDEX ON $(basename $(@F))'

can/provinces.shp: can/gpr_000b11a_e.zip
	ogr2ogr $@ /vsizip/$</$(basename $(<F)).shp $(TSRS)

# Montreal, Ottawa, Toronto, Edmonton, Calgary, vancouver
can/places.shp: can/lcsd000a15a_e.zip
	ogr2ogr -overwrite $@ /vsizip/$</$(basename $(<F)).shp $(TSRS) \
		-where "CSDUID IN ('2466023', '3506008', '3520005', '4811061', '4806016', '5915022')"

can/gpr_000b11a_e.zip can/lcsd000a15a_e.zip: | can
	curl -o $@ $(STATCAN)/$(@F)

can/gpc_000b11m_e can/ghy_000c11m_e can/ghy_000h11m_e: can/%: can/%.zip
	unzip -d $@ $< -x '*.pdf'

can/gpc_000b11m_e.zip can/ghy_000c11m_e.zip can/ghy_000h11m_e.zip: | can
	curl -o $@ $(UTLIBRARY)/$(@F)

%.shp: %.zip
	ogr2ogr $@ /vsizip/$< $(basename $(<F)) $(TSRS)

.SECONDEXPANSION:
TIGER2014/%.zip TIGER2016/%.zip GENZ2015/shp/%.zip: | $$(@D)
	curl -o $@ $(CENSUS)/$@

TIGER2016/AREAWATER TIGER2014/PRISECROADS TIGER2015/PLACE TIGER2015/UAC GENZ2015/shp \
	city can bounds buffer png svg:; mkdir -p $@

# Stadia

National_Football_League_section = Clubs
List_of_National_Hockey_League_arenas_section = Current_arenas
Major_League_Baseball_section = Teams
National_Basketball_Association_section = Teams
List_of_Major_League_Soccer_stadiums_section = Stadiums

National_Football_League_league = nfl
List_of_National_Hockey_League_arenas_league = nhl
Major_League_Baseball_league = mlb
National_Basketball_Association_league = nba
List_of_Major_League_Soccer_stadiums_league = mls

.PHONY: arenas
arenas: $(ARENAS)

wiki/%.geojson: kml/%.kml | wiki
	@rm -f $@
	ogr2ogr $@ $< -f GeoJSON -nln $* -sql "SELECT Name, '$($*_league)' league FROM "'"$(subst _, ,$($*_section))"'

kml/%.kml: | kml
	curl -Gso $@ $(KMLEXPORT) -d article=$* -d section=$($*_section)

kml wiki: ; mkdir -p $@
