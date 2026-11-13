# OCP-004: Deploy a third-party image (Etherpad) as app-03 – and prove why it runs under restricted-v2

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Workloads · Image assessment · Security (random UID / SCC) |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~40 min |
| **Status** | Done |
| **Related** | [OCP-002](OCP-002-deployment-self-heal.md) · [OCP-001](OCP-001-bare-pod-no-self-heal.md) |

## 1. User story / requirement
> As an **application team**, I want **`app-03` deployed as a Deployment from an Etherpad container image**, so that **users get a collaborative editor** – running securely under OpenShift's default restrictions.

## 2. Acceptance criteria
- [x] Deployment `app-03` created from the Etherpad image in my namespace
- [x] Pod Running and Ready, no restarts
- [x] Admitted under the default `restricted-v2` SCC (no `anyuid`), no Pod Security warnings
- [x] Application answers over HTTP
- [x] *(extra)* Explained **why** the image works with OpenShift's random UID
- [x] *(extra)* Identified production risks in the image

## 3. Background / concepts
**OpenShift's random UID.** Under `restricted-v2`, OpenShift ignores the image's `USER` and runs the container as a **random high UID from the project's range**, always with **GID 0 (root group)**. This stops a compromised container from running as a predictable user.

**What this breaks.** Many community images assume they run as their own fixed user and write to folders owned by that user. With a random UID they hit `EACCES: permission denied` → `CrashLoopBackOff`.

**The correct fix (in the image, not the cluster).** Make writable paths **owned by group 0 and group-writable**:
```dockerfile
RUN chgrp -R 0 /app && chmod -R g=u /app
```
The wrong "fix" is granting `anyuid` – it works, but weakens isolation.

## 4. Plan
1. **Inspect the image before deploying** – user, ports, entrypoint, working dir, age.
2. Deploy with the hardened Deployment pattern from OCP-002; port 9001; more memory for Node.js.
3. Verify SCC, UID, health, logs.
4. Test HTTP pod-to-pod (image has no `curl`).
5. Check filesystem permissions to explain the result.
6. **Rollback:** `oc delete deployment app-03`.

## 5. Implementation
**Step 1 – image inspection (no deploy yet):**
```
$ oc image info <registry>/etherpad:<tag>
Created:       5y ago
Image Size:    104.9MB in 11 layers          (compressed)
OS / Arch:     linux / amd64
Entrypoint:    docker-entrypoint.sh
Command:       node --experimental-worker node_modules/ep_etherpad-lite/node/server.js
Working Dir:   /opt/etherpad-lite
User:          etherpad                      ← a name, not a UID
Exposes Ports: 9001/tcp
Environment:   NODE_VERSION=10.23.1, NODE_ENV=production
```
Risk assessment before deploying: named (non-numeric) user + app writes under its working dir → **likely permission problems under a random UID**; 5-year-old image on Node 10 → **unpatched**.

**Step 2 – deploy:** manifest [`scripts/OCP-004/app-03-deploy.yaml`](../scripts/OCP-004/app-03-deploy.yaml)
```bash
oc apply -f app-03-deploy.yaml --dry-run=server
oc apply -f app-03-deploy.yaml
oc rollout status deployment/app-03 --timeout=180s
```

