-- Ansatz nach: https://workshop.pgrouting.org/2.1.0-dev/en/chapters/topology.html#load
CREATE TABLE wuppertal_roads_topology AS
SELECT r.*
FROM planet_osm_roads r,
     (SELECT way FROM planet_osm_polygon
      WHERE name = 'Wuppertal' AND boundary = 'administrative' AND admin_level = '6') AS wuppertal_boundary
WHERE ST_Within(r.way, wuppertal_boundary.way);

-- Vorbereiten für pgr_createTopology
ALTER TABLE wuppertal_roads_topology ADD COLUMN "source" integer;
ALTER TABLE wuppertal_roads_topology ADD COLUMN "target" integer;

-- SRID abfragen zur Toleranzbestimmung. SRID == 3857 => 1.00 als Toleranzwert, entspricht 1m
SELECT find_srid('public','wuppertal_roads_topology','way');

-- pgr_createTopology mit der Toleranz von 1m
SELECT pgr_createTopology('wuppertal_roads_topology', 1.0000, 'way', 'osm_id');

-- Topologie analysieren
SELECT pgr_analyzeGraph('wuppertal_roads_topology', 1.000000, the_geom := 'way', id := 'osm_id');

-- Kosten hinzufügen
ALTER TABLE wuppertal_roads_topology ADD COLUMN length DOUBLE PRECISION;
UPDATE wuppertal_roads_topology SET length = ST_Length(ST_Transform(way, 4326)::geography);


-- Dikstra-Algorithmus vorbereiten
SELECT osm_id, source, target FROM wuppertal_roads_topology
    WHERE osm_id IN (240943960, 477449989, 193966767)
    ORDER BY osm_id;

-- Dijkastra-Algorithmus anwenden
SELECT * FROM pgr_dijkstra('
    SELECT osm_id AS id,
         source,
         target,
         length AS cost
        FROM wuppertal_roads_topology',
    873, 5, directed := false);

-- A*-Algorithmus vorbereiten
ALTER TABLE wuppertal_roads_topology ADD COLUMN y1 DOUBLE PRECISION;
ALTER TABLE wuppertal_roads_topology ADD COLUMN x2 DOUBLE PRECISION;
ALTER TABLE wuppertal_roads_topology ADD COLUMN y2 DOUBLE PRECISION;
ALTER TABLE wuppertal_roads_topology ADD COLUMN x1 DOUBLE PRECISION;

UPDATE wuppertal_roads_topology
SET x1 = ST_X(ST_StartPoint(way)),
    y1 = ST_Y(ST_StartPoint(way)),
    x2 = ST_X(ST_EndPoint(way)),
    y2 = ST_Y(ST_EndPoint(way));

-- A*-Algorithmus anwenden
SELECT * FROM pgr_astar(
    'SELECT r.osm_id AS id, r.source, r.target, r.length AS cost,
        r.x1 AS x1, r.y1 AS y1,
        r.x2 AS x2, r.y2 AS y2
    FROM wuppertal_roads_topology r',
    873, 5, -- Start- und Ziel-Knoten
    directed := false,
    heuristic := 1);

-- GeoJSON Output
SELECT ST_AsGeoJSON(way)
FROM wuppertal_roads_topology
WHERE osm_id IN (SELECT edge FROM pgr_dijkstra('SELECT osm_id AS id, source, target, length as cost FROM wuppertal_roads_topology',
    2768,  -- Startknoten
    738, -- Zielknoten
    directed := false));

-- Auf Deutschland beziehen
CREATE TABLE germany_roads AS
SELECT r.*
FROM planet_osm_roads r,
     (SELECT way FROM planet_osm_polygon
      WHERE name = 'Deutschland'
        AND boundary = 'administrative'
        AND admin_level = '2') AS germany_boundary
WHERE ST_Within(r.way, germany_boundary.way);

ALTER TABLE germany_roads ADD COLUMN "source" integer;
ALTER TABLE germany_roads ADD COLUMN "target" integer;

