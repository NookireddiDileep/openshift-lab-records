# OCP-012: Create a MySQL database from an OpenShift Template – persistent, probed, and proven durable

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Templates · Stateful apps · Persistent storage (PVC) |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~25 min |
| **Status** | Done |
| **Related** | [OCP-011 – MySQL from a Docker image](OCP-011-mysql-database-from-docker-image.md) · [RCA-002 – data loss without PVC](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md) |

## 1. User story / requirement
> As an **application team**, I want a **MySQL database created from an OpenShift Template**, so that **I get a correctly designed database stack (credentials, storage, service, probes) in one step** – and it must be **Running**.

## 2. Acceptance criteria
- [x] Database created from an OpenShift Template
- [x] Pod Running and Ready; SQL verified
- [x] *(extra)* Inspected the template **before** using it (parameters, objects, StorageClass)
- [x] *(extra)* Compared with the Docker-image approach (OCP-011)
- [x] *(extra)* **Durability test passed** – data survived Pod deletion (the test that failed in RCA-002)

## 3. Background / concepts
- **Template** = a parameterised list of objects. `oc process` renders it; `oc new-app --template` renders **and** creates. Parameters can have **generators** (`expression` → random values) – used here for user and passwords.
- `mysql-persistent` (shipped by the **Samples Operator** in the `openshift` namespace) creates: **Secret**, **Service**, **PersistentVolumeClaim**, **DeploymentConfig**.
- **PVC → PV → StorageClass:** the PVC asks for 1 Gi RWO; the default StorageClass dynamically provisions a PV for it; the Pod mounts it at the data directory, so the data outlives any single Pod.

## 4. Plan
1. List database templates; inspect `mysql-persistent` – description, parameters, objects; confirm a default StorageClass exists.
2. `oc new-app --template=mysql-persistent` with service name, database name and volume size; let it generate credentials.
3. Verify PVC Bound, rollout, SQL, volume mount, probes, strategy, SCC, image.
4. Durability test: write → delete Pod → read back.
5. **Rollback:** `oc delete all,pvc,secret -l template=mysql-persistent-template` (⚠️ deleting the PVC deletes the data – reclaim policy `Delete`).

## 5. Implementation
Script: [`scripts/OCP-012/mysql-from-template.sh`](../scripts/OCP-012/mysql-from-template.sh)
```bash
oc get templates -n openshift | grep -Ei "mysql|mariadb|postgres"
oc process --parameters mysql-persistent -n openshift
oc get template mysql-persistent -n openshift -o jsonpath='{range .objects[*]}{.kind}{"  "}{.metadata.name}{"\n"}{end}'
oc get sc
oc new-app --template=mysql-persistent \
  -p DATABASE_SERVICE_NAME=mysql-tpl -p MYSQL_DATABASE=appdb -p VOLUME_CAPACITY=1Gi
```

## 6. Validation / evidence
**Templates available** (database-related, trimmed):
```
mariadb-ephemeral / mariadb-persistent
mysql-ephemeral   / mysql-persistent
postgresql-ephemeral / postgresql-persistent
cakephp-mysql-*, dancer-mysql-*, django-psql-*, nodejs-postgresql-*, rails-*   (app + DB examples)
```
**Template inspected before use:**
```
Labels:      samples.operator.openshift.io/managed=true
Description: MySQL database service, with persistent storage ...
             NOTE: Scaling to more than one replica is not supported. You must have persistent volumes available ...

NAME                    GENERATOR    VALUE
MEMORY_LIMIT                         512Mi
DATABASE_SERVICE_NAME                mysql
MYSQL_USER              expression   user[A-Z0-9]{3}
MYSQL_PASSWORD          expression   [a-zA-Z0-9]{16}
MYSQL_ROOT_PASSWORD     expression   [a-zA-Z0-9]{16}
MYSQL_DATABASE                       sampledb
VOLUME_CAPACITY                      1Gi
MYSQL_VERSION                        8.0-el8

Objects: Secret, Service, PersistentVolumeClaim, DeploymentConfig

$ oc get sc
NAME                    PROVISIONER                                   RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION
nfs-storage (default)   k8s-sigs.io/nfs-subdir-external-provisioner   Delete          Immediate           false
```
**Created:**
```
--> Deploying template "mysql-persistent" ...
    * MySQL Connection Username=<generated>
    * MySQL Connection Password=<generated – redacted>
    * MySQL root user Password=<generated – redacted>
    * MySQL Database Name=appdb
    secret "mysql-tpl" created
    service "mysql-tpl" created
    persistentvolumeclaim "mysql-tpl" created
Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
    deploymentconfig.apps.openshift.io "mysql-tpl" created
```
**PVC bound, rolled out, Running:**
```
NAME        STATUS   VOLUME          CAPACITY   ACCESS MODES   STORAGECLASS
mysql-tpl   Bound    pvc-52155a1e…   1Gi        RWO            nfs-storage

replication controller "mysql-tpl-1" successfully rolled out
mysql-tpl-1-2zpd6    1/1   Running     0   14s
mysql-tpl-1-deploy   0/1   Completed   0   18s      ← DeploymentConfig's deployer Pod
```
**SQL, storage, security, probes, strategy:**
```
VERSION()   DATABASE()   CURRENT_USER()
8.0.45      appdb        user<XXX>@%

$ df -h /var/lib/mysql/data
<nfs-server>:/<export>/my-apps-mysql-tpl-pvc-52155a1e…  226G  78G  148G  35%  /var/lib/mysql/data   ← NFS volume, not overlay

uid=1001250000(1001250000) gid=0(root)              SCC: restricted-v2
image: image-registry.openshift-image-registry.svc:5000/openshift/mysql@sha256:99f64deb…     ← Red Hat image, by digest
readiness: exec  MYSQL_PWD="$MYSQL_PASSWORD" mysqladmin -u $MYSQL_USER ping
liveness:  exec  (same command)  initialDelaySeconds=30 periodSeconds=10 timeoutSeconds=1 failureThreshold=3
strategy:  Recreate
```
**Durability test – write, delete the Pod, read back:**
```
$ ... -e "CREATE TABLE t(...); INSERT INTO t VALUES (1,'survives a restart?'); SELECT * FROM t;"
id      note
1       survives a restart?

$ oc delete pod mysql-tpl-1-2zpd6
old=mysql-tpl-1-2zpd6  new=mysql-tpl-1-jz9ms
mysql-tpl-1-jz9ms    1/1   Running   0   62s

$ oc logs $NEW | grep -Ei "initializ|ready for connections"
[InnoDB] InnoDB initialization has ended.                          ← normal engine start
/usr/libexec/mysqld: ready for connections. Version: '8.0.45' ... port: 3306     ← ONE line, no port-0 init server

$ ... -e "SELECT * FROM t;"
id      note
1       survives a restart?                                         ← DATA SURVIVED
```

