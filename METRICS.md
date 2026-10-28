# Valkey exporter metrics (Tanzu Valkey 3.5.1)

All metrics exposed by the Tanzu Valkey exporter sidecar on this lab cluster, captured on 2026-10-28 from the primary (`vk-repl-1`) and a replica (`vk-repl-0`).

| | |
|---|---|
| **Exporter** | `Valkey Metrics Exporter v1.82.0` (based on upstream redis_exporter) |
| **Valkey** | `9.0.6` |
| **Endpoint** | `http://<pod-ip>:9121/metrics` (plain HTTP, see issues.md issue 15) |
| **Prefix** | `redis_` |
| **Count** | 203 metric families: 194 `redis_*` and 9 exporter-process metrics |

**Columns:** *Type* is the Prometheus type. *Labels* lists label names besides the ones Prometheus adds (`namespace`, `pod`, `node`, …). *Seen on* shows whether the metric appears on the primary (P), a replica (R) or both. ⭐ marks metrics used by the workshop alert rules, dashboard or module 7.

Most exporter descriptions are just "`<field>` metric"; those rows point to the `INFO` field instead. See `valkey-cli INFO` and the [Valkey INFO docs](https://valkey.io/commands/info/) for the meaning.

Regenerate after an exporter upgrade:

```bash
kubectl port-forward -n "$VALKEY_NS" "pod/$(primary_pod)" 9121:9121 &
curl -s http://localhost:9121/metrics | grep -E '^# (HELP|TYPE)'
kill %1
```

## Contents

- [Exporter and scrape health](#exporter-and-scrape-health) (10)
- [Server and instance info](#server-and-instance-info) (14)
- [CPU and event loop](#cpu-and-event-loop) (11)
- [Memory and fragmentation](#memory-and-fragmentation) (43)
- [Clients and connections](#clients-and-connections) (19)
- [Network](#network) (4)
- [Commands, throughput and errors](#commands-throughput-and-errors) (21)
- [Slow log and command log](#slow-log-and-command-log) (12)
- [Keyspace and expiry](#keyspace-and-expiry) (11)
- [Replication](#replication) (19)
- [Persistence (RDB / AOF / fork)](#persistence-rdb--aof--fork) (23)
- [ACL and security](#acl-and-security) (4)
- [Pub/Sub](#pubsub) (3)
- [Exporter process (Go runtime)](#exporter-process-go-runtime) (9)

## Exporter and scrape health

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_exporter_build_info` | gauge | `build_date`, `commit_sha`, `golang_version`, `version` | P+R | redis exporter build_info |
| `redis_exporter_last_scrape_connect_time_seconds` | gauge |  | P+R | from `INFO` field `exporter_last_scrape_connect_time_seconds` |
| `redis_exporter_last_scrape_duration_seconds` | gauge |  | P+R | from `INFO` field `exporter_last_scrape_duration_seconds` |
| `redis_exporter_last_scrape_error` | gauge | `err` | P+R | The last scrape error status. |
| `redis_exporter_scrape_duration_seconds` | summary |  | P+R | Durations of scrapes by the exporter |
| `redis_exporter_scrapes_total` | counter |  | P+R | Current total redis scrapes. |
| `redis_last_key_groups_scrape_duration_milliseconds` | gauge |  | P+R | Duration of the last key group metrics scrape in milliseconds |
| `redis_target_scrape_request_errors_total` | counter |  | P+R | Errors in requests to the exporter |
| `redis_up` ⭐ | gauge |  | P+R | Information about the Redis instance |
| `redis_uptime_in_seconds` | gauge |  | P+R | from `INFO` field `uptime_in_seconds` |

## Server and instance info

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_cluster_connections` | gauge |  | P+R | from `INFO` field `cluster_connections` |
| `redis_cluster_enabled` | gauge |  | P+R | from `INFO` field `cluster_enabled` |
| `redis_config_client_output_buffer_limit_bytes` | gauge | `class`, `limit` | P+R | The configured buffer limits per class |
| `redis_config_client_output_buffer_limit_overcome_seconds` | gauge | `class`, `limit` | P+R | How long for buffer limits per class to be exceeded before replicas are dropped |
| `redis_config_io_threads` | gauge |  | P+R | from `INFO` field `config_io_threads` |
| `redis_config_maxclients` ⭐ | gauge |  | P+R | from `INFO` field `config_maxclients` |
| `redis_config_maxmemory` | gauge |  | P+R | from `INFO` field `config_maxmemory` |
| `redis_config_repl_backlog_size` | gauge |  | P+R | from `INFO` field `config_repl_backlog_size` |
| `redis_instance_info` ⭐ | gauge | `master_replid`, `maxmemory_policy`, `os`, `process_id`, `redis_build_id`, `redis_mode`, `redis_version`, `role`, `run_id`, `tcp_port`, `valkey_release_stage`, `valkey_version` | P+R | from `INFO` field `instance_info` |
| `redis_io_threads_active` | gauge |  | P+R | from `INFO` field `io_threads_active` |
| `redis_number_of_functions` | gauge |  | P+R | from `INFO` field `number_of_functions` |
| `redis_number_of_libraries` | gauge |  | P+R | from `INFO` field `number_of_libraries` |
| `redis_process_id` | gauge |  | P+R | from `INFO` field `process_id` |
| `redis_start_time_seconds` | gauge |  | P+R | Start time of the Redis instance since unix epoch in seconds. |

## CPU and event loop

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_configured_hz` | gauge |  | P+R | from `INFO` field `configured_hz` |
| `redis_cpu_sys_children_seconds_total` | counter |  | P+R | from `INFO` field `cpu_sys_children_seconds_total` |
| `redis_cpu_sys_main_thread_seconds_total` | counter |  | P+R | from `INFO` field `cpu_sys_main_thread_seconds_total` |
| `redis_cpu_sys_seconds_total` ⭐ | counter |  | P+R | from `INFO` field `cpu_sys_seconds_total` |
| `redis_cpu_user_children_seconds_total` | counter |  | P+R | from `INFO` field `cpu_user_children_seconds_total` |
| `redis_cpu_user_main_thread_seconds_total` | counter |  | P+R | from `INFO` field `cpu_user_main_thread_seconds_total` |
| `redis_cpu_user_seconds_total` ⭐ | counter |  | P+R | from `INFO` field `cpu_user_seconds_total` |
| `redis_eventloop_cycles_total` | counter |  | P+R | from `INFO` field `eventloop_cycles_total` |
| `redis_eventloop_duration_cmd_sum_usec_total` | counter |  | P+R | from `INFO` field `eventloop_duration_cmd_sum_usec_total` |
| `redis_eventloop_duration_sum_usec_total` | counter |  | P+R | from `INFO` field `eventloop_duration_sum_usec_total` |
| `redis_hz` | gauge |  | P+R | from `INFO` field `hz` |

## Memory and fragmentation

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_active_defrag_running` | gauge |  | P+R | from `INFO` field `active_defrag_running` |
| `redis_allocator_active_bytes` | gauge |  | P+R | from `INFO` field `allocator_active_bytes` |
| `redis_allocator_allocated_bytes` | gauge |  | P+R | from `INFO` field `allocator_allocated_bytes` |
| `redis_allocator_frag_bytes` | gauge |  | P+R | from `INFO` field `allocator_frag_bytes` |
| `redis_allocator_frag_ratio` | gauge |  | P+R | from `INFO` field `allocator_frag_ratio` |
| `redis_allocator_muzzy_bytes` | gauge |  | P+R | from `INFO` field `allocator_muzzy_bytes` |
| `redis_allocator_resident_bytes` | gauge |  | P+R | from `INFO` field `allocator_resident_bytes` |
| `redis_allocator_rss_bytes` | gauge |  | P+R | from `INFO` field `allocator_rss_bytes` |
| `redis_allocator_rss_ratio` | gauge |  | P+R | from `INFO` field `allocator_rss_ratio` |
| `redis_current_eviction_exceeded_time_ms` | gauge |  | P+R | from `INFO` field `current_eviction_exceeded_time_ms` |
| `redis_defrag_hits` | gauge |  | P+R | from `INFO` field `defrag_hits` |
| `redis_defrag_key_hits` | gauge |  | P+R | from `INFO` field `defrag_key_hits` |
| `redis_defrag_key_misses` | gauge |  | P+R | from `INFO` field `defrag_key_misses` |
| `redis_defrag_misses` | gauge |  | P+R | from `INFO` field `defrag_misses` |
| `redis_evicted_scripts_total` | counter |  | P+R | from `INFO` field `evicted_scripts_total` |
| `redis_eviction_exceeded_time_ms_total` | counter |  | P+R | from `INFO` field `eviction_exceeded_time_ms_total` |
| `redis_lazyfree_pending_objects` | gauge |  | P+R | from `INFO` field `lazyfree_pending_objects` |
| `redis_lazyfreed_objects` | gauge |  | P+R | from `INFO` field `lazyfreed_objects` |
| `redis_mem_aof_buffer_bytes` | gauge |  | P+R | from `INFO` field `mem_aof_buffer_bytes` |
| `redis_mem_clients_normal` | gauge |  | P+R | from `INFO` field `mem_clients_normal` |
| `redis_mem_clients_slaves` | gauge |  | P+R | from `INFO` field `mem_clients_slaves` |
| `redis_mem_cluster_links_bytes` | gauge |  | P+R | from `INFO` field `mem_cluster_links_bytes` |
| `redis_mem_fragmentation_bytes` | gauge |  | P+R | from `INFO` field `mem_fragmentation_bytes` |
| `redis_mem_fragmentation_ratio` ⭐ | gauge |  | P+R | from `INFO` field `mem_fragmentation_ratio` |
| `redis_mem_not_counted_for_eviction_bytes` | gauge |  | P+R | from `INFO` field `mem_not_counted_for_eviction_bytes` |
| `redis_mem_overhead_db_hashtable_rehashing_bytes` | gauge |  | P+R | from `INFO` field `mem_overhead_db_hashtable_rehashing_bytes` |
| `redis_mem_replication_backlog_bytes` | gauge |  | P+R | from `INFO` field `mem_replication_backlog_bytes` |
| `redis_mem_total_replication_buffers_bytes` | gauge |  | P+R | from `INFO` field `mem_total_replication_buffers_bytes` |
| `redis_memory_max_bytes` ⭐ | gauge |  | P+R | from `INFO` field `memory_max_bytes` |
| `redis_memory_used_bytes` ⭐ | gauge |  | P+R | from `INFO` field `memory_used_bytes` |
| `redis_memory_used_dataset_bytes` | gauge |  | P+R | from `INFO` field `memory_used_dataset_bytes` |
| `redis_memory_used_functions_bytes` | gauge |  | P+R | from `INFO` field `memory_used_functions_bytes` |
| `redis_memory_used_lua_bytes` | gauge |  | P+R | from `INFO` field `memory_used_lua_bytes` |
| `redis_memory_used_overhead_bytes` | gauge |  | P+R | from `INFO` field `memory_used_overhead_bytes` |
| `redis_memory_used_peak_bytes` | gauge |  | P+R | from `INFO` field `memory_used_peak_bytes` |
| `redis_memory_used_rss_bytes` ⭐ | gauge |  | P+R | from `INFO` field `memory_used_rss_bytes` |
| `redis_memory_used_scripts_bytes` | gauge |  | P+R | from `INFO` field `memory_used_scripts_bytes` |
| `redis_memory_used_scripts_eval_bytes` | gauge |  | P+R | from `INFO` field `memory_used_scripts_eval_bytes` |
| `redis_memory_used_startup_bytes` | gauge |  | P+R | from `INFO` field `memory_used_startup_bytes` |
| `redis_memory_used_vm_eval_bytes` | gauge |  | P+R | from `INFO` field `memory_used_vm_eval_bytes` |
| `redis_memory_used_vm_functions_bytes` | gauge |  | P+R | from `INFO` field `memory_used_vm_functions_bytes` |
| `redis_memory_used_vm_total` | gauge |  | P+R | from `INFO` field `memory_used_vm_total` |
| `redis_number_of_cached_scripts` | gauge |  | P+R | from `INFO` field `number_of_cached_scripts` |

## Clients and connections

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_blocked_clients` ⭐ | gauge |  | P+R | from `INFO` field `blocked_clients` |
| `redis_client_output_buffer_limit_disconnections_total` | counter |  | P+R | from `INFO` field `client_output_buffer_limit_disconnections_total` |
| `redis_client_query_buffer_limit_disconnections_total` | counter |  | P+R | from `INFO` field `client_query_buffer_limit_disconnections_total` |
| `redis_client_recent_max_input_buffer_bytes` | gauge |  | P+R | from `INFO` field `client_recent_max_input_buffer_bytes` |
| `redis_client_recent_max_output_buffer_bytes` | gauge |  | P+R | from `INFO` field `client_recent_max_output_buffer_bytes` |
| `redis_clients_in_timeout_table` | gauge |  | P+R | from `INFO` field `clients_in_timeout_table` |
| `redis_connected_clients` ⭐ | gauge |  | P+R | from `INFO` field `connected_clients` |
| `redis_connections_received_total` ⭐ | counter |  | P+R | from `INFO` field `connections_received_total` |
| `redis_evicted_clients_total` | counter |  | P+R | from `INFO` field `evicted_clients_total` |
| `redis_max_clients` | gauge |  | P+R | from `INFO` field `max_clients` |
| `redis_pubsub_clients` | gauge |  | P+R | from `INFO` field `pubsub_clients` |
| `redis_rejected_connections_total` ⭐ | counter |  | P+R | from `INFO` field `rejected_connections_total` |
| `redis_total_blocking_keys` | gauge |  | P+R | from `INFO` field `total_blocking_keys` |
| `redis_total_blocking_keys_on_nokey` | gauge |  | P+R | from `INFO` field `total_blocking_keys_on_nokey` |
| `redis_tracking_clients` | gauge |  | P+R | from `INFO` field `tracking_clients` |
| `redis_tracking_total_items` | gauge |  | P+R | from `INFO` field `tracking_total_items` |
| `redis_tracking_total_keys` | gauge |  | P+R | from `INFO` field `tracking_total_keys` |
| `redis_tracking_total_prefixes` | gauge |  | P+R | from `INFO` field `tracking_total_prefixes` |
| `redis_watching_clients` | gauge |  | P+R | from `INFO` field `watching_clients` |

## Network

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_net_input_bytes_total` ⭐ | counter |  | P+R | from `INFO` field `net_input_bytes_total` |
| `redis_net_output_bytes_total` ⭐ | counter |  | P+R | from `INFO` field `net_output_bytes_total` |
| `redis_net_repl_input_bytes_total` | counter |  | P+R | from `INFO` field `net_repl_input_bytes_total` |
| `redis_net_repl_output_bytes_total` | counter |  | P+R | from `INFO` field `net_repl_output_bytes_total` |

## Commands, throughput and errors

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_commands_duration_seconds_total` ⭐ | counter | `cmd` | P+R | Total amount of time in seconds spent per command |
| `redis_commands_failed_calls_total` | counter | `cmd` | P+R | Total number of errors prior command execution per command |
| `redis_commands_latencies_usec` | histogram | `cmd` | P+R | A histogram of latencies per command |
| `redis_commands_processed_total` ⭐ | counter |  | P+R | from `INFO` field `commands_processed_total` |
| `redis_commands_rejected_calls_total` | counter | `cmd` | P+R | Total number of errors within command execution per command |
| `redis_commands_total` ⭐ | counter | `cmd` | P+R | Total number of calls per command |
| `redis_dump_payload_sanitizations` | counter |  | P+R | from `INFO` field `dump_payload_sanitizations` |
| `redis_errors_total` | counter | `err` | P+R | Total number of errors per error type |
| `redis_instantaneous_eventloop_cycles_per_sec` | gauge |  | P+R | from `INFO` field `instantaneous_eventloop_cycles_per_sec` |
| `redis_instantaneous_eventloop_duration_usec` | gauge |  | P+R | from `INFO` field `instantaneous_eventloop_duration_usec` |
| `redis_io_threaded_reads_processed` | counter |  | P+R | from `INFO` field `io_threaded_reads_processed` |
| `redis_io_threaded_writes_processed` | counter |  | P+R | from `INFO` field `io_threaded_writes_processed` |
| `redis_latency_percentiles_usec` | summary | `cmd`, `quantile` | P+R | A summary of latency percentile distribution per command |
| `redis_migrate_cached_sockets_total` | gauge |  | P+R | from `INFO` field `migrate_cached_sockets_total` |
| `redis_reply_buffer_expands_total` | counter |  | P+R | from `INFO` field `reply_buffer_expands_total` |
| `redis_reply_buffer_shrinks_total` | counter |  | P+R | from `INFO` field `reply_buffer_shrinks_total` |
| `redis_total_error_replies` | counter |  | P+R | from `INFO` field `total_error_replies` |
| `redis_total_reads_processed` | counter |  | P+R | from `INFO` field `total_reads_processed` |
| `redis_total_watched_keys` | gauge |  | P+R | from `INFO` field `total_watched_keys` |
| `redis_total_writes_processed` | counter |  | P+R | from `INFO` field `total_writes_processed` |
| `redis_unexpected_error_replies` | counter |  | P+R | from `INFO` field `unexpected_error_replies` |

## Slow log and command log

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_commandlog_execution_slower_than` | gauge |  | P+R | Execution time threshold in microseconds for the slow command log |
| `redis_commandlog_large_reply_length` | gauge |  | P+R | Total entries in the large-reply command log |
| `redis_commandlog_large_reply_max_len` | gauge |  | P+R | Maximum number of entries retained in the large-reply command log |
| `redis_commandlog_large_request_length` | gauge |  | P+R | Total entries in the large-request command log |
| `redis_commandlog_large_request_max_len` | gauge |  | P+R | Maximum number of entries retained in the large-request command log |
| `redis_commandlog_reply_larger_than` | gauge |  | P+R | Reply size threshold in bytes for the large-reply command log |
| `redis_commandlog_request_larger_than` | gauge |  | P+R | Request size threshold in bytes for the large-request command log |
| `redis_commandlog_slow_execution_max_len` | gauge |  | P+R | Maximum number of entries retained in the slow command log |
| `redis_commandlog_slow_length` | gauge |  | P+R | Total entries in the slow command log |
| `redis_last_slow_execution_duration_seconds` | gauge |  | P+R | The amount of time needed for last slow execution, in seconds |
| `redis_slowlog_last_id` | gauge |  | P+R | Last id of slowlog |
| `redis_slowlog_length` ⭐ | gauge |  | P+R | Total slowlog |

## Keyspace and expiry

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_db_avg_ttl_seconds` | gauge | `db` | P+R | Avg TTL in seconds |
| `redis_db_keys` ⭐ | gauge | `db` | P+R | Total number of keys by DB |
| `redis_db_keys_cached` | gauge | `db` | P+R | Total number of cached keys by DB |
| `redis_db_keys_expiring` ⭐ | gauge | `db` | P+R | Total number of expiring keys by DB |
| `redis_evicted_keys_total` ⭐ | counter |  | P+R | from `INFO` field `evicted_keys_total` |
| `redis_expire_cycle_cpu_time_ms_total` | counter |  | P+R | from `INFO` field `expire_cycle_cpu_time_ms_total` |
| `redis_expired_keys_total` ⭐ | counter |  | P+R | from `INFO` field `expired_keys_total` |
| `redis_expired_stale_percentage` | gauge |  | P+R | from `INFO` field `expired_stale_percentage` |
| `redis_expired_time_cap_reached_total` | counter |  | P+R | from `INFO` field `expired_time_cap_reached_total` |
| `redis_keyspace_hits_total` ⭐ | counter |  | P+R | from `INFO` field `keyspace_hits_total` |
| `redis_keyspace_misses_total` ⭐ | counter |  | P+R | from `INFO` field `keyspace_misses_total` |

## Replication

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_connected_slave_lag_seconds` ⭐ | gauge | `slave_ip`, `slave_port`, `slave_state` | P | Lag of connected slave |
| `redis_connected_slave_offset_bytes` | gauge | `slave_ip`, `slave_port`, `slave_state` | P | Offset of connected slave |
| `redis_connected_slaves` ⭐ | gauge |  | P+R | from `INFO` field `connected_slaves` |
| `redis_master_last_io_seconds_ago` | gauge | `master_host`, `master_port` | R | Master last io seconds ago |
| `redis_master_link_up` ⭐ | gauge | `master_host`, `master_port` | R | Master link status on Redis slave |
| `redis_master_repl_offset` ⭐ | gauge |  | P+R | from `INFO` field `master_repl_offset` |
| `redis_master_sync_in_progress` | gauge | `master_host`, `master_port` | R | Master sync in progress |
| `redis_repl_backlog_first_byte_offset` | gauge |  | P+R | from `INFO` field `repl_backlog_first_byte_offset` |
| `redis_repl_backlog_history_bytes` | gauge |  | P+R | from `INFO` field `repl_backlog_history_bytes` |
| `redis_repl_backlog_is_active` | gauge |  | P+R | from `INFO` field `repl_backlog_is_active` |
| `redis_replica_partial_resync_accepted` | gauge |  | P+R | from `INFO` field `replica_partial_resync_accepted` |
| `redis_replica_partial_resync_denied` | gauge |  | P+R | from `INFO` field `replica_partial_resync_denied` |
| `redis_replica_resyncs_full` | gauge |  | P+R | from `INFO` field `replica_resyncs_full` |
| `redis_replication_backlog_bytes` | gauge |  | P+R | from `INFO` field `replication_backlog_bytes` |
| `redis_second_repl_offset` | gauge |  | P+R | from `INFO` field `second_repl_offset` |
| `redis_slave_expires_tracked_keys` | gauge |  | P+R | from `INFO` field `slave_expires_tracked_keys` |
| `redis_slave_info` | gauge | `master_host`, `master_port`, `read_only` | R | Information about the Redis slave |
| `redis_slave_priority` | gauge |  | R | from `INFO` field `slave_priority` |
| `redis_slave_repl_offset` | gauge | `master_host`, `master_port` | R | Slave replication offset |

## Persistence (RDB / AOF / fork)

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_aof_current_rewrite_duration_sec` | gauge |  | P+R | from `INFO` field `aof_current_rewrite_duration_sec` |
| `redis_aof_enabled` | gauge |  | P+R | from `INFO` field `aof_enabled` |
| `redis_aof_last_bgrewrite_status` | gauge |  | P+R | from `INFO` field `aof_last_bgrewrite_status` |
| `redis_aof_last_cow_size_bytes` | gauge |  | P+R | from `INFO` field `aof_last_cow_size_bytes` |
| `redis_aof_last_rewrite_duration_sec` | gauge |  | P+R | from `INFO` field `aof_last_rewrite_duration_sec` |
| `redis_aof_last_write_status` | gauge |  | P+R | from `INFO` field `aof_last_write_status` |
| `redis_aof_rewrite_in_progress` | gauge |  | P+R | from `INFO` field `aof_rewrite_in_progress` |
| `redis_aof_rewrite_scheduled` | gauge |  | P+R | from `INFO` field `aof_rewrite_scheduled` |
| `redis_async_loading` | gauge |  | P+R | from `INFO` field `async_loading` |
| `redis_latest_fork_seconds` | gauge |  | P+R | from `INFO` field `latest_fork_seconds` |
| `redis_loading_dump_file` | gauge |  | P+R | from `INFO` field `loading_dump_file` |
| `redis_module_fork_in_progress` | gauge |  | P+R | from `INFO` field `module_fork_in_progress` |
| `redis_module_fork_last_cow_size` | gauge |  | P+R | from `INFO` field `module_fork_last_cow_size` |
| `redis_rdb_bgsave_in_progress` | gauge |  | P+R | from `INFO` field `rdb_bgsave_in_progress` |
| `redis_rdb_changes_since_last_save` ⭐ | gauge |  | P+R | from `INFO` field `rdb_changes_since_last_save` |
| `redis_rdb_current_bgsave_duration_sec` | gauge |  | P+R | from `INFO` field `rdb_current_bgsave_duration_sec` |
| `redis_rdb_last_bgsave_duration_sec` | gauge |  | P+R | from `INFO` field `rdb_last_bgsave_duration_sec` |
| `redis_rdb_last_bgsave_status` ⭐ | gauge |  | P+R | from `INFO` field `rdb_last_bgsave_status` |
| `redis_rdb_last_cow_size_bytes` | gauge |  | P+R | from `INFO` field `rdb_last_cow_size_bytes` |
| `redis_rdb_last_load_expired_keys` | gauge |  | P+R | from `INFO` field `rdb_last_load_expired_keys` |
| `redis_rdb_last_load_loaded_keys` | gauge |  | P+R | from `INFO` field `rdb_last_load_loaded_keys` |
| `redis_rdb_last_save_timestamp_seconds` ⭐ | gauge |  | P+R | from `INFO` field `rdb_last_save_timestamp_seconds` |
| `redis_rdb_saves_total` | gauge |  | P+R | from `INFO` field `rdb_saves_total` |

## ACL and security

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_acl_access_denied_auth_total` | counter |  | P+R | from `INFO` field `acl_access_denied_auth_total` |
| `redis_acl_access_denied_channel_total` | counter |  | P+R | from `INFO` field `acl_access_denied_channel_total` |
| `redis_acl_access_denied_cmd_total` | counter |  | P+R | from `INFO` field `acl_access_denied_cmd_total` |
| `redis_acl_access_denied_key_total` | counter |  | P+R | from `INFO` field `acl_access_denied_key_total` |

## Pub/Sub

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `redis_pubsub_channels` | gauge |  | P+R | from `INFO` field `pubsub_channels` |
| `redis_pubsub_patterns` | gauge |  | P+R | from `INFO` field `pubsub_patterns` |
| `redis_pubsubshard_channels` | gauge |  | P+R | from `INFO` field `pubsubshard_channels` |

## Exporter process (Go runtime)

| Metric | Type | Labels | Seen on | Description |
|---|---|---|---|---|
| `process_cpu_seconds_total` | counter |  | P+R | Total user and system CPU time spent in seconds. |
| `process_max_fds` | gauge |  | P+R | Maximum number of open file descriptors. |
| `process_network_receive_bytes_total` | counter |  | P+R | Number of bytes received by the process over the network. |
| `process_network_transmit_bytes_total` | counter |  | P+R | Number of bytes sent by the process over the network. |
| `process_open_fds` | gauge |  | P+R | Number of open file descriptors. |
| `process_resident_memory_bytes` | gauge |  | P+R | Resident memory size in bytes. |
| `process_start_time_seconds` | gauge |  | P+R | Start time of the process since unix epoch in seconds. |
| `process_virtual_memory_bytes` | gauge |  | P+R | Virtual memory size in bytes. |
| `process_virtual_memory_max_bytes` | gauge |  | P+R | Maximum amount of virtual memory available in bytes. |
