#!/usr/bin/env bash
# RB-S56: add a startupProbe with a generous budget (30 x 5 s = 150 s) and keep the liveness probe tight.
# usage: ./fix.sh
# Works only in the CURRENT project; touches only deployment/rca-s56-slow.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Adding startupProbe (GET / :8080, every 5 s, up to 30 failures = 150 s to start)"
oc patch deployment rca-s56-slow --type=json -p '[
  {"op":"add","path":"/spec/template/spec/containers/0/startupProbe",
   "value":{"httpGet":{"path":"/","port":8080},"periodSeconds":5,"failureThreshold":30}},
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":0}
]'
echo ">> Waiting for the rollout (the app needs ~45 s to start)"
oc rollout status deployment/rca-s56-slow --timeout=240s
