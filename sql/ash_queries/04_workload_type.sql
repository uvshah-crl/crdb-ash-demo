-- ASH Demo: Workload Type Separation (STATEMENT vs JOB vs SYSTEM)
-- "Is the load coming from user SQL, background jobs, or internal system work?"
-- No Oracle equivalent — this is unique to CockroachDB.
--
-- STATEMENT = user SQL | JOB = backups/imports | SYSTEM = raft, gc, etc.

SELECT
    workload_type,
    work_event_type,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
GROUP BY workload_type, work_event_type
ORDER BY samples DESC;
