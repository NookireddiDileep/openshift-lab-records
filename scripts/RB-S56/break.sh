#!/usr/bin/env bash
# RB-S56: deploy a slow-starting app (takes ~45 s to listen) guarded by an over-eager liveness probe.
# usage: ./break.sh
# Works only in the CURRENT project. Objects are all named rca-s56-*.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Creating Deployment rca-s56-slow: the container sleeps 45 s before httpd starts listening,"
echo "   liveness probe = GET / :8080, first check after 5 s, every 5 s, 3 failures allowed (~20 s budget)"
oc apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rca-s56-slow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rca-s56-slow
  template:
    metadata:
      labels:
        app: rca-s56-slow
    spec:
      terminationGracePeriodSeconds: 5
      containers:
        - name: web
          image: registry.access.redhat.com/ubi9/httpd-24:latest
          args: ["/bin/sh", "-c", "echo 'simulating slow start'; sleep 45; exec /usr/bin/run-httpd"]
          ports:
            - containerPort: 8080
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 1
            failureThreshold: 3
YAML

echo ">> Done. Watch the restart loop with:  oc get pods -l app=rca-s56-slow -w"
