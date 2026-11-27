#!/usr/bin/env bash
# RB-S18: size the memory from the measured peak (~200 MiB): request 256Mi, limit 384Mi.
# usage: ./fix.sh
# Works only in the CURRENT project; touches only deployment/rca-s18-report.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Setting requests cpu=50m,memory=256Mi and limits cpu=500m,memory=384Mi"
oc set resources deployment/rca-s18-report \
  --requests=cpu=50m,memory=256Mi --limits=cpu=500m,memory=384Mi
echo ">> Waiting for the rollout"
oc rollout status deployment/rca-s18-report --timeout=180s
