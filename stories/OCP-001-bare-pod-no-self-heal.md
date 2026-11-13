# OCP-001: Deploy app-01 as a bare Pod (no self-healing)

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Workloads · Pods · Security (SCC / Pod Security) |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~30 min |
| **Status** | Done (hardening follow-up open) |

## 1. User story / requirement
> As an **application team**, I want **my first application `app-01` deployed from a Pod definition in my own namespace**, so that **I understand the most basic workload unit — and confirm that, if it is deleted, the platform does _not_ recreate it automatically**.

## 2. Acceptance criteria
- [x] A Pod named `app-01` is created from a YAML Pod manifest in my own project
- [x] The Pod reaches `Running` and the application responds
- [x] The Pod has **no controller** (no `ownerReferences`)
- [x] After deleting the Pod, it is **not** recreated (no self-healing)

## 3. Background / concepts
| | Bare Pod (this story) | Deployment |
|---|---|---|
| Owner | none – no `ownerReferences` | ReplicaSet → Deployment |
| Pod object deleted | **gone for good** | ReplicaSet creates a new Pod (self-heal) |
| Node fails | Pod is lost | Pod rescheduled on another node |
| Scaling / rolling updates | not possible | built in |

**Container restart ≠ self-healing.** `restartPolicy: Always` lets the **kubelet restart a crashed container inside the same Pod**. It does nothing if the **Pod object** is deleted – recreating Pods is a *controller's* job (ReplicaSet, StatefulSet, DaemonSet, Job). A bare Pod has no controller, so nothing brings it back.

**Production note:** bare Pods are almost never used for real applications – they're used for one-off debugging/test pods (`oc run`, `oc debug`). This story deliberately shows *why*.

## 4. Plan
1. Use a personal project on the shared lab (never `default`, `openshift-*`, `kube-*`).
2. Write a Pod manifest using a non-root, OpenShift-friendly image (`ubi9/httpd-24`, listens on 8080) with resource requests/limits.
3. Validate with a server-side dry run, then create.
4. Verify Running, owner, SCC, and that the app answers.
5. Delete the Pod and confirm it is not recreated.
6. **Rollback:** `oc delete pod app-01` (nothing else is created).

## 5. Implementation
```bash
oc whoami
oc new-project my-apps          # personal project; names must be DNS-1123 (no "_")
oc project -q                   # my-apps
```
Manifest: [`scripts/OCP-001/app-01-pod.yaml`](../scripts/OCP-001/app-01-pod.yaml)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-01
  labels:
    app: app-01
spec:
  containers:
  - name: app-01
    image: registry.access.redhat.com/ubi9/httpd-24
    ports:
    - containerPort: 8080
    resources:
      requests: { cpu: 50m, memory: 64Mi }
      limits:   { cpu: 200m, memory: 128Mi }
  restartPolicy: Always
```
```bash
oc apply -f app-01-pod.yaml --dry-run=server
oc apply -f app-01-pod.yaml
```

## 6. Validation / evidence
**Pod running** (scheduled in ~16 s):
```
NAME     READY   STATUS              RESTARTS   AGE   IP            NODE
app-01   0/1     ContainerCreating   0          14s   <none>        master-0
app-01   1/1     Running             0          16s   10.128.x.x    master-0
```
**SCC that admitted the Pod:**
```
$ oc get pod app-01 -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
anyuid
```
**Application responds** (403 = httpd up, no index page yet):
```
$ oc exec app-01 -- curl -s -o /dev/null -w '%{http_code}\n' localhost:8080
403
```
**Delete → no self-heal:**
```
$ oc delete pod app-01
pod "app-01" deleted
$ oc get pods
No resources found in my-apps namespace.
```
**Events confirm nothing was recreated** – the last event is `Killing`; no new `Scheduled`/`Created`:
```
Normal   Pulling   pod/app-01   Pulling image "registry.access.redhat.com/ubi9/httpd-24"
Normal   Pulled    pod/app-01   Successfully pulled image ... in 14.958s. Image size: 309720855 bytes.
Normal   Created   pod/app-01   Created container: app-01
Normal   Started   pod/app-01   Started container app-01
Normal   Killing   pod/app-01   Stopping container app-01
```

## 7. Issues hit & observations
| # | Observation | Cause | Action |
|---|---|---|---|
| 1 | `oc new-project` → `AlreadyExists` | Command re-run after the project had already been created | None – `oc project -q` confirmed I was in the right project |
| 2 | **Pod Security warnings** on apply: `allowPrivilegeEscalation != false`, `unrestricted capabilities`, `runAsNonRoot != true`, `seccompProfile` not set | Namespace enforces/warns at Pod Security level `restricted`; my manifest didn't declare a `securityContext` | Hardened manifest written: [`app-01-pod-hardened.yaml`](../scripts/OCP-001/app-01-pod-hardened.yaml) – follow-up to validate |
| 3 | Pod admitted with **SCC `anyuid`** instead of the default `restricted-v2` | On this shared lab, my user/service account can use `anyuid`; SCC admission picks the highest-priority SCC the requester can use, and `anyuid` (priority 10) wins over `restricted-v2` | Follow-up: confirm who is granted `anyuid` (`oc adm policy who-can use scc anyuid`). In production, `anyuid` should only be granted to a dedicated service account that needs it |
| 4 | Pod scheduled on a **control-plane node** (`master-0`) | Lab is a compact cluster where control-plane nodes are also schedulable workers | None for lab; in production keep app workloads off control-plane nodes |

## 8. Production considerations
- Use a **Deployment** (or StatefulSet) for anything that must stay up – bare Pods are for debugging only.
- Always declare a **restricted-compliant `securityContext`** so the Pod is secure regardless of which SCC admits it.
- Don't grant `anyuid` broadly; grant it to a dedicated service account (`oc adm policy add-scc-to-user anyuid -z <sa>`) only when an image genuinely needs a fixed UID.
- Always set **requests/limits** – they drive scheduling and QoS.

## 9. Lessons learned
- *Container restart* (kubelet, `restartPolicy`) and *Pod self-healing* (controllers) are different mechanisms.
- Server-side dry run (`--dry-run=server`) surfaces admission warnings before anything is created.
- The `openshift.io/scc` annotation shows which SCC actually admitted a Pod – worth checking on every new workload.

## 10. Interview talking point
> "I deployed an app as a bare Pod and showed that deleting it removes it permanently, because no controller owns it – unlike a Deployment, where the ReplicaSet recreates it. While doing it I noticed the Pod was admitted under the `anyuid` SCC and triggered Pod Security `restricted` warnings, so I hardened the manifest with an explicit `securityContext` – `runAsNonRoot`, dropped capabilities, no privilege escalation and the `RuntimeDefault` seccomp profile – so it's secure regardless of which SCC admits it."
