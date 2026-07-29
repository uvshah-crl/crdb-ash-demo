-- ASH Demo: Internal System Work
-- "What is CockroachDB doing behind the scenes?"
-- No Oracle equivalent — Oracle doesn't expose internal background process activity in ASH.
--
-- SYSTEM workload_id values: RAFT, GC, INTENT_RESOLUTION, RANGEFEED,
--   REPLICATE_QUEUE, SPLIT_QUEUE, LEASE_ACQUISITION, etc.

SELECT
    workload_id AS system_task,
    work_event_type,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
  AND workload_type = 'SYSTEM'
GROUP BY workload_id, work_event_type
ORDER BY samples DESC
LIMIT 15;
