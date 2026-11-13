#!/usr/bin/env bash
# RCA-003: read-only triage for "app not reachable via its Route" – follows the request path outside -> in
# usage: ./route-triage.sh <namespace>
set -uo pipefail
NS=${1:?namespace}
echo "== Route";     oc get route -n "$NS" -o custom-columns=NAME:.metadata.name,HOST:.spec.host,SVC:.spec.to.name,PORT:.spec.port.targetPort,TLS:.spec.tls.termination,ADMITTED:.status.ingress[0].conditions[0].status
H=$(oc get route -n "$NS" -o jsonpath='{.items[0].spec.host}')
echo "== DNS";       getent hosts "$H" || echo "DNS: $H does not resolve"
echo "== HTTP";      curl -s -o /dev/null -m 5 -w '%{http_code}\n' "http://$H/" || true
echo "== Service";   oc get svc -n "$NS" -o custom-columns=NAME:.metadata.name,SELECTOR:.spec.selector,PORT:.spec.ports[*].port,TARGETPORT:.spec.ports[*].targetPort,PORTNAME:.spec.ports[*].name
SVC=$(oc get route -n "$NS" -o jsonpath='{.items[0].spec.to.name}')
oc get svc "$SVC" -n "$NS" >/dev/null 2>&1 || echo "!! Route points to Service '$SVC' which does NOT exist"
echo "== Endpoints"; oc get endpoints -n "$NS"
echo "== Pods";      oc get pods -n "$NS" --show-labels
P=$(oc get pod -n "$NS" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -n "$P" ] && { echo "== Listening ports (hex) in $P"; oc exec -n "$NS" "$P" -- sh -c 'cat /proc/net/tcp | awk "NR>1 && \$4==\"0A\" {print \$2}"'; }
