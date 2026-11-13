# OCP-011: Run a MySQL database from a Docker image and get it to Running – then test its data

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Stateful apps · Secrets · Random UID · Storage |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~40 min |
| **Status** | Done (persistence gap → [RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md)) |

## 1. User story / requirement
> As an **application team**, I want a **MySQL database created from a Docker image with `oc create deployment`**, so that **my application has a database**, and **it must be in a Running state**.

Story steps: `podman search mysql` → `oc create deployment mysql-db --image=<image>` → make sure it's Running.

## 2. Acceptance criteria
- [x] Found the image with `podman search`
- [x] Created `mysql-db` with `oc create deployment`
- [x] Pod **Running** with 0 restarts
- [x] *(extra)* Proved it **works** with real SQL (version, database, user, create/insert/select)
- [x] *(extra)* Credentials stored in a **Secret**, never printed
- [x] *(extra)* Tested what happens to data when the Pod is replaced → **data lost** → [RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md)

## 3. Background / concepts
- **Databases refuse to start without credentials.** The official `mysql` image exits unless one of `MYSQL_ROOT_PASSWORD`, `MYSQL_ALLOW_EMPTY_PASSWORD` or `MYSQL_RANDOM_ROOT_PASSWORD` is set.
- **Secrets, not plain env vars:** `oc set env --from=secret/<name>` injects every key of a Secret as environment variables – values stay out of the Deployment spec, shell history and Git.
- **Random UID:** this image works under OpenShift's random UID because its data and socket directories are **world-writable with the sticky bit** (`drwxrwxrwt`) – a different approach from the "group 0 writable" pattern in OCP-004/007.
- **"Running" ≠ "ready" ≠ "durable".** A Pod can be Running before the database accepts connections (no readiness probe), and a database can be healthy while its data lives somewhere that disappears with the Pod.

## 4. Plan
1. Search images; pick the official one.
2. Create the Deployment exactly as the story says; observe.
3. Add credentials from a Secret; wait for rollout.
4. Prove it works with SQL; check UID, SCC, data location, probes.
5. Replace the Pod and check whether data survives.
6. **Rollback:** `oc delete deployment mysql-db && oc delete secret mysql-db-secret`.

## 5. Implementation
Script: [`scripts/OCP-011/mysql-db.sh`](../scripts/OCP-011/mysql-db.sh)
```bash
podman search docker.io/mysql --filter is-official=true
oc create deployment mysql-db --image=docker.io/library/mysql:8.0
oc create secret generic mysql-db-secret \
  --from-literal=MYSQL_ROOT_PASSWORD="$(openssl rand -base64 12)" \
  --from-literal=MYSQL_USER=appuser \
  --from-literal=MYSQL_PASSWORD="$(openssl rand -base64 12)" \
  --from-literal=MYSQL_DATABASE=appdb
oc set env deployment/mysql-db --from=secret/mysql-db-secret
```

