# OCP-006: Get `/etc/passwd` from app-03 without logging in – and who added the random UID's entry

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Troubleshooting · Evidence collection · Container runtime (CRI-O) |
| **Priority** | Low |
| **Date** | 2026-11-13 |
| **Time spent** | ~20 min |
| **Status** | Done |
| **Related** | [OCP-004](OCP-004-third-party-image-etherpad.md) · [OCP-005](OCP-005-container-os-vs-node-kernel.md) |

## 1. User story / requirement
> As a **platform engineer**, I want the **contents of `/etc/passwd` from the running app-03 container without logging in to it**, so that **I can collect evidence remotely – scriptable, repeatable and attachable to a ticket – without an interactive session**.

## 2. Acceptance criteria
- [x] Output of `cat /etc/passwd` from app-03, obtained **without** an interactive shell (`oc rsh`)
- [x] Output saved locally as evidence
- [x] *(extra)* Shown 3 methods: exec by Pod, exec by Deployment, copy out
- [x] *(extra)* Explained the passwd entry for OpenShift's random UID

## 3. Background / concepts
| Method | Interactive? | Typical use |
|---|---|---|
| `oc rsh <pod>` | **yes** – a login shell | hands-on debugging |
| `oc exec <pod> -- <cmd>` | no – one command, output comes back to your terminal | evidence, scripts, automation |
| `oc exec deploy/<name> -- <cmd>` | no – OpenShift picks a Pod of the Deployment | stable command; Pod names change on every restart |
| `oc cp <pod>:<path> <local>` | no – copies a file out (uses `tar` inside the image) | pulling logs/config files |

**Random UIDs and `/etc/passwd`.** Under `restricted-v2` a container runs as a random UID (here `1001250000`) that the image author never knew. Many tools (ssh, git, some Python/Java libraries) fail if `getpwuid()` finds no entry for the current UID. On OpenShift, the **CRI-O container runtime** handles this: when the container's UID isn't in the image's `/etc/passwd`, CRI-O adds an entry for it while creating the container.

## 4. Plan
1. Run `cat /etc/passwd` via `oc exec` by Pod name.
2. Run it via the Deployment (no Pod name).
3. Save the output to a local file; also copy the file out with `oc cp`.
4. Check whether the running UID has an entry, and work out who created it.

## 5. Implementation
```bash
POD=$(oc get pod -l app=app-03 -o jsonpath='{.items[0].metadata.name}')

oc exec $POD -- cat /etc/passwd                              # 1. by Pod
oc exec deploy/app-03 -- cat /etc/passwd | tail -5           # 2. by Deployment
oc exec deploy/app-03 -- cat /etc/passwd > app-03-passwd.txt # 3. save as evidence
oc cp $POD:/etc/passwd ./app-03-passwd-copy.txt              # 4. copy out

oc exec deploy/app-03 -- id
oc exec deploy/app-03 -- sh -c 'grep -c "$(id -u)" /etc/passwd'
oc exec deploy/app-03 -- ls -l /etc/passwd
```

## 6. Validation / evidence
**`/etc/passwd` from app-03, without logging in** (full file: [`scripts/OCP-006/app-03-passwd.txt`](../scripts/OCP-006/app-03-passwd.txt)):
```
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
...                                                          (Debian 10 system accounts)
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
_apt:x:100:65534::/nonexistent:/usr/sbin/nologin
node:x:1000:1000::/home/node:/bin/bash                       ← from the Node.js base image
etherpad:x:5001:5001::/home/etherpad:/bin/sh                 ← the image's intended user
1001250000:x:1001250000:0:1001250000 user:/:/sbin/nologin    ← added at container start for the random UID
```
**Saved locally and copied out – identical size:**
```
$ wc -l app-03-passwd.txt
22 app-03-passwd.txt
-rw-r--r-- 1 <me> <me> 1068 app-03-passwd.txt

$ oc cp $POD:/etc/passwd ./app-03-passwd-copy.txt
tar: Removing leading `/' from member names                  ← normal: oc cp uses tar in the container
-rw-r--r-- 1 <me> <me> 1068 app-03-passwd-copy.txt
```
**Who added the random UID's entry?**
```
$ oc exec deploy/app-03 -- id
uid=1001250000(1001250000) gid=0(root) groups=0(root),1001250000

$ oc exec deploy/app-03 -- sh -c 'grep -c "$(id -u)" /etc/passwd'
1

$ oc exec deploy/app-03 -- ls -l /etc/passwd
-rw-r--r--. 1 root root 1068 Nov 13 09:43 /etc/passwd
```
| Clue | Conclusion |
|---|---|
| Entry is the **last line**, after the image's own `node` and `etherpad` users | Added **after** the image was built |
| `/etc/passwd` is **`root:root` 644** | The app (UID 1001250000) **cannot** write it |
| Modified at **09:43** – the moment the Pod was created | Written when the container was created |
| Format: GID `0`, name `<uid> user`, home `/`, shell `/sbin/nologin` | Matches the entry CRI-O injects for a UID missing from `/etc/passwd` |

→ **The container runtime (CRI-O) added the entry**, not the image and not the application.

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | **Correction of my earlier assumption.** In OCP-004/005 I read `uid=1001250000(1001250000)` as "the UID has no username" | It does have one – the username is literally `1001250000`. Checking `/etc/passwd` proved the assumption wrong |
| 2 | Random UID has a valid passwd entry, injected at container creation | OpenShift/CRI-O solves the "unknown UID" problem at the runtime level; image authors don't need `nss_wrapper` hacks for this |
| 3 | `tar: Removing leading '/' from member names` from `oc cp` | Normal – `oc cp` streams a tar archive from the container. It needs `tar` in the image; minimal images without it fail (`oc exec … cat > file` still works) |
| 4 | `oc exec deploy/app-03` works without a Pod name | Pod names change on every restart/self-heal; targeting the Deployment keeps commands and runbooks stable |
| 5 | Passwd shows `node` (UID 1000, `/bin/bash`) and `etherpad` (UID 5001) accounts | Unused at runtime under the random UID – harmless, but shows the image wasn't trimmed (more surface for scanners to flag) |

## 8. Production considerations
- Collect evidence with `oc exec … > file` – non-interactive, scriptable, attachable to tickets. Reserve `oc rsh` for live debugging.
- **`exec`, `rsh` and `cp` are powerful**: they give command execution inside running workloads. In production, restrict the `pods/exec` subresource via RBAC to the people who need it, and audit its use (API audit logs).
- Never copy secrets or sensitive files out of Pods to personal machines; `/etc/passwd` here contains no hashes (`x` = shadowed) and is safe to share.
- Write runbooks against `deploy/<name>`, not Pod names.

## 9. Lessons learned
- "Without logging in" = `oc exec`: one command, output returned to you.
- On OpenShift the random UID gets a passwd entry **from CRI-O at container creation**.
- Verify assumptions with evidence – here a 2-second `grep` overturned an earlier conclusion.

## 10. Interview talking point
> "I pulled `/etc/passwd` from a running container without opening a shell – `oc exec` against the Deployment, with the output saved locally as evidence, and also with `oc cp`. It showed something many people don't know: the container ran as OpenShift's random UID, which the image never defined, yet `/etc/passwd` had an entry for it. The file was root-owned and read-only to the app, and timestamped at container creation, so it was the CRI-O runtime that injected it – that's how OpenShift avoids apps breaking when they look up their own user. It also corrected an assumption I'd made earlier, which is why I always check with evidence."
