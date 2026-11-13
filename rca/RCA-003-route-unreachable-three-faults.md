# RCA-003: Application unreachable via its Route – three configuration faults (host, Route→Service, Service→Pod)

| Field | Value |
|---|---|
| **Date** | 2026-11-13 |
| **Environment** | Lab OpenShift 4.19, shared training cluster – assigned project `project-03` (sanitised) |
| **Severity** | Sev2 in production terms (application fully unavailable to users) |
| **Component** | Route · Service · Endpoints |
| **Status** | **Resolved** – verified with curl and in a browser |
| **Time to detect / resolve** | n/a (reported) / ~10 min triage + ~2 min fix |
| **Source** | Trainer story 08: "Unable to access the application over the route URL – check and fix" |

## 1. Problem statement
The Etherpad application in `project-03` could not be opened in a browser via its Route URL. The Pod itself was Running and healthy.

## 2. Impact
- Application **completely unreachable** from outside the cluster (browser/clients).
- No data loss; the Pod kept running throughout.
- On the shared cluster, the Route also claimed a hostname intended for another project (`app4`), risking a collision when that project was fixed.

## 3. Symptoms & detection
A read-only sweep of all training projects' Routes showed four broken ones, all with malformed hostnames:
```
project-01  app1.app.<cluster>.<lab-domain>                    HTTP 000
project-02  app2.app.nstest.<lab-domain>                     HTTP 000
project-03  app4.aps.nstest.cloud-llab.<lab-domain-typo>     HTTP 000     ← chosen (unassigned, most faults)
project-04  app4.aps.nstest.<lab-domain-typo>                HTTP 000
project-05..08                                               HTTP 200
```
`HTTP 000` = no HTTP connection at all – the request never reached the router.

## 4. Timeline
| Time (IST) | Event |
|---|---|
| 17:05 | Claimed a project in the team group; first pick (`project-06`) turned out already working |
| 17:11 | Read-only sweep of all 8 Routes → projects 01–04 broken |
| 17:12 | Claimed `project-03`; full read-only triage |
| 17:13 | Backup of Service + Route taken; Service selector fixed → endpoints appeared |
| 17:13 | Route host + target Service fixed → Route admitted |
| 17:14 | `curl` → `HTTP 200`, `<title>Etherpad</title>` |
| 17:15 | Browser confirmed – Etherpad pad loads |

## 5. Investigation
Triage followed the request path **outside → in**: DNS → Route → Service → Endpoints → Pod → container port.

| # | Layer | Check | Result |
|---|---|---|---|
| 1 | DNS | `getent hosts <route-host>` | ❌ **does not resolve** |
| 2 | Route → Service | `.spec.to.name` vs. existing Services | ❌ Route targets **`web_app`**; the Service is **`web-app`** |
| 3 | Service → Pods | Service selector vs. Pod labels; `oc get endpoints` | ❌ selector **`app=web_app`**, Pod label **`app=web-app`** → `ENDPOINTS <none>` |
| 4 | Route → Service port | Route `targetPort` vs. Service port name | ✅ `8080-9001` matches |
| 5 | Service → container port | `targetPort` vs. listening socket | ✅ `9001`; `/proc/net/tcp` shows `00000000:2329` LISTEN (0x2329 = 9001) |
| 6 | Workload | Deployment / Pod status, logs | ✅ 1/1 Running; "access your Etherpad instance at http://0.0.0.0:9001/" |

Evidence (object names sanitised – the real names followed the same hyphen/underscore pattern):
```
service/web-app   ClusterIP   8080/TCP   SELECTOR app=web_app          ← underscore
pod/web-app-…     Running     LABELS   app=web-app,pod-template-hash=…  ← hyphen
NAME      ENDPOINTS
web-app   <none>                                                         ← Service matches no Pods

route/web-route   HOST app4.aps.nstest.cloud-llab.<lab-domain-typo>   SERVICES web_app   PORT 8080-9001
DNS: does not resolve
```

## 6. Root cause
Three independent configuration errors, each sufficient on its own to make the app unreachable:

| # | Fault | Effect |
|---|---|---|
| **1** | **Route host misspelled** (`aps`/`nstest`/`cloud-llab`/domain typo) and using another project's name (`app4`) | Host is outside the cluster's wildcard DNS (`*.apps.<cluster-domain>`) → browsers can't resolve it → `HTTP 000` |
| **2** | **Route targets a non-existent Service** (`web_app` vs. `web-app`) | Even with a valid host, the router has no backend → `503 Application is not available` |
| **3** | **Service selector doesn't match Pod labels** (`app=web_app` vs. `app=web-app`) | Service has **no endpoints** → `503` even with a correct Route |

