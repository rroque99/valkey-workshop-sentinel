#!/bin/sh
# Show the primary and replicas as seen by Sentinel (run inside the client pod)
. /scripts/common.sh
echo "== Primary (SENTINEL get-master-addr-by-name $MASTER_GROUP)"
sentinel_cli SENTINEL get-master-addr-by-name "$MASTER_GROUP"
echo
echo "== Replicas (SENTINEL replicas $MASTER_GROUP)"
sentinel_cli SENTINEL replicas "$MASTER_GROUP" | paste - - | grep -E '^(name|ip|port|flags|master-link-status|slave-repl-offset|slave-priority)[[:space:]]' | paste - - - - - - -
echo
echo "== Sentinels known (SENTINEL sentinels $MASTER_GROUP)"
sentinel_cli SENTINEL sentinels "$MASTER_GROUP" | paste - - | grep -E '^(ip|port|flags)[[:space:]]' | paste - - -
echo
echo "== Quorum check"
sentinel_cli SENTINEL ckquorum "$MASTER_GROUP"
