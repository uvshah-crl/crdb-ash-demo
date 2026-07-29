-- ASH Demo: Admission Control Pressure
-- "Is the cluster throttling work due to resource pressure?"
-- CockroachDB-specific — no Oracle equivalent.
--
-- ADMISSION work_events show which internal queues are backing up:
--   kv-regular-cpu-queue, kv-elastic-store-queue, sql-kv-response, etc.
-- High ADMISSION counts = cluster running hot, may need more capacity.

SELECT
    work_event,
    app_name,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
  AND work_event_type = 'ADMISSION'
GROUP BY work_event, app_name
ORDER BY samples DESC;
