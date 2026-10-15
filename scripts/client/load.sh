#!/bin/sh
# Generate load against the CURRENT primary with valkey-benchmark.
# Uses the admin account because benchmark keys (key:*, counter:*, mylist) are
# outside the appuser key pattern (~app:*).
#   /scripts/load.sh                 # default mixed SET/GET workload, runs until Ctrl-C
#   REQUESTS=200000 /scripts/load.sh # finite run
#   TESTS=get CLIENTS=100 /scripts/load.sh
. /scripts/common.sh
set -- $(current_primary)
host="$1"; port="$2"
[ -z "$host" ] && { echo "Cannot resolve primary from Sentinel"; exit 1; }
TESTS="${TESTS:-set,get,incr,lpush,lpop}"
CLIENTS="${CLIENTS:-20}"
SIZE="${SIZE:-256}"
KEYSPACE="${KEYSPACE:-200000}"
REQUESTS="${REQUESTS:-}"
echo "valkey-benchmark -> $host:$port tests=$TESTS clients=$CLIENTS size=${SIZE}B keyspace=$KEYSPACE"
if [ -n "$REQUESTS" ]; then
  # shellcheck disable=SC2086
  valkey-benchmark $TLS_FLAGS -h "$host" -p "$port" --user "${BENCH_USER:-admin}" -a "$ADMIN_PASSWORD" \
    -t "$TESTS" -c "$CLIENTS" -d "$SIZE" -r "$KEYSPACE" -n "$REQUESTS" -q
else
  # shellcheck disable=SC2086
  valkey-benchmark $TLS_FLAGS -h "$host" -p "$port" --user "${BENCH_USER:-admin}" -a "$ADMIN_PASSWORD" \
    -t "$TESTS" -c "$CLIENTS" -d "$SIZE" -r "$KEYSPACE" -n 1000000 -l -q
fi
