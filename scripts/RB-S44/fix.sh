#!/usr/bin/env bash
# RB-S44: rewrite the Secret value correctly (stringData lets the API server do the base64),
# then restart the Deployment because env vars are read only at container start.
# Works only in the CURRENT project; touches only rca-s44-* objects.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

REAL_PASSWORD='S3cr3t-pass'   # lab-only dummy value

echo ">> Re-writing the Secret value with stringData (no manual base64, no newline)"
oc patch secret rca-s44-db --type=merge \
  -p "{\"stringData\":{\"DB_PASSWORD\":\"$REAL_PASSWORD\"}}"

echo ">> Restarting so the env var is re-read from the Secret"
oc rollout restart deployment/rca-s44-client
oc rollout status deployment/rca-s44-client --timeout=180s
