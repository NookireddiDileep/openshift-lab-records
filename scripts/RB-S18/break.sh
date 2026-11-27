#!/usr/bin/env bash
# RB-S18: deploy a "report generator" stand-in that needs ~200 MiB of memory but has a 128 MiB limit,
# so the kernel OOM-kills the container again and again (OOMKilled, exit code 137).
# usage: ./break.sh
# Works only in the CURRENT project. Object is named rca-s18-report.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Creating rca-s18-report: allocates 10 MiB per second up to ~200 MiB, memory limit 128Mi (the mistake)"
oc apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rca-s18-report
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rca-s18-report
  template:
    metadata:
      labels:
        app: rca-s18-report
    spec:
      containers:
        - name: report
          image: registry.access.redhat.com/ubi9/python-311:latest
          command: ["python3", "-u", "-c"]
          args:
            - |
              import time
              held = []
              for i in range(20):
                  held.append(b"x" * (10 * 1024 * 1024))
                  print("loaded %d MiB" % ((i + 1) * 10))
                  time.sleep(1)
              print("batch loaded, holding memory")
              while True:
                  time.sleep(60)
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 128Mi
YAML

echo ">> Done. Watch it get OOM-killed (about 12-15 s after each start):"
echo "   oc get pods -l app=rca-s18-report -w"
echo "   oc describe pod -l app=rca-s18-report | grep -A6 'Last State'"
