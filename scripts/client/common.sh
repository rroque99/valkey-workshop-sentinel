#!/bin/sh
# Shared settings for scripts that run INSIDE the valkey-client pod.
# Env vars injected by the pod spec: SENTINEL_HOST, MASTER_GROUP, VALKEY_USER,
# VALKEY_PASSWORD, SENTINEL_PASSWORD, ADMIN_PASSWORD, VALKEY_TLS (optional)
SENTINEL_PORT="${SENTINEL_PORT:-26379}"
TLS_FLAGS=""
[ "${VALKEY_TLS:-false}" = "true" ] && TLS_FLAGS="--tls --insecure"

# Sentinel is protected by its own password (sentinelSecret), separate from the
# data-node ACL users.
sentinel_cli() {
  # shellcheck disable=SC2086
  valkey-cli $TLS_FLAGS -h "$SENTINEL_HOST" -p "$SENTINEL_PORT" -a "$SENTINEL_PASSWORD" --no-auth-warning "$@"
}

# Prints "<host> <port>" of the current primary, as Sentinel sees it
current_primary() {
  sentinel_cli SENTINEL get-master-addr-by-name "$MASTER_GROUP" 2>/dev/null | tr '\n' ' '
}

data_cli() {
  _h="$1"; _p="$2"; shift 2
  # shellcheck disable=SC2086
  valkey-cli $TLS_FLAGS -h "$_h" -p "$_p" --user "$VALKEY_USER" --pass "$VALKEY_PASSWORD" --no-auth-warning "$@"
}
