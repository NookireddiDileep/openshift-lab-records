# OCP-003: Scale app-02 from 1 to 2 replicas (declaratively) + configuration drift demo

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Workloads · Scaling · GitOps practices |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~20 min |
| **Status** | Done |
| **Related** | [OCP-002 – Deployment self-healing](OCP-002-deployment-self-heal.md) |

## 1. User story / requirement
> As an **application team**, I want **`app-02` scaled from 1 to 2 replicas in my namespace**, so that **the application has more capacity and survives the loss of one Pod without downtime**.

## 2. Acceptance criteria
- [x] Deployment `app-02` runs **2/2** replicas
- [x] The ReplicaSet's desired count is 2
- [x] Change made **declaratively** (manifest updated and applied), reviewed with `oc diff` first
- [x] *(extra)* Replicas checked for node placement (HA)
- [x] *(extra)* Demonstrated configuration drift from an imperative change, and how `oc apply` corrects it

## 3. Background / concepts
| | Imperative (`oc scale`) | Declarative (edit manifest → `oc apply`) |
|---|---|---|
| Speed | fastest | one extra step |
| Source of truth | the live cluster | the manifest (ideally in Git) |
| Reviewable / auditable | no | yes – `oc diff`, Git history, PR review |
| Risk | **drift** – the file no longer matches the cluster | none – file and cluster agree |

- **Configuration drift:** if someone scales with `oc scale` but the manifest still says the old value, the next `oc apply` of that file silently reverts the change. GitOps tools (e.g. Argo CD) are built around preventing exactly this.
- **`metadata.generation`** increases on every spec change; the controller records the generation it has processed in `status.observedGeneration`. Comparing the two shows whether a change has been acted on.
- **Replicas ≠ HA by themselves:** two replicas on the same node die together if that node fails – placement matters.

## 4. Plan
1. Record the current state (1 replica, its node).
2. Change `replicas: 1 → 2` in the manifest; review with `oc diff`; apply.
3. Verify Deployment, ReplicaSet, Pods and node placement.
4. Drift demo: `oc scale --replicas=3`, show the drift with `oc diff`, re-apply the file.
5. **Rollback:** set `replicas: 1` in the manifest and `oc apply`.

## 5. Implementation
Manifest: [`scripts/OCP-003/app-02-deploy.yaml`](../scripts/OCP-003/app-02-deploy.yaml)
```bash
sed -i 's/replicas: 1/replicas: 2/' app-02-deploy.yaml
oc diff -f app-02-deploy.yaml
oc apply -f app-02-deploy.yaml
oc rollout status deployment/app-02
```

## 6. Validation / evidence
**Before:**
```
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
app-02   1/1     1            1           5m6s

NAME                      READY   STATUS    AGE     NODE
app-02-7df4f6bd64-78dzp   1/1     Running   4m28s   worker-1
```
**Review the change before applying (`oc diff`):**
```diff
-  generation: 3
+  generation: 4
 ...
 spec:
   progressDeadlineSeconds: 600
-  replicas: 1
+  replicas: 2
```
**Apply and roll out:**
```
deployment.apps/app-02 configured
Waiting for deployment "app-02" rollout to finish: 1 of 2 updated replicas are available...
deployment "app-02" successfully rolled out
```
**After:**
```
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
app-02   2/2     2            2           5m12s

NAME                DESIRED   CURRENT   READY   AGE
app-02-7df4f6bd64   2         2         2       5m13s

NAME                      READY   STATUS    AGE     NODE
app-02-7df4f6bd64-78dzp   1/1     Running   4m35s   worker-1
app-02-7df4f6bd64-f64sj   1/1     Running   7s      master-0     ← different node
```
The ReplicaSet name (`…-7df4f6bd64`) is unchanged – scaling only changes the **replica count**, not the Pod template, so no new ReplicaSet and no rollout of existing Pods.

**Drift demo – imperative change, then re-apply the file:**
```
$ oc scale deployment/app-02 --replicas=3
deployment.apps/app-02 scaled
NAME     READY   UP-TO-DATE   AVAILABLE
app-02   2/3     3            2              ← live cluster now says 3

$ oc diff -f app-02-deploy.yaml               ← file still says 2
-  generation: 5
+  generation: 6
-  replicas: 3
+  replicas: 2

$ oc apply -f app-02-deploy.yaml
deployment.apps/app-02 configured
NAME     READY   UP-TO-DATE   AVAILABLE
app-02   2/2     2            2              ← the file wins; the manual change is gone
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | The two replicas landed on **different nodes** (worker and control-plane) | The scheduler's default scoring spreads Pods of the same app across nodes when it can – but this is best-effort, not guaranteed |
| 2 | Same ReplicaSet before and after scaling | Scaling changes `spec.replicas` only; a new ReplicaSet is created only when the **Pod template** changes |
| 3 | `generation` 3→4 and 5→6 | Each spec change increments `metadata.generation`; `status.observedGeneration` shows when the controller has processed it |
| 4 | `oc describe … \| grep -A5 Events` showed only the older scale events from OCP-002, not the new "1 to 2" line | The newest event fell outside the 5 lines of context. Lesson: use `oc get events --field-selector involvedObject.name=app-02 --sort-by=.lastTimestamp` for complete, ordered evidence |

## 8. Production considerations
- Make replica changes **in Git** and let a pipeline or GitOps tool apply them – never only with `oc scale` on a live cluster.
- For guaranteed spread, add **topologySpreadConstraints** or **pod anti-affinity** across nodes/zones instead of relying on default scheduler scoring.
- Add a **PodDisruptionBudget** (e.g. `minAvailable: 1`) so node drains during upgrades never take both replicas down at once.
- For load-driven scaling use a **HorizontalPodAutoscaler** – then don't hard-code `replicas` in the manifest, or Git and the HPA will fight (another form of drift).
- Keep application workloads off control-plane nodes in production (here the lab's control-plane nodes are schedulable).

## 9. Lessons learned
- `oc diff` before `oc apply` is a cheap, powerful safety check – it's effectively a change preview.
- Imperative changes are fine for experiments, but the manifest must stay the source of truth.
- Scaling is not the same as an update: same ReplicaSet, no new rollout.

## 10. Interview talking point
> "I scaled a Deployment from one to two replicas declaratively – changed the manifest, reviewed the change with `oc diff`, then applied it – and checked that the replicas landed on different nodes. Then I demonstrated configuration drift: I scaled to three with `oc scale`, `oc diff` showed the live cluster no longer matched the file, and re-applying the file put it back to two. That's exactly why production changes should go through Git, and why GitOps tools continuously reconcile against it."
