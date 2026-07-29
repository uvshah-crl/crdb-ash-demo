-- ASH Demo: Join with Statement Statistics
-- "Which SQL statements are consuming the most resources?"
-- workload_id for STATEMENT type is the hex encoding of the 8-byte statement
-- fingerprint ID — the same fingerprint that's in crdb_internal.statement_statistics.
--
-- No direct Oracle equivalent — Oracle ASH embeds SQL_ID directly in v$ash rows.
-- In CockroachDB, you join on the fingerprint to get the query text.

SELECT
    ash.workload_id,
    substring(ss.metadata->>'query', 1, 80) AS query_preview,
    ash.work_event_type,
    count(*) AS samples
FROM information_schema.crdb_cluster_active_session_history ash
JOIN crdb_internal.statement_statistics ss
    ON ash.workload_id = encode(ss.fingerprint_id, 'hex')
WHERE ash.workload_type = 'STATEMENT'
  AND ash.sample_time > now() - INTERVAL '30 minutes'
GROUP BY ash.workload_id, query_preview, ash.work_event_type
ORDER BY samples DESC
LIMIT 20;
