# OCP-019: Create a static 1Gi NFS PersistentVolume and PVC and bind it to a Pod

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Storage · Static provisioning · PV/PVC binding · NFS |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~25 min |
| **Status** | Done |
| **Related** | [OCP-012 – dynamic PVC via StorageClass](OCP-012-mysql-from-openshift-template.md) · [RCA-002 – data loss without a volume](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md) |

## 1. User story / requirement
> As a **platform administrator**, I want to **create a static 1Gi PersistentVolume on an existing NFS export, a PersistentVolumeClaim, and bind it to a Pod**, so that **an application can use pre-existing shared storage**.

Given: NFS server `<nfs-server>`, export path `/do-180`.

## 2. Acceptance criteria
- [x] Static PV (1Gi, NFS) created
- [x] PVC created and **bound to that specific PV** (not a dynamically provisioned one)
- [x] Pod running with the volume mounted; write + read works
- [x] *(extra)* Data survives Pod deletion
- [x] *(extra)* Documented NFS behaviour: capacity not enforced, shared contents, ID squashing

## 3. Background / concepts
| | Dynamic provisioning (OCP-012) | **Static provisioning (this story)** |
|---|---|---|
| Who creates the PV | the StorageClass provisioner, on demand | an **administrator**, by hand |
| What the PV points at | a new, private directory/disk per PVC | an **existing** export/disk chosen by the admin |
| PVC asks for | a StorageClass | `storageClassName: ""` + (optionally) a specific `volumeName` |
| Isolation | per PVC (own subdirectory) | whatever the admin points it at – here a **shared** folder |

```
NFS <nfs-server>:/do-180
        ▲
PersistentVolume  pv-do180-<ns>   (cluster-scoped, 1Gi, RWX, Retain, claimRef → my PVC)
        ▲  1:1 binding
PersistentVolumeClaim  pvc-do180  (my namespace, 1Gi, storageClassName "", volumeName → my PV)
        ▲
Pod nfs-pod  →  /data
```
**Two traps on a shared cluster, and how the manifest avoids them**
1. **Default StorageClass hijack** – the cluster has a default class; a PVC without `storageClassName: ""` would get a *new dynamic* volume instead of my PV.
2. **PV theft** – PVs are cluster-wide; any matching PVC in any namespace could bind it. `claimRef` on the PV + `volumeName` on the PVC reserve the pair for each other; a unique PV name avoids name clashes.

## 4. Plan
1. Check rights to create PVs (cluster-scoped), existing PVs for the export, and StorageClasses.
2. Apply PV + PVC + Pod (server dry run first).
3. Verify PV/PVC status, the mount inside the Pod, write/read.
4. Delete and recreate the Pod; confirm data persists.
5. **Rollback:** delete Pod and PVC; with `Retain`, the PV goes to `Released` – delete it explicitly. Data on the NFS export is **not** deleted (clean up own files manually).

## 5. Implementation
Manifest: [`scripts/OCP-019/static-pv-pvc-pod.yaml`](../scripts/OCP-019/static-pv-pvc-pod.yaml)
```bash
oc auth can-i create persistentvolumes         # yes (admin group in this lab)
oc get pv | grep -i do-180 || echo "no existing PV for /do-180"
oc get sc                                       # nfs-storage (default) exists → must opt out
oc apply -f static-pv-pvc-pod.yaml --dry-run=server && oc apply -f static-pv-pvc-pod.yaml
```

