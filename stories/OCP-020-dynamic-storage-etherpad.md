# OCP-020: Allocate 1Gi of dynamic storage to an application – and fix Etherpad's data loss

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Storage · Dynamic provisioning · StorageClass · Stateful apps |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~35 min |
| **Status** | Done |
| **Related** | [OCP-004 – Etherpad DirtyDB inside the container](OCP-004-third-party-image-etherpad.md) · [OCP-019 – static PV](OCP-019-static-pv-pvc-nfs.md) · [RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md) |

## 1. User story / requirement
> As an **application team**, I want **1Gi of dynamically provisioned storage allocated to my application**, so that **its data survives restarts without an administrator creating volumes by hand**.

Application chosen: **app-03 (Etherpad)** – in [OCP-004](OCP-004-third-party-image-etherpad.md) I found it stores all pads in `dirty.db` **inside the container**, so every restart lost them. This story closes that follow-up.

## 2. Acceptance criteria
- [x] 1Gi PVC created **without** a pre-made PV; the default StorageClass provisions it
- [x] PVC Bound; PV created automatically by the provisioner
- [x] Volume mounted at the application's data directory; app starts normally
- [x] **Application data survives Pod deletion** – proven with the app's own API + export, and in the browser

## 3. Background / concepts
| | Static (OCP-019) | **Dynamic (this story)** |
|---|---|---|
| Who creates the PV | admin, by hand | the **StorageClass provisioner**, on demand |
| PVC specifies | `storageClassName: ""` + `volumeName` | nothing / a class name → **default class** used |
| Storage location | an existing shared path | a **new private directory per PVC** |
| Reclaim policy | chosen by admin (`Retain` here) | from the StorageClass (`Delete` here) |

