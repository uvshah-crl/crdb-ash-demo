-- ASH Demo: Lock Contention Hotspots
-- "Which applications are experiencing lock waits, and what kind?"
-- Oracle equivalent: concurrency wait class analysis in ASH Analytics
--
-- LOCK work_events: LockWait, LatchWait, TxnPushWait, TxnQueryWait
-- train-events workload uses SELECT FOR UPDATE SKIP LOCKED — expect LOCK samples.

SELECT
    work_event,
    app_name,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
  AND work_event_type = 'LOCK'
GROUP BY work_event, app_name
ORDER BY samples DESC;
