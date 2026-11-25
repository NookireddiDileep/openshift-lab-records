#!/usr/bin/env bash
# RB-S43: build an app that reads APP_MODE (env var) and /config/app.properties (mounted file)
# from ONE ConfigMap, then change the ConfigMap. The env var stays stale; the file updates.
# Works only in the CURRENT project. Objects are all named rca-s43-*.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

if ! oc get deployment rca-s43-web >/dev/null 2>&1; then
  echo ">> Creating ConfigMap rca-s43-config (APP_MODE=blue, app.properties with mode=blue)"
  oc create configmap rca-s43-config \
    --from-literal=APP_MODE=blue \
    --from-literal=app.properties="mode=blue"
  echo ">> Creating Deployment rca-s43-web (env var AND mounted file from the same ConfigMap)"
  oc apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rca-s43-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rca-s43-web
  template:
    metadata:
      labels:
        app: rca-s43-web
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
                  name: rca-s43-config
                  key: APP_MODE
          volumeMounts:
            - name: cfg
              mountPath: /config
      volumes:
        - name: cfg
          configMap:
            name: rca-s43-config
YAML
  oc rollout status deployment/rca-s43-web --timeout=180s
fi

echo ">> Saving a backup of the ConfigMap to rca-s43-backup.yaml"
oc get configmap rca-s43-config -o yaml >rca-s43-backup.yaml

echo ">> Changing the ConfigMap: blue -> green (this is the 'config change' from the ticket)"
oc patch configmap rca-s43-config --type=merge \
  -p '{"data":{"APP_MODE":"green","app.properties":"mode=green"}}'

echo ">> Done. Now compare (the file may take up to ~1-2 min to update):"
echo "   oc exec deployment/rca-s43-web -- printenv APP_MODE          # still blue"
echo "   oc exec deployment/rca-s43-web -- cat /config/app.properties # becomes mode=green"