## 6. Validation / evidence
**Search:**
```
$ podman search docker.io/mysql --filter is-official=true
docker.io/library/mysql  MySQL is a widely used, open-source relation...
$ podman search quay.io/sclorg/mysql --limit 5
quay.io/sclorg/mysql-80-c9s   MySQL 8.0 SQL Database Server container imag...   ← OpenShift-ready alternative
quay.io/sclorg/mysql-84-c9s   MySQL 8.4 SQL Database Server container imag...
```
**Created as the story says – fails without credentials:**
```
deployment.apps/mysql-db created
NAME                       READY   STATUS   RESTARTS      AGE
mysql-db-9f577798c-c6crm   0/1     Error    2 (22s ago)   45s

[ERROR] [Entrypoint]: Database is uninitialized and password option is not specified
    You need to specify one of the following as an environment variable:
    - MYSQL_ROOT_PASSWORD
    - MYSQL_ALLOW_EMPTY_PASSWORD
    - MYSQL_RANDOM_ROOT_PASSWORD
```
**Credentials from a Secret → new rollout → initialises:**
```
secret/mysql-db-secret created
deployment.apps/mysql-db updated
deployment "mysql-db" successfully rolled out
NAME                       READY   STATUS        RESTARTS   AGE
mysql-db-87bd997f8-7qqk8   1/1     Running       0          1s       ← "Ready" after 1 s (no readiness probe)
mysql-db-9f577798c-c6crm   0/1     Terminating   3          72s

[Note] [Entrypoint]: Initializing database files
[Warning] [MY-010122] One can only use the --user switch if running as root
[Warning] [MY-010453] root@localhost is created with an empty password ! ...   ← temporary, replaced by the Secret's password
```
**Running and accepting connections – two "ready" lines:**
```
mysqld: ready for connections. Version: '8.0.46'  socket: '/var/run/mysqld/mysqld.sock'  port: 0      ← temporary init server, no network
mysqld: ready for connections. Version: '8.0.46'  socket: '/var/run/mysqld/mysqld.sock'  port: 3306   ← real server

NAME                       READY   STATUS    RESTARTS   AGE
mysql-db-87bd997f8-7qqk8   1/1     Running   0          95s
```
**It actually works – real SQL** (credentials read from the Pod's environment, never shown):
```
$ oc exec $POD -- bash -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h 127.0.0.1 "$MYSQL_DATABASE" -e "SELECT VERSION() AS version, DATABASE() AS db, CURRENT_USER() AS user;"'
version db      user
8.0.46  appdb   appuser@%

$ ... -e "CREATE TABLE t(id INT PRIMARY KEY, note VARCHAR(50)); INSERT INTO t VALUES (1,'hello from OCP'); SELECT * FROM t;"
id      note
1       hello from OCP
```
**Why the random UID can write, and where the data lives:**
```
$ oc exec $POD -- id
uid=1001250000(1001250000) gid=0(root) groups=0(root),1001250000
$ oc exec $POD -- ls -ld /var/lib/mysql /var/run/mysqld
drwxrwxrwt. 1 mysql mysql 4096 /var/lib/mysql       ← world-writable + sticky bit
drwxrwxrwt. 1 mysql mysql  110 /var/run/mysqld
$ oc exec $POD -- df -h /var/lib/mysql
overlay         120G   75G   45G  63% /               ← container's own writable layer – NOT a volume
$ SCC: restricted-v2
$ readinessProbe: (empty)
```
**Data test – replace the Pod:** see [RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md) – the table was gone after the Deployment self-healed.

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | First Pod: `Error`, *"password option is not specified"* | Expected – the image requires credentials; fixed with a Secret |
| 2 | `oc logs --previous` → *"unable to retrieve container logs"* | The crashed container had already been removed during the restart. Capture logs promptly (or ship them to central logging) |
| 3 | **Ready after 1 s** | No readiness probe → OpenShift marks the Pod Ready as soon as the process starts; MySQL needed ~2 s more. Proposed: [`readiness-probe-patch.yaml`](../scripts/OCP-011/readiness-probe-patch.yaml) |
| 4 | Two `ready for connections` lines (`port: 0`, then `port: 3306`) | The entrypoint runs a temporary, network-less server to set the root password from the Secret, then starts the real one |
| 5 | `root@localhost … empty password` warning | Part of that temporary init; the Secret's password is applied before the real server starts |
| 6 | `--user switch` warning | The image is designed to start as root and drop to `mysql`; under a random UID the switch is ignored |
| 7 | Random UID could write `/var/lib/mysql` | Directories are `drwxrwxrwt` – my "permission denied" prediction was wrong |
| 8 | **Data on the container's overlay layer** | No volume mounted → data is deleted with the Pod → [RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md) |

## 8. Production considerations
- **Persistent storage is mandatory** for a database: a PVC (RWO) mounted at the data directory – or a managed/operator-run database.
- Use a **StatefulSet** (stable identity + per-replica volume) or a database Operator (e.g. MySQL/MariaDB/PostgreSQL operators) rather than a plain Deployment.
- **Readiness + liveness probes** (`mysqladmin ping`), and resource requests/limits (databases are memory-hungry).
- Deployment strategy **Recreate** for single-writer databases on RWO volumes (avoids two Pods using the same data during a rolling update).
- Credentials from Secrets (or an external vault); restrict who can read Secrets; rotate passwords.
- Prefer a supported image (e.g. Red Hat's `rhel9/mysql-80` / `sclorg` images) and avoid Docker Hub pull limits by mirroring (OCP-009).
- Backups (e.g. `mysqldump` CronJob, volume snapshots) – a PVC alone is not a backup.

## 9. Lessons learned
- "Running" is the weakest form of proof – verify with the application's own protocol (SQL here).
- Self-healing restores **Pods**, not **data**.
- Read entrypoint logs fully: the "empty password" and `port: 0` lines look alarming but are part of a normal init sequence.

## 10. Interview talking point
> "I deployed MySQL from the official Docker image with `oc create deployment`. It crash-looped first because no password was set, so I created a Secret with random credentials and injected it with `oc set env --from=secret` – the passwords were never printed. Then I proved it worked with real SQL, not just 'Running'. I also found the Pod was marked Ready before MySQL accepted connections because there was no readiness probe, and that the data lived on the container's overlay layer. I deleted the Pod: the Deployment self-healed, but the new Pod initialised an empty database and my table was gone – which is exactly why databases need a PVC, a StatefulSet or an Operator, plus probes and backups."

## Follow-ups
- [ ] Add a PVC at `/var/lib/mysql`, repeat the delete test, prove data survives
- [ ] Apply the readiness probe and show Ready only after MySQL answers
- [ ] Strategy `Recreate`; resource requests/limits
