#!/usr/bin/env bash
# RB-S18: check the memory settings, restart count, last state and QoS class of the report pod.
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

echo ">> Resources now configured"
oc get deployment rca-s18-report -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
echo ">> Pod status (expect 1/1 Running; RESTARTS must stop growing)"
oc get pods -l app=rca-s18-report
echo ">> Restart count and last terminated reason per pod (OOMKilled only on old pods)"
oc get pods -l app=rca-s18-report \
  -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[0].restartCount}{" lastReason="}{.status.containerStatuses[0].lastState.terminated.reason}{" qos="}{.status.qosClass}{"\n"}{end}'
echo ">> Memory usage (needs cluster metrics; may take a minute to appear)"
oc adm top pod -l app=rca-s18-report --containers || true
echo ">> Rollout status"
oc rollout status deployment/rca-s18-report --timeout=60s