## 6. Validation / evidence
**Running under restricted-v2:**
```
deployment "app-03" successfully rolled out
NAME                      READY   STATUS    RESTARTS   AGE
app-03-84ffd6f577-f2xdl   1/1     Running   0          82s

$ oc get pod $POD -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
restricted-v2

$ oc exec $POD -- id
uid=1001250000(1001250000) gid=0(root) groups=0(root),1001250000     ← random UID, GID 0
```
**Application started** (logs, DEBUG lines filtered):
```
[WARN]  DirtyDB is used. This is fine for testing but not recommended for production. File location: /opt/etherpad-lite/var/dirty.db
[WARN]  Update available: Download the actual version 3.3.17
[INFO]  Your Etherpad version is 1.8.7 (c89da1a)
[INFO]  You can access your Etherpad instance at http://0.0.0.0:9001/
```
**Why the random UID can write** – directories are group 0 and group-writable:
```
$ oc exec $POD -- ls -ldn /opt/etherpad-lite /opt/etherpad-lite/var /opt/etherpad-lite/SESSIONKEY.txt
drwxrwxr-x. 1       5001 0 68  /opt/etherpad-lite
drwxrwxr-x. 1       5001 0 22  /opt/etherpad-lite/var
-rw-r--r--. 1 1001250000 0 64  /opt/etherpad-lite/SESSIONKEY.txt     ← created by the random UID

$ oc exec $POD -- touch /opt/etherpad-lite/var/.writetest && echo WRITE_OK
WRITE_OK
```
**HTTP test pod-to-pod** (no `curl` in this image, so tested from app-02):
```
$ oc exec $POD -- sh -c 'command -v curl || echo "no curl in image"'
no curl in image

$ oc exec <app-02-pod> -- curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://<app-03-pod-ip>:9001/
HTTP 200
$ oc exec <app-02-pod> -- curl -s http://<app-03-pod-ip>:9001/ | grep -io '<title>.*</title>'
<title>Etherpad</title>
```
**Data is written inside the container:**
```
dirty.db: 0 bytes at start → 348 bytes after the first request
```

## 7. Issues hit & observations
| # | Observation | Explanation / impact |
|---|---|---|
| 1 | My prediction (permission denied under random UID) was **wrong** | This build was prepared for OpenShift: app directories are **GID 0 + group-writable** (`drwxrwxr-x … 5001 0`). Lesson: inspect *and* verify – don't assume |
| 2 | `curl` check inside the Pod printed nothing | Image has **no curl** (minimal image) and `2>/dev/null` hid the error. Tested from another Pod instead – which also proves pod-to-pod networking |
| 3 | **DirtyDB inside the container** (`/opt/etherpad-lite/var/dirty.db`) | **Every restart, reschedule or self-heal deletes all pads.** Needs a persistent volume (PVC) or an external database (PostgreSQL/MySQL) – see follow-ups |
| 4 | Etherpad **1.8.7** (log: 3.3.17 available), image **5 years old**, **Node 10** (end-of-life) | Unpatched CVEs likely. Not acceptable for production – rebuild on a supported base and current version, and scan the image |
| 5 | `ADMIN_PASSWORD` / `USER_PASSWORD` not set | Admin UI disabled (safe default here). In production, inject credentials from a **Secret**, never hard-code |
| 6 | Using the `:latest` tag | Not reproducible – the image behind `latest` can change. Pin a version tag or `@sha256` digest |
| 7 | Random session/API keys generated at startup (`SESSIONKEY.txt`, `APIKEY.txt`) | Regenerated on every new Pod → sessions/API clients break after a restart; keys should come from a Secret |

## 8. Production considerations
- **Assess images before deploying:** user, ports, writable paths, base OS, age, CVE scan (e.g. Red Hat Quay / ACS image scanning).
- **Random-UID compatibility belongs in the image** (`chgrp -R 0 … && chmod -R g=u …`), not in a cluster-wide `anyuid` grant.
- **Persist state:** PVC for `var/`, or better, an external database; then scale to multiple replicas.
- **Secrets** for admin password and session/API keys.
- **Pin image by digest**, use an internal registry/mirror, and add readiness/liveness probes on port 9001.

## 9. Lessons learned
- `oc image info` is a 10-second pre-flight check that tells you most of what can go wrong.
- The random UID always has **GID 0** – that's the hook that makes group-0-writable images work.
- A Running Pod isn't the end of validation – check *where data goes* and *what version* you're running.

## 10. Interview talking point
> "Before deploying a third-party Etherpad image I inspected it with `oc image info` – a named user, a writable working directory and a five-year-old Node 10 base – so I expected permission errors under OpenShift's random UID. It actually ran under `restricted-v2`, and I proved why: the directories were owned by group 0 and group-writable, and the random UID always runs with GID 0. I also flagged production risks: data stored in a DirtyDB file inside the container, so every restart loses it, plus an outdated, unpatched image on the `latest` tag – the fixes being a PVC or external database, secrets for credentials, and a rebuilt, pinned image."

## Follow-ups
- [ ] Persist Etherpad data with a PVC and prove it survives a Pod deletion
- [ ] Expose app-03 with a Service and Route
- [ ] Add readiness/liveness probes on port 9001
