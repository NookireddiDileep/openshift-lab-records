# OCP-002: Deploy app-02 as a Deployment (self-healing)

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Workloads · Deployments · ReplicaSets · Security (SCC) |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~30 min |
| **Status** | Done |
| **Related** | [OCP-001 – bare Pod, no self-healing](OCP-001-bare-pod-no-self-heal.md) |

## 1. User story / requirement
> As an **application team**, I want **`app-02` deployed as a Deployment in my namespace**, so that **if its Pod is deleted or lost, the platform automatically recreates it (self-healing)**.

## 2. Acceptance criteria
- [x] Deployment `app-02` created from a manifest in my own project
- [x] Pod is owned by a ReplicaSet (controller-managed)
- [x] Application responds
- [x] Deleting the Pod results in a **new Pod** being created automatically
- [x] *(extra)* Self-healing also works with multiple replicas
- [x] *(extra)* Pod is admitted under `restricted-v2` with no Pod Security warnings

## 3. Background / concepts
```
Deployment app-02         → desired state (replicas, Pod template, update strategy)
  └─ ReplicaSet app-02-<hash>   → reconciles: "desired N, actual M" → creates/deletes Pods
       └─ Pod app-02-<hash>-<id> → disposable; replaced with a new name if deleted
```
- **Self-healing = reconciliation.** The ReplicaSet controller continuously compares desired vs. actual replicas. When a Pod disappears (deleted, evicted, node lost), it creates a replacement – with a **new name and usually a new IP**, possibly on a **different node**.
- **What is *not* self-healed:** deleting the **Deployment** itself removes the desired state, so everything is removed – by design.
- **Contrast with OCP-001:** a bare Pod has no controller, so nothing recreates it.

## 4. Plan
1. Confirm I'm in my own project.
2. Write a Deployment manifest with a restricted-compliant `securityContext` and requests/limits (lessons from OCP-001).
3. Server-side dry run → apply → wait for rollout.
4. Verify the ownership chain, SCC and app response.
5. Delete the Pod and confirm a new one is created.
6. Repeat at 3 replicas; scale back to 1.
7. **Rollback:** `oc delete deployment app-02` (removes ReplicaSet and Pods).

## 5. Implementation
Manifest: [`scripts/OCP-002/app-02-deploy.yaml`](../scripts/OCP-002/app-02-deploy.yaml)
```bash
oc project -q                                  # my-apps
oc apply -f app-02-deploy.yaml --dry-run=server
oc apply -f app-02-deploy.yaml
oc rollout status deployment/app-02
```

## 6. Validation / evidence
**Rollout and ownership chain:**
```
deployment "app-02" successfully rolled out

NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/app-02   1/1     1            1           5s

NAME                                DESIRED   CURRENT   READY   AGE
replicaset.apps/app-02-7df4f6bd64   1         1         1       5s

NAME                          READY   STATUS    RESTARTS   AGE   IP            NODE
pod/app-02-7df4f6bd64-ksnzb   1/1     Running   0          5s    10.128.x.x    master-0
```
```
$ oc get pod $POD -o jsonpath='{.metadata.ownerReferences[0].kind} / {.metadata.ownerReferences[0].name}'
ReplicaSet / app-02-7df4f6bd64

$ oc get pod $POD -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
restricted-v2

$ oc exec $POD -- curl -s -o /dev/null -w '%{http_code}\n' localhost:8080
403                                    # httpd up, no index page
```

