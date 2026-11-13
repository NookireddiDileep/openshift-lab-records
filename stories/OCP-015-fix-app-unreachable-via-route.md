# OCP-015: Fix an application that can't be reached over its Route URL (shared-cluster troubleshooting task)

| Field | Value |
|---|---|
| **Type** | Bug / Troubleshooting task |
| **Area** | Routes · Services · Endpoints · DNS · Team coordination |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~15 min |
| **Status** | Done |
| **RCA** | [RCA-003 – route unreachable, three faults](../rca/RCA-003-route-unreachable-three-faults.md) |

## 1. User story / requirement
> As an **application owner**, I can't open my application in a browser using its Route URL. **Check and fix the issues** so the application is reachable over the browser via its Route URL.

Context: eight pre-built training projects (`project-01` … `project-08`), each with a broken application. Team members claim one project at a time in a group chat and fix it.

## 2. Acceptance criteria
- [x] Claimed an unassigned project before making changes
- [x] Root cause(s) identified with evidence (not guessed)
- [x] Application reachable via its Route URL from **curl** (`HTTP 200`, correct page title)
- [x] Application reachable via its Route URL in a **browser**
- [x] Changes minimal, backed up, and documented → [RCA-003](../rca/RCA-003-route-unreachable-three-faults.md)

## 3. Background / concepts
Request path for an OpenShift Route – every hop must line up:
```
Browser ─DNS─► *.apps.<cluster-domain> ─► Router (HAProxy) ─► Route (host) ─► Service (selector) ─► Endpoints ─► Pod :port
```
| Hop | Must match | Symptom when it doesn't |
|---|---|---|
| DNS | Route host is inside the wildcard `*.apps.<cluster-domain>` | browser "can't resolve" / curl `000` |
| Route → Service | `spec.to.name` = an existing Service | router `503 Application is not available` |
| Route → Service port | `spec.port.targetPort` = Service port name/number | `503` |
| Service → Pods | `spec.selector` ⊆ Pod labels | `ENDPOINTS <none>` → `503` |
| Service → container | `targetPort` = port the app listens on | `502` / connection refused |

## 4. Plan
1. **Coordinate:** claim a project in the group; work only in it (`-n $PRJ` on every command).
2. **Find a genuinely broken project:** read-only sweep of all eight Routes.
3. **Triage read-only, outside → in**; list *all* faults before fixing.
4. **Back up**, then fix inside → out with the smallest changes, verifying each.
5. Verify with curl and a browser; report back in the group.

## 5. Implementation
**Project selection.** First pick (`project-06`) was already healthy (`HTTP 200`) – likely fixed earlier or never broken. A read-only sweep found the broken ones:
```bash
for i in 01 02 03 04 05 06 07 08; do
  H=$(oc get route -n project-$i -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
  echo "project-$i  $H  HTTP $(curl -s -o /dev/null -m 5 -w '%{http_code}' http://$H/)"
done
```
```
project-01..04   (malformed hosts)   HTTP 000      ← broken
project-05..08                       HTTP 200      ← working
```
Claimed **`project-03`** (unassigned, most faults).

**Triage** with [`scripts/RCA-003/route-triage.sh`](../scripts/RCA-003/route-triage.sh) found three faults:
1. Route host misspelled (and using another project's `app4` name) → DNS doesn't resolve
2. Route targets Service `web_app`, which doesn't exist (Service is `web-app`)
3. Service selector `app=web_app` ≠ Pod label `app=web-app` → `ENDPOINTS <none>`

**Fix** (details and full evidence in [RCA-003](../rca/RCA-003-route-unreachable-three-faults.md)):
```bash
oc get svc,route -n project-03 -o yaml > project-03-before.yaml
oc patch svc web-app -n project-03 --type=merge -p '{"spec":{"selector":{"app":"web-app"}}}'
oc patch route web-route -n project-03 --type=merge \
  -p '{"spec":{"host":"app3.apps.<cluster-domain>","to":{"name":"web-app"}}}'
```

## 6. Validation / evidence
```
ENDPOINTS:  <pod-ip>:9001                              ← was <none>
ROUTE:      app3.apps.<cluster-domain>  web-app  8080-9001  ADMITTED=True
DNS:        <router-node-ip>  app3.apps.<cluster-domain>
curl:       HTTP 200   <title>Etherpad</title>
Browser:    Etherpad loads and opens a pad ("Not secure" – plain HTTP)
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | First claimed project was already working | Shared cluster – others may have fixed it. Verified state before touching anything, then released it |
| 2 | Three independent faults in one app | Fixing only the visible one (hostname) would still have given a 503 |
| 3 | Two faults were hyphen vs. underscore | Kubernetes names can't contain `_`, but label **values** and a Route's `to.name` field accept any string – so the mismatch wasn't rejected at creation |
| 4 | Kept the host as `app3`, not `app4` | Route hosts must be unique; `app4` belongs to `project-04` |
| 5 | Browser shows "Not secure"; pad text warns about DirtyDB | Plain-HTTP route (add edge TLS); ephemeral data store (see [OCP-004](OCP-004-third-party-image-etherpad.md)) |
| 6 | `project-06` / `project-07` were already healthy when checked | Reported back to the trainer in case faults were expected there |

## 8. Production considerations
- In a shared environment: **claim → back up → change → verify → report**. Never edit someone else's namespace.
- Keep Route, Service and Deployment in **one manifest set** with shared labels; validate selectors and route targets in CI.
- Alert on **Services with zero endpoints** and run synthetic checks per Route.
- Use TLS routes for anything user-facing.

## 9. Lessons learned
- Read-only triage first, fixes second – and list all faults before fixing any.
- `ENDPOINTS <none>` and `getent hosts` are the two fastest signals for route problems.
- Team coordination is part of the fix on shared infrastructure.

## 10. Interview talking point
> "On a shared training cluster I claimed a broken project, confirmed it was really broken with a read-only sweep of all the routes, and triaged from the outside in. There were three faults: a misspelled hostname outside the wildcard DNS, a route pointing at a Service name that didn't exist, and a Service selector that didn't match the Pod labels. I backed up the objects, fixed them with two patches, and verified with curl and a browser – then reported back to the team. The full RCA has the five whys and preventive actions."
