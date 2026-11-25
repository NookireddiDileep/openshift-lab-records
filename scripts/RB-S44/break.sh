#!/usr/bin/env bash
# RB-S44: store a database password in a Secret the WRONG way, then watch the "login" fail.
# Usage: ./break.sh [newline|double]   (default: newline)
#   newline : password encoded with 'echo | base64'  -> hidden trailing newline
#   double  : password base64-encoded twice          -> app receives the base64 text
# The "database" is a tiny check in the pod that compares DB_PASSWORD with the real password.
# Works only in the CURRENT project. Objects are all named rca-s44-*.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

VARIANT="${1:-newline}"
REAL_PASSWORD='S3cr3t-pass'   # lab-only dummy value, the password the "database" expects

case "$VARIANT" in
  newline) ENCODED=$(echo "$REAL_PASSWORD" | base64 -w0) ;;           # echo adds a newline
  double) ENCODED=$(printf '%s' "$REAL_PASSWORD" | base64 -w0 | base64 -w0) ;;
  *)
    echo "Unknown variant '$VARIANT' (use newline or double)" >&2
    exit 1
    ;;
esac

echo ">> Creating Secret rca-s44-db with the '$VARIANT' mistake (value written under data:)"
oc apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: rca-s44-db
type: Opaque
data:
  DB_PASSWORD: $ENCODED
YAML

echo ">> Creating Deployment rca-s44-client (stands in for the app logging in to the database)"
oc apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rca-s44-client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rca-s44-client
  template:
    metadata:
      labels:
        app: rca-s44-client
    spec:
      containers:
        - name: client
          image: registry.access.redhat.com/ubi9/ubi-minimal:latest
          command:
            - /bin/sh
            - -c
            - |
              while true; do
                if [ "$DB_PASSWORD" = "S3cr3t-pass" ]; then
                  echo "login OK"
                else
                  echo "ERROR 1045 (28000): Access denied for user 'app' (using password: YES)"
                fi
                sleep 10
              done
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: rca-s44-db
                  key: DB_PASSWORD
YAML
oc rollout status deployment/rca-s44-client --timeout=180s

echo ">> Done. Now look at the symptom:"
echo "   oc logs deployment/rca-s44-client --tail=3"
