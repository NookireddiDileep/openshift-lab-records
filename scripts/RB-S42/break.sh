#!/usr/bin/env bash
# RB-S42: build a healthy app that reads its config from a ConfigMap + Secret, then inject ONE fault.
# usage: ./break.sh [a|b|c]
#   a = ConfigMap name typo   b = ConfigMap key typo   c = Secret name typo   (default: a)
# Works only in the CURRENT project. Objects are all named rca-s42-*.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
FAULT=${1:-a}
echo "Project: $PROJECT   Fault: $FAULT"

echo ">> Creating ConfigMap rca-s42-config and Secret rca-s42-db (if missing)"
oc get configmap rca-s42-config >/dev/null 2>&1 || oc create configmap rca-s42-config --from-literal=APP_MODE=lab
oc get secret rca-s42-db >/dev/null 2>&1 || oc create secret generic rca-s42-db --from-literal=DB_PASSWORD=not-a-real-password

if ! oc get deployment rca-s42-web >/dev/null 2>&1; then
  echo ">> Creating a healthy Deployment rca-s42-web (env from the ConfigMap and the Secret)"
  oc apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rca-s42-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rca-s42-web
  template:
    metadata:
      labels:
        app: rca-s42-web
    spec:
      containers:
        - name: web
          image: registry.access.redhat.com/ubi9/httpd-24:latest
          ports:
            - containerPort: 8080
          env:
            - name: APP_MODE
              valueFrom:
                configMapKeyRef:
                  name: rca-s42-config
                  key: APP_MODE
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: rca-s42-db
                  key: DB_PASSWORD
YAML
  oc rollout status deployment/rca-s42-web --timeout=180s
fi

echo ">> Saving a backup of the healthy Deployment to rca-s42-backup.yaml"
oc get deployment rca-s42-web -o yaml >rca-s42-backup.yaml

case "$FAULT" in
  a) PATH_OP='/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/name'; VALUE='rca-s42-confg' ;;
  b) PATH_OP='/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key'; VALUE='APP_MODEE' ;;
  c) PATH_OP='/spec/template/spec/containers/0/env/1/valueFrom/secretKeyRef/name'; VALUE='rca-s42-dbb' ;;
  *) echo "Unknown fault '$FAULT' (use a, b or c)" >&2; exit 2 ;;
esac

echo ">> Injecting the fault: $PATH_OP -> $VALUE"
oc patch deployment rca-s42-web --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"$PATH_OP\",\"value\":\"$VALUE\"}]"

echo ">> Done. Watch it fail with:  oc get pods -w   (expect CreateContainerConfigError on the new pod)"
