-- Cluster settings for ASH demo.
-- Applied once after cluster creation by 00_setup_cluster.sh.

-- Enable Active Session History (preview in v26.2)
SET CLUSTER SETTING obs.ash.enabled = true;
SET CLUSTER SETTING obs.ash.sample_interval = '1s';
SET CLUSTER SETTING obs.ash.buffer_size = 1000000;
SET CLUSTER SETTING obs.ash.log_interval = '5m';

-- Allow crdb_internal table reads
SET CLUSTER SETTING sql.override.allow_unsafe_internals.enabled = true;

-- Increase observability table cardinality limits
SET CLUSTER SETTING sql.metrics.max_mem_stmt_fingerprints = 100000;
SET CLUSTER SETTING sql.metrics.max_mem_txn_fingerprints = 100000;
