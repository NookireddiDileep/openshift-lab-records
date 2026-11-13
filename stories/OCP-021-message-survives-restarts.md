# OCP-021: Make an application print a required message that survives Pod deletes and restarts

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | ConfigMaps · Immutable containers · SCC / service accounts |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~30 min |
| **Status** | Done |
| **RCA** | [RCA-004 – wrong image tag + CrashLoopBackOff (root-only httpd)](../rca/RCA-004-image-tag-and-root-only-httpd.md) |

## 1. User story / requirement
> As an **application owner**, I want an app created from a given image to print **"Hello &lt;Company&gt;"** – and keep printing it **after the Pod is deleted or restarted multiple times**.

Given image: `docker.io/<user>/my-demo-app:V2.0.0`.

## 2. Acceptance criteria
- [x] Application created from the requested image
- [x] Application prints the required message
- [x] Message still correct after **3 Pod deletions and a rollout restart**
- [x] Reachable via a Route
- [x] *(extra)* Faults on the way root-caused → [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md)

## 3. Background / concepts
**Containers are immutable at runtime.** Every new Pod starts from the image; anything written inside a running container (outside a volume) is lost on restart. Durable changes must come from the **Pod spec**, which the Deployment re-applies to every Pod:

| Change made via | Survives Pod delete/restart? |
|---|---|
| `oc exec … > file` inside the container | ❌ |
| ConfigMap / Secret mounted as a volume | ✅ |
| Environment variable in the Deployment | ✅ |
| New image version | ✅ |

## 4. Plan
1. Inspect the image before deploying → tag not found → list tags → use the correct one.
2. Deploy; diagnose the CrashLoopBackOff; fix with a **dedicated service account + anyuid** (not `default`).
3. Inspect where the page comes from (`oc debug`).
4. Show the wrong way (edit inside container) fails after one restart.
5. Right way: ConfigMap mounted at the document root.
6. Prove: 3 deletes + rollout restart; expose a Route.
7. **Rollback:** `oc set volume deployment/app-07 --remove --name=html`; `oc delete cm app-07-html`.

## 5. Implementation
Script: [`scripts/OCP-021/app-07.sh`](../scripts/OCP-021/app-07.sh)
```bash
skopeo list-tags docker://docker.io/<user>/my-demo-app        # → v1.0.0, v2.0.0  (no "V2.0.0")
oc create deployment app-07 --image=docker.io/<user>/my-demo-app:v2.0.0
oc create sa app-07-sa
oc adm policy add-scc-to-user anyuid -z app-07-sa
oc set serviceaccount deployment/app-07 app-07-sa
oc create configmap app-07-html --from-literal=index.html='<h1>Hello <Company></h1>'
oc set volume deployment/app-07 --add --name=html --type=configmap \
  --configmap-name=app-07-html --mount-path=/var/www/html
```

## 6. Validation / evidence
**Where the page came from (`oc debug` – shell instead of httpd):**
```
uid=0(root) gid=0(root)
drwx--x---. 3 root apache  /run/httpd            ← root-only runtime dir (see RCA-004)
-rw-r--r--. 1 root root 22 /var/www/html/index.html
<h1> hello world</h1>                            ← baked into the image
```
**After the SCC fix – running as root under a dedicated SA:**
```
anyuid  sa=app-07-sa
uid=0(root) gid=0(root) groups=0(root)
<h1> hello world</h1>
```
**Wrong way – edit inside the running container:**
```
$ oc exec $POD -- sh -c 'echo "<h1>Hello <Company></h1>" > /var/www/html/index.html'
$ oc exec $POD -- curl -s localhost:80
<h1>Hello <Company></h1>
$ oc delete pod $POD
$ oc exec deploy/app-07 -- curl -s localhost:80
<h1> hello world</h1>                            ← edit lost after ONE restart
```
**Right way – ConfigMap mounted by the Deployment:**
```
configmap/app-07-html created
deployment.apps/app-07 volume updated
<h1>Hello <Company></h1>

after delete #1: <h1>Hello <Company></h1>
after delete #2: <h1>Hello <Company></h1>
after delete #3: <h1>Hello <Company></h1>
deployment.apps/app-07 restarted
after rollout restart: <h1>Hello <Company></h1>

route.route.openshift.io/app-07 exposed
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | `manifest unknown` for tag `V2.0.0` | **Tags are case-sensitive** – the registry has `v2.0.0`. Found with `skopeo list-tags` → [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md) |
| 2 | `CrashLoopBackOff`: `(13)Permission denied: AH00058: Error retrieving pid file run/httpd.pid` | Root-only CentOS httpd image under the random-UID `restricted-v2` SCC → [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md) |
| 3 | `oc exec` failed: `container not found` | The container kept dying – used **`oc debug deployment/…`** (copy of the Pod with a shell instead of the entrypoint) to inspect it |
| 4 | Debug Pod ran as **uid 0** even before the fix | `oc debug` creates the Pod as **my user**, whose admin group may use `anyuid` – same effect as in [OCP-001](OCP-001-bare-pod-no-self-heal.md). The Deployment's Pods use the service account, which couldn't |
| 5 | v1.0.0 and v2.0.0 have identical metadata | Differences (if any) are in the content, not the config – inspect before assuming |
| 6 | Mounting a ConfigMap at `/var/www/html` replaces the whole directory | Fine here (one file). To replace a single file and keep the rest, mount with `subPath` – but then ConfigMap updates aren't propagated automatically |
| 7 | Old Pod showed `Completed` during the rollout restart | httpd exited cleanly (code 0) on SIGTERM before removal – normal |
| 8 | Page served on port **80** as root | Works with `anyuid`; a rebuilt non-root image listening on 8080 would avoid the extra privilege |

## 8. Production considerations
- **Never patch running containers** – configuration lives in ConfigMaps/Secrets/env in Git; content changes ship as new images or config objects.
- Grant elevated SCCs only to a **dedicated service account**, and prefer **rebuilding the image** to run non-root (pid/log dirs group-0 writable, port 8080) so `restricted-v2` is enough.
- Pin images by **exact tag or digest**; verify tags exist (`skopeo list-tags` / `skopeo inspect`) in CI before deploying.
- Updating the ConfigMap later: mounted (non-subPath) files update in running Pods after a short delay; httpd serves the new file without restart. Use `oc rollout restart` for apps that only read config at startup.

## 9. Lessons learned
- "Survives restarts" = "defined in the Pod spec", not "changed inside the container".
- `skopeo list-tags` answers "does this tag exist?" in one command.
- `oc debug` is the tool when a container dies too fast to `exec` into.

## 10. Interview talking point
> "The story asked for an app that prints a specific message even after Pods are deleted. The given tag didn't exist – tags are case-sensitive, and `skopeo list-tags` showed lowercase `v2.0.0`. The image then crash-looped: it was a root-only httpd that couldn't write its pid file under OpenShift's random UID, so I created a dedicated service account with `anyuid` instead of touching the default one. I showed that editing the page inside the container is lost after one restart, then put the content in a ConfigMap mounted by the Deployment – it survived three deletions and a rollout restart. Long term I'd rebuild the image to run non-root on 8080 and drop the extra SCC."
