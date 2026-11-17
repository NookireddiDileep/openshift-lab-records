#!/usr/bin/env bash
# RB-S42: read-only checks that the fix worked. Works only in the CURRENT project.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'." >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo "== Pods (expect 1/1 Running, no CreateContainerConfigError)"
oc get pods -l app=rca-s42-web
echo "== Rollout"
oc rollout status deployment/rca-s42-web --timeout=60s
echo "== APP_MODE as seen inside the container (expect: lab)"
oc exec deployment/rca-s42-web -- printenv APP_MODE
echo "== DB_PASSWORD is set? (value deliberately not printed)"
oc exec deployment/rca-s42-web -- sh -c 'test -n "$DB_PASSWORD" && echo yes || echo NO'
echo "== Recent warnings (expect none from the new pod)"
oc get events --field-selector type=Warning --sort-by=.lastTimestamp | tail -5 || true
