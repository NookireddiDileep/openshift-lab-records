# OCP-013: Copy data from Pods to my local machine – files, directories, and a restore-tested database backup

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Data movement · Backup & restore · `oc cp` / `oc rsync` / `oc exec` |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~30 min |
| **Status** | Done |
| **Related** | [OCP-012 – MySQL from template](OCP-012-mysql-from-openshift-template.md) · [OCP-006 – oc exec without login](OCP-006-exec-without-login.md) |

## 1. User story / requirement
> As a **platform engineer**, I want to **copy data from running Pods to my local machine**, so that **I can take backups, collect evidence and move data out of the cluster when needed**.

"Local machine" here = the lab terminal where `oc` runs.

## 2. Acceptance criteria
- [x] File copied from a Pod to local, **verified by checksum**
- [x] Directory copied from a Pod to local
- [x] Database backup copied to local
- [x] *(extra)* **Backup proven by a restore drill**: drop table → restore from the local file → data back

## 3. Background / concepts
| Tool | Best for | Needs inside the container | Behaviour seen |
|---|---|---|---|
| `oc cp pod:/path ./dst` | single files / small dirs | `tar` | new timestamp (time of copy) |
| `oc rsync pod:/dir ./dst` | directories, repeatable syncs (delta only) | `rsync`, else falls back to `tar` | **destination must already exist**; preserves mtime/permissions |
| `oc exec pod -- cmd > file` | command output: DB dumps, logs, reports | just the command | streams stdout to a local file |
| `oc exec -i pod -- cmd < file` | sending local data **into** a Pod (e.g. restore) | the command | **`-i` required**, or stdin isn't forwarded |

**Logical vs. physical database backup:** `mysqldump` produces a consistent, portable SQL file (`--single-transaction` gives a consistent snapshot for InnoDB without locking). Copying raw InnoDB files (`*.ibd`) from a **running** server is not a reliable backup – data may still be in memory/redo logs, and a single `.ibd` can't be restored on its own.

## 4. Plan
1. Copy a web file with `oc cp`; compare SHA-256 inside the Pod vs. local.
2. Copy the web root directory with `oc rsync`.
3. Dump the MySQL database from OCP-012 to a local file with `oc exec … > file`.
4. Also stream raw DB files with `tar` – to show why it isn't a real backup.
5. **Restore drill:** drop the table, restore from the local dump, verify.
6. **Rollback:** local files can be deleted; the restore drill leaves the DB exactly as before.

## 5. Implementation
Script: [`scripts/OCP-013/copy-from-pod.sh`](../scripts/OCP-013/copy-from-pod.sh)

## 6. Validation / evidence
**1) `oc cp` – single file, checksum identical:**
```
$ oc cp $WEB_POD:/var/www/html/index.html ./index.html
tar: Removing leading `/' from member names                       ← oc cp runs tar in the container
-rw-r--r-- 1 <me> <me> 223 Nov 13 12:17 index.html               ← timestamp = time of copy

$ oc exec $WEB_POD -- sha256sum /var/www/html/index.html
4eb3724d8e5b440128746341721b15971169183fc4a91dbea537ab17713f778d  /var/www/html/index.html
$ sha256sum ./index.html
4eb3724d8e5b440128746341721b15971169183fc4a91dbea537ab17713f778d  ./index.html
```
**2) `oc rsync` – directory. First attempt failed:**
```
$ oc rsync $WEB_POD:/var/www/html ./web-backup
error: invalid path ./web-backup: stat ./web-backup: no such file or directory
```
**After `mkdir -p web-backup`:**
```
sent 47 bytes  received 343 bytes  780.00 bytes/sec           ← real rsync (image has it) – no tar fallback
total size is 223  speedup is 0.57
web-backup/html:
-rw-rw-r-- 1 <me> <me> 223 Nov 13 11:24 index.html             ← original mtime and group-write preserved
4eb3724d8e5b440128746341721b15971169183fc4a91dbea537ab17713f778d  web-backup/html/index.html
```
**3) Database backup to local (`oc exec … > file`):**
```
$ oc exec $DB_POD -- bash -c 'mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h127.0.0.1 \
      --no-tablespaces --single-transaction "$MYSQL_DATABASE"' > appdb-backup.sql
