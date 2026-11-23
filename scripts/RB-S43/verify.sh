#!/usr/bin/env bash
# RB-S43: read-only checks that the env var and the mounted file now agree.
# Works only in the CURRENT project.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo "== ConfigMap value (the source of truth)"
oc get configmap rca-s43-config -o jsonpath='{.data.APP_MODE}{"\n"}'
echo "== Env var as seen inside the running container"
oc exec deployment/rca-s43-web -- printenv APP_MODE
echo "== Mounted file as seen inside the running container"
oc exec deployment/rca-s43-web -- cat /config/app.properties
echo "== Pod start time (a fresh pod after the restart means the env var was re-read)"
oc get pods -l app=rca-s43-web -o custom-columns=NAME:.metadata.name,STARTED:.status.startTime
