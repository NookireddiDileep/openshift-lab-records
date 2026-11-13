# OCP-018: Split application traffic between two versions – v1 80% / v2 20% (canary on one Route)

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Release strategies · Routes · Weighted backends (canary / A-B) |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~15 min |
| **Status** | Done |
| **Related** | [OCP-017 – Blue-Green](OCP-017-blue-green-deployment.md) |

## 1. User story / requirement
> As a **release manager**, I want to **split traffic between two versions – v1-app 80% and v2-app 20%** – so that **a small share of users tries the new version first** and I can increase it gradually (canary release).

## 2. Acceptance criteria
- [x] Two versions behind one Route: `v1-app` and `v2-app`
- [x] Route weights set to **80 / 20**
- [x] Measured split matches: **80 × v1, 20 × v2** out of 100 requests
- [x] *(extra)* Showed per-user stickiness, then progressed 50/50 → 0/100 (release complete)

## 3. Background / concepts
| | Blue-Green (OCP-017) | **Canary / weighted split (this story)** |
|---|---|---|
| Traffic to new version | 0% → 100% at once | gradual: 20% → 50% → 100% |
| Risk exposure | all users at the switch | only the canary share |
| Mechanism on OpenShift | change Route `spec.to` | Route `spec.to` + `spec.alternateBackends` with **weights** |
| Rollback | repoint | set the new version's weight to 0 |

```
                        80% ──► Service v1-app ──► v1 Pods
Route split-app ────────┤
                        20% ──► Service v2-app ──► v2 Pods
```
- `oc set route-backends <route> svcA=W svcB=W` writes the primary backend (`spec.to`) and `spec.alternateBackends` with weights (up to 4 backends; weights are relative, 0–256).
- The two versions are the blue/green Deployments from OCP-017, exposed under the story's names via two new Services (`v1-app` → blue Pods, `v2-app` → green Pods) – no new Deployments needed.

## 4. Plan
1. Create Services `v1-app` and `v2-app`; confirm both have endpoints.
2. Create Route `split-app` and set weights 80/20.
3. Wait for the router reload (~5 s, learned in OCP-017); send 100 requests and count versions.
4. Repeat with a cookie jar to see what a single browser user gets.
5. Progress to 50/50, then 0/100.
6. **Rollback:** `oc set route-backends split-app v1-app=100 v2-app=0`.

## 5. Implementation
Files: [`split-services.yaml`](../scripts/OCP-018/split-services.yaml) · [`canary.sh`](../scripts/OCP-018/canary.sh)
```bash
oc apply -f split-services.yaml
oc expose service/v1-app --name=split-app
oc set route-backends split-app v1-app=80 v2-app=20
```

## 6. Validation / evidence
**Both Services have endpoints:**
```
NAME     ENDPOINTS
v1-app   <ip>:8080,<ip>:8080
v2-app   <ip>:8080,<ip>:8080
```
**Weights on the Route:**
```
$ oc set route-backends split-app
NAME              KIND     TO      WEIGHT
routes/split-app  Service  v1-app  80 (80%)
routes/split-app  Service  v2-app  20 (20%)

primary: v1-app=80
alternate: v2-app=20
```
**100 requests at 80/20:**
```
$ for i in $(seq 1 100); do curl -s http://$H/ | grep -o 'version [12]'; done | sort | uniq -c
     80 version 1
     20 version 2
```
**One "user" with a cookie (20 requests):**
```
     20 version 1        ← sticky: the router's session cookie pins this client to one backend
```
**Progressing the canary:**
```
50/50  →      50 version 1
              50 version 2
0/100  →      20 version 2          (20 of 20)

NAME              KIND     TO      WEIGHT
routes/split-app  Service  v1-app  0 (0%)
routes/split-app  Service  v2-app  100 (100%)
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | Split was **exactly** 80/20 and 50/50, not approximately | For Routes with multiple weighted backends the HAProxy router balances **round-robin** (a deterministic rotation), so 100 cookieless requests reproduce the ratio exactly |
| 2 | With a cookie jar, **all 20 requests hit v1** | The router sets a session cookie; a browser user sticks to one backend. In production the percentage applies **across users/sessions**, not across one user's requests – which is what you want for a consistent user experience |
| 3 | Waited ~7 s after each weight change | Router `RELOAD_INTERVAL=5s` (OCP-017); measuring immediately would mix old and new weights |
| 4 | `spec.to` stays `v1-app` even at 0% | The "primary" backend can have weight 0; traffic follows the weights, not which field a Service is in |
| 5 | Same Pods as OCP-017 served both experiments | Services are just label selectors – several Services (and Routes) can front the same Pods |

## 8. Production considerations
- **Decide on metrics before raising the weight**: error rate, latency, business KPIs for the canary share; automate promotion/rollback (e.g. Argo Rollouts, OpenShift Service Mesh, or pipeline gates).
- Cookie stickiness keeps users on one version; disable it (`haproxy.router.openshift.io/disable_cookies: "true"`) only for stateless APIs where per-request spreading is desired.
- Both versions usually share the database – schema changes must be backward-compatible (expand/contract).
- Route weights split at the **edge** (north-south traffic). For service-to-service (east-west) splitting, use a service mesh.
- Clean up after promotion: remove the alternate backend and scale v1 down.

## 9. Lessons learned
- A canary on OpenShift is one command: `oc set route-backends route a=80 b=20`.
- Measure it – with and without cookies – because "the split" means different things for anonymous requests and for real users.
- Always wait for the router reload before measuring.

## 10. Interview talking point
> "I split traffic between two versions on one Route with weighted backends – `oc set route-backends split-app v1-app=80 v2-app=20`. A hundred requests came back exactly 80/20 because the router round-robins weighted backends. With a cookie jar, every request from that client went to the same version, since the router pins sessions – so in production the percentage applies across users, which keeps each user's experience consistent. Then I progressed to 50/50 and 100% on v2, waiting for the router's 5-second reload between steps; rollback is just setting v2 back to zero."
