---
title: "CE-001 – What Kubernetes and OpenShift actually solve (and how)"
tags: [kubernetes, openshift, core-engineering, control-loops, fundamentals]
---

# CE-001 – What Kubernetes and OpenShift actually solve (and how)

> **Status:** living article, extended as new findings come from labs and real incidents.
>
> **Core engineering series:** each article explains one idea from first principles:
> the problem, the mechanism that solves it, where that mechanism breaks, and how to
> prove it on a real cluster. Where I have already proven something in a lab, I link
> to that record instead of repeating it.

---

## 0. In plain words (start here if you're new)

**Imagine a restaurant chain.**

In the old way, every restaurant is run by hand. If a cook falls sick, the manager
phones around for a replacement. If a busy evening comes, customers wait. If a kitchen
floods, that restaurant is closed until someone rebuilds it. Every branch cooks the
dish slightly differently.

Kubernetes is like hiring a **tireless head office** that never sleeps. You don't tell
it *how* to run each kitchen; you tell it **what you want**:

> "Always have 3 cooks making pizza, using this exact recipe, and serve customers at this address."

Head office then checks, every few seconds, whether that's still true, and fixes it
when it isn't:

| In the restaurant | In Kubernetes / OpenShift |
|---|---|
| The written instruction "3 pizza cooks, this recipe" | **Desired state**: a YAML file |
| Head office's order book (the single record of what should exist) | **etcd** |
| The front desk at head office that takes every request | **API server** |
| Supervisors who keep checking "do we have 3 cooks?" | **Controllers** |
| The person who decides which kitchen has room for a new cook | **Scheduler** |
| The shift lead in each kitchen who makes sure cooks are actually working | **kubelet** |
| A kitchen | **Node** (a server) |
| A cook at work | **Pod** (one running copy of an app) |
| The sealed meal kit every cook starts from, identical everywhere | **Container image** |
| The restaurant's phone number, which stays the same whoever answers | **Service** |
| The sign on the street that brings customers in | **Route** / Ingress |
| Each franchise owner's separate section, with its own budget and keys | **Namespace / Project** |
| The storeroom that survives when a cook leaves | **Persistent volume** |
| **OpenShift** = Kubernetes plus a franchise package: security rules, a building contractor that renovates every kitchen the same way, and a delivery service built in | Red Hat's distribution of Kubernetes |

The rest of this article explains each "head office job" properly. Every section starts
with a **plain-words** line, then goes into the engineering.

---

## 1. The one idea everything follows from

Traditional operations manages **machines**: install, configure, start, patch, repair.
Kubernetes manages **intent**: you write down what should exist, and software keeps
reality matching it, forever.

```
   you (or Git)                       the cluster
 ┌──────────────┐   kubectl/oc    ┌───────────────┐       ┌──────────────────────┐
 │ desired state│ ──────────────▶ │  API server    │ ◀───▶ │ etcd (the only truth) │
 │ (YAML)       │                 └───────┬───────┘       └──────────────────────┘
 └──────────────┘                         │ watch
                     ┌────────────────────┼─────────────────────┐
                     ▼                    ▼                     ▼
              controllers           scheduler                kubelet (each node)
        "is actual = desired?"  "which node fits?"   "are my pods' containers running?"
               └──────────── observe → compare → act → repeat ────────────┘
```

Every feature in this article is the same loop with a different controller:

| Loop | Watches | Acts when actual ≠ desired |
|---|---|---|
| ReplicaSet controller | number of matching pods | creates or deletes pods |
| Deployment controller | the pod template | creates a new ReplicaSet, shifts pods over |
| Scheduler | pods with no node | binds each pod to a node that fits |
| kubelet | pods bound to its node | starts, restarts or stops containers via CRI-O |
| Node lifecycle controller | node heartbeats | marks the node NotReady, then evicts its pods |
| EndpointSlice controller | pods matching a Service selector | updates the backend list |
| HPA controller | a metric vs a target | changes `spec.replicas` |
| OpenShift Operators (CVO, MCO, …) | the platform's own config | upgrade, reconfigure, roll nodes |

