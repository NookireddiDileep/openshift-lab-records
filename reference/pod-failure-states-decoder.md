# Pod failure states decoder: from symptom to root cause

> Concept note in my own words. Plain-language first, then the real mechanism, then the questions a senior (L4) OpenShift interviewer asks. Use it as the "start here" page when a pod is broken. Each section links to stories, RCAs and runbooks in this repo where I hit the same state.

**Contents**

1. [The big picture: a pod's journey](#1-the-big-picture-a-pods-journey)
2. [How to read pod status correctly](#2-how-to-read-pod-status-correctly)
3. [The universal 5-step method](#3-the-universal-5-step-method)
4. [When there is no pod at all](#4-when-there-is-no-pod-at-all)
5. [Pending](#5-pending)
6. [ContainerCreating (stuck)](#6-containercreating-stuck)
7. [ErrImagePull / ImagePullBackOff](#7-errimagepull--imagepullbackoff)
8. [CreateContainerConfigError / CreateContainerError](#8-createcontainerconfigerror--createcontainererror)
9. [Init:… states](#9-init-states)
10. [CrashLoopBackOff](#10-crashloopbackoff)
11. [OOMKilled](#11-oomkilled)
12. [Running but not Ready (0/1)](#12-running-but-not-ready-01)
13. [Error / Completed (exit codes)](#13-error--completed-exit-codes)
14. [Evicted](#14-evicted)
15. [Terminating (stuck)](#15-terminating-stuck)
16. [Unknown / node lost](#16-unknown--node-lost)
17. [Exit code cheat sheet](#17-exit-code-cheat-sheet)
18. [L4 interview drill](#18-l4-interview-drill)

---

## 1. The big picture: a pod's journey

**Plain-language version.** Think of a pod as **a restaurant order**:

1. **Order placed:** you `oc apply` a Deployment. The API server checks you're allowed (RBAC), checks the dish is allowed in this restaurant (admission: **SCC**, quota) and writes it down (etcd).
2. **Table assigned:** the **scheduler** picks a node with enough room.
3. **Ingredients fetched:** the node's **kubelet** asks **CRI-O** to pull the image.
4. **Kitchen prepared:** volumes are attached and mounted, the network is plugged in (CNI), ConfigMaps and Secrets are fetched.
5. **Cooking:** the container process starts.
6. **Health inspection:** probes check it's alive (liveness) and ready to serve (readiness).
7. **Served:** a Ready pod is added to its Service's endpoints and receives traffic.
8. **Table cleared:** on delete, the pod gets SIGTERM, a grace period, then SIGKILL.

Every failure state is simply **the step where the order got stuck**:

```text
 apply ──► admission ──► scheduler ──► kubelet: image ──► volumes/network/config ──► start ──► probes ──► Ready ──► delete
   │           │             │                │                     │                   │          │                 │
 no pod    no pod        Pending       ErrImagePull /        ContainerCreating     CrashLoop-   0/1 Running    Terminating
 (RBAC)  (SCC/quota:                   ImagePullBackOff      CreateContainer-      BackOff,     (readiness)    (stuck)
          FailedCreate)                                      ConfigError           OOMKilled,
                                                                                   Error
            + at any time: Evicted (node pressure), Unknown (node lost)
```

**Rule:** find *which step* failed and you know *which component* to investigate: API/admission, scheduler, kubelet + CRI-O, storage/CNI, the application, or the node.

---

## 2. How to read pod status correctly

The `STATUS` column in `oc get pods` is a **summary** built from several fields. Seniors read the fields underneath:

| Field | Where | Values | Tells you |
|---|---|---|---|
| **Phase** | `status.phase` | `Pending`, `Running`, `Succeeded`, `Failed`, `Unknown` | The pod's overall lifecycle stage (only five values) |
| **Conditions** | `status.conditions` | `PodScheduled`, `Initialized`, `ContainersReady`, `Ready` (True/False + reason) | Which gate it passed or failed |
| **Container state** | `status.containerStatuses[].state` | `waiting` / `running` / `terminated` + **reason** | What the container is doing *now* |
| **Last state** | `status.containerStatuses[].lastState` | Usually `terminated` with `reason`, `exitCode` | **Why the previous run died** (the key field for crash loops) |
| **Restart count** | `restartCount` | Number | How often the kubelet restarted it |

So `CrashLoopBackOff` isn't a phase. It's the **reason** for a container **waiting** before the next restart. `OOMKilled` is a **reason** in `lastState.terminated`.

```bash
oc get pod <pod> -o jsonpath='{.status.phase}{"\n"}'
oc get pod <pod> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
oc get pod <pod> -o jsonpath='{range .status.containerStatuses[*]}{.name}: state={.state} last={.lastState}{"\n"}{end}'
```

---

## 3. The universal 5-step method

Use the same order every time; interviewers listen for the method as much as the answer.

1. **Scope:** one pod, one node, one namespace, or everything? (`oc get pods -A -o wide | grep -v Running`)
2. **Status and events:** `oc describe pod <pod>`, read the **Events at the bottom** and `Last State`.
3. **Logs:** `oc logs <pod> -c <container>` and `oc logs <pod> --previous` (the run that crashed).
4. **Go one level up or down:**
   - Up: Deployment → ReplicaSet events (`oc describe rs`), quota, SCC
   - Down: the node (`oc describe node`, `oc debug node/<n>` → `crictl`, `journalctl -u kubelet -u crio`)
5. **Fix, verify, prevent:** apply the fix, confirm pods are Ready and endpoints populated, then write the RCA and the prevention (alert, policy, template).

```bash
oc get events -n <ns> --sort-by=.lastTimestamp | tail -30     # namespace timeline
oc get events -n <ns> --field-selector involvedObject.name=<pod>
```

---

## 4. When there is no pod at all

**Plain-language version:** the order never reached the kitchen. The Deployment says `0/3` ready, but `oc get pods` shows nothing.

**What's really happening:** the **ReplicaSet** tried to create pods and the API server **rejected** them at admission. The error lives on the ReplicaSet, not on a pod.

```bash
oc get deploy,rs -n <ns>
oc describe rs <rs-name> | grep -A5 Events      # look for FailedCreate
```

| Event message (FailedCreate) | Cause | Fix |
|---|---|---|
| `exceeded quota: compute, requested: limits.cpu=…` | ResourceQuota full | Lower requests, raise quota, or clean up |
| `must specify limits.cpu` / `requests.memory` | Quota exists but pod has no resources and no LimitRange defaults | Add resources or a LimitRange |
| `unable to validate against any security context constraint` | Pod asks for something no SCC allowed for its ServiceAccount allows (root UID, hostPath, privileged, host network) | Fix the pod spec; grant a broader SCC to a dedicated ServiceAccount only with approval |
| `serviceaccount "x" not found` | Wrong ServiceAccount name | Create it or fix the name |
| Admission webhook denied | Policy engine (e.g. ACS, Gatekeeper, Kyverno) blocked it | Read the policy message; fix the spec or request an exception |

**L4 angle:** *"A deployment shows 0/3 and there are no pods. Where do you look?"* → "Pods are created by the ReplicaSet, so I describe the ReplicaSet. `FailedCreate` there means admission rejected them: quota, SCC or a webhook. The pod never existed, so there are no pod events to read."

Upstream Kubernetes evidence (K3s, `kubectl`): [Lab 11 namespaces and quotas](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-11-namespaces/README.md) in kubernetes-labs.

---

## 5. Pending

**Plain-language version:** the order is accepted but **no table is free**, or the table needs something (a storage booking) that isn't ready.

**What's really happening:** `PodScheduled=False`. The **scheduler** filtered every node out, or the pod waits for a PVC.

```bash
oc describe pod <pod> | sed -n '/Events/,$p'
#  Warning FailedScheduling  0/6 nodes are available: 3 Insufficient cpu,
#  3 node(s) had untolerated taint {node-role.kubernetes.io/master: }.
```

The `FailedScheduling` message is a per-node tally of **why** each node was rejected. Read it carefully:

| Message fragment | Meaning | Fix |
|---|---|---|
| `Insufficient cpu` / `memory` | **Requests** don't fit (usage doesn't matter, requests do) | Lower requests, add nodes, remove idle reservations |
| `didn't match Pod's node affinity/selector` | `nodeSelector`/affinity points at labels no node has | Fix labels or the selector |
| `had untolerated taint` | Nodes are tainted (masters, infra, GPU) and the pod has no toleration | Add toleration only if it truly belongs there |
| `didn't match pod anti-affinity rules` | Spread rules can't be satisfied (e.g. 4 replicas, 3 nodes, hard anti-affinity) | Use `preferred` anti-affinity or topology spread |
| `pod has unbound immediate PersistentVolumeClaims` | PVC is Pending | Go to the PVC: `oc describe pvc` (StorageClass, provisioner, capacity) |
| `volume node affinity conflict` | PV exists only in a zone/node the pod can't use | Zone-aware StorageClass (`WaitForFirstConsumer`), or schedule in that zone |
| `Too many pods` | Node's max-pods reached | More nodes or higher `maxPods` via KubeletConfig |

**L4 angle:**
- *"Nodes show 30% CPU usage, yet the pod is Pending for Insufficient cpu. Why?"* → "The scheduler counts **requests**, not usage. The nodes are fully *reserved* by requests even if they're idle. Right-size requests from real usage metrics."
- *"How do you prevent this at scale?"* → "Capacity alerts on requested vs allocatable, ClusterAutoscaler/MachineAutoscaler where possible, quotas per team, and request right-sizing reviews."

Related: [OCP-022](../stories/OCP-022-statefulset-3-replicas.md) (per-pod PVCs), [OCP-019](../stories/OCP-019-static-pv-pvc-nfs.md) (PV/PVC binding).

Upstream Kubernetes evidence (K3s, `kubectl`): [Scenario 03 Pending pod](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-03-pending-pod/README.md), [Scenario 07 PVC Pending](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-07-persistent-volume/README.md) in kubernetes-labs.

---

## 6. ContainerCreating (stuck)

**Plain-language version:** the table is assigned but the **kitchen isn't ready**: storage isn't attached, or the network isn't plugged in.

**What's really happening:** the pod is scheduled; the kubelet is preparing the **sandbox** (pause container + network namespace via CNI) and **volumes** (attach to node, then mount into the pod).

| Event | Cause | Check / fix |
|---|---|---|
| `FailedAttachVolume` / `Multi-Attach error` | RWO volume still attached to another node (old pod on a dead/drained node) | `oc get volumeattachment`; the old pod/node must release it. Don't force-detach without knowing the old node is really down |
| `FailedMount ... timed out` | NFS/iSCSI/Ceph unreachable, wrong export, permissions | Storage path, CSI driver pods logs in their namespace |
| `MountVolume.SetUp failed ... configmap/secret not found` | Volume refers to a missing ConfigMap/Secret | Create it or fix the name |
| `FailedCreatePodSandBox ... network` | CNI (OVN-Kubernetes) problem on that node | `oc get pods -n openshift-ovn-kubernetes -o wide` for that node; node network |
| Nothing obvious, many pods affected on one node | Node-level problem (disk full, CRI-O hung) | `oc debug node/<n>` → `crictl pods`, `journalctl -u crio -u kubelet` |

**L4 angle:** *"After a node failure, a StatefulSet pod is stuck ContainerCreating with Multi-Attach on its new node. Why, and what do you do?"* → "The RWO volume is still attached to the failed node; Kubernetes can't be sure the old pod stopped writing, so it won't attach it elsewhere (that protects data). I confirm the old node is really down (BMC/console), then fence it: delete the node object or use the out-of-service taint so the volume can detach. Force-detaching while the old node might still write risks corruption."

Related: [OCP-020](../stories/OCP-020-dynamic-storage-etherpad.md).

---

## 7. ErrImagePull / ImagePullBackOff

**Plain-language version:** the kitchen can't get the **ingredients**: the image name is wrong, the store is closed, or you're not allowed in.

**What's really happening:** the kubelet asks **CRI-O** to pull the image. `ErrImagePull` is a failed attempt; `ImagePullBackOff` is the kubelet **waiting** before the next try (delay doubles, capped at 5 minutes). The container never started, so **there are no logs**: the answer is in the **events**.

| Event text | Cause | Fix |
|---|---|---|
| `manifest unknown` / `not found` | Wrong name or tag | Correct the reference; pin tags/digests |
| `unauthorized` / `authentication required` | Private registry, no pull secret | Pull secret in the **same namespace**, linked to the ServiceAccount (`oc secrets link default <secret> --for=pull`) |
| `x509: certificate signed by unknown authority` | Registry uses a CA the nodes don't trust | Add CA to `image.config.openshift.io/cluster` (`additionalTrustedCA`) |
| `i/o timeout` / `no such host` | DNS, proxy or firewall from the node to the registry | Test from the node: `crictl pull <image>` |
| `toomanyrequests` | Registry rate limit (e.g. Docker Hub) | Mirror images to an internal registry |
| Only some nodes fail | Node-specific: DNS, disk full, mirror config | Compare nodes; `crictl pull` on a failing one |

**L4 angle:**
- *"Why are there no logs?"* → "Logs come from a running container; it never started."
- *"The registry is down for an hour. What still works?"* → "Pods whose image is already cached on their node with `IfNotPresent` keep starting. New nodes, new tags and `imagePullPolicy: Always` fail. That's why we mirror critical images internally."

Related: [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md) (wrong image tag).

Upstream Kubernetes evidence (K3s, `kubectl`): [Scenario 02 ImagePullBackOff](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-02-imagepullbackoff/README.md) in kubernetes-labs.

---

## 8. CreateContainerConfigError / CreateContainerError

**Plain-language version:** ingredients arrived, but the **recipe card is missing a line**: a config value the container needs doesn't exist.

**What's really happening:**

- **`CreateContainerConfigError`:** the kubelet can't **build** the container's configuration: an env var refers to a ConfigMap/Secret (or a **key** inside one) that doesn't exist, or similar.
- **`CreateContainerError` / `RunContainerError`:** the config was built but the **runtime** failed to create or start the process, e.g. the command/entrypoint doesn't exist in the image, or a bad mount.

```bash
oc describe pod <pod> | sed -n '/Events/,$p'
#  Error: couldn't find key DB_HOST in ConfigMap app/app-config
oc get configmap app-config -o yaml
```

**Fix:** create the missing object or key, or correct the reference. The kubelet keeps retrying, so the pod starts by itself once the object exists; a rollout restart only makes it immediate. For optional values, `configMapKeyRef.optional: true`.

**L4 angle:** *"A config change went out and only new pods fail with CreateContainerConfigError; old pods are fine. Why?"* → "Old pods already read their env vars at start. The change removed or renamed a key, so only new pods, which resolve the reference at creation, fail. Fix the key, and add a check in CI that every referenced key exists."

Related: [RB-S42](../runbooks/RB-S42-createcontainerconfigerror-missing-configmap-key.md).

Upstream Kubernetes evidence (K3s, `kubectl`): [Scenario 04 ConfigMap](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-04-configmap/README.md), [Scenario 05 Secret](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-05-secret/README.md) in kubernetes-labs.

---

## 9. Init:… states

**Plain-language version:** before the main dish, a **prep cook** must finish: init containers run first, one at a time, and must each **succeed**.

| Status | Meaning |
|---|---|
| `Init:0/2` | Waiting for init container 1 of 2 to finish (often waiting on a dependency, e.g. "wait for DB") |
| `Init:Error` | An init container exited non-zero |
| `Init:CrashLoopBackOff` | It keeps failing and is being restarted |
| `PodInitializing` | Init done; main containers starting |

```bash
oc logs <pod> -c <init-container-name>
oc get pod <pod> -o jsonpath='{.spec.initContainers[*].name}'
```

**L4 angle:** "Init containers are the right place for one-time setup or wait-for-dependency logic, but a wait loop with no timeout can hold a whole rollout. Give them timeouts and clear log messages."

---

## 10. CrashLoopBackOff

**Plain-language version:** the dish **keeps burning**. The cook starts, it fails, management waits a bit longer each time before trying again.

**What's really happening:** the container's **main process exits** (any exit code, even 0 for a Deployment), the kubelet restarts it per `restartPolicy`, and between restarts it waits with **exponential backoff**: 10 s, 20 s, 40 s… capped at 5 minutes, reset after 10 minutes of healthy running. `CrashLoopBackOff` is the **waiting** reason, not the cause. The cause is in **`lastState`** and the **previous logs**.

```bash
oc describe pod <pod> | grep -A6 'Last State'      # reason, exit code, finished time
oc logs <pod> --previous                           # logs of the run that died
oc get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'
```

| `Last State` | Likely cause |
|---|---|
| `Error`, exit **1** | App error: bad config, missing dependency, wrong arguments. Read previous logs |
| exit **126 / 127** | Command not executable / not found in the image |
| `OOMKilled`, exit **137** | Memory limit hit (see [§11](#11-oomkilled)) |
| exit **137**, reason `Error`, events show `Liveness probe failed` | **Liveness probe** killed it (wrong path/port, too short `initialDelaySeconds`, slow start) |
| exit **0**, reason `Completed`, restarts climbing | The process finished; a Deployment expects it to run forever (wrong command, or it should be a Job) |
| exit **1/2** with `permission denied` in logs | **OpenShift random UID** can't write to root-owned paths, or binds a port < 1024 |

**OpenShift-specific cause (very common):** images built for "run as root" fail under the `restricted-v2` SCC. The pod gets a **random UID** (e.g. `1000680000`) in the root **group** (GID 0). Fix the image: make writable paths group-owned by GID 0 and group-writable, listen on 8080. Granting `anyuid` is the last resort.

**Debug a container that dies too fast to `exec` into:**

```bash
oc debug deploy/<name>                      # copy of the pod with a shell instead of the entrypoint
oc debug pod/<pod>                          # same, from a single pod's spec
```

**L4 angle:**
- *"Is CrashLoopBackOff the problem?"* → "No, it's the kubelet's backoff. The problem is why the process exits: `lastState` plus `--previous` logs."
- *"It works on Docker, crashes on OpenShift. Why?"* → "Random non-root UID under restricted-v2; root-owned paths or a privileged port."
- *"Liveness probe or app bug: how do you tell?"* → "Events show `Liveness probe failed` before each kill and the exit is SIGKILL/137 or SIGTERM/143 after the grace period. An app bug shows its own exit code and error in previous logs."

Related: [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md) (root-only httpd), [OCP-004](../stories/OCP-004-third-party-image-etherpad.md), [OCP-006](../stories/OCP-006-exec-without-login.md) (random UID), [RB-S56](../runbooks/RB-S56-liveness-probe-kills-slow-starting-app.md), [RB-S57](../runbooks/RB-S57-liveness-probe-checks-dependency.md) (liveness probes).

Upstream Kubernetes evidence (K3s, `kubectl`): [Scenario 01 CrashLoopBackOff](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-01-crashloop/README.md), [Scenario 06 probe failures](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-06-liveness-readiness/README.md) in kubernetes-labs.

---

## 11. OOMKilled

**Plain-language version:** the cook needed **more desk space** than the desk allowed, so management removed them.

**What's really happening:** the container's processes used more memory than its **cgroup limit** (`resources.limits.memory`). The Linux kernel's **OOM killer** chose a process inside that cgroup and sent **SIGKILL** → exit code **137**, reason `OOMKilled`. This happens even if the node has lots of free memory. (If the **node** runs out instead, the kernel OOM killer or kubelet **eviction** acts at node level, see [§14](#14-evicted).)

```bash
oc describe pod <pod> | grep -B2 -A4 OOMKilled
oc adm top pod <pod> --containers                   # live usage
# trend (console → Observe → Metrics):
#   container_memory_working_set_bytes{namespace="<ns>",pod="<pod>"}
```

**Fix:**

1. Compare real usage over time with the limit. Is it a **leak** (grows forever) or a **spike** (load, batch)?
2. Raise the limit to fit real peak + margin; keep request ≈ normal usage.
3. **JVM/runtime awareness:** make the runtime respect the container limit (e.g. Java `-XX:MaxRAMPercentage=75`), since heap is only part of memory (metaspace, threads, native buffers).
4. Fix the leak in the app if usage climbs steadily.

**L4 angle:**
- *"Node has 20 GB free, pod still OOMKilled. Explain."* → "The kill is per cgroup: the container hit **its own limit**. Node free memory is irrelevant."
- *"Exit 137 always means OOM?"* → "No. 137 is SIGKILL. OOM is one source; a liveness-probe kill after the grace period or a manual kill also gives 137. The `OOMKilled` reason is the proof."
- *"Requests vs limits for memory?"* → "Request = what the scheduler reserves; limit = hard cap that triggers OOM. For critical workloads set request = limit (Guaranteed QoS) so they're last to be evicted and never overcommitted."

Upstream Kubernetes evidence (K3s, `kubectl`): [Lab 07 requests and limits](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-07-resource-management/README.md), [Scenario 09 OOMKilled](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-09-resource-limits/README.md) in kubernetes-labs.

---

## 12. Running but not Ready (0/1)

**Plain-language version:** the cook is in the kitchen but **not yet allowed to serve**: the health inspector (readiness probe) says no.

**What's really happening:** the container is running, but its **readiness probe** fails, so condition `Ready=False` and the pod is **removed from the Service's EndpointSlices**. No restart happens (that's liveness). Users see **503** from the router if *no* pod is ready.

```bash
oc get pods                                             # READY 0/1, STATUS Running
oc describe pod <pod> | grep -i -A3 readiness           # probe config + "Readiness probe failed: ..."
oc get endpointslices -l kubernetes.io/service-name=<svc>
```

| Cause | Fix |
|---|---|
| Probe path/port wrong | Match the app's real health endpoint and port |
| App still warming up (cache, JIT) | `initialDelaySeconds` / startup probe |
| Readiness checks a **dependency** (DB down → all pods unready → full outage) | Readiness should reflect "can *I* serve"; degrade gracefully instead |
| App bound to `127.0.0.1` | Bind to `0.0.0.0`; probes come from the kubelet via the pod IP |

**L4 angle:** *"Route returns 503 'Application is not available' but pods are Running. First check?"* → "Endpoints. Running isn't Ready. If the EndpointSlice is empty, readiness is failing or the Service selector doesn't match pod labels."

Related: [RCA-003](../rca/RCA-003-route-unreachable-three-faults.md), [OCP-015](../stories/OCP-015-fix-app-unreachable-via-route.md).

Upstream Kubernetes evidence (K3s, `kubectl`): [Lab 08 health checks](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-08-health-checks/README.md), [Scenario 06 probe failures](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/scenario-06-liveness-readiness/README.md) in kubernetes-labs.

---

## 13. Error / Completed (exit codes)

**Plain-language version:** the cook **finished**: well (`Completed`, exit 0) or badly (`Error`, non-zero).

- For **Jobs/CronJobs** (`restartPolicy: OnFailure/Never`), `Completed` is success, `Error` is a failed attempt counted against `backoffLimit`.
- For **Deployments** (`restartPolicy: Always`), any exit leads to restart and eventually `CrashLoopBackOff`.

Read the exit code with [§17](#17-exit-code-cheat-sheet), then `oc logs <pod>` (Job pods stay around until cleaned up).

Upstream Kubernetes evidence (K3s, `kubectl`): [Lab 09 Jobs and CronJobs](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-09-jobs-cronjobs/README.md) in kubernetes-labs.

---

## 14. Evicted

**Plain-language version:** the building ran short of space, so management **asked some tenants to leave**, starting with those using more than they booked.

**What's really happening:** two different things are called eviction:

1. **Node-pressure eviction** (kubelet): the node crosses a threshold (`memory.available`, `nodefs.available`, `imagefs.available`, PIDs). The kubelet terminates pods, ranking by **usage above requests** and **priority**. In practice BestEffort pods go first and Guaranteed pods last. Evicted pods stay with `status.phase=Failed`, `reason=Evicted`, and their controller creates replacements elsewhere.
2. **API-initiated eviction**: `oc adm drain`, node maintenance, upgrades. These respect **PodDisruptionBudgets**.

```bash
oc get pods -A --field-selector=status.phase=Failed | grep Evicted
oc describe pod <evicted-pod> | grep -i -A2 message     # "The node was low on resource: ephemeral-storage..."
oc describe node <node> | grep -A6 Conditions            # MemoryPressure / DiskPressure
```

| Pressure | Usual cause | Fix |
|---|---|---|
| `ephemeral-storage` / `nodefs` | Pods writing big logs or temp files to the container filesystem / `emptyDir` | `ephemeral-storage` requests/limits, log rotation, PVC for data |
| `imagefs` | Too many images | Image garbage collection thresholds, prune |
| `memory` | Pods using far above their requests | Set realistic requests; limits; more capacity |

Clean up old evicted pods: `oc delete pods -A --field-selector=status.phase=Failed`.

**L4 angle:** *"Which pods get evicted first, and how do you protect critical ones?"* → "The kubelet ranks by usage above request and priority. Protect critical workloads with requests = limits (Guaranteed), a higher PriorityClass, and enough headroom; protect availability during drains with PDBs."

---

## 15. Terminating (stuck)

**Plain-language version:** the table should be cleared, but **someone is still sitting there**, or a sign on the table says "don't clear yet".

**What's really happening:** on delete the API sets `deletionTimestamp`. The kubelet sends **SIGTERM**, waits `terminationGracePeriodSeconds` (default 30), then **SIGKILL**, and reports back. The object disappears only when the kubelet confirms *and* all **finalizers** are removed.

| Cause | Evidence | Fix |
|---|---|---|
| **Finalizer** not removed (controller gone or failing) | `oc get pod <p> -o jsonpath='{.metadata.finalizers}'` | Fix the owning controller; remove the finalizer only if you understand what it protects |
| **Node down/unreachable**: kubelet can't confirm | Node `NotReady`; pod on that node | Recover the node, or confirm it's dead and delete the node object / out-of-service taint |
| Process stuck in **`D` state** (waiting on NFS/storage) | `oc debug node` → `ps -eo pid,stat,wchan:30,cmd \| awk '$2~/D/'` | Fix the storage path; the kernel can't kill a task in uninterruptible I/O |
| App ignores SIGTERM and has a long grace period | Waits the full grace period | Handle SIGTERM in the app; sensible grace period; `preStop` hook |

**Force delete:** `oc delete pod <p> --grace-period=0 --force` only removes the **API object**. If the node is alive, the container may **keep running**. For StatefulSets this can create **two pods with the same identity** writing to the same data. Use only when the node is confirmed dead.

**L4 angle:** *"Why is force-deleting a StatefulSet pod on an unreachable node dangerous?"* → "The API forgets the pod but the node may still run it. The StatefulSet creates `db-0` again elsewhere: two `db-0`s, split-brain on the same data. Fence the node first."

---

## 16. Unknown / node lost

**Plain-language version:** management **lost contact with that floor**: nobody knows if the workers there are still working.

**What's really happening:** the node stopped sending heartbeats (Lease objects). The node becomes `NotReady`/`Unknown`; after the toleration period (default about 5 minutes for `node.kubernetes.io/unreachable`) pods are marked for deletion and controllers replace them elsewhere. Pods may show `Unknown` or `Terminating`.

```bash
oc get nodes
oc describe node <node> | grep -A8 Conditions
oc get pods -A -o wide --field-selector spec.nodeName=<node>
```

Then troubleshoot the node itself: power/BMC/console, kubelet and CRI-O, network to `api-int`, certificates (pending CSRs after long downtime), MachineConfig state.

---

## 17. Exit code cheat sheet

| Code | Meaning | Typical cause |
|---|---|---|
| 0 | Success | Job finished; for a Deployment, the process shouldn't have exited |
| 1 | General error | Application error: read logs |
| 2 | Misuse of shell builtin / bad arguments | Wrong command arguments |
| 126 | Command found but not executable | Permissions, wrong file |
| 127 | Command not found | Typo in command, missing binary in image |
| 128 + n | Killed by signal n | See below |
| 130 | SIGINT (2) | Interrupted |
| 137 | SIGKILL (9) | OOM kill, liveness kill after grace period, force kill |
| 139 | SIGSEGV (11) | Segmentation fault in the app/native library |
| 143 | SIGTERM (15) | Normal termination request (delete, rollout, liveness) |

---

## 18. L4 interview drill

Answer each in under two minutes using [the 5-step method](#3-the-universal-5-step-method): symptom → evidence → mechanism → fix → prevention.

1. A Deployment shows `0/3` and there are no pods. Walk me through it. *(§4)*
2. Pending with `Insufficient memory`, but nodes are at 40% memory usage. *(§5: requests vs usage)*
3. After a node crash, a database pod is stuck `ContainerCreating` with `Multi-Attach`. *(§6: fencing)*
4. Image pulls fail on 2 of 10 nodes only. *(§7: node-specific)*
5. Pods fail only after a config change, old ones are fine. *(§8)*
6. CrashLoopBackOff, exit 137, no `OOMKilled`. What else kills with SIGKILL? *(§10, §11)*
7. Works on Docker, crashes on OpenShift with `permission denied`. *(§10: random UID)*
8. Node has free memory; container OOMKilled. Explain cgroups. *(§11)*
9. Route returns 503, pods are Running. *(§12: readiness, endpoints)*
10. During a database outage every frontend pod restarted. Root cause and design fix. *(§10/§12: liveness checking a dependency; [RB-S57](../runbooks/RB-S57-liveness-probe-checks-dependency.md))*
11. Many pods `Evicted` with ephemeral-storage on one node. *(§14)*
12. A namespace won't delete; pods stuck Terminating for hours. *(§15: finalizers, D state)*
13. Why is `--force` deletion of StatefulSet pods dangerous? *(§15)*
14. What happens to pods when a node loses network for 10 minutes? *(§16)*
15. Read this: `Last State: Terminated, Reason: Error, Exit Code: 143`. What happened? *(§17: SIGTERM, probably a liveness kill or a rollout)*

**What makes an answer L4 rather than L2:** you name the **component** that owns the step (scheduler, kubelet, CRI-O, admission, CSI, kernel), explain **why** it behaves that way, mention the **risk** of the obvious fix (force delete, `anyuid`, raising limits blindly), and finish with **prevention** at platform level (policy, alert, template, capacity).

See also: [Upstream translation and scenario map in kubernetes-labs](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/labs/lab-13-production-troubleshooting/README.md#upstream-kubernetes-translation-of-the-pod-failure-states-decoder) · [oc command bank](oc-command-bank.md) · [CRI-O container runtime](cri-o-container-runtime.md) · [OpenShift vs Kubernetes architecture](openshift-vs-kubernetes-architecture.md)
