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
FROM wuppertal_roads_no_null;

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

-- Route visualisieren:
SELECT ST_AsGeoJSON(way)
FROM wuppertal_roads
WHERE osm_id IN (SELECT edge FROM pgr_dijkstra('SELECT osm_id AS id, source, target, cost, reverse_cost FROM wuppertal_roads',
    345,  -- Startknoten
    2169, -- Zielknoten
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
ALTER TABLE wuppertal_roads_directed ADD COLUMN geom

-- pgRouting
SELECT * FROM pgr_dijkstra('SELECT id, source, target, length_m::double precision AS cost FROM wuppertal_roads_directed', 2196, 210);

SELECT ST_AsGeoJSON(way)
FROM wuppertal_roads
WHERE id IN (
    SELECT edge
    FROM pgr_dijkstra(
        'SELECT id, source, target, length_m::double precision AS cost FROM wuppertal_roads_directed',
        346,  -- Startknoten
        7106  -- Zielknoten
    )
);
