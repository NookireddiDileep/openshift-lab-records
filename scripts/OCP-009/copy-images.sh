#!/usr/bin/env bash
# OCP-009: copy container images into my project's space in the OpenShift internal registry.
# Uses methods that copy blobs registry-to-registry (no local unpacking, works for rootless users without subuid).
set -euo pipefail
REG=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
NS=$(oc project -q)
oc registry login --skip-check

# 1) oc image mirror – OpenShift's registry-to-registry copy
oc image mirror registry.access.redhat.com/ubi9/httpd-24:latest \
  "$REG/$NS/ubi9-httpd:mirrored" --insecure=true --keep-manifest-list=false   # --insecure: lab self-signed route cert only

# 2) skopeo copy – same idea, generic tool
skopeo copy docker://docker.io/library/nginx:alpine "docker://$REG/$NS/nginx:copied" \
  --dest-tls-verify=false --override-os linux --override-arch amd64           # lab only: self-signed cert

# verify: copied images resolve to the INTERNAL registry
for t in ubi9-httpd:mirrored nginx:copied; do
  oc get istag "$t" -o jsonpath='{.image.dockerImageReference}{"\n"}'
done
