#!/usr/bin/env bash
# RB-S57: check that the frontend stays up and stops restarting while the database is still down.
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

echo ">> Database replicas (expect 0 before the recovery step, so the outage is still in place)"
oc get deployment rca-s57-db
echo ">> Frontend pods (expect 2/2 Running; RESTARTS must stop growing)"
oc get pods -l app=rca-s57-front
echo ">> Restart counts per pod"
oc get pods -l app=rca-s57-front \
  -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
echo ">> Probes now configured on the frontend"
oc get deployment rca-s57-front -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}{"\n"}{.spec.template.spec.containers[0].readinessProbe}{"\n"}'
echo ">> Recent Unhealthy events (none should be newer than the fix)"
oc get events --field-selector reason=Unhealthy --sort-by=.lastTimestamp | tail -n 5 || true
echo ">> Rollout status"
oc rollout status deployment/rca-s57-front --timeout=60s
