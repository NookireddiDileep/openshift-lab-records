#!/usr/bin/env bash
# RB-S56: check that the app starts once and stays up.
# usage: ./verify.sh
# Read-only; works only in the CURRENT project.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Pods (expect 1/1 Running, RESTARTS 0)"
oc get pods -l app=rca-s56-slow
echo ">> Restart count and last termination reason"
oc get pods -l app=rca-s56-slow \
  -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[0].restartCount}{" lastState="}{.status.containerStatuses[0].lastState}{"\n"}{end}'
echo ">> Recent Unhealthy/Killing events (expect none newer than the rollout)"
oc get events --field-selector reason=Unhealthy --sort-by=.lastTimestamp | tail -n 5 || true
echo ">> Rollout status"
oc rollout status deployment/rca-s56-slow --timeout=60s
