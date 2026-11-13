#!/usr/bin/env bash
# OCP-017: safe Blue-Green switch – test the target first, switch the Route, verify, keep rollback ready
# usage: ./switch.sh <bg-green|bg-blue>
set -euo pipefail
TARGET=${1:?target service: bg-green or bg-blue}
ROUTE=bg
LIVE=$(oc get route "$ROUTE" -o jsonpath='{.spec.host}')
CURRENT=$(oc get route "$ROUTE" -o jsonpath='{.spec.to.name}')
[ "$CURRENT" = "$TARGET" ] && { echo "already live on $TARGET"; exit 0; }

# 1) target must have ready endpoints
[ -n "$(oc get endpoints "$TARGET" -o jsonpath='{.subsets[*].addresses[*].ip}')" ] || { echo "no ready endpoints for $TARGET"; exit 1; }

# 2) smoke-test the target through its own test route (wait out the router reload interval)
TEST_HOST=$(oc get route "${TARGET}-test" -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [ -n "$TEST_HOST" ]; then
  for i in $(seq 1 10); do curl -sf -m 2 "http://$TEST_HOST/" >/dev/null && break; sleep 1; done
  curl -sf -m 2 "http://$TEST_HOST/" >/dev/null || { echo "smoke test failed on $TEST_HOST"; exit 1; }
fi

# 3) switch
oc patch route "$ROUTE" --type=merge -p "{\"spec\":{\"to\":{\"name\":\"$TARGET\"}}}"
echo "switched $ROUTE: $CURRENT -> $TARGET (rollback: $0 $CURRENT)"

# 4) verify (router reloads every ~5 s)
for i in $(seq 1 10); do curl -s -m 2 "http://$LIVE/" | grep -o '<h1>.*</h1>'; sleep 1; done | sort | uniq -c