**Why this matters in an outage:** "the platform does it" always means "a specific
controller does it, on a specific signal, with a specific delay". Troubleshooting is
finding which loop is not converging, and why.

---

## 2. The problems, one by one

Each section follows the same order: **problem → mechanism → limits → prove it**.

### 2.1 A process crashes or hangs

> **In plain words:** a cook faints. The shift lead notices within seconds and puts a fresh cook at the same station. If a cook is standing still but not cooking, a regular "are you OK?" check catches that too.

**Problem.** The service dies at 2 AM; someone gets paged to restart it.

**Mechanism.**
- The kubelet restarts a failed container according to the pod's `restartPolicy`. The waits between restarts back off exponentially: 10 s, 20 s, 40 s and so on, up to 5 minutes (that wait is `CrashLoopBackOff`).
- A **liveness probe** turns "hung but not dead" into "dead", so the restart logic applies.
- A **readiness probe** takes a pod out of Service endpoints without restarting it.
- A **startup probe** holds the other two off while a slow app boots.

**Limits.**
- A bare Pod is only restarted on the **same node**. If the node goes, the Pod goes ([OCP-001](../stories/OCP-001-bare-pod-no-self-heal.md)). Replacement needs a controller ([OCP-002](../stories/OCP-002-deployment-self-heal.md)).
- **A wrong probe makes things worse:**
  - A liveness probe that kills a slow-starting app ([RB-S56](../runbooks/RB-S56-liveness-probe-kills-slow-starting-app.md)).
  - A liveness probe that checks a dependency, so one database blip restarts every pod ([RB-S57](../runbooks/RB-S57-liveness-probe-checks-dependency.md)).
- Restarts hide the cause. Read `oc logs --previous` and the exit code: **1** means the app quit, **137** means it was killed (OOM or SIGKILL).

Every failure state, decoded down to the mechanism: [Pod failure states decoder](../reference/pod-failure-states-decoder.md).

**Prove it.** `oc delete pod <pod>` under a Deployment, then watch a replacement appear.
`oc get pod -o jsonpath='{.status.containerStatuses[0].lastState}'` shows why the last attempt died.

### 2.2 A whole server fails

> **In plain words:** a whole kitchen floods. Head office notices the kitchen has stopped reporting in, waits a few minutes to be sure, then opens the same stations in the other kitchens.

**Problem.** Hardware or a hypervisor host dies. Traditional fix: a failover runbook, and a restore onto a new VM.

**Mechanism.**
- Each kubelet renews a **Lease** about every 10 s.
- If renewals stop for the node-monitor grace period (tens of seconds), the node lifecycle controller marks the node `NotReady` / `Unknown` and taints it.
- Pods carry a default toleration of **300 s** for those taints. After that they are evicted, and their controllers create replacements on healthy nodes.

**Limits.**
- **Recovery is minutes, not seconds:** grace period plus 300 s, plus image pull and app start. Tune `tolerationSeconds` per workload if that's too slow.
- **StatefulSet pods are not replaced while the old pod might still be running.** Two copies writing to the same volume is worse than downtime, so a human (or fencing) must confirm the node is gone.
- **Capacity:** if the remaining nodes can't fit the evicted pods, they stay `Pending`. N+1 capacity is a design decision, not a feature.

**Prove it.** Cordon and drain a worker in a lab (`oc adm drain <node> --ignore-daemonsets --delete-emptydir-data`), then watch the pods move.

### 2.3 Load changes

> **In plain words:** a festival brings a queue out of the door. Head office sees the cooks are overloaded and adds more, and when the rush ends it sends the extras home. If every kitchen is full, it can rent another kitchen.

**Problem.** Month-end, a sale or a batch job. Traditional fix: request a VM, wait for change approval.

