-- Alle aktiven Tasks
SELECT pid, usename, query, now() - query_start AS runtime
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '10 seconds';

-- Abbruch von Task mit PID == 32368
SELECT pg_cancel_backend(32368);
