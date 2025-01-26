-- Eingrenzung auf Wuppertal anhand https://www.openstreetmap.org/relation/62478:
SELECT way
FROM planet_osm_polygon
WHERE name = 'Wuppertal' AND boundary = 'administrative' AND admin_level = '6';

CREATE TABLE wuppertal_roads AS
SELECT l.*
FROM planet_osm_line l,
     (SELECT way FROM planet_osm_polygon
      WHERE name = 'Wuppertal' AND boundary = 'administrative' AND admin_level = '6') AS wuppertal_boundary
WHERE ST_Within(l.way, wuppertal_boundary.way);

-- Sämtliche Nicht-Straßen aus dem Datensatz eliminieren - NULL Values stehen lassen!:
DELETE FROM wuppertal_roads
WHERE highway NOT IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'residential', 'unclassified', 'service');

-- Knoten erzeugen:
CREATE TABLE wuppertal_nodes AS
SELECT row_number() OVER () AS id, (ST_DumpPoints(way)).geom AS geom
FROM wuppertal_roads;

-- Straßennetz mit Knoten verknüpfen:
ALTER TABLE wuppertal_roads ADD COLUMN source BIGINT;
ALTER TABLE wuppertal_roads ADD COLUMN target BIGINT;

WITH nodes AS (
    SELECT id, geom FROM wuppertal_nodes
)
UPDATE wuppertal_roads r
SET
    source = (SELECT id FROM nodes ORDER BY r.way <-> nodes.geom LIMIT 1), -- Auswahl des Knotens mit der kürzesten Distanz zur Linie
    target = (SELECT id FROM nodes ORDER BY r.way <-> nodes.geom LIMIT 1 OFFSET 1); -- Wahl des Offsets, damit Linien mit differenten Start- und Endpunkten erstellt werden können.

SELECT COUNT(*) FROM wuppertal_roads WHERE source IS NULL OR target IS NULL; -- Überprüfung von source und target

-- Kosten berechnen:
ALTER TABLE wuppertal_roads ADD COLUMN cost FLOAT;
UPDATE wuppertal_roads SET cost = ST_Length(way);

ALTER TABLE wuppertal_roads ADD COLUMN reverse_cost FLOAT;
UPDATE wuppertal_roads SET reverse_cost = cost;


SELECT COUNT(*) FROM wuppertal_roads WHERE cost IS NULL OR cost <= 0; -- Fehlerüberprüfung

-- TEST INPUTS:
-- Routenfindung mit Test Inputs:
SELECT id
FROM wuppertal_nodes
ORDER BY geom <-> ST_Transform(ST_SetSRID(ST_Point(7.150, 51.250), 4326), 3857) LIMIT 1; -- ID: 346

SELECT id FROM wuppertal_nodes
ORDER BY geom <-> st_transform(ST_SetSRID(ST_Point(7.500, 51.270), 4326), 3857) LIMIT 1; -- ID: 7106

-- Überprüfung der Start- und Zielknoten:
SELECT id, geom FROM wuppertal_nodes WHERE id = 346;
SELECT id, geom FROM wuppertal_nodes WHERE id = 7106;

SELECT source, target, osm_id
FROM wuppertal_roads
WHERE source = 346 OR target = 7106;

SELECT osm_id, cost
FROM wuppertal_roads
WHERE cost IS NULL;

SELECT COUNT(DISTINCT source), COUNT(DISTINCT target) FROM wuppertal_roads;

-- Dijkstra-Algorithmus zur Routenfindung
SELECT seq, node, edge, r.cost, r.reverse_cost, w.geom
FROM pgr_dijkstra(
    'SELECT osm_id AS id, source, target, cost, reverse_cost FROM wuppertal_roads',
    346,  -- Startknoten
    7106, -- Zielknoten
    directed := false
) AS route
JOIN wuppertal_roads r ON route.edge = r.osm_id
JOIN wuppertal_nodes w ON route.node = w.id;

-- Route visualisieren (689 - 7109 ergibt einen Route):
SELECT ST_AsGeoJSON(way)
FROM wuppertal_roads_filtered
WHERE osm_id IN (SELECT edge FROM pgr_dijkstra('SELECT osm_id AS id, source, target, cost, reverse_cost FROM wuppertal_roads_filtered',
    689,  -- Startknoten
    7109, -- Zielknoten
    directed := false));

-- DEBUGGING
SELECT * FROM pgr_analyzeGraph('wuppertal_roads', 0.0001);

-- Doppelte Kanten ermitteln:
SELECT source, target, COUNT(*)
FROM wuppertal_roads
GROUP BY source, target
HAVING COUNT(*) > 1;

-- Doppelte Kanten eliminieren:
DELETE FROM wuppertal_roads
WHERE osm_id IN (
    SELECT osm_id FROM (
        SELECT osm_id,
               ROW_NUMBER() OVER (PARTITION BY source, target ORDER BY osm_id) AS rn
        FROM wuppertal_roads
    ) as t
    WHERE rn > 1);