**Mechanism.**
- **HorizontalPodAutoscaler:** every ~15 s, desired replicas = `ceil(current × currentMetric / target)`, clamped to min/max. Scale-down waits through a stabilisation window (default 5 min) so it doesn't flap.
- **Cluster autoscaler** (OpenShift: `ClusterAutoscaler` + `MachineAutoscaler`): adds nodes when pods are `Pending` for lack of room, and removes under-used ones.
- **Proven in a lab:** [OCP-003](../stories/OCP-003-scale-deployment.md) (manual and declarative scaling) and [OCP-023](../stories/OCP-023-hpa-cpu-autoscaling.md) (HPA under load, up and down).

**Limits.**
- **HPA on CPU needs CPU `requests`**: utilisation is measured against the request. No request, no scaling.
- **Scaling only helps a stateless, horizontally scalable tier.** A single database writer doesn't scale by adding pods.
- **Node autoscaling takes minutes** to provision a machine, so spikes faster than that need headroom.

### 2.4 Releasing changes safely

> **In plain words:** a new recipe is introduced one cook at a time while the restaurant stays open. A new cook only serves customers once a taste test passes. If customers complain, everyone switches back to the old recipe in one step.

**Problem.** Every release means a maintenance window, downtime and a rollback plan on paper.

**Mechanism.**
- **Rolling update:**
  - The Deployment controller creates a new ReplicaSet and shifts pods over in steps. Defaults are `maxSurge 25%` and `maxUnavailable 25%`.
  - A new pod only counts once it is **Ready**, so the readiness probe is what stops a bad version from taking traffic.
  - Old ReplicaSets are kept (`revisionHistoryLimit`, default 10), so `oc rollout undo` is instant.
- **Blue-green and canary** come from Service or Route switching and weighted Routes ([OCP-017](../stories/OCP-017-blue-green-deployment.md), [OCP-018](../stories/OCP-018-traffic-split-canary.md)).
- **OpenShift extras:** ImageStream triggers redeploy when an image tag moves ([OCP-008](../stories/OCP-008-imagestream-trigger-and-route.md)).

**Limits.**
- **Only the pod template triggers a rollout.** Changing a ConfigMap does not ([RB-S43](../runbooks/RB-S43-configmap-updated-app-still-old-value.md)).
- **A tag is not an image.** Redeploying `:v2` can run a stale cached copy under `IfNotPresent`; pin digests for anything that must be exact.
- **Database schema changes are not rolled back by `rollout undo`.** Releases need backward-compatible migrations.

### 2.5 Finding and reaching other services

> **In plain words:** customers always ring the same restaurant number, whichever cook picks up. Cooks come and go; the number never changes.

**Problem.** Hard-coded IPs, load balancer tickets, DNS requests, firewall changes.

**Mechanism.**
- **A Service** gives a stable virtual IP and DNS name (`<svc>.<ns>.svc.cluster.local`) in front of changing pod IPs.
- **The endpoint list:** the EndpointSlice controller lists the **ready** pods matching the selector. The network layer (OVN-Kubernetes on OpenShift) load-balances to them.
- **External traffic:** Routes (OpenShift, HAProxy routers) or Ingress / Gateway API (upstream).

**Limits.**
- **Selector and labels are the classic failure:** a Service with no endpoints means a selector/label mismatch or no Ready pods. Three such faults stacked up in [RCA-003](../rca/RCA-003-route-unreachable-three-faults.md).
- **DNS search lists and `ndots:5`** turn one lookup into several. Fully qualified names avoid that.
- **Every pod can reach every other pod by default.** Isolation is opt-in (2.8).

### 2.6 Configuration that differs per environment

> **In plain words:** every branch gets the same sealed meal kit; only the local menu card (prices, opening hours) differs. Nobody re-cooks the recipe by hand in each kitchen.

