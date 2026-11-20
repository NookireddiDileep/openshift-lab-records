#!/usr/bin/env bash
# RB-S57: make the frontend liveness probe check only the frontend itself (own port), add a shallow readiness probe.
# usage: ./fix.sh
# Works only in the CURRENT project; touches only deployment/rca-s57-front.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Replacing the dependency-checking liveness probe with GET / on the frontend's own port 8080"
echo ">> Adding a readiness probe on the same endpoint (shallow: no dependency check)"
oc patch deployment rca-s57-front --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe",
   "value":{"httpGet":{"path":"/","port":8080},"initialDelaySeconds":10,"periodSeconds":10,"timeoutSeconds":3,"failureThreshold":3}},
  {"op":"add","path":"/spec/template/spec/containers/0/readinessProbe",
   "value":{"httpGet":{"path":"/","port":8080},"periodSeconds":5,"timeoutSeconds":2,"failureThreshold":3}}
]'
echo ">> Waiting for the rollout (the database stays DOWN on purpose, the frontend must stay up)"
oc rollout status deployment/rca-s57-front --timeout=180s
