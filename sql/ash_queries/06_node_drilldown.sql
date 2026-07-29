-- ASH Demo: Node-Level Drilldown (Incident Scenario)
-- "CPU spiked on a specific node — what was running there?"
-- Oracle equivalent: filtering by INSTANCE_NUMBER in RAC's gv$active_session_history
--
-- Replace node_id filter with the actual node you want to investigate.

SELECT
    node_id,
    work_event_type,
    app_name,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
GROUP BY node_id, work_event_type, app_name
ORDER BY node_id, samples DESC;
