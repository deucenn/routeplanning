SELECT * FROM pgr_dijkstra(
  'SELECT gid AS id, source, target, cost FROM your_roads_table',
  <start_node_id>, <end_node_id>,
  directed := false
);

select pgr_version();

SELECT * FROM pgr_dijkstra(
    'SELECT osm_id AS id,
         source,
         target,
         length AS cost
        FROM planet_osm_roads',
    9411, -- source id
    3986, -- target id
    directed := false);

SELECT * FROM planet_osm_line
WHERE highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'residential');

select osm_id as gid,
       name,
       st_length(way) as cost
from planet_osm_line
where highway in ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'residential');

--CREATE TABLE roads AS
SELECT
    osm_id AS gid,
    (SELECT osm_id FROM planet_osm_point WHERE ST_Equals(way, ST_StartPoint(planet_osm_line.way))) AS source,
    (SELECT osm_id FROM planet_osm_point WHERE ST_Equals(way, ST_EndPoint(planet_osm_line.way))) AS target,
    ST_Length(way) AS cost
FROM planet_osm_line;
