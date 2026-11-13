# RCA-002: MySQL data lost after Pod replacement – database stored on the container's ephemeral layer

| Field | Value |
|---|---|
| **Date** | 2026-11-13 |
| **Environment** | Lab OpenShift 4.19 cluster, project `my-apps` (sanitised) |
| **Severity** | Sev2 in production terms (data loss); lab: simulated |
| **Component** | Deployment `mysql-db` · storage · self-healing |
| **Status** | Root cause confirmed; fix designed (PVC) – to be implemented |
| **Time to detect / resolve** | immediate (test) / fix pending |
| **Related story** | [OCP-011 – MySQL from a Docker image](../stories/OCP-011-mysql-database-from-docker-image.md) |

## 1. Problem statement
After the `mysql-db` Pod was deleted (simulating a crash, eviction or node failure), the Deployment created a replacement Pod that started with an **empty database** – table `appdb.t` and its rows were gone.

## 2. Impact
- **All data written to the database was lost** (in production: every record since the last Pod start).
- The application would have reconnected to an empty schema – a silent failure: the Pod was Running and Ready.
- Lab: one test table; no external users.

## 3. Symptoms & detection
Detected by a deliberate test (data written → Pod deleted → data read back):
```
$ oc exec $POD -- mysql ... -e "SELECT * FROM t;"
id      note
1       hello from OCP                         ← before

$ oc delete pod mysql-db-87bd997f8-7qqk8
deployment "mysql-db" successfully rolled out
old=mysql-db-87bd997f8-7qqk8  new=mysql-db-87bd997f8-76vks

$ oc exec $NEW -- mysql ... -e "SELECT * FROM t;"
ERROR 1146 (42S02) at line 1: Table 'appdb.t' doesn't exist   ← after
```
Health signals showed **nothing wrong**: Pod `Running`, `1/1 Ready`, 0 restarts.

## 4. Timeline
| Time (IST) | Event |
|---|---|
| 16:32 | MySQL initialised; table `t` created and row inserted |
| 16:35 | Row confirmed present; Pod deleted |
| 16:35 | ReplicaSet created a replacement Pod (self-healing worked) |
| 16:35 | New Pod log: temporary init server (`port: 0`) – **database initialised from scratch** |
| 16:36 | Query failed: `Table 'appdb.t' doesn't exist` – data loss confirmed |

## 5. Investigation
| # | Hypothesis | Check | Result |
|---|---|---|---|
| 1 | Connected to a different database/user | Same Secret, same `MYSQL_DATABASE=appdb`, same user | **Ruled out** |
| 2 | Table dropped by someone | Fresh init sequence in the new Pod's logs; no other clients | **Ruled out** |
| 3 | Data directory not persistent | `df -h /var/lib/mysql` and the Deployment's volumes | **Confirmed** |

```
$ oc exec $POD -- df -h /var/lib/mysql
overlay         120G   75G   45G  63% /        ← the container's root overlay, not a mounted volume
```
The new Pod's logs show the temporary initialisation server again – it only runs when the data directory is empty:
```
mysqld: ready for connections. Version: '8.0.46' ... port: 0      ← init of an EMPTY data dir
mysqld: ready for connections. Version: '8.0.46' ... port: 3306
```

## 6. Root cause
The Deployment was created with `oc create deployment --image=…`, which defines **no volumes**. MySQL therefore wrote its data directory `/var/lib/mysql` into the **container's writable overlay layer**. That layer belongs to the container and is **deleted when the Pod is deleted**. The ReplicaSet correctly replaced the Pod – but a new Pod gets a new, empty writable layer, so MySQL initialised a fresh database.

**5 Whys**
1. Why was the table missing? → The new Pod started with an empty data directory.
2. Why was it empty? → Data lived in the old container's writable layer, which was deleted with the Pod.
3. Why there? → No volume was mounted at `/var/lib/mysql`.
4. Why no volume? → `oc create deployment` creates a stateless Deployment; storage must be added explicitly, and it wasn't.
5. Why wasn't that caught? → Validation checked "Running" and SQL access, not **durability**; health checks can't detect missing persistence.

## 7. Resolution (designed – to implement in the follow-up)
```bash
# persistent volume for the data directory
oc set volume deployment/mysql-db --add --name=mysql-data \
  --type=pvc --claim-name=mysql-db-data --claim-size=1Gi --claim-mode=ReadWriteOnce \
  --mount-path=/var/lib/mysql
# single writer on an RWO volume: no overlapping Pods during updates
oc patch deployment/mysql-db -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
```
Verification to perform: write a row → delete the Pod → new Pod logs show **no** initialisation → row still present.

## 8. Preventive actions
| Action | Type | Owner | Status |
|---|---|---|---|
| PVC for every stateful workload's data path | Prevent | me | Planned (follow-up) |
| Use StatefulSet / database Operator for databases | Prevent | platform team | Recommended |
| Add a **durability test** (write → delete Pod → read) to the acceptance checklist for stateful apps | Detect | me | Done (this RCA) |
| Policy check: flag database images deployed without a volume on their data path | Detect | platform team | Proposed |
| Regular backups (`mysqldump` CronJob / volume snapshots) + restore test | Recover | app team | Proposed |
| Readiness probe so "Ready" means "accepting connections" | Prevent | me | Proposed (patch in OCP-011) |

## 9. Lessons learned
- **Self-healing restores Pods, not data.** A healthy-looking Pod can be serving an empty database.
- `oc create deployment` / plain Deployments are stateless by default – persistence is always an explicit decision.
- Test failure modes deliberately; "Running" and even "SQL works" didn't reveal this.

## 10. Interview talking point
> "In a lab I ran MySQL from the Docker image as a plain Deployment and then deliberately deleted the Pod. Self-healing worked – a new Pod came up Running and Ready – but my table was gone. The data directory was on the container's overlay layer because no volume was mounted, so the new Pod initialised an empty database; the logs showed the init server running again. The fix is a PVC on `/var/lib/mysql`, Recreate strategy for the single-writer volume, ideally a StatefulSet or an Operator, plus backups – and I added a write-delete-read durability test to my checklist for any stateful app."
