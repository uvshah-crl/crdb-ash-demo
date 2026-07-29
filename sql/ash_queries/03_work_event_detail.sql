-- ASH Demo: Drill into CPU Work Events
-- "What SQL operations are consuming CPU?"
-- Shows specific CPU operations: Optimize, tablereader, hashJoiner, upsert, etc.
--
-- Oracle equivalent: drilling into "CPU + Wait for CPU" wait class to see SQL_ID breakdown

SELECT
    work_event,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
  AND work_event_type = 'CPU'
GROUP BY work_event
ORDER BY samples DESC
LIMIT 15;