```
oc set volume --type=pvc --claim-size=1Gi  ──► PVC app-03-data (no class named → default: nfs-storage)
                                                   │
                       nfs-subdir-external-provisioner creates
                                                   ▼
             PV pvc-<uid>  →  NFS dir  <namespace>-app-03-data-pvc-<uid>   (private to this PVC)
                                                   ▲
                       Deployment app-03 mounts it at /opt/etherpad-lite/var (dirty.db)
```
**Why `Recreate`:** Etherpad writes one database file. With the default RollingUpdate, the old and new Pods would briefly run **together on the same file** → corruption risk (and NFS doesn't enforce RWO – OCP-019).

## 4. Plan
1. Record the "before": no volumes, data dir on `overlay`.
2. Switch strategy to `Recreate`.
3. `oc set volume --add --type=pvc --claim-size=1Gi` at `/opt/etherpad-lite/var`.
4. Verify PVC/PV, provisioner, mount, permissions, app start.
5. Prove persistence with real application data across a Pod deletion.
6. **Rollback:** `oc set volume deployment/app-03 --remove --name=etherpad-data`; delete PVC (⚠️ reclaim `Delete` removes the data).

## 5. Implementation
Script: [`scripts/OCP-020/add-dynamic-storage.sh`](../scripts/OCP-020/add-dynamic-storage.sh)
```bash
oc patch deployment app-03 --type=merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
oc set volume deployment/app-03 --add --name=etherpad-data \
  --type=pvc --claim-name=app-03-data --claim-size=1Gi --claim-mode=rwo \
  --mount-path=/opt/etherpad-lite/var
```

## 6. Validation / evidence
**Before:**
```
strategy: RollingUpdate
volumes: (none)
overlay   150G   89G   62G  60% /              ← data dir inside the container
```
**After – dynamic provisioning:**
```
NAME          STATUS   VOLUME          CAPACITY   ACCESS MODES   STORAGECLASS
app-03-data   Bound    pvc-86161c98…   1Gi        RWO            nfs-storage

PV              CAP   RECLAIM   SC            STATUS
pvc-86161c98…   1Gi   Delete    nfs-storage   Bound
provisioned-by: k8s-sigs.io/nfs-subdir-external-provisioner
nfs path:       <export-root>/my-apps-app-03-data-pvc-86161c98…        ← private directory named <ns>-<pvc>-<pv>
```
**Mounted and writable:**
```
<nfs-server>:<export-root>/my-apps-app-03-data-pvc-…  226G  77G  149G  35% /opt/etherpad-lite/var
drwxrwxrwx. 2 root       root  22  .                  ← provisioner creates the dir world-writable
-rw-r--r--. 1 1001250000 root   0  dirty.db           ← created by the random UID; group root kept (no squash on this export)
[WARN]  DirtyDB is used ... File location: /opt/etherpad-lite/var/dirty.db
[INFO]  You can access your Etherpad instance at http://0.0.0.0:9001/
```
**Persistence – first attempts and what they taught me** (see §7):
```
curl /p/nooki-pad            → HTTP 200, but grep "pad:nooki-pad" = 0     ← curl doesn't create a pad
browser opened pad           → dirty.db 174 → 2322 bytes; still 2322 after Pod restart; pad key count = 2
typed text grep / export     → text never saved (typing didn't reach the server)
```
**Persistence – conclusive test via Etherpad's API and export:**
```
$ curl -s "http://<route>/api/1/setText" --data-urlencode "apikey=$KEY" \
       --data-urlencode "padID=nooki-pad" --data-urlencode "text=persistence test by nooki 12:13"
{"code":0,"message":"ok","data":null}

--- before restart:
persistence test by nooki 12:13
pod "app-03-…" deleted
deployment "app-03" successfully rolled out
--- after restart:
persistence test by nooki 12:13                  ← data survived the Pod replacement
```

## 7. Issues hit & observations
| # | Observation | Explanation / lesson |
|---|---|---|
| 1 | `curl /p/<pad>` returned 200 but created no pad | The page is just HTML; Etherpad creates and edits pads over a **websocket from the browser's JavaScript**. Test an app through its real interfaces |
| 2 | `grep` for typed text found nothing | Typing hadn't reached the server; also Etherpad stores edits as changesets, so raw-file greps are unreliable. The app's **export** endpoint is the right read path |
| 3 | Final proof used the **Etherpad HTTP API** (`setText`) + **export** | Deterministic, scriptable, no UI timing issues; the API key was read inside the Pod and never printed |
| 4 | Provisioned dir is **`drwxrwxrwx`** and files keep **group root** | Unlike the static `/do-180` export (GID squashed to `nobody`, OCP-019), this export works with OpenShift's random UID out of the box |
| 5 | PVC got its **own directory** `<ns>-<pvc>-<pv-name>` | Isolation per claim – the main advantage over the shared static export |
| 6 | Reclaim policy **`Delete`** | Deleting the PVC deletes the data – deliberate decision needed for important data (snapshot/backup or a `Retain` class) |
| 7 | `df` shows the export's full 226G | Same as OCP-019: NFS doesn't enforce the 1Gi request |
| 8 | `APIKEY.txt` lives outside `var/` | It's regenerated on every new Pod – API clients must re-read it; in production provide it via a Secret |
| 9 | Needed a Service + Route for app-03 to test in a browser | `oc expose deployment app-03 --port=9001` then `oc expose service/app-03` |

## 8. Production considerations
- Prefer **dynamic provisioning** (CSI) for isolation and automation; choose the StorageClass deliberately (performance, reclaim policy, expansion).
- **Recreate** (or a StatefulSet) for single-writer data; RWO is not enforced by NFS.
- Size limits need **server-side quotas** on NFS – or a storage backend that enforces size.
- Etherpad specifically: replace DirtyDB with a real database (PostgreSQL/MySQL) for production; keep secrets (API key, admin password) in Secrets.
- Back up PVC data (snapshots / OADP / app-level export) – a PVC protects against Pod loss, not against deletion or corruption.

## 9. Lessons learned
- One command – `oc set volume --add --type=pvc --claim-size=…` – creates the claim, triggers dynamic provisioning and mounts it.
- **Prove persistence with application-level data**, not just "the file still exists".
- When a test result looks wrong, question the test before the system.

## 10. Interview talking point
> "Etherpad was keeping its data inside the container, so every restart lost every pad. I allocated a 1Gi dynamically provisioned volume with `oc set volume`: the PVC used the default StorageClass, the NFS provisioner created a private directory and PV on demand, and I mounted it at Etherpad's data path – switching the Deployment to Recreate so two Pods never write the same database file. My first persistence checks were misleading because a curl doesn't create a pad and the typed text never saved, so I used Etherpad's own API to write a known line, exported it, deleted the Pod, and exported it again – same text. Proving persistence at the application level, not just at the file level."