SELECT pgr_createTopology('germany_roads', 1.0000, 'way', 'osm_id');

SELECT pgr_analyzeGraph('germany_roads', 1.000000, the_geom := 'way', id := 'osm_id');

ALTER TABLE germany_roads ADD COLUMN length DOUBLE PRECISION;
UPDATE germany_roads SET length = ST_Length(ST_Transform(way, 4326)::geography);

SELECT * FROM pgr_dijkstra('
    SELECT osm_id AS id,
         source,
         target,
         length AS cost
        FROM germany_roads',
    873, 5, directed := false);

SELECT ST_AsGeoJSON(way)
FROM germany_roads
WHERE osm_id IN (SELECT edge FROM pgr_dijkstra('SELECT osm_id AS id, source, target, length as cost FROM germany_roads
',
    6001264,  -- Startknoten
    2084647, -- Zielknoten
    directed := false));

-- A*
ALTER TABLE germany_roads ADD COLUMN y1 DOUBLE PRECISION;
ALTER TABLE germany_roads ADD COLUMN x2 DOUBLE PRECISION;
ALTER TABLE germany_roads ADD COLUMN y2 DOUBLE PRECISION;
ALTER TABLE germany_roads ADD COLUMN x1 DOUBLE PRECISION;

UPDATE germany_roads
SET x1 = ST_X(ST_StartPoint(way)),
    y1 = ST_Y(ST_StartPoint(way)),
    x2 = ST_X(ST_EndPoint(way)),
    y2 = ST_Y(ST_EndPoint(way));

-- A*-Algorithmus anwenden
SELECT * FROM pgr_astar(
    'SELECT r.osm_id AS id, r.source, r.target, r.length AS cost,
        r.x1 AS x1, r.y1 AS y1,
        r.x2 AS x2, r.y2 AS y2
    FROM germany_roads r',
    1181197, 5, -- Start- und Ziel-Knoten
    directed := false,
    heuristic := 1);

-- Auf gesamten Datensatz beziehen
ALTER TABLE planet_osm_roads ADD COLUMN "source" integer;
ALTER TABLE planet_osm_roads ADD COLUMN "target" integer;

SELECT find_srid('public','planet_osm_roads','way');

SELECT pgr_createTopology('planet_osm_roads', 1.0000, 'way', 'osm_id');

SELECT pgr_analyzeGraph('planet_osm_roads', 1.000000, the_geom := 'way', id := 'osm_id');

ALTER TABLE planet_osm_roads ADD COLUMN length DOUBLE PRECISION;
UPDATE planet_osm_roads SET length = ST_Length(ST_Transform(way, 4326)::geography);

SELECT * FROM pgr_dijkstra('
    SELECT osm_id AS id,
         source,
         target,
         length AS cost
        FROM planet_osm_roads',
    873, 5, directed := false);

SELECT ST_AsGeoJSON(way)
FROM planet_osm_roads
WHERE osm_id IN (SELECT edge FROM pgr_dijkstra('SELECT osm_id AS id, source, target, length as cost FROM planet_osm_roads',
    16786,  -- Startknoten
    158099, -- Zielknoten
    directed := false));

-- Ausgabe als GPS-Koordinaten
SELECT
    ST_X(ST_Transform(ST_StartPoint(geom), 4326)) AS lon_start,
    ST_Y(ST_Transform(ST_StartPoint(geom), 4326)) AS lat_start,
    ST_X(ST_Transform(ST_EndPoint(geom), 4326)) AS lon_end,
    ST_Y(ST_Transform(ST_EndPoint(geom), 4326)) AS lat_end
FROM (
    SELECT 'SRID=3857;LINESTRING(784980.6548612369 6666049.865171235,785054.8604337997 6666084.707513016,785228.9084576549 6666177.123141654)'::geometry AS geom
) AS subquery;

-- Visualisierung in Google Maps
https://www.google.com/maps/dir/51.2523,7.0516/51.2530,7.0538