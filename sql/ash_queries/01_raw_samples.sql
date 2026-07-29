-- ASH Demo: Raw Samples
-- "What does an ASH sample look like?"
-- Oracle equivalent: SELECT * FROM v$active_session_history
--
-- Each row = one second where something was actively running on a node.

SELECT
    sample_time,
    node_id,
    workload_type,
    workload_id,
    app_name,
    work_event_type,
    work_event
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '2 minutes'
ORDER BY sample_time DESC
LIMIT 20;
