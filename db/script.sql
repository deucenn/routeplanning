SELECT * FROM pgr_dijkstra(
  'SELECT gid AS id, source, target, cost FROM your_roads_table',
  <start_node_id>, <end_node_id>,
  directed := false
);