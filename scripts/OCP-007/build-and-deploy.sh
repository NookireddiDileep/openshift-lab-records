#!/usr/bin/env bash
# OCP-007: build my own image inside OpenShift (Docker strategy, binary input) and deploy it
set -euo pipefail
APP=app-04
oc new-build --name="$APP" --strategy=docker --binary
oc start-build "$APP" --from-dir=. --follow
oc get istag "$APP:latest"
oc new-app --image-stream="$APP:latest" --name="$APP"
oc rollout status "deployment/$APP"
POD=$(oc get pod -l deployment="$APP" -o jsonpath='{.items[0].metadata.name}')
oc exec "$POD" -- curl -s localhost:8080 | grep -E "<h1>|Version"