-- Isolierte Knoten ermitteln:
SELECT DISTINCT source FROM wuppertal_roads
EXCEPT
SELECT DISTINCT target FROM wuppertal_roads;

-- Isolierte Knoten eliminieren:
DELETE FROM wuppertal_roads
WHERE source NOT IN (SELECT DISTINCT target FROM wuppertal_roads)
AND target NOT IN (SELECT DISTINCT source FROM wuppertal_roads);

-- Fehlerhafte Gemoetrien ermitteln:
UPDATE wuppertal_roads
SET way = ST_MakeValid(way)
WHERE NOT ST_IsValid(way);

-- Gleiche source und target Werte entfernen:
DELETE FROM wuppertal_roads
WHERE source = target;

-- NEUER TEST:
-- Den Start- und Endpunkten der Linie den nächstgelegenen Knotenn zuweisen:
ALTER TABLE wuppertal_roads ADD COLUMN source_geom geometry;
ALTER TABLE wuppertal_roads ADD COLUMN target_geom geometry;

UPDATE wuppertal_roads r
SET
    source_geom = ST_StartPoint(r.way),
    target_geom = ST_EndPoint(r.way);

WITH nodes AS (
    SELECT id, geom FROM wuppertal_nodes
)
UPDATE wuppertal_roads r
SET
    source = (SELECT id FROM nodes ORDER BY r.source_geom <-> nodes.geom LIMIT 1),
    target = (SELECT id FROM nodes ORDER BY r.target_geom <-> nodes.geom LIMIT 1);

ALTER TABLE wuppertal_roads ADD COLUMN length_m DOUBLE PRECISION;
UPDATE wuppertal_roads SET length_m = ST_Length(way);

CREATE TABLE wuppertal_roads_directed AS
SELECT
    source,
    target,
    length_m
FROM wuppertal_roads;

-- Hinzufügen von entgegengesetzter Richtung
INSERT INTO wuppertal_roads_directed
SELECT target, source, length_m FROM wuppertal_roads;

ALTER TABLE wuppertal_roads_directed ADD COLUMN id SERIAL PRIMARY KEY;

-- pgRouting
SELECT * FROM pgr_dijkstra('SELECT id, source, target, length_m::double precision AS cost FROM wuppertal_roads_directed', 2196, 210);

SELECT ST_AsGeoJSON(way)
FROM wuppertal_roads_directed
WHERE id IN (
    SELECT edge
    FROM pgr_dijkstra(
        'SELECT id, source, target, length_m::double precision AS cost FROM wuppertal_roads_directed',
        346,  -- Startknoten
        7106  -- Zielknoten
    )
);


-- Bushaltestellen durch public_transport == platform dargestellt

SELECT pgr_createTopology('wuppertal_roads', 1.0, 'way', 'osm_id');

SELECT DISTINCT highway, public_transport
FROM wuppertal_roads;

CREATE TABLE wuppertal_roads_filtered AS
SELECT * FROM wuppertal_roads
WHERE "highway" NOT IN ('bus_stop', 'platform', 'footway', 'path')
  AND "public_transport" IS NULL;

-- ALle Knoten des Ways betrachten:
SELECT (dp).path[1] AS node_position,
       (dp).geom AS node_geom
FROM (
    SELECT ST_DumpPoints(way) AS dp
    FROM planet_osm_line
    WHERE osm_id = 1153231506
) AS points;

-- Die Start und Endknoten verwenden.
-- TODO: Topologie erstellen, auf Basis der topologischen Netzwerkstruktur Routing durchführen.


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

-- TODO: Toleranzwert erhöhen und analysieren
    -- 5.0 & 10.0 ausprobiert: geringfügig besser

-- Spalten nullen
UPDATE wuppertal_roads_topology
SET source = NULL,
    target = NULL,
    length = NULL;

DROP TABLE wuppertal_roads_topology_vertices_pgr;

-- Ansatz nach https://docs.pgrouting.org/2.2/en/src/topology/doc/pgr_nodeNetwork.html#pgr-node-network
select * from pgr_nodenetwork('wuppertal_roads_topology', 1.0, 'osm_id', 'way', 'noded');

select pgr_createTopology('wuppertal_roads_topology_noded', 1.00, 'way');

select pgr_analyzegraph('wuppertal_roads_topology_noded', 1.0, 'way');

ALTER TABLE wuppertal_roads_topology_noded ADD COLUMN length DOUBLE PRECISION;
UPDATE wuppertal_roads_topology_noded SET length = ST_Length(ST_Transform(way, 4326)::geography);

SELECT ST_AsGeoJSON(way)
FROM wuppertal_roads_topology_noded
WHERE old_id IN (SELECT edge FROM pgr_dijkstra('SELECT old_id AS id, source, target, length as cost FROM wuppertal_roads_topology_noded',
    1287,  -- Startknoten
    1938, -- Zielknoten
    directed := false));