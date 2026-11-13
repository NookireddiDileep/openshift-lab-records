# OCP-022: StatefulSet with 3 replicas – 1Gi RWO volume per Pod from the default StorageClass

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Workloads · StatefulSets · volumeClaimTemplates · Headless Services |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~25 min |
| **Status** | Done |
| **Related** | [OCP-002 – Deployment](OCP-002-deployment-self-heal.md) · [OCP-020 – dynamic storage](OCP-020-dynamic-storage-etherpad.md) |

## 1. User story / requirement
> As a **platform engineer**, I want a **StatefulSet application with 3 replicas, each with 1Gi of RWO storage from the default StorageClass**, so that **each replica keeps its own identity and data** – the pattern used by databases and clustered systems.

## 2. Acceptance criteria
- [x] StatefulSet with **3 replicas**, all Running
- [x] **One PVC per replica**, 1Gi, **RWO**, from the **default StorageClass**
- [x] *(extra)* Ordered creation, stable names, stable per-Pod DNS
- [x] *(extra)* Pod replacement keeps **name + PVC + data**; scale-down keeps PVCs; scale-up reattaches them

## 3. Background / concepts
| | Deployment | **StatefulSet** |
|---|---|---|
| Pod names | random | **stable, ordinal**: `web-0`, `web-1`, `web-2` |
| Storage | shared PVC or none | **one PVC per Pod** from `volumeClaimTemplates` (`<template>-<pod>`) |
| Replaced Pod | new name | **same name, same PVC** |
| Order | parallel | **ordered**: 0→1→2 up, 2→1→0 down (default `OrderedReady`) |
| Network identity | Service VIP | **headless Service** → DNS per Pod: `<pod>.<svc>.<ns>.svc.cluster.local` |
| Scale-down / delete | — | **PVCs kept** by default (data safety) |

## 4. Plan
1. Confirm the default StorageClass.
2. Headless Service + StatefulSet (3 replicas, `volumeClaimTemplates` 1Gi RWO, no class named). Each Pod appends its name + start time to `/data/history.log`.
3. Verify order, names, PVCs, per-Pod data, DNS.
4. Delete `web-1`; scale 3→2→3; check names, PVCs and data.
5. **Rollback:** `oc delete sts web svc web`; PVCs remain → `oc delete pvc -l app=web-sts` (⚠️ reclaim `Delete` removes data).

## 5. Implementation
Manifest: [`scripts/OCP-022/web-sts.yaml`](../scripts/OCP-022/web-sts.yaml)
```bash
oc get sc                                  # nfs-storage (default)
oc apply -f web-sts.yaml --dry-run=server && oc apply -f web-sts.yaml
oc rollout status statefulset/web --timeout=180s
```

## 6. Validation / evidence
**Rollout – one Pod at a time:**
```
Waiting for 3 pods to be ready...
Waiting for 2 pods to be ready...
Waiting for 1 pods to be ready...
partitioned roll out complete: 3 new pods have been updated...
```
**Stable, ordinal names; ordered creation:**
```
NAME   READY
web    3/3

NAME    READY   STATUS    AGE   NODE
web-0   1/1     Running   27s   master-0
web-1   1/1     Running   21s   worker-1
web-2   1/1     Running   17s   worker-1

SuccessfulCreate  statefulset/web  create Pod web-0 ...   (27s ago)
SuccessfulCreate  statefulset/web  create Pod web-1 ...   (21s ago)
SuccessfulCreate  statefulset/web  create Pod web-2 ...   (17s ago)
```
**One 1Gi RWO PVC per Pod, default StorageClass:**
```
NAME         STATUS   VOLUME          CAPACITY   ACCESS MODES   STORAGECLASS
data-web-0   Bound    pvc-5d1111d5…   1Gi        RWO            nfs-storage
data-web-1   Bound    pvc-9c77de96…   1Gi        RWO            nfs-storage
data-web-2   Bound    pvc-8e727edd…   1Gi        RWO            nfs-storage
```
**Each Pod has its own data:**
```
== web-0:  12:27:06 started web-0
== web-1:  12:27:11 started web-1
== web-2:  12:27:15 started web-2
```
**Stable per-Pod DNS via the headless Service:**
```
$ getent hosts web-1.web.my-apps.svc.cluster.local
<web-1-ip>    web-1.web.my-apps.svc.cluster.local      ← exactly one Pod

$ getent hosts web.my-apps.svc.cluster.local
<web-0-ip>    web.my-apps.svc.cluster.local
<web-1-ip>    web.my-apps.svc.cluster.local
<web-2-ip>    web.my-apps.svc.cluster.local            ← all Pod IPs, no virtual IP (clusterIP: None)
```
**Delete `web-1` → same name, same PVC, data kept:**
```
pod "web-1" deleted
pod/web-1 condition met
12:27:11 started web-1
12:28:15 started web-1          ← second line appended to the SAME volume
claimName: data-web-1
```
**Scale 3 → 2 → 3:**
```
scale to 2:  web-2  Terminating          (PVCs: data-web-0, data-web-1, data-web-2 – all still Bound)
scale to 3:  web-2  Running
$ oc exec web-2 -- cat /data/history.log
12:27:15 started web-2
12:28:50 started web-2          ← new web-2 reattached its own data-web-2
grace period: 30s
```

