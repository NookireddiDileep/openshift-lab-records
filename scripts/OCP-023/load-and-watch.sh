#!/usr/bin/env bash
# OCP-023: generate CPU load in one Pod for 3 min and watch the HPA for ~9 min
set -euo pipefail
POD=$(oc get pod -l app=hpa-app -o jsonpath='{.items[0].metadata.name}')
echo "burning CPU in $POD for 180 s"
oc exec "$POD" -- timeout 180 sha256sum /dev/zero >/dev/null 2>&1 &
for i in $(seq 1 27); do
  # jsonpath, not column numbers: TARGETS ("cpu: 2%/60%") contains a space and shifts awk columns
  oc get hpa hpa-app -o jsonpath="{.metadata.name} $(date +%H:%M:%S)  cpu={.status.currentMetrics[0].resource.current.averageUtilization}%  replicas={.status.currentReplicas}  desired={.status.desiredReplicas}{'\n'}"
  sleep 20
done
wait || true
oc get events --field-selector involvedObject.kind=HorizontalPodAutoscaler,involvedObject.name=hpa-app \
  --sort-by=.lastTimestamp -o custom-columns=TIME:.lastTimestamp,REASON:.reason,MESSAGE:.message
