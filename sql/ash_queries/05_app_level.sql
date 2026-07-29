-- ASH Demo: Per-Application Breakdown
-- "Which application is driving the most load?"
-- Oracle equivalent: filtering by MODULE or PROGRAM in v$active_session_history
--
-- app_name is set via the connection string's application_name parameter.

SELECT
    app_name,
    work_event_type,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
  AND workload_type = 'STATEMENT'
GROUP BY app_name, work_event_type
ORDER BY samples DESC;
