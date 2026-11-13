#!/usr/bin/env bash
# OCP-010: build an image locally with podman, push it to the OpenShift internal registry, deploy it two ways.
set -euo pipefail
REG=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
NS=$(oc project -q)
IMG="$REG/$NS/test-app:1.0"
# ignore_chown_errors: only because this host's user has no subuid/subgid ranges (see RCA-001)
PODMAN=(podman --storage-opt ignore_chown_errors=true)

"${PODMAN[@]}" build -t "$IMG" .
oc whoami -t | podman login -u "$(oc whoami)" --password-stdin "$REG" --tls-verify=false   # lab: self-signed route cert
"${PODMAN[@]}" push "$IMG" --tls-verify=false

oc set image-lookup test-app                                   # short name usable by plain Deployments
oc new-app --image-stream=test-app:1.0 --name=app-06           # OpenShift way: digest + trigger + Service
oc create deployment test-app \
  --image="image-registry.openshift-image-registry.svc:5000/$NS/test-app:1.0"   # Kubernetes way: tag as typed, no Service
oc rollout status deployment/app-06
oc rollout status deployment/test-app