## 7. Template vs. Docker image (OCP-011)
| | OCP-011 `oc create deployment` (Docker Hub) | OCP-012 `mysql-persistent` template |
|---|---|---|
| Credentials | added manually (Secret) | **generated** into a Secret |
| Data | container overlay → **lost** on Pod delete ([RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md)) | **PVC** → **survived** Pod delete |
| Readiness / liveness | none | `mysqladmin ping` both |
| Strategy | RollingUpdate | **Recreate** |
| Service | none | created |
| Image | Docker Hub `mysql:8.0` | Red Hat `mysql:8.0-el8` via `openshift` ImageStream, by digest |
| Workload type | Deployment | **DeploymentConfig** (deprecated) |

## 8. Issues hit & observations
| # | Observation | Explanation / impact |
|---|---|---|
| 1 | Template creates a **DeploymentConfig** – deprecation warning on every command | DCs are deprecated since OCP 4.14. `oc rollout status deployment/…` doesn't find it – use `dc/`. Migrate to a Deployment (or an Operator) for new work |
| 2 | **`oc new-app` printed the generated passwords** to the terminal | Credentials end up in scrollback, screen-shares, CI logs. Redirect output, or pre-create the Secret; rotate if exposed. Redacted here |
| 3 | Storage is **NFS** (`nfs-subdir-external-provisioner`) | Fine for labs; for databases NFS is generally discouraged (locking, latency) and **can't enforce RWO** – two Pods could mount it. Prefer block storage (e.g. ODF/Ceph RBD, cloud disks) |
| 4 | Reclaim policy **Delete**, **no volume expansion** | Deleting the PVC deletes the data; the volume can't be grown later – size it right or pick a StorageClass that allows expansion |
| 5 | Liveness `timeoutSeconds: 1` | Tight – a busy database or slow storage could fail the probe and get restarted. Consider 3–5 s |
| 6 | `mysql-tpl-1-deploy` Pod left in `Completed` | DeploymentConfig deployer Pod – normal for DCs |
| 7 | Template note: **"Scaling to more than one replica is not supported"** | Single instance, no HA – production needs replication via an Operator or a managed DB |

## 9. Production considerations
- Use a **database Operator** (or a managed service) for HA, backups, upgrades; templates give a single instance.
- **Block storage** with snapshots for databases; check reclaim policy (`Retain` for important data) and expansion support.
- **Backups + restore tests** – a PVC protects against Pod loss, not against corruption, deletion or cluster loss.
- Keep generated credentials out of logs; store/rotate them via Secrets or an external vault.
- Prefer templates/manifests that create **Deployments** (DCs are deprecated); keep the template's good defaults (probes, Recreate, Secret, PVC).

## 10. Lessons learned
- A good template encodes operational knowledge – probes, storage, strategy, secrets – that a one-line `oc create deployment` leaves out.
- The durability test (write → delete → read) is the real proof of persistence; logs confirm it (no re-initialisation).
- Read a template before you run it: parameters, generated values, objects, and its own warnings.

## 11. Interview talking point
> "I deployed MySQL from the `mysql-persistent` OpenShift template after inspecting its parameters and objects. It generated credentials into a Secret, created a Service and a 1 Gi PVC on the default StorageClass, and a DeploymentConfig with readiness and liveness probes and the Recreate strategy. I verified it with SQL and then repeated the durability test that had lost data with a plain Deployment: I wrote a row, deleted the Pod, and the row was still there – the logs showed no re-initialisation. I also flagged that the template uses a deprecated DeploymentConfig, prints passwords to the terminal, and that NFS isn't ideal for databases."