## 6. Validation / evidence
**PV and PVC bound to each other – no StorageClass involved:**
```
PV                 CAP   MODES             RECLAIM   STATUS   CLAIM       SC
pv-do180-my-apps   1Gi   [ReadWriteMany]   Retain    Bound    pvc-do180   <none>

NAME        STATUS   VOLUME             CAPACITY   ACCESS MODES   STORAGECLASS
pvc-do180   Bound    pv-do180-my-apps   1Gi        RWX            (empty)
```
**Pod events – waited for the binding first:**
```
Warning  FailedScheduling  0/2 nodes are available: pod has unbound immediate PersistentVolumeClaims.   (×2, ~28 s)
Normal   Scheduled         Successfully assigned my-apps/nfs-pod to worker-1
```
**Mounted, writable – and the real size:**
```
$ oc exec nfs-pod -- df -h /data
<nfs-server>:/do-180  226G   77G  149G  35% /data        ← 226G visible, not 1Gi

$ oc exec nfs-pod -- id
uid=1001250000(1001250000) gid=0(root) groups=0(root),1001250000

$ ... echo "written by ... at ..." > /data/nooki-test.txt && cat /data/nooki-test.txt
written by  at Fri Nov 13 12:03:52 UTC 2026                ← empty name: no `hostname` binary in ubi-minimal
```
**Shared contents and ID squashing:**
```
$ ls -l /data | head
-rw-r--r--. 1 <other-uid> nobody  0  <other trainee's test file>
-rw-r--r--. 1       1001 nobody   0  file01 … file08         ← other users' files on the same export

$ ls -ln /data/nooki-test.txt
-rw-r--r--. 1 1001250000 65534 44  /data/nooki-test.txt     ← my UID kept, GID 0 squashed to 65534 (nobody)
```
**Persistence across Pod replacement:**
```
$ oc delete pod nfs-pod && oc apply -f static-pv-pvc-pod.yaml
persistentvolume/pv-do180-my-apps configured                ← see §7 #6
persistentvolumeclaim/pvc-do180 unchanged
pod/nfs-pod created
pod/nfs-pod condition met
$ oc exec nfs-pod -- cat /data/nooki-test.txt
written by  at Fri Nov 13 12:03:52 UTC 2026                 ← same data
PV phase: Bound
```

## 7. Issues hit & observations
| # | Observation | Explanation / impact |
|---|---|---|
| 1 | **`df` shows 226G, not 1Gi** | NFS PVs **don't enforce capacity** – `1Gi` is only used to match PVC to PV. A Pod can fill the whole export. Enforce limits with **quotas on the NFS server** (or use storage that enforces size) |
| 2 | **Other users' files visible** in `/data` | The static PV points at a **shared directory** – every PV/Pod using `/do-180` shares data. No isolation between namespaces/teams. Dynamic provisioning (OCP-012) avoided this with a per-PVC subdirectory |
| 3 | My file: **GID 0 → 65534 (nobody)** | The NFS server squashes GID 0 (root group) to `nobody`. Apps relying on group-0 permissions (the OpenShift random-UID pattern) may hit permission problems on such exports |
| 4 | `FailedScheduling … unbound immediate PersistentVolumeClaims` (~28 s) | Pod was created in the same apply as the PVC; the scheduler waits until the claim is bound. Harmless; to avoid it, apply PV/PVC first and the Pod after `oc wait` on the PVC |
| 5 | `hostname: command not found` | ubi-minimal doesn't ship it (use `$HOSTNAME` or `cat /etc/hostname`) |
| 6 | Re-apply printed `persistentvolume … configured` without my changing it | After binding, the controller fills extra fields in the PV's `claimRef` (the PVC's UID/resourceVersion); `oc apply` reconciles against them. Harmless |
| 7 | `Retain` reclaim policy | Deleting the PVC leaves the PV `Released` and the data on the export – safe for shared data, but needs manual cleanup |

## 8. Production considerations
- **Prefer dynamic provisioning** (CSI / StorageClass) for isolation, size enforcement and automation; use static PVs for pre-existing data or special cases.
- When static PVs are needed: **unique names**, `claimRef`/`volumeName` pre-binding, labels for ownership, and a **dedicated export or subdirectory per consumer**.
- Set **NFS server-side quotas**; agree on squash/ownership settings with the storage team (UID/GID mapping vs. OpenShift's random UIDs).
- Restrict who can create PVs (cluster-admin only) – a PV can point at any NFS server/path the nodes can reach.
- Document reclaim behaviour; `Retain` needs an operational process to clean up.

## 9. Lessons learned
- `storageClassName: ""` is the switch between static and dynamic binding when a default StorageClass exists.
- `claimRef` + `volumeName` make a static binding deterministic on a shared cluster.
- NFS "capacity" is a label, not a limit – check what's really behind a PV with `df` inside the Pod.

## 10. Interview talking point
> "I created a static NFS PersistentVolume and PVC and bound them to a Pod. Because the cluster had a default StorageClass, I set `storageClassName: ""` on the claim – otherwise it would have been dynamically provisioned – and pre-bound the pair with `claimRef` and `volumeName` so no other namespace's claim could take the PV. Inside the Pod, `df` showed the whole 226-gigabyte export, not 1Gi: NFS doesn't enforce PV capacity, so quotas belong on the server. The export was shared with other users' files, and the server squashed my group 0 to nobody – exactly why I'd prefer dynamic, per-claim provisioning for isolation and keep static PVs for pre-existing data."
