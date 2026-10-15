#!/bin/sh
# Sentinel-aware write loop. Every INTERVAL seconds it:
#   1. asks Sentinel who the primary is   (exactly what a Sentinel-aware client library does)
#   2. INCRs app:failover:counter on that primary
# It prints one line per attempt so you can see the failover window, and keeps
# a local count of acknowledged writes. Compare it with the server counter
# afterwards to spot writes lost to asynchronous replication.
#
#   kubectl exec -it valkey-client -n $VALKEY_NS -- /scripts/write-loop.sh
. /scripts/common.sh
INTERVAL="${INTERVAL:-0.5}"
KEY="${KEY:-app:failover:counter}"
ok=0; fail=0; last=""
trap 'echo; echo "acknowledged=$ok failed=$fail last_value=$last"; exit 0' INT TERM
echo "Writing to $KEY via Sentinel $SENTINEL_HOST:$SENTINEL_PORT (master group $MASTER_GROUP). Ctrl-C to stop."
while true; do
  set -- $(current_primary)
  host="$1"; port="$2"
  ts="$(date +%H:%M:%S)"
  if [ -z "$host" ]; then
    fail=$((fail+1)); echo "$ts  NO PRIMARY (Sentinel unreachable or failover in progress)"
  else
    out="$(data_cli "$host" "$port" INCR "$KEY" 2>&1)"
    case "$out" in
      ''|*[!0-9]*) fail=$((fail+1)); echo "$ts  primary=$host:$port  ERROR: $out" ;;
      *)           ok=$((ok+1)); last="$out"; echo "$ts  primary=$host:$port  $KEY=$out  (acked=$ok failed=$fail)" ;;
    esac
  fi
  sleep "$INTERVAL"
done