## 7. Issues hit & observations
| # | Observation | Explanation / impact |
|---|---|---|
| 1 | PVC names `data-web-N` | `<volumeClaimTemplate name>-<pod name>` – deterministic, so a Pod always finds its own volume |
| 2 | PVCs carry the Pod label `app=web-sts` | StatefulSet-created PVCs get the selector labels – easy to list/clean up |
| 3 | Scale-down kept `data-web-2`; scale-up reattached it | Default `persistentVolumeClaimRetentionPolicy` = Retain on scale-down and delete. Configurable (`whenScaled`/`whenDeleted: Delete`) |
| 4 | `web-2` still **Terminating after 15 s**; deleting `web-1` also took ~30 s | The container (`sh` running `sleep infinity`) **ignores SIGTERM**, so Kubernetes waits the full `terminationGracePeriodSeconds` (30 s) then kills it. Real apps must handle SIGTERM to shut down cleanly and quickly – especially important for StatefulSets, which stop Pods one at a time |
| 5 | `oc wait pod/web-2` returned immediately, then `exec` failed: *container is not created or running* | The wait matched the **old, still-terminating** `web-2` (same name!). With stable names, scripts must wait on the **new** Pod (e.g. check `metadata.uid` changed, or `oc rollout status sts/web`) |
| 6 | Pods spread over both nodes | Not guaranteed – production stateful apps add pod anti-affinity / topology spread so replicas don't share a node |
| 7 | RWO on NFS | Not enforced by NFS (OCP-019); on block storage RWO also ties a volume to one node, which affects rescheduling |

## 8. Production considerations
- Use StatefulSets (or better, an **Operator**) for databases/clustered apps that need stable identity + per-replica storage; replication itself is the app's job.
- Handle **SIGTERM** and set a realistic grace period; ordered shutdown multiplies slow stops.
- **Anti-affinity / topology spread** across nodes and zones; **PodDisruptionBudget** for upgrades.
- Pick a StorageClass with the right performance, reclaim policy and expansion; back up each replica's PVC.
- Decide the PVC retention policy explicitly; clean up orphaned PVCs after decommissioning.
- `podManagementPolicy: Parallel` when ordering isn't needed (faster scale-out).

## 9. Lessons learned
- StatefulSet = stable name + stable storage + stable DNS + ordering.
- Data follows the **name**, not the Pod object – deleting or scaling never loses it by default.
- Same-name replacement Pods need careful scripting.

## 10. Interview talking point
> "I built a three-replica StatefulSet with a headless Service and a volumeClaimTemplate for 1Gi RWO on the default StorageClass. Pods came up in order as web-0, web-1, web-2, each with its own PVC – data-web-0 to 2 – and each pod resolved at its own DNS name while the headless service returned all three IPs. Deleting web-1 brought back web-1 on the same PVC with its data, and scaling down kept data-web-2, which the new web-2 reattached on scale-up. Two practical findings: my test container ignored SIGTERM so each stop took the full 30-second grace period, and a script waiting on 'web-2' matched the old terminating pod – with stable names you have to wait on the new pod's UID or the rollout status."
