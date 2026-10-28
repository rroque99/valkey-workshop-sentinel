# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Helper functions for the Valkey Sentinel workshop. Sourced by env.sh.
# Compatible with bash and zsh.
# -----------------------------------------------------------------------------

# List the Valkey data pods (primary + replicas) of the replication group.
#   repl_pods [namespace] [replication-name]
repl_pods() {
  local ns="${1:-$VALKEY_NS}" name="${2:-$REPL_NAME}"
  kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep -E "^${name}-[0-9]+$"
}

# List the Sentinel pods. Matches <name>-N and <name>-sentinel-N.
#   sentinel_pods [namespace] [sentinel-name]
sentinel_pods() {
  local ns="${1:-$VALKEY_NS}" name="${2:-$SENTINEL_NAME}"
  kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep -E "^${name}(-sentinel)?-[0-9]+$"
}

# First Running Sentinel pod
sentinel_pod() {
  local ns="${1:-$VALKEY_NS}" p
  for p in $(sentinel_pods "$ns" "${2:-$SENTINEL_NAME}"); do
    if [ "$(kubectl get pod -n "$ns" "$p" -o jsonpath='{.status.phase}')" = "Running" ]; then
      echo "$p"; return 0
    fi
  done
  return 1
}

# Headless Service that exposes Sentinel (port 26379)
sentinel_svc() {
  local ns="${1:-$VALKEY_NS}"
  kubectl get svc -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.clusterIP}{" "}{.spec.ports[*].port}{"\n"}{end}' \
    | awk '$2=="None" && / 26379/ {print $1; exit}'
}

# valkey-cli against a data pod as the human "admin" user.
#   vcli <pod> <valkey command...>
vcli() {
  local ns="${VKNS:-$VALKEY_NS}" pod="$1"; shift
  set -- --user admin --pass "${VALKEY_ADMIN_PASSWORD}" --no-auth-warning "$@"
  if [ "${VALKEY_TLS}" = "true" ]; then
    set -- --tls --insecure "$@"
  fi
  if [ -n "${VALKEY_CONTAINER}" ]; then
    kubectl exec --quiet -n "$ns" "$pod" -c "${VALKEY_CONTAINER}" -- valkey-cli "$@"
  else
    kubectl exec --quiet -n "$ns" "$pod" -- valkey-cli "$@"
  fi
}

# valkey-cli against a Sentinel (port 26379), authenticated with the Sentinel
# password (spec.valkeySentinelConfig.sentinelSecret -> requirepass).
#   scli <sentinel command...>        e.g. scli SENTINEL masters
scli() {
  local ns="${VKNS:-$VALKEY_NS}" pod
  pod="$(sentinel_pod "$ns")" || { echo "No running Sentinel pod found in $ns" >&2; return 1; }
  set -- -p 26379 -a "${SENTINEL_PASSWORD}" --no-auth-warning "$@"
  if [ "${VALKEY_TLS}" = "true" ]; then
    set -- --tls --insecure "$@"
  fi
  if [ -n "${SENTINEL_CONTAINER}" ]; then
    kubectl exec --quiet -n "$ns" "$pod" -c "${SENTINEL_CONTAINER}" -- valkey-cli "$@"
  else
    kubectl exec --quiet -n "$ns" "$pod" -- valkey-cli "$@"
  fi
}

# Address (ip/host) of the current primary as reported by Sentinel
primary_addr() {
  scli SENTINEL get-master-addr-by-name "${MASTER_GROUP}" | head -1 | tr -d '\r'
}

# Pod name of the current primary (resolved from Sentinel's view)
primary_pod() {
  local addr p ip
  addr="$(primary_addr)" || return 1
  for p in $(repl_pods); do
    ip="$(kubectl get pod -n "$VALKEY_NS" "$p" -o jsonpath='{.status.podIP}')"
    case "$addr" in
      "$ip"|"$p"|"$p".*) echo "$p"; return 0 ;;
    esac
  done
  echo "Could not map primary address '$addr' to a pod" >&2
  return 1
}

# Pod names of the replicas (everything except the primary)
replica_pods() {
  local primary
  primary="$(primary_pod)" || return 1
  repl_pods | grep -v -x "$primary"
}

# Render a manifest template, substituting ONLY the workshop variables.
#   render <file>            -> prints to stdout
#   render <file> | kubectl apply -f -
render() {
  "${WORKSHOP_HOME}/scripts/render.sh" "$@"
}

# Export SENTINEL_HOST and VALKEY_IMAGE (needed to render the client pod manifest)
client_env() {
  local svc
  svc="$(sentinel_svc)" || return 1
  export SENTINEL_HOST="${svc}.${VALKEY_NS}.svc.${CLUSTER_DOMAIN}"
  export VALKEY_IMAGE="$(kubectl get pod "$(repl_pods | head -1)" -n "${VALKEY_NS}" -o jsonpath='{.spec.containers[0].image}')"
  echo "SENTINEL_HOST=${SENTINEL_HOST}"
  echo "VALKEY_IMAGE=${VALKEY_IMAGE}"
}