**Self-heal test – delete the Pod:**
```
$ oc delete pod app-02-7df4f6bd64-ksnzb
pod "app-02-7df4f6bd64-ksnzb" deleted

$ oc get pods -l app=app-02
NAME                      READY   STATUS    RESTARTS   AGE
app-02-7df4f6bd64-gt4xr   1/1     Running   0          18s      ← new Pod, new name
```
Events – the replacement was created while the old one was still terminating:
```
Normal   Pulling          pod/app-02-7df4f6bd64-gt4xr   Pulling image "registry.access.redhat.com/ubi9/httpd-24"
Normal   AddedInterface   pod/app-02-7df4f6bd64-gt4xr   Add eth0 [10.129.x.x/23] from ovn-kubernetes
Normal   Killing          pod/app-02-7df4f6bd64-ksnzb   Stopping container app-02
Normal   Pulled           pod/app-02-7df4f6bd64-gt4xr   Successfully pulled image ... in 13.408s
Normal   Created          pod/app-02-7df4f6bd64-gt4xr   Created container: app-02
Normal   Started          pod/app-02-7df4f6bd64-gt4xr   Started container app-02
```
The new Pod got an IP from a **different node's subnet** (`10.129.x.x` vs `10.128.x.x`) – it was scheduled fresh, on another node.

**Self-heal at scale – 3 replicas, delete all:**
```
$ oc scale deployment/app-02 --replicas=3
NAME                      READY   STATUS    RESTARTS   AGE
app-02-7df4f6bd64-4dvbh   1/1     Running   0          15s
app-02-7df4f6bd64-gt4xr   1/1     Running   0          33s
app-02-7df4f6bd64-lc87h   1/1     Running   0          15s

$ oc delete pod -l app=app-02 --wait=false
pod "app-02-7df4f6bd64-4dvbh" deleted
pod "app-02-7df4f6bd64-gt4xr" deleted
pod "app-02-7df4f6bd64-lc87h" deleted

$ oc get pods -l app=app-02          # 20 s later
NAME                      READY   STATUS    RESTARTS   AGE
app-02-7df4f6bd64-4f778   1/1     Running   0          20s
app-02-7df4f6bd64-78dzp   1/1     Running   0          20s
app-02-7df4f6bd64-n4wkv   1/1     Running   0          20s

$ oc scale deployment/app-02 --replicas=1
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | No Pod Security warnings this time | `securityContext` hardened up front, based on [OCP-001](OCP-001-bare-pod-no-self-heal.md) |
| 2 | Pod admitted under **`restricted-v2`** (in OCP-001 my bare Pod got `anyuid`) | **Confirms the OCP-001 finding:** Deployment Pods are created by the ReplicaSet controller using the project's `default` service account, which cannot use `anyuid`. My user's admin-group access no longer applies. Same image, different creator → different SCC |
| 3 | Replacement Pod landed on a different node | The scheduler places every new Pod from scratch; replacements aren't pinned to the old node |
| 4 | Replacement started before the old Pod finished terminating | The ReplicaSet counts Pods being deleted as gone and creates the replacement immediately |
| 5 | ~13 s of the ~18 s recovery was image pull | Image wasn't cached on the new node (≈310 MB). Smaller images or pre-pulled images speed up recovery |

## 8. Production considerations
- **1 replica = downtime during recovery** (~18 s here). Run **≥2 replicas** spread across nodes (pod anti-affinity / topology spread constraints) plus a **PodDisruptionBudget** for real HA.
- Add **readiness and liveness probes** so traffic only reaches ready Pods and hung containers are restarted.
- Recovery time depends on image pull time – keep images small and use an internal registry/mirror.
- Pin images by digest or a specific tag (not `latest`) for reproducible rollouts.

## 9. Lessons learned
- Self-healing comes from **controllers reconciling desired state**, not from the Pod itself.
- The SCC a Pod gets depends on **who creates it**: user (bare Pod) vs. controller's service account (Deployment).
- Replacement Pods are new objects – new name, new IP, possibly a new node – so apps must never rely on a fixed Pod name or IP (that's what Services are for).

## 10. Interview talking point
> "I deployed an app as a Deployment and showed self-healing: when I deleted the Pod, the ReplicaSet created a replacement within about 18 seconds, on a different node with a new IP – and with three replicas it recovered all three. I also proved something from my previous lab: the bare Pod I created directly ran under `anyuid` because of my user's permissions, but the Deployment's Pods ran under `restricted-v2`, because the controller creates them using the service account. Same image, different SCC, depending on who creates the Pod."
