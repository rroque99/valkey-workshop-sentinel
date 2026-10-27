# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Tanzu for Valkey on Kubernetes - Sentinel HA Operator Workshop
# Environment file. Edit the values in the "EDIT ME" section, then:
#
#     source ./env.sh
#
# Re-source this file in every new terminal you open during the workshop.
# -----------------------------------------------------------------------------

# Resolve the workshop root directory (works in bash and zsh)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  _env_file="${BASH_SOURCE[0]}"
else
  _env_file="${(%):-%x}"
fi
export WORKSHOP_HOME="$(cd "$(dirname "${_env_file}")" && pwd)"
unset _env_file

# ============================== EDIT ME ======================================

# --- Broadcom registry (Broadcom Support Portal credentials / token) ---------
# Do NOT hard-code the password here. Export it in your shell instead:
#   export REGISTRY_USERNAME='you@example.com'
#   export REGISTRY_PASSWORD='<token>'
export REGISTRY_SERVER="tanzu-valkey.packages.broadcom.com"
export REGISTRY_USERNAME="${REGISTRY_USERNAME:-}"
export REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"

# --- Operator ----------------------------------------------------------------
export OPERATOR_NS="tanzu-for-valkey-on-kubernetes"
export OPERATOR_RELEASE="valkey-operator"
export OPERATOR_DEPLOY="valkey-operator"          # deployment name created by the chart
export OPERATOR_VERSION="3.5.1"
export CLUSTER_DOMAIN="cluster.local"             # must match your cluster DNS suffix

# --- Valkey instance ---------------------------------------------------------
export VALKEY_NS="valkey-workshop"
export SENTINEL_NAME="vk-sentinel"                # ValkeySentinel CR name
export REPL_NAME="vk-repl"                        # ValkeyReplication created/monitored by Sentinel
export MASTER_GROUP="valkey-server"               # Sentinel master group name used by the operator
export VALKEY_VERSION="valkey-9.0.6"              # initial version (module 03)
export VALKEY_TARGET_VERSION="valkey-9.1.2"       # upgrade target (module 11)
export STORAGE_SIZE="2Gi"                         # PVC size per Valkey data pod
export SERVICE_TYPE="ClusterIP"                   # ClusterIP | LoadBalancer

# --- Supporting components ---------------------------------------------------
export MONITORING_NS="monitoring"
export MONITORING_SERVICE_TYPE="ClusterIP"        # ClusterIP (port-forward) | LoadBalancer
export MINIO_NS="minio"
export BACKUP_BUCKET="valkey-backups"
export DR_NS="valkey-workshop-dr"                 # DR "site" namespace (or namespace on DR cluster)
export DR_CONTEXT=""                              # optional: kube context of a 2nd cluster for DR

# --- Optional: container names (leave empty to use the pod's default) -------
export VALKEY_CONTAINER=""
export SENTINEL_CONTAINER=""

# ============================ END EDIT ME ====================================

# Generated-once lab passwords (stored in .secrets/, never commit this folder)
mkdir -p "${WORKSHOP_HOME}/.secrets"
chmod 700 "${WORKSHOP_HOME}/.secrets"
for _s in default admin app monitor sentinel commander minio grafana; do
  _f="${WORKSHOP_HOME}/.secrets/${_s}"
  [ -s "${_f}" ] || (umask 077; openssl rand -hex 16 > "${_f}")
done
unset _s _f

export VALKEY_DEFAULT_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/default")"    # platform user (operator, Sentinel, replication, exporter)
export VALKEY_ADMIN_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/admin")"        # human operators
export VALKEY_APP_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/app")"            # application user
export VALKEY_MONITOR_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/monitor")"    # read-only troubleshooting user
export SENTINEL_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/sentinel")"         # Sentinel API + Sentinel peers (sentinelSecret, module 03)
export COMMANDER_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/commander")"       # Valkey Commander login
export MINIO_ROOT_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/minio")"          # MinIO (backup target)
export GRAFANA_ADMIN_PASSWORD="$(cat "${WORKSHOP_HOME}/.secrets/grafana")"     # Grafana admin

# Set to "true" after you enable TLS in module 05 (optional lab)
export VALKEY_TLS="${VALKEY_TLS:-false}"

# Variables that scripts/render.sh is allowed to substitute in manifests.
# Anything not listed here (for example $labels in alert rules) is left untouched.
export WORKSHOP_VARS="REGISTRY_SERVER OPERATOR_NS OPERATOR_VERSION CLUSTER_DOMAIN VALKEY_NS \
SENTINEL_NAME REPL_NAME MASTER_GROUP VALKEY_VERSION VALKEY_TARGET_VERSION STORAGE_SIZE SERVICE_TYPE \
MONITORING_NS MINIO_NS BACKUP_BUCKET DR_NS VALKEY_DEFAULT_PASSWORD VALKEY_ADMIN_PASSWORD \
VALKEY_APP_PASSWORD VALKEY_MONITOR_PASSWORD SENTINEL_PASSWORD COMMANDER_PASSWORD MINIO_ROOT_PASSWORD \
VALKEY_IMAGE DR_SOURCE_HOST SENTINEL_HOST"

export PATH="${WORKSHOP_HOME}/scripts:${PATH}"

# Helper functions: vcli, scli, repl_pods, sentinel_pods, primary_pod, ...
# shellcheck source=scripts/lib.sh
. "${WORKSHOP_HOME}/scripts/lib.sh"

echo "Workshop environment loaded (WORKSHOP_HOME=${WORKSHOP_HOME})"
echo "  Valkey namespace : ${VALKEY_NS}   Sentinel: ${SENTINEL_NAME}   Replication: ${REPL_NAME}"
echo "  kube context     : $(kubectl config current-context 2>/dev/null || echo '<none>')"
