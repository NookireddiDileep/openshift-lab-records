#!/usr/bin/env bash
# OCP-018: progressive canary on one Route – set weights, wait for the router, measure
# usage: ./canary.sh <v1-weight> <v2-weight>     e.g. ./canary.sh 80 20
set -euo pipefail
W1=${1:?v1 weight}; W2=${2:?v2 weight}
ROUTE=split-app
oc set route-backends "$ROUTE" "v1-app=$W1" "v2-app=$W2"
oc set route-backends "$ROUTE"
sleep 7                                   # router RELOAD_INTERVAL is 5s (OCP-017)
H=$(oc get route "$ROUTE" -o jsonpath='{.spec.host}')
for i in $(seq 1 100); do curl -s -m 2 "http://$H/" | grep -o 'version [12]' || echo ERROR; done | sort | uniq -c
