# OCP-008: Rebuild → automatic redeploy (ImageStream trigger) and expose app-04 with a Route

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Builds · ImageStream triggers · Rollouts · Routes |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~15 min |
| **Status** | Done |
| **Related** | [OCP-007 – build my own image](OCP-007-own-image-openshift-build.md) |

## 1. User story / requirement
> As a **developer**, I want **a new build of my image to roll out to the running application automatically**, and the app **reachable from outside the cluster**, so that **shipping a change is just "build" – no manual redeploy step**.

## 2. Acceptance criteria
- [x] Change the application content (v1.0 → v1.1) and rebuild the image
- [x] New image pushed with a **new digest**
- [x] Deployment rolls out the new image **without any manual deploy command**
- [x] Application serves v1.1
- [x] Application exposed outside the cluster with a Route – **verified with curl via the Route hostname**

## 3. Background / concepts
```
oc start-build ──► new image pushed ──► ImageStream tag app-04:latest moves to new digest
                                              │
                         image-change trigger │ (annotation set by oc new-app)
                                              ▼
                     Deployment pod template updated to new digest ──► rolling update
```
- When `oc new-app` creates a Deployment from an ImageStream, it adds an **image-change trigger** (annotation `image.openshift.io/triggers`). When the tag points to a new digest, OpenShift updates the Deployment's image → a normal **rolling update** follows.
- **Route:** OpenShift's way to expose a Service on a hostname via the cluster's ingress routers (HAProxy). `oc expose service/<name>` creates a plain-HTTP route on a generated hostname `<route>-<namespace>.apps.<cluster-domain>`.

## 4. Plan
1. Edit `index.html` (Version 1.0 → 1.1).
2. `oc start-build --from-dir` – rebuild and push.
3. Watch the Deployment roll out on its own; verify v1.1.
4. `oc expose service/app-04 --port=8080`; check the Route.
5. **Rollback:** `oc rollout undo deployment/app-04` (previous ReplicaSet/digest), `oc delete route app-04`.

## 5. Implementation
```bash
cd ~/app-04 && sed -i 's/Version: 1.0/Version: 1.1/' index.html
oc start-build app-04 --from-dir=. --follow
oc rollout status deployment/app-04          # only watching – no deploy command issued
oc exec deploy/app-04 -- curl -s localhost:8080 | grep Version
oc expose service/app-04 --port=8080
oc get route app-04
```

## 6. Validation / evidence
**New image, new digest:**
```
Successfully pushed image-registry.openshift-image-registry.svc:5000/my-apps/app-04@sha256:d64696b7…
Push successful
```
| Build | Digest |
|---|---|
| v1.0 (OCP-007) | `sha256:6bada123…` |
| v1.1 (this story) | `sha256:d64696b7…` |

**Rolled out automatically – the only command was `oc rollout status` (observe only):**
```
Waiting for deployment "app-04" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "app-04" rollout to finish: 1 old replicas are pending termination...
deployment "app-04" successfully rolled out
```
**Serving the new version:**
```
$ oc exec deploy/app-04 -- curl -s localhost:8080 | grep Version
  <p>Version: 1.1</p>
```
**Exposed with a Route:**
```
route.route.openshift.io/app-04 exposed
NAME     HOST/PORT                                  SERVICES   PORT   TERMINATION
app-04   app-04-my-apps.apps.<cluster-domain>       app-04     8080   (none = plain HTTP)
```

**Proof of the trigger, the revisions, and external access:**
```
$ oc get deploy app-04 -o jsonpath='{.metadata.annotations.image\.openshift\.io/triggers}'
[{"from":{"kind":"ImageStreamTag","name":"app-04:latest","namespace":"my-apps"},
  "fieldPath":"spec.template.spec.containers[?(@.name==\"app-04\")].image"}]
        ↑ watch ImageStreamTag app-04:latest → write its digest into the container's image field

$ oc rollout history deployment/app-04
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>

$ curl -s http://$(oc get route app-04 -o jsonpath='{.spec.host}') | grep Version
  <p>Version: 1.1</p>          ← reached from outside the Pod, through the router and Route
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | Rollout started with no `oc rollout`/`oc set image` from me | Image-change trigger created by `oc new-app` fired when the ImageStream tag moved |
| 2 | "1 old replicas are pending termination" | Default **RollingUpdate**: new Pod comes up first, old Pod is terminated after – no downtime window for this single-replica app once the new Pod is Ready |
| 3 | Route has **no TLS termination** | `oc expose` creates plain HTTP. Production routes should be `edge` or `reencrypt` TLS |
| 5 | **3 revisions**, not 2 | Revision 1 is the Deployment as first created by `oc new-app`; the trigger then resolved the ImageStream tag into the image field (revision 2 = v1.0 – matching the "Waiting for deployment spec update to be observed" lines in OCP-007), and the rebuild produced revision 3 = v1.1 |
| 6 | `CHANGE-CAUSE` is `<none>` for every revision | Nothing records *why* each rollout happened. Annotate it: `oc annotate deployment/app-04 kubernetes.io/change-cause="v1.1: updated page" --overwrite` – makes `rollout history` an audit trail |
| 4 | `--port=8080` needed on `oc expose` | The Service has two ports (8080, 8443 inherited from the base image – see OCP-007); without it the Route may target the wrong one |

## 8. Production considerations
- Automatic redeploy on every build is great for **dev**; for **prod**, promote explicitly: tag a tested digest (`oc tag app-04@sha256:… app-04:prod`) and have only prod's Deployment follow `:prod`.
- Add **readiness probes** so the rolling update only shifts traffic once the new Pod actually serves.
- Use **TLS routes** (`oc create route edge …`) and, for public apps, a proper certificate.
- Record a **change-cause** on each rollout so `oc rollout history` explains itself.
- Keep rollback simple: `oc rollout undo` works because the previous ReplicaSet still references the old digest.

## 9. Lessons learned
- ImageStream + image-change trigger = "build is deploy" with no extra tooling.
- Digests make versions unambiguous – two builds, two digests, easy to audit and roll back.
- `oc expose` is quick but plain HTTP; security comes from choosing the route type.

## 10. Interview talking point
> "After building my own image, I changed the page to version 1.1 and started a new build. The new image got a new digest, the ImageStream tag moved, and the Deployment rolled out on its own – the image-change trigger from `oc new-app` did it, with a rolling update and no manual deploy. Then I exposed it with a Route. For production I'd keep automatic triggers for dev only and promote tested digests to a prod tag, add readiness probes, and use a TLS route instead of plain HTTP."