-rw-r--r-- 1 <me> <me> 1857 appdb-backup.sql
-- MySQL dump 10.13  Distrib 8.0.45, for Linux (x86_64)
-- Host: 127.0.0.1    Database: appdb
INSERT INTO `t` VALUES (1,'survives a restart?');
```
**4) Raw files streamed with tar (for comparison):**
```
$ oc exec $DB_POD -- tar czf - -C /var/lib/mysql/data appdb > appdb-files.tgz
appdb/
appdb/t.ibd                                ← a live InnoDB tablespace file – not a restorable backup on its own
```
**5) Restore drill – the proof the backup works:**
```
# simulate data loss
$ ... -e "DROP TABLE t;"
$ ... -e "SELECT * FROM t;"
ERROR 1146 (42S02) at line 1: Table 'appdb.t' doesn't exist

# restore from the file on my local machine (note -i)
$ oc exec -i $DB_POD -- bash -c 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -h127.0.0.1 "$MYSQL_DATABASE"' < appdb-backup.sql

# verify
$ ... -e "SELECT * FROM t;"
id      note
1       survives a restart?                ← data restored from the local backup
```
**Final local inventory:**
```
-rw-r--r--  1.9K  appdb-backup.sql
-rw-r--r--  2.1K  appdb-files.tgz
-rw-r--r--   223  index.html
drwxrwxr-x        web-backup/html/index.html
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | `oc rsync` → `invalid path ./web-backup` | Unlike `oc cp`, **`oc rsync` requires the local destination directory to exist** |
| 2 | `oc rsync` used real rsync; `oc cp` used tar | The UBI httpd image ships rsync. rsync preserved the original mtime (11:24) and permissions; `oc cp` stamped the copy time (12:17) |
| 3 | Restore as **root failed**: `ERROR 1045 Access denied for user 'root'@'localhost'` although `MYSQL_ROOT_PASSWORD` was set | MySQL accounts are **user@host**. Without `-h`, the client used the Unix socket → `root@localhost`, a different account. With `-h127.0.0.1` the same password logged in as **`root@%`** (verified: `CURRENT_USER()` → `root@%`). The image applies `MYSQL_ROOT_PASSWORD` to the network root account |
| 4 | My first restore attempt failed silently (`exit code 1` × 3) | I had appended `2>/dev/null`, which **hid the error**. Lesson: never suppress stderr while debugging – filter instead (`grep -v "Using a password"`) |
| 5 | Restored with the **application user**, no root needed | Least privilege: the app user owns `appdb`, so it can restore its own schema. Root is only needed for new databases |
| 6 | Raw `t.ibd` copy is not a backup | Live InnoDB files aren't consistent on their own; use `mysqldump`, a database-native tool, or storage snapshots with the DB quiesced |
| 7 | Credentials never left the Pod | Every `mysql`/`mysqldump` call read `$MYSQL_*` from the Pod's own environment |

## 8. Production considerations
- **Automate backups** (e.g. a CronJob running `mysqldump` to a backup PVC or object storage), with retention and encryption – manual copies to a bastion are for ad-hoc needs only.
- **A backup isn't proven until it's restored** – schedule restore tests.
- Treat local copies of production data as **sensitive**: encrypt, restrict, and delete when done; follow data-protection rules.
- Restrict `pods/exec` (used by `oc cp`, `oc rsync`, `oc exec`) via RBAC – it can exfiltrate data.
- For large data, prefer `oc rsync` (delta), compression, or volume snapshots (CSI) / OADP instead of streaming through the API server.

## 9. Lessons learned
- Pick the tool by **what** you copy: file (`oc cp`), directory (`oc rsync`), command output (`oc exec >`), data **into** a Pod (`oc exec -i <`).
- Always verify copies – checksums for files, a restore for backups.
- `user@host` matters in MySQL: socket and TCP logins can be different accounts.

## 10. Interview talking point
> "I copied data from Pods three ways: `oc cp` for a file – verified with matching SHA-256 inside and outside the Pod – `oc rsync` for a directory, which needed the destination to exist and preserved timestamps, and `oc exec` with output redirected for a consistent `mysqldump` backup. Then I proved the backup by dropping the table and restoring it from the local file with `oc exec -i`. Root login failed at first even though the password was set – it turned out the socket connection mapped to `root@localhost`, while the password belonged to `root@%`, which I confirmed over TCP. I restored with the app user instead, following least privilege."
