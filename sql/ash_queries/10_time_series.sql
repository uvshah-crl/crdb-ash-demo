-- ASH Demo: Time-Bucketed Trends
-- "How did the workload profile change over time?"
-- Oracle equivalent: ASH Analytics time-series chart
--
-- Shows per-minute breakdown of work event types.

SELECT
    date_trunc('minute', sample_time) AS minute,
    work_event_type,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
GROUP BY minute, work_event_type
ORDER BY minute DESC, samples DESC;
