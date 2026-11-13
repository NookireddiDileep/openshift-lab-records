# OCP-016: Create and access an application through an Ingress (OpenShift default ingress controller)

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Networking · Ingress · Routes · Router (HAProxy) |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~15 min |
| **Status** | Done |
| **Related** | [OCP-008 – Route for app-04](OCP-008-imagestream-trigger-and-route.md) · [OCP-015 / RCA-003 – route troubleshooting](OCP-015-fix-app-unreachable-via-route.md) |

## 1. User story / requirement
> As a **developer**, I want to **expose my application through a standard Kubernetes Ingress, using OpenShift's default ingress controller**, so that **my manifests stay portable across Kubernetes distributions** while the app is still reachable from outside the cluster.

## 2. Acceptance criteria
- [x] Ingress created for an existing application (`app-04`, my own image from OCP-007)
- [x] Ingress uses the default ingress class / controller
- [x] Application reachable through the Ingress host (`HTTP 200`, my page content)
- [x] *(extra)* Showed how OpenShift implements Ingress: an owned, auto-generated Route

## 3. Background / concepts
| | Route (OpenShift) | Ingress (Kubernetes) |
|---|---|---|
| API | `route.openshift.io/v1` | `networking.k8s.io/v1` |
| Portable to other Kubernetes | no | **yes** |
| TLS modes | edge / passthrough / re-encrypt built in | basic TLS; OpenShift extras via annotations (e.g. `route.openshift.io/termination`) |
| Advanced features | weighted backends (A/B), per-route timeouts | via controller-specific annotations |
| How OpenShift serves it | read directly by the router | **converted into a Route** by the `ingress-to-route` controller |

```
Ingress app-04-ingress ──(ingress-to-route controller)──► Route app-04-ingress-<random>  (ownerReference → Ingress)
                                                              │
Browser ─► *.apps.<cluster-domain> ─► router-default (HAProxy) ┘ ─► Service app-04 :8080 ─► Pod
```

## 4. Plan
1. Find the ingress class and the cluster's apps domain.
2. Write an Ingress for Service `app-04` port 8080 with a host inside the apps domain.
3. Apply (server dry-run first); access with curl and a browser.
4. Inspect the generated Route; delete it to show it's managed by the Ingress.
5. **Rollback:** `oc delete ingress app-04-ingress` (its generated Route is garbage-collected with it).

## 5. Implementation
Manifest: [`scripts/OCP-016/app-04-ingress.yaml`](../scripts/OCP-016/app-04-ingress.yaml)
```bash
oc get ingressclass
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'
DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
NS=$(oc project -q)
# write the manifest with an UNQUOTED heredoc (<<EOF) so ${NS} and ${DOMAIN} expand,
# host: app04-ingress-${NS}.${DOMAIN}, backend service app-04 port 8080
oc apply -f app-04-ingress.yaml --dry-run=server
oc apply -f app-04-ingress.yaml
```

## 6. Validation / evidence
**Default ingress class:**
```
NAME                CONTROLLER                      PARAMETERS
openshift-default   openshift.io/ingress-to-route   IngressController.operator.openshift.io/default
```
**Ingress admitted by the default router:**
```
NAME             CLASS               HOSTS                                    ADDRESS                         PORTS
app-04-ingress   openshift-default   app04-ingress-my-apps.apps.<domain>      router-default.apps.<domain>    80
```
**Accessed through the Ingress host:**
```
$ curl -s -o /dev/null -w "HTTP %{http_code}\n" http://app04-ingress-my-apps.apps.<domain>/
HTTP 200
$ curl -s http://app04-ingress-my-apps.apps.<domain>/ | grep -E "<h1>|Version"
  <h1>Hello from app-04</h1>
  <p>Version: 1.1</p>
```
**The Route OpenShift generated from the Ingress:**
```
NAME                   HOST/PORT                               PATH   SERVICES   PORT
app-04                 app-04-my-apps.apps.<domain>                   app-04     8080       ← my Route from OCP-008
app-04-ingress-bfr2l   app04-ingress-my-apps.apps.<domain>     /      app-04     8080-tcp   ← generated from the Ingress

owner: Ingress/app-04-ingress
host:  app04-ingress-my-apps.apps.<domain>
svc:   app-04
```
**Managed by the Ingress – deleted Route is recreated:**
```
$ oc delete route app-04-ingress-bfr2l
route.route.openshift.io "app-04-ingress-bfr2l" deleted
$ (5 s later) generated routes owned by the Ingress:
app-04-ingress-vshdm  2026-11-13T11:50:14Z      ← new name, new timestamp
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | Ingress class controller is `openshift.io/ingress-to-route` | OpenShift's router serves Routes; Ingresses are translated, not served directly |
| 2 | Generated Route is **owned** by the Ingress and **recreated** when deleted | The controller reconciles the Route from the Ingress. Change the **Ingress**, not the generated Route – manual edits to the Route are overwritten |
| 3 | Ingress `port.number: 8080` became Route `targetPort: 8080-tcp` | The controller maps the number to the Service's **port name** |
| 4 | Generated Route carries the Ingress's labels (`app=app-04`) | Labels are copied, so label selectors find both objects |
| 5 | Ingress `ADDRESS` = `router-default.apps.<domain>` | Status shows which router admitted it – useful when there are multiple ingress controllers/shards |
| 6 | app-04 now reachable via **two hosts** (OCP-008 Route + this Ingress) | Independent objects to the same Service – remove whichever isn't needed |
| 7 | Host must be inside `*.apps.<domain>` | Same DNS rule as in RCA-003; outside it, the name won't resolve |
| 8 | Unquoted heredoc (`<<EOF`) for the manifest | Needed so `${NS}`/`${DOMAIN}` expand – earlier stories used `<<'EOF'` to keep text literal |

## 8. Production considerations
- Use **Ingress** when manifests must be portable (Helm charts, multi-distribution); use **Route** when you need OpenShift features (re-encrypt/passthrough TLS, weighted backends).
- TLS: add `spec.tls` with a secret, or the annotation `route.openshift.io/termination: edge|reencrypt` for the generated Route.
- With multiple ingress controllers (sharding), `ingressClassName` and namespace/route selectors decide which router serves it.
- Manage the Ingress in Git; never hand-edit the generated Route.

## 9. Lessons learned
- On OpenShift, Ingress is a portable front-end to the Route machinery – the router only ever sees Routes.
- Owned objects (generated Routes, ReplicaSets, DaemonSet Pods) are recreated by their owner; change the owner.
- `oc get ingressclass` + the cluster apps domain are the two facts needed to write a working Ingress.

## 10. Interview talking point
> "I exposed my app through a standard Kubernetes Ingress using the `openshift-default` ingress class. It was admitted by the default HAProxy router and returned my page. OpenShift's `ingress-to-route` controller generated a Route owned by the Ingress – it translated the port number to the Service's port name and copied the labels – and when I deleted that Route it was recreated immediately. So on OpenShift you manage the Ingress and let the platform manage the Route; I'd choose Ingress for portable manifests and Routes when I need re-encrypt or passthrough TLS or weighted backends."
