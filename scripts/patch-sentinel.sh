#!/usr/bin/env bash
# Apply a merge-patch template to the workshop ValkeySentinel CR.
#   patch-sentinel.sh manifests/06-tools/04-admin-patch.yaml
set -euo pipefail
: "${SENTINEL_NAME:?Run 'source ./env.sh' first}"
patch="$("${WORKSHOP_HOME}/scripts/render.sh" "$1" | sed -e '/^---$/d' -e '/^[[:space:]]*#/d')"
echo "Patching valkeysentinel/${SENTINEL_NAME} in ${VALKEY_NS} with:"
echo "${patch}" | sed 's/^/    /'
kubectl patch valkeysentinel "${SENTINEL_NAME}" -n "${VALKEY_NS}" --type merge -p "${patch}"
