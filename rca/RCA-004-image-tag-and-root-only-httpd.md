# RCA-004: App from a demo image unavailable – wrong image tag, then CrashLoopBackOff (root-only httpd under random UID)

| Field | Value |
|---|---|
| **Date** | 2026-11-13 |
| **Environment** | Lab OpenShift 4.19, my project (sanitised) |
| **Severity** | Sev3 (new deployment blocked; nothing in production affected) |
| **Component** | Image reference · SCC / service accounts · httpd |
| **Status** | Resolved |
| **Story** | [OCP-021](../stories/OCP-021-message-survives-restarts.md) |

## 1. Problem statement
Deploying `docker.io/<user>/my-demo-app:V2.0.0` failed twice: first the image couldn't be found; after correcting the tag, the Pod went into `CrashLoopBackOff`.

## 2. Impact
Application could not be created/started. No impact on other workloads.

## 3. Symptoms & detection
```
$ oc image info docker.io/<user>/my-demo-app:V2.0.0
error: image "…:V2.0.0" not found: manifest unknown: manifest unknown

$ oc get pods -l app=app-07
app-07-…   0/1   CrashLoopBackOff   4 (21s ago)   2m
$ oc logs $POD
AH00558: httpd: Could not reliably determine the server's fully qualified domain name ...
(13)Permission denied: AH00058: Error retrieving pid file run/httpd.pid
AH00059: Remove it before continuing if it is corrupted.
$ oc exec $POD -- …
error: unable to upgrade connection: container not found ("my-demo-app")
```

## 4. Timeline
| Time (IST) | Event |
|---|---|
| 17:47 | `manifest unknown` on inspect |
| 17:48 | `skopeo list-tags` → `v1.0.0`, `v2.0.0` – tag case mismatch identified |
| 17:51 | Deployed `v2.0.0` → CrashLoopBackOff; logs show pid-file permission error |
| 17:52 | `oc debug` inspection; dedicated SA + anyuid applied → Running as root |
| 17:53 | App serving; story completed with a ConfigMap |

## 5. Investigation
| # | Hypothesis | Check | Result |
|---|---|---|---|
| 1 | Registry/network problem | `skopeo list-tags` on the same repo worked | Ruled out |
| 2 | Tag doesn't exist | list of tags | **Confirmed**: `v2.0.0`, not `V2.0.0` |
| 3 | App bug | Logs: permission error on pid file | Ruled out |
| 4 | Image expects root; OpenShift runs random UID | `oc image info` (httpd entrypoint, port 80, no USER); SCC annotation `restricted-v2`; `oc debug` showing `/run/httpd` = `drwx--x--- root apache` | **Confirmed** |

```
Entrypoint: /usr/sbin/httpd   Command: -D FOREGROUND   Exposes Ports: 80/tcp   (no USER → root)
SCC: restricted-v2            → random non-root UID
/run/httpd: drwx--x---. root apache     → random UID can't create httpd.pid there
```

## 6. Root cause
**Fault 1 – image reference:** the requested tag `V2.0.0` doesn't exist; registry tags are **case-sensitive** and the published tag is `v2.0.0`.

**Fault 2 – security context mismatch:** the image is a CentOS-style httpd built to start **as root** (pid file in root-only `/run/httpd`, listens on privileged port 80). Under OpenShift's default `restricted-v2` SCC it runs as a **random non-root UID**, can't write its pid file, exits, and restarts in a loop.

**5 Whys (fault 2)**
1. Why CrashLoopBackOff? → httpd exits at startup.
2. Why? → `Permission denied` creating `run/httpd.pid`.
3. Why? → `/run/httpd` is writable only by root/apache, and the process ran as a random UID.
4. Why a random UID? → Default SCC `restricted-v2`; the Deployment's service account had no other SCC.
5. Why does the image need root? → Built for plain Docker/Podman as root, not for OpenShift's non-root model.

## 7. Resolution
```bash
skopeo list-tags docker://docker.io/<user>/my-demo-app                # find the real tag
oc create deployment app-07 --image=docker.io/<user>/my-demo-app:v2.0.0
oc create sa app-07-sa
oc adm policy add-scc-to-user anyuid -z app-07-sa                     # only this SA, not 'default'
oc set serviceaccount deployment/app-07 app-07-sa
```
Verification:
```
anyuid  sa=app-07-sa
uid=0(root) gid=0(root) groups=0(root)
deployment "app-07" successfully rolled out
```

## 8. Preventive actions
| Action | Type | Status |
|---|---|---|
| Verify image references in CI (`skopeo inspect`/`list-tags`); pin by digest | Prevent | Proposed |
| Prefer OpenShift-compatible images (non-root, group-0 writable runtime dirs, port ≥1024); rebuild this one | Prevent | Proposed |
| When an exception is needed: dedicated SA + least-privileged SCC, documented | Prevent | Done |
| Use `oc debug deployment/<name>` in runbooks for fast-crashing containers | Process | Done |

## 9. Lessons learned
- `manifest unknown` → first check the exact tag spelling and case.
- Root-only images fail on OpenShift by design; fix the image or grant a scoped exception – never broadly.
- `oc debug` runs as the requesting user – it can behave differently from the real Pod (service account). Compare SCCs before concluding.

## 10. Interview talking point
> "A demo image failed twice. First, `manifest unknown` – the story's tag had a capital V, but registry tags are case-sensitive and `skopeo list-tags` showed lowercase. Then it crash-looped with a permission error on httpd's pid file: the image was built to run as root, but OpenShift's restricted-v2 SCC runs a random UID. I confirmed it with `oc debug`, then created a dedicated service account with `anyuid` – scoped to this app only – and recommended rebuilding it to run non-root on port 8080."
