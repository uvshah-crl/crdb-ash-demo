-- ASH Demo: Work Event Type Breakdown (Wait Class Distribution)
-- "What resources is the cluster consuming right now?"
-- Oracle equivalent: ASH Analytics wait class breakdown
--
-- COUNT(*) = "database seconds" — same methodology as Oracle ASH.

SELECT
    work_event_type,
    count(*) AS samples,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS pct
FROM information_schema.crdb_cluster_active_session_history
WHERE sample_time > now() - INTERVAL '5 minutes'
GROUP BY work_event_type
ORDER BY samples DESC;
