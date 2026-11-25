#!/usr/bin/env bash
# RB-S44: read-only checks of the stored value and of what the container sees.
# Prints byte counts rather than the password itself.
# Works only in the CURRENT project.
set -euo pipefail

PROJECT=$(oc project -q)
case "$PROJECT" in
  default | openshift-* | kube-*)
    echo "Refusing to run in project '$PROJECT'. Switch to your own project: oc new-project <name>" >&2
    exit 1
    ;;
esac
echo "Project: $PROJECT"

echo "== Length of the value stored in the Secret after ONE base64 decode (expect 11 for S3cr3t-pass)"
oc get secret rca-s44-db -o jsonpath='{.data.DB_PASSWORD}' | base64 -d | wc -c
echo "== Last byte of the decoded value (a trailing newline prints as \\n)"
oc get secret rca-s44-db -o jsonpath='{.data.DB_PASSWORD}' | base64 -d | tail -c 1 | od -An -c
echo "== Length of DB_PASSWORD as the running container sees it (expect 11)"
oc exec deployment/rca-s44-client -- sh -c 'printf %s "$DB_PASSWORD" | wc -c'
echo "== Latest client log lines"
oc logs deployment/rca-s44-client --tail=3
