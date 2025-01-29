-- Runtime Messungen
EXPLAIN ANALYZE
SELECT * FROM pgr_dijkstra('
    SELECT osm_id AS id,
         source,
         target,
         length AS cost
        FROM wuppertal_roads_topology',
    873, 5, directed := false);

DO $$
DECLARE
    total_time DOUBLE PRECISION := 0;
    extracted_time DOUBLE PRECISION;
    run_time TEXT;
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        -- EXPLAIN ANALYZE ausführen und Ergebnis in eine Variable speichern
        EXECUTE 'EXPLAIN ANALYZE SELECT * FROM pgr_dijkstra(
                    ''SELECT osm_id AS id, source, target, length AS cost FROM wuppertal_roads_topology'',
                    873, 5, directed := false)'
        INTO run_time;

        -- "Execution Time" extrahieren
        extracted_time := substring(run_time FROM 'Execution Time: ([0-9\.]+) ms')::DOUBLE PRECISION;

        -- NULL-Werte ignorieren
        IF extracted_time IS NOT NULL THEN
            total_time := total_time + extracted_time;
        END IF;

        -- Kurze Pause, um Caching-Effekte zu minimieren
        PERFORM pg_sleep(0.1);
    END LOOP;

    -- Durchschnitt berechnen & ausgeben
    RAISE NOTICE 'Durchschnittliche Execution Time: % ms', total_time / 100;
END $$;





EXPLAIN ANALYZE
SELECT * FROM pgr_astar(
    'SELECT r.osm_id AS id, r.source, r.target, r.length AS cost,
        r.x1 AS x1, r.y1 AS y1,
        r.x2 AS x2, r.y2 AS y2
    FROM wuppertal_roads_topology r',
    873, 5, -- Start- und Ziel-Knoten
    directed := false,
    heuristic := 1);

EXPLAIN ANALYZE
SELECT * FROM pgr_astar(
    'SELECT r.osm_id AS id, r.source, r.target, r.length AS cost,
        r.x1 AS x1, r.y1 AS y1,
        r.x2 AS x2, r.y2 AS y2
    FROM wuppertal_roads_topology r',
    873, 5, -- Start- und Ziel-Knoten
    directed := false,
    heuristic := 2);

EXPLAIN ANALYZE
SELECT * FROM pgr_dijkstra('
    SELECT osm_id AS id,
         source,
         target,
         length AS cost
        FROM germany_roads',
    873, 5, directed := false); -- 4081.063ms

EXPLAIN ANALYZE
SELECT * FROM pgr_astar(
    'SELECT r.osm_id AS id, r.source, r.target, r.length AS cost,
        r.x1 AS x1, r.y1 AS y1,
        r.x2 AS x2, r.y2 AS y2
    FROM germany_roads r',
    873, 5, -- Start- und Ziel-Knoten
    directed := false,
    heuristic := 1); -- 3717.398ms

EXPLAIN ANALYZE
SELECT * FROM pgr_astar(
    'SELECT r.osm_id AS id, r.source, r.target, r.length AS cost,
        r.x1 AS x1, r.y1 AS y1,
        r.x2 AS x2, r.y2 AS y2
    FROM germany_roads r',
    873, 5, -- Start- und Ziel-Knoten
    directed := false,
    heuristic := 2); -- 3717.398ms

EXPLAIN ANALYZE
SELECT * FROM pgr_dijkstra(
    'SELECT osm_id AS id,
         source,
         target,
         length AS cost
     FROM germany_roads',
    1181197, 5, directed := false); -- 4295.489ms

EXPLAIN ANALYZE
SELECT * FROM pgr_astar(
    'SELECT r.osm_id AS id, r.source, r.target, r.length AS cost,
        r.x1 AS x1, r.y1 AS y1,
        r.x2 AS x2, r.y2 AS y2
    FROM germany_roads r',
    1181197, 5, -- Start- und Ziel-Knoten
    directed := false,
    heuristic := 1); -- 4103.991ms