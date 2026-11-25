#!/usr/bin/env bash
# RB-S57: deploy a "database" stand-in + a 2-replica frontend whose liveness probe checks the database,
# then simulate a database outage (scale it to 0). The frontend pods start restarting even though they are healthy.
# usage: ./break.sh
# Works only in the CURRENT project. Objects are all named rca-s57-*.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Creating rca-s57-db (an httpd stand-in for a database, listening on 8080) and its Service"
oc apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rca-s57-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rca-s57-db
  template:
    metadata:
      labels:
        app: rca-s57-db
    spec:
      containers:
        - name: db
          image: registry.access.redhat.com/ubi9/httpd-24:latest
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: rca-s57-db
spec:
  selector:
    app: rca-s57-db
  ports:
    - port: 8080
      targetPort: 8080
YAML

echo ">> Creating rca-s57-front (2 replicas). Its liveness probe opens a TCP connection to the database"
echo "   Service every 10 s (bash /dev/tcp), 3 failures allowed: this is the mistake."
oc apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rca-s57-front
spec:
  replicas: 2
  selector:
    matchLabels:
      app: rca-s57-front
  template:
    metadata:
      labels:
        app: rca-s57-front
    spec:
      terminationGracePeriodSeconds: 5
      containers:
        - name: web
          image: registry.access.redhat.com/ubi9/httpd-24:latest
          ports:
            - containerPort: 8080
          livenessProbe:
            exec:
              command:
                - /bin/bash
                - -c
                - "timeout 2 bash -c 'exec 3<>/dev/tcp/rca-s57-db/8080'"
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
YAML

echo ">> Waiting for both Deployments to be healthy (the database is up, so the probe passes)"
oc rollout status deployment/rca-s57-db --timeout=180s
oc rollout status deployment/rca-s57-front --timeout=180s

echo ">> Simulating the database outage: scaling rca-s57-db to 0"
oc scale deployment/rca-s57-db --replicas=0

echo ">> Done. Watch the frontend restarts (about 30-40 s after the outage starts):"
echo "   oc get pods -l app=rca-s57-front -w"
