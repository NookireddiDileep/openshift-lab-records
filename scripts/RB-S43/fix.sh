#!/usr/bin/env bash
# RB-S43: restart the Deployment so new pods read the current ConfigMap values.
# Works only in the CURRENT project; touches only rca-s43-* objects.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Rolling restart so APP_MODE is re-read from the ConfigMap at container start"
oc rollout restart deployment/rca-s43-web
oc rollout status deployment/rca-s43-web --timeout=180s