**Problem.** "Works on my machine": config files edited by hand on each server, drifting apart.

**Mechanism.**
- **One immutable image** runs everywhere.
- **What changes per environment** (env vars, config files, credentials) comes from ConfigMaps and Secrets, as variables or mounted files.

**Limits.**
- **Secrets are base64-encoded, not encrypted.** Protection comes from RBAC, encryption at rest for etcd, and an external store (Vault / External Secrets) for real credentials.
- **Common failures:**
  - A missing key → `CreateContainerConfigError` ([RB-S42](../runbooks/RB-S42-createcontainerconfigerror-missing-configmap-key.md)).
  - A newline or double base64 in a password ([RB-S44](../runbooks/RB-S44-secret-password-newline-or-double-base64.md)).
  - Environment variables don't refresh in a running pod; mounted files do, eventually.

### 2.7 Wasted capacity, and noisy neighbours

> **In plain words:** instead of one cook per kitchen, many cooks share kitchens, and each is promised (and limited to) a fair amount of space and gas. A cook who grabs too much is stopped before others go hungry.

**Problem.** One application per VM, running at 10–20% utilisation; or one runaway app starves its neighbours.

**Mechanism.**
- **Requests** are what the scheduler reserves, and **limits** are what the kernel enforces through cgroups.
- **CPU over the limit is throttled; memory over the limit is killed** (OOMKilled, exit 137).
- **QoS classes decide who is evicted first under node pressure:** `Guaranteed` (requests = limits), then `Burstable`, then `BestEffort`.
- **ResourceQuota and LimitRange** set a ceiling and defaults per project.

**Limits.**
- **Requests that don't match reality break it in both directions.**
  - Too high: nodes look full while idle.
  - Too low: nodes are overcommitted, and pods are evicted or OOM-killed under load.
- **A node can be "full" by requests while showing low real usage**, or the reverse. Check both: `oc describe node` (allocated) and `oc adm top node` (actual).
- **Control-plane nodes that also run workloads compete with etcd and the API server** for the same memory.

### 2.8 Many teams on one platform

> **In plain words:** many franchise owners share one building, but each has their own locked section, budget and staff list. Nobody gets the master key by default.

**Problem.** Separate servers per team, access by ticket, nobody sure who can touch what.

**Mechanism.**
- **Namespaces / Projects** are the unit of tenancy.
- **RBAC** controls who can do what.
- **ResourceQuota** controls how much each project can use.
- **NetworkPolicy** controls who can talk to whom.
- **OpenShift adds:**
  - **SCCs:** by default the `restricted-v2` SCC runs every container as a random, non-root UID from the project's range, with group 0.
  - **Project templates** apply guardrails automatically to every new project.

**Limits.**
- **Namespaces are a soft boundary.** Everyone shares the kernel, nodes and control plane, so strict isolation needs separate node pools or clusters.
- **Root-only images break under `restricted-v2`** ([OCP-004](../stories/OCP-004-third-party-image-etherpad.md), [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md)). The fix belongs in the image (group-0-owned, group-writable paths), not in granting `anyuid` to everyone.
- **Which SCC a pod gets depends on who creates it,** a user or a ServiceAccount, not only the namespace.

### 2.9 State: data that must survive

> **In plain words:** whatever a cook keeps on the worktop is binned at the end of the shift. Anything important goes in the storeroom, which stays when the cook leaves. The storeroom isn't a backup, though: if it burns down, you need a copy somewhere else.

**Problem.** A container's filesystem disappears with the container.

**Mechanism.**
- **PersistentVolumeClaims** ask for storage. A StorageClass + CSI driver provisions it dynamically, or an admin pre-creates it (static).
- **StatefulSets** give each replica a stable name and its own PVC.
- **Proven in labs:** static PV ([OCP-019](../stories/OCP-019-static-pv-pvc-nfs.md)), dynamic PVC ([OCP-020](../stories/OCP-020-dynamic-storage-etherpad.md)), StatefulSet ([OCP-022](../stories/OCP-022-statefulset-3-replicas.md)). The failure it prevents is in [RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md).

