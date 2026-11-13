#!/usr/bin/env bash
# OCP-020: give app-03 (Etherpad) a dynamically provisioned 1Gi volume for its data, then prove persistence
set -euo pipefail
APP=app-03
# single writer on one data file: never run old + new Pod together
oc patch deployment "$APP" --type=merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
# PVC is created by this command; no StorageClass named → the cluster's default class provisions it
oc set volume deployment/"$APP" --add --name=etherpad-data \
  --type=pvc --claim-name=app-03-data --claim-size=1Gi --claim-mode=rwo \
  --mount-path=/opt/etherpad-lite/var
oc rollout status deployment/"$APP" --timeout=180s
oc get pvc app-03-data

# persistence test through the application's own API and export (key read inside the Pod, never printed)
R=$(oc get route "$APP" -o jsonpath='{.spec.host}')
KEY=$(oc exec deploy/"$APP" -- cat /opt/etherpad-lite/APIKEY.txt)
curl -s "http://$R/api/1/setText" --data-urlencode "apikey=$KEY" --data-urlencode "padID=nooki-pad" \
     --data-urlencode "text=persistence test $(date -u +%H:%M)"; echo
curl -s "http://$R/p/nooki-pad/export/txt"
oc delete pod -l app="$APP" && oc rollout status deployment/"$APP" --timeout=180s && sleep 6
curl -s "http://$R/p/nooki-pad/export/txt"
