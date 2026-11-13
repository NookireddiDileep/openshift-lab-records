# OCP-005: Log in to app-03 and check the OS version – container userland vs. node kernel

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Troubleshooting · Container fundamentals · Image security |
| **Priority** | Low |
| **Date** | 2026-11-13 |
| **Time spent** | ~15 min |
| **Status** | Done |
| **Related** | [OCP-004 – Etherpad image under restricted-v2](OCP-004-third-party-image-etherpad.md) |

## 1. User story / requirement
> As a **platform engineer**, I want to **log in to the running application `app-03` and check its OS version**, so that **I know what base OS the application runs on (for patching, CVE checks and support)**.

## 2. Acceptance criteria
- [x] Opened a shell inside the running app-03 container
- [x] Identified the container's OS and version
- [x] *(extra)* Compared it with the node's OS and kernel, and explained the difference
- [x] *(extra)* Assessed the result for support / security status

## 3. Background / concepts
- **"Logging in" to an app on OpenShift** = opening a shell inside a running container with `oc rsh <pod>` (interactive) or running one command with `oc exec <pod> -- <cmd>`. There is no SSH into containers.
- **A container has its own userland but not its own kernel.** The image supplies the filesystem – libraries, package manager and `/etc/os-release` – while **every container on a node shares that node's kernel**.
- So "what OS is this app running?" has two correct answers:
  - **Userland OS** → `/etc/os-release` inside the container (what you patch by rebuilding the image)
  - **Kernel** → `uname -r`, which is the **node's** kernel (what you patch by updating the nodes – on OpenShift, via the cluster upgrade / MachineConfig)
- The container also has its own **hostname** (UTS namespace) – `uname -a` shows the Pod name, not the node's.

## 4. Plan
1. Find the app-03 Pod.
2. Interactive login with `oc rsh`, check OS, kernel, user and runtime version.
3. Repeat non-interactively with `oc exec` for clean evidence.
4. Compare with the node's OS image, kernel and container runtime.

## 5. Implementation
```bash
POD=$(oc get pod -l app=app-03 -o jsonpath='{.items[0].metadata.name}')
oc rsh $POD                      # interactive shell inside the container
  cat /etc/os-release
  uname -a
  id
  node --version
  exit
```
```bash
# evidence, non-interactively
oc exec $POD -- cat /etc/os-release
oc exec $POD -- cat /etc/debian_version
oc exec $POD -- uname -r
oc exec $POD -- node --version

# the node the Pod runs on
NODE=$(oc get pod $POD -o jsonpath='{.spec.nodeName}')
oc get node $NODE -o jsonpath='{.status.nodeInfo.osImage}{"\n"}{.status.nodeInfo.kernelVersion}{"\n"}{.status.nodeInfo.containerRuntimeVersion}{"\n"}'
```

## 6. Validation / evidence
**Inside the container (`oc rsh`):**
```
$ cat /etc/os-release
PRETTY_NAME="Debian GNU/Linux 10 (buster)"
NAME="Debian GNU/Linux"
VERSION_ID="10"
VERSION="10 (buster)"
VERSION_CODENAME=buster
ID=debian

$ cat /etc/debian_version
10.7

$ uname -a
Linux app-03-84ffd6f577-f2xdl 5.14.0-570.128.1.el9_6.x86_64 #1 SMP PREEMPT_DYNAMIC ... x86_64 GNU/Linux
        ↑ hostname = Pod name

$ id
uid=1001250000(1001250000) gid=0(root) groups=0(root),1001250000

$ node --version
v10.23.1
```
**The node the Pod runs on:**
```
Node:     master-0
OS image: Red Hat Enterprise Linux CoreOS 9.6.20260715-0 (Plow)
Kernel:   5.14.0-570.128.1.el9_6.x86_64          ← identical to uname -r inside the container
Runtime:  cri-o://1.32.13-8.rhaos4.19...el9       ← CRI-O built for OpenShift 4.19
```

**Summary**
| Layer | Value | Comes from | Patched by |
|---|---|---|---|
| Container userland OS | **Debian 10 (buster), 10.7** | the image | rebuilding the image |
| Application runtime | **Node.js v10.23.1** | the image | rebuilding the image |
| Kernel | **5.14.0-570.128.1.el9_6** | the **node** (shared) | cluster / node updates |
| Node OS | **RHEL CoreOS 9.6** | OpenShift | cluster upgrade (MCO) |
| Container runtime | **CRI-O 1.32** (OCP 4.19) | OpenShift | cluster upgrade |

## 7. Issues hit & observations
| # | Observation | Explanation / impact |
|---|---|---|
| 1 | Pasting a block that included `oc rsh` stopped at the Pod's `$` prompt; the following lines didn't run on the terminal | `oc rsh` is interactive – it waits for input inside the Pod. Keep `oc rsh` out of scripts and pasted blocks; use `oc exec` for automation |
| 2 | Container kernel == node kernel | Containers share the host kernel; kernel CVEs are fixed by updating nodes, not images |
| 3 | **Debian 10 (buster) is end-of-life** | No more security updates for the base OS – confirms the image risk raised in OCP-004 |
| 4 | **Node.js 10 is end-of-life** | No more security fixes for the application runtime |
| 5 | Nodes run RHCOS 9.6 / CRI-O 1.32 | Places the cluster on OpenShift 4.19 – useful context when checking compatibility and CVEs |

## 8. Production considerations
- Track **both layers**: image base OS + runtime (rebuild and redeploy) and node OS + kernel (cluster upgrades).
- Base images should be **supported** (e.g. Red Hat UBI) and **scanned** continuously (Red Hat Quay / Advanced Cluster Security) – an EOL base like Debian 10 + Node 10 should fail policy.
- Prefer `oc exec` (or `oc debug`) for evidence and automation; restrict `rsh`/`exec` via RBAC in production, since it is interactive access into running workloads, and audit its use.
- Minimal images may not ship a shell at all – then use `oc debug` or ephemeral debug containers.

## 9. Lessons learned
- `/etc/os-release` answers "which distribution is the image"; `uname -r` answers "which kernel" – and that's always the node's.
- A container's hostname is its Pod name.
- Interactive commands (`oc rsh`) don't belong in pasted command blocks.

## 10. Interview talking point
> "I logged into a running container with `oc rsh` and checked its OS: the image was Debian 10, but `uname -r` showed the RHEL 9 kernel of the CoreOS node – identical to the node's kernel – because containers share the host kernel and only bring their own userland. That matters for patching: base-OS CVEs are fixed by rebuilding the image, kernel CVEs by upgrading the nodes. In this case both Debian 10 and Node.js 10 were end-of-life, so I flagged the image as needing a rebuild on a supported base."