**Limits.**
- **Kubernetes provides the volume, not the database.** Replication, backups, failover and consistency are still the application's (or an Operator's) job.
- **Storage class properties are hard constraints:** access mode (RWO vs RWX), binding mode (`Immediate` vs `WaitForFirstConsumer`), and whether expansion is allowed. A class with no expansion means a full PVC needs migrating, not resizing.
- **A PVC is not a backup.** Use snapshots, OADP/Velero, or database-native backups, and test the restore.

### 2.10 Drift and "snowflake" servers

> **In plain words:** if someone quietly changes a recipe in one branch, head office notices it no longer matches the master copy and puts it back. With GitOps, the master copy lives in one shared notebook (Git) that every change must go through.

**Problem.** Every server patched and tweaked by hand; nobody knows the real state.

**Mechanism.**
- **Declarative objects + reconciliation** mean the cluster itself corrects drift within its own objects ([OCP-003](../stories/OCP-003-scale-deployment.md) shows a drift demo).
- **GitOps (Argo CD)** extends the same loop to Git: Git is the desired state, and the cluster is continuously synced to it. See the [GitOps labs](../gitops/README.md).

**Limits.**
- Imperative changes (`oc edit`, `oc scale`) are overwritten by the GitOps sync, which is the point, but surprising in an incident. Agree when to suspend sync.
- Secrets in Git need a pattern (sealed secrets, External Secrets), never plain YAML.

### 2.11 Running the platform itself (what OpenShift adds)

> **In plain words:** OpenShift also takes care of the buildings: renovating every kitchen to the same standard, one at a time, so the chain never closes.

Upstream Kubernetes leaves installation, OS patching and upgrades to you. OpenShift
applies the same control-loop idea to the platform:

| Platform problem | OpenShift mechanism |
|---|---|
| Upgrading the control plane and all components consistently | **Cluster Version Operator** applies a tested release payload, one component Operator at a time |
| Patching and configuring node OSes | **RHCOS + Machine Config Operator**: node config is declarative (`MachineConfig`), and nodes are drained, updated and rebooted one by one |
| Adding or replacing nodes | **Machine API**: `MachineSet` replicas, the same idea as pod replicas |
| Installing platform services (registry, monitoring, ingress, logging) | **Operators + OLM**: each service is an Operator that keeps it configured |
| Building images in-cluster | **BuildConfigs, ImageStreams**, and the internal registry |
| Fleet management | **ACM**: policies, upgrades and placement across many clusters |

**Limits.**
- **Upgrades still need planning:** deprecated APIs, Operator compatibility, PodDisruptionBudgets that block drains, and capacity for one node out at a time.
- **Being "managed by Operators" changes how you fix things.** Editing a managed resource by hand gets reverted; change the Operator's config instead.

---

## 3. A day in the life: one online shop on sale day

The same story, told end to end without jargon. Each step names the mechanism from section 2.

| Time | What happens | Without the platform | With Kubernetes / OpenShift |
|---|---|---|---|
| 08:00 | Sale starts; visitors jump 5× | Site slows down, people ring the ops team | The autoscaler adds copies of the web app within a minute or two (2.3) |
| 09:30 | A bug makes the checkout app crash every few minutes | Someone restarts it by hand, again and again | It restarts itself each time; customers barely notice; engineers read the crash logs calmly (2.1) |
| 11:00 | The fix is released at peak time | Wait for tonight's maintenance window | Rolling update: new copies replace old ones one by one, with no downtime (2.4) |
| 13:15 | One server's hardware fails | Outage on that server until it's rebuilt | Its apps restart on the other servers within minutes (2.2) |
| 15:00 | The payments team deploys too, on the same platform | They wait for their own servers | They work in their own project with their own limits; neither team can affect the other (2.7, 2.8) |
| 20:00 | Rush is over | Extra servers sit idle for weeks | Extra copies are removed automatically (2.3) |
| Next day | Someone asks "what exactly changed yesterday?" | Read change tickets and shell history | Read Git history: every change is recorded (2.10) |

