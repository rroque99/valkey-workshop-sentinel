#!/usr/bin/env bash
# Render a manifest template by substituting ONLY the variables listed in
# $WORKSHOP_VARS (see env.sh). Other "$..." strings are left untouched.
#
#   render.sh manifests/03-sentinel/valkey-sentinel.yaml | kubectl apply -f -
set -euo pipefail

if [ -z "${WORKSHOP_VARS:-}" ]; then
  echo "WORKSHOP_VARS is not set. Run 'source ./env.sh' first." >&2
  exit 1
fi
if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst not found (install the 'gettext' package)." >&2
  exit 1
fi

shell_format=""
for v in ${WORKSHOP_VARS}; do
  shell_format="${shell_format} \${${v}}"
done

for f in "$@"; do
  envsubst "${shell_format}" < "$f"
  echo "---"
done
