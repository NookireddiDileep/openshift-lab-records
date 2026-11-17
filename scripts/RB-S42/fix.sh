#!/usr/bin/env bash
# RB-S42: put the three references back to the correct names/keys (what you'd do by hand after triage).
# Works only in the CURRENT project; touches only rca-s42-* objects.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'." >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo ">> Re-pointing the env references at rca-s42-config/APP_MODE and rca-s42-db/DB_PASSWORD"
oc patch deployment rca-s42-web --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/name","value":"rca-s42-config"},
  {"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key","value":"APP_MODE"},
  {"op":"replace","path":"/spec/template/spec/containers/0/env/1/valueFrom/secretKeyRef/name","value":"rca-s42-db"}
]'
oc rollout status deployment/rca-s42-web --timeout=180s