What *didn't* change: someone still had to write good health checks, set sensible
limits, keep backups of the orders database, and watch the dashboards.

---

## 4. What it does not solve

- **Bad application design:** an app that keeps state in memory, can't run two copies, or takes minutes to start won't become resilient by being containerised.
- **Your data:** consistency, backups and disaster recovery remain design work.
- **Operations discipline:** monitoring, alerting, capacity planning, change control and runbooks still decide how an incident goes. The platform removes toil, not responsibility.
- **Complexity:** it adds whole new layers to understand (overlay networking, CSI storage, admission, certificates, etcd). Teams that adopt it without that skill trade old problems for harder new ones.

---

## 5. The engineer's checklist (from all of the above)

When something on a cluster "isn't working", ask which loop isn't converging:

1. **Is the desired state what I think it is?** `oc get <obj> -o yaml`, and the Git source if GitOps.
2. **Which controller owns this?** Follow `ownerReferences`: pod → ReplicaSet → Deployment.
3. **What does the controller report?** `status.conditions` and **events** (`oc get events --sort-by=.lastTimestamp`).
4. **Is the scheduler able to place it?** `Pending` + `FailedScheduling` → requests, taints, affinity, quota.
5. **Is the kubelet able to run it?** Image pull, config errors, SCC, probes, exit codes, `--previous` logs.
6. **Is traffic able to reach it?** Readiness → EndpointSlice → Service → Route/Ingress → DNS.
7. **Is the platform healthy?** `oc get co`, node conditions, `oc adm top nodes`.

---

## 6. Interview angle

- **"Why Kubernetes?"** Desired state + reconciliation. Then one before/after example from real operations, for example patching: per-server change windows on VMs versus an image rebuild and a rolling update with no downtime.
- **"What happens when a node dies?"** Lease stops → NotReady + taint → 300 s toleration → eviction → controller recreates elsewhere. Mention StatefulSet safety and capacity.
- **"What does OpenShift add over Kubernetes?"** The same reconciliation applied to the platform itself (CVO, MCO, Operators), plus secure defaults (SCC), Routes, builds and an integrated registry.
- **"What doesn't it solve?"** Data, app design, operations discipline. Saying this is what separates experience from marketing.

---

## 7. Glossary (one line each)

| Term | Plain meaning |
|---|---|
| Container | An app packed with everything it needs, so it runs the same anywhere |
| Image | The packed, read-only template a container is started from |
| Pod | The smallest thing Kubernetes runs: one or more containers sharing a network address |
| Node | A server (physical or virtual) that runs pods |
| Cluster | A group of nodes managed together as one platform |
| Control plane | The "head office": API server, etcd, scheduler, controllers |
| Deployment | "Keep N copies of this app running, and update them safely" |
| ReplicaSet | The helper a Deployment uses to keep exactly N copies |
| StatefulSet | Like a Deployment, for apps where each copy needs its own name and storage |
| Service | A stable name and address in front of a changing set of pods |
| Route / Ingress | The way traffic from outside the cluster reaches a Service |
| Namespace / Project | A separate area for one team or app, with its own permissions and limits |
| ConfigMap / Secret | Settings and passwords kept outside the image |
| PVC (PersistentVolumeClaim) | A request for storage that outlives any one pod |
| Probe | A regular health check: is it alive? is it ready for traffic? |
| HPA | Adds or removes copies automatically based on load |
| Operator | Software that runs another piece of software the way an expert admin would |
| SCC | OpenShift's security rule set deciding what a container may do (e.g. never run as root) |
| GitOps | Keeping the cluster's desired state in Git and syncing automatically |
