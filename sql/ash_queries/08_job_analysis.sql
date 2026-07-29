-- ASH Demo: Background Job Resource Consumption
-- "What resources is the BACKUP job consuming?"
-- No Oracle equivalent — Oracle ASH doesn't distinguish backup sessions automatically.
--
-- Shows CPU/IO/NETWORK breakdown for JOB workload type.

SELECT
    workload_id AS job_id,
    work_event_type,
    work_event,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '10 minutes'
  AND workload_type = 'JOB'
GROUP BY workload_id, work_event_type, work_event
ORDER BY samples DESC;