**5 Whys (for the class of problem)**
1. Why was the app unreachable? → The request couldn't resolve, and even if it had, the Route and Service led to no Pods.
2. Why? → Names and labels in three objects didn't match each other or the DNS domain.
3. Why didn't anything fail at creation time? → Kubernetes/OpenShift accept a Route to a Service that doesn't exist and a Service whose selector matches nothing – these are **valid objects**, just disconnected.
4. Why wasn't it caught after deployment? → The Pod looked healthy (Running/Ready); nothing checked the **end-to-end path**.
5. Underlying cause → hand-typed names/hosts (hyphen vs. underscore, domain typos) with no validation or end-to-end test.

## 7. Resolution
Backup first, then the smallest change per fault, verified after each – **inside → out**:
```bash
oc get svc,route -n project-03 -o yaml > project-03-before.yaml          # backup / rollback point

# Fault 3 – Service selector
oc patch svc web-app -n project-03 --type=merge -p '{"spec":{"selector":{"app":"web-app"}}}'
# → ENDPOINTS: <pod-ip>:9001

# Faults 1 + 2 – Route host and target Service
oc patch route web-route -n project-03 --type=merge \
  -p '{"spec":{"host":"app3.apps.<cluster-domain>","to":{"name":"web-app"}}}'
```
**Verification:**
```
NAME      ENDPOINTS
web-app   <pod-ip>:9001                                   ← Service now selects the Pod

HOST                       SVC       PORT        ADMITTED
app3.apps.<cluster-domain> web-app   8080-9001   True     ← router accepted the new host

$ getent hosts app3.apps.<cluster-domain>
<router-node-ip>  app3.apps.<cluster-domain>              ← resolves via the *.apps wildcard (router runs on the control-plane node)

$ curl -s -o /dev/null -w "HTTP %{http_code}\n" http://app3.apps.<cluster-domain>/
HTTP 200
$ curl -s http://app3.apps.<cluster-domain>/ | grep -io '<title>.*</title>'
<title>Etherpad</title>
```
**Browser:** Etherpad loads and opens a pad ✅ (browser shows "Not secure" – plain HTTP).

Host chosen as **`app3`** (matching the project) rather than keeping `app4`: Route hosts must be unique cluster-wide, and `app4` belongs to `project-04`.

## 8. Preventive actions
| Action | Type | Status |
|---|---|---|
| Manage Route/Service/Deployment from **one manifest set** (e.g. Kustomize with shared `commonLabels`, or `oc expose` instead of hand-written Routes) so names/labels can't drift | Prevent | Proposed |
| Prefer **generated hostnames** (omit `spec.host` → `<route>-<ns>.apps.<domain>`) unless a custom host is required | Prevent | Proposed |
| Validate before deploy: Route `to.name` exists, Service selector matches Pod template labels, host is within the apps domain (CI check / policy) | Prevent | Proposed |
| **Endpoint-based alerting**: alert when a Service has 0 endpoints, and synthetic HTTP checks per Route | Detect | Proposed |
| Reusable triage script (outside → in) | Process | Done – [`scripts/RCA-003/route-triage.sh`](../scripts/RCA-003/route-triage.sh) |
| Add **edge TLS** to the Route | Security | Follow-up |
| Etherpad uses DirtyDB on ephemeral storage (shown in the pad) | Data | See [OCP-004](../stories/OCP-004-third-party-image-etherpad.md) follow-ups |

## 9. Lessons learned
- **"Running" Pods say nothing about reachability.** Check the whole path: DNS → Route → Service → Endpoints → Pod → port.
- **`ENDPOINTS <none>`** is the fastest single signal of a Service/Pod label mismatch.
- Kubernetes accepts disconnected objects silently – a Route can point at a Service that doesn't exist.
- Don't stop at the first fault: fixing only the hostname would have left two more.
- On shared clusters: claim before touching, back up before changing, and avoid hostnames that belong to someone else.

## 10. Interview talking point
> "An app was unreachable via its route while the Pod was Running. I triaged from the outside in: the route's hostname had typos so it didn't resolve in the cluster's wildcard DNS; the route pointed at a Service name with an underscore that didn't exist; and the Service's selector used an underscore while the Pod label used a hyphen, so the Service had no endpoints. Three independent faults – fixing only the hostname would still have given a 503. I backed up the objects, patched the selector, saw the endpoint appear, fixed the route's host and target, and verified with curl and in the browser. Preventive actions: manage all three objects from one manifest set, validate selectors and route targets in CI, and alert on Services with zero endpoints."
