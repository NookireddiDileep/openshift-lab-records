#!/usr/bin/env bash
# OCP-021: run a root-only httpd image safely and make its page content survive restarts
set -euo pipefail
IMG=docker.io/<user>/my-demo-app:v2.0.0          # tags are case-sensitive: check with `skopeo list-tags`
MSG='<h1>Hello <Company></h1>'

skopeo list-tags docker://${IMG%:*}               # confirm the tag exists before deploying
oc create deployment app-07 --image="$IMG"

# image needs root (pid file in root-only /run/httpd, port 80) → dedicated SA with anyuid, never 'default'
oc create sa app-07-sa
oc adm policy add-scc-to-user anyuid -z app-07-sa
oc set serviceaccount deployment/app-07 app-07-sa

# content from a ConfigMap, mounted by the Deployment into every Pod (not edited inside a container)
oc create configmap app-07-html --from-literal=index.html="$MSG"
oc set volume deployment/app-07 --add --name=html --type=configmap \
  --configmap-name=app-07-html --mount-path=/var/www/html
oc rollout status deployment/app-07

for i in 1 2 3; do
  oc delete pod -l app=app-07 --wait=true >/dev/null; oc rollout status deployment/app-07 >/dev/null
  echo "after delete #$i: $(oc exec deploy/app-07 -- curl -s localhost:80)"
done
oc expose deployment app-07 --port=80 && oc expose service/app-07
