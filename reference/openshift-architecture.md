# OpenShift Architecture

Nookireddi Dileep · Nov 2026 · Based on OpenShift Container Platform 4.18

**Part A — The platform**
1. Introduction
2. OpenShift in Plain Words
3. OpenShift Cluster Architecture
4. Control Plane Components
5. The Operator Layer (CVO, ClusterOperators, OLM)
6. Node Components (RHCOS, kubelet, CRI-O, OVN-Kubernetes, MCD)
7. End-to-End OpenShift API Request Flow

**Part B — Running applications**

8. Pod Lifecycle
9. Deployment and ReplicaSet Workflow
10. Other Workload Types
11. Scheduler Decision Process
12. Requests, Limits, Quotas
13. Autoscaling
14. Health Probe Workflow
15. End-to-End Pod Creation Workflow

**Part C — Delivering applications**

16. Build and ImageStream Workflow
17. Internal Image Registry and Mirroring
18. Templates and Helm
19. Web Console

**Part D — Networking**

20. Service Networking and Service Types
21. OVN-Kubernetes
22. Routes and the Ingress Controller
23. DNS Resolution
24. NetworkPolicy and Egress Control

**Part E — Configuration and storage**

25. ConfigMap Workflow
26. Secret Workflow
27. Persistent Storage Workflow

**Part F — Security**

28. Authentication Flow (`oc login`)
29. RBAC Authorization Flow
30. Projects and Namespace Isolation
31. Security Context Constraints (SCC)
32. Certificates and the Service CA

**Part G — Running the platform (day 2)**

33. MachineConfig and Node Update Flow
34. Node Tuning
35. Machine API and Node Lifecycle
36. Cluster Upgrade Flow
37. Installation and Bootstrap Flow
38. Monitoring, Logging, Telemetry
39. Backup and Disaster Recovery
40. The Add-on Ecosystem

**Part H — Putting it together**

41. Production Troubleshooting Workflow
42. OpenShift Best Practices
43. Senior Platform Engineer Interview Revision
44. Recommended Learning Path
45. Glossary
46. Conclusion

---

# 🟥 OpenShift Architecture

> **A from-scratch guide to how OpenShift 4 works: what every component does, in plain words first and then in technical detail, and what happens end to end when you log in, deploy, build, expose, store, secure, update and upgrade.**

> You don't need to know Kubernetes first. Every term is explained the first time it appears, and the **Glossary** at the end collects them all. If you already know Kubernetes, the "OpenShift difference" notes in each section show what changes.
>
> Companion docs: [OpenShift vs Kubernetes](openshift-vs-kubernetes-architecture.md) · [oc command bank](oc-command-bank.md) · [Pod failure states decoder](pod-failure-states-decoder.md) · upstream version: [Kubernetes Architecture](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/ARCHITECTURE.md)

---

# 📖 Introduction

Modern applications are shipped as **containers**: a packaged application with everything it needs (code, libraries, runtime) in one image, so it runs the same way everywhere.

Running one container is easy. Running hundreds of them across many servers, keeping them alive, connecting them, giving them storage, securing them and updating them without downtime is hard. That job is called **container orchestration**, and **Kubernetes** is the open-source standard for it.

**OpenShift Container Platform (OCP)** is Red Hat's enterprise distribution of Kubernetes. It contains all of Kubernetes, and adds everything a company needs around it, already integrated and supported:

- an operating system for the servers (RHCOS)
- networking (OVN-Kubernetes) and a way in from outside (Routes)
- an image registry and in-cluster builds
- login, users and stricter security defaults
- monitoring, a web console, and one-click upgrades of the whole stack

The one idea that explains OpenShift 4:

> **Operators manage everything, the platform included.** Every platform component, from the API server to the node operating system, is looked after by an *operator*: a program that constantly compares what is running with what should be running and fixes any difference.

So almost every OpenShift problem is one of two questions:

1. Is the **application** healthy? (Pods, Services, Routes, storage)
2. Is the **platform** healthy? (ClusterOperators, nodes, node configuration, certificates)

This document explains how both work, from the ground up.

---

# 🏢 OpenShift in Plain Words

Think of an OpenShift cluster as a **large, well-run office building** that rents space to applications.

| In the building | In OpenShift | What it does |
|---|---|---|
| Management office | **Control plane** | Takes every request, makes every decision |
| The building's record book | **etcd** | Remembers everything: every tenant, every room, every rule |
| Front desk | **API server** | The only way to talk to management; checks your ID and permissions first |
| Room allocator | **Scheduler** | Decides which floor has space for a new tenant |
| Supervisors walking the halls | **Controllers** | Notice anything that differs from the plan and fix it |
| Maintenance crew on duty 24×7 | **Operators** | Keep the building itself (lifts, power, locks) running and upgraded |
| Floors | **Nodes** (servers) | Where the work actually happens |
| Floor manager | **kubelet** | Makes sure the tenants on its floor are running |
| Rooms | **Pods** | Where an application's containers live |
| Tenants' departments | **Projects** | Separate areas for each team, with their own keys and budgets |
| Building rules | **SCCs and RBAC** | Who may do what, and what tenants may never do (no one gets the master key) |
| Reception phone directory | **Services and DNS** | A fixed name and number for each department, even when people move rooms |
| Front gate with a visitor list | **Routes / router** | How visitors from outside reach the right department |
| Storage lockers | **Persistent Volumes** | Space that keeps your things even if you change rooms |

**Kubernetes vs OpenShift, in one line:** upstream Kubernetes gives you the management office and you build the rest of the building yourself; OpenShift delivers the whole building, finished, with the maintenance crew already hired.

**The core rule of both: desired state.** You never tell OpenShift "start this container now". You write down what you want ("3 copies of this app, always"), and the system keeps working until reality matches, and keeps it that way. If a copy dies, a controller notices and starts a new one. This loop is called **reconciliation**:

```text
   ┌──────────────► Observe what is running
   │                        │
   │                        ▼
   │              Compare with what you asked for
   │                        │
   │                        ▼
   └─────────────── Act to remove the difference
```

---

# 🧪 What the lab cluster looks like

The hands-on notes in this repo come from a multi-node OpenShift 4.x lab cluster (3 control plane nodes plus workers). If you have used the single-node K3s labs in kubernetes-labs, these are the differences you will notice:

| Single-node K3s (kubernetes-labs) | Multi-node OpenShift (this repo) |
|---|---|
| One `k3s` process holds the whole control plane | Each control plane component runs as Pods on 3 control plane nodes, managed by its own operator |
| SQLite (kine) datastore | 3-member etcd cluster with quorum |
| Ubuntu, packages managed by hand | RHCOS: an immutable OS managed by the Machine Config Operator |
| containerd | CRI-O |
| Flannel + kube-router | OVN-Kubernetes |
| Traefik Ingress | HAProxy-based router; Routes and Ingress both supported |
| Pods may run as root | `restricted-v2` SCC: random non-root user ID, no privilege escalation |
| Upgrade = replace the binary | Upgrade = the Cluster Version Operator rolls out a signed release image |

---

# 🏗️ OpenShift Cluster Architecture

A **cluster** is a group of servers (called **nodes**) that work together as one platform. OpenShift nodes have three roles:

- **Control plane nodes** (also called masters): run the "brain" (API servers, etcd, scheduler, controllers and the platform operators). A standard cluster has exactly 3, so it survives losing one.
- **Compute nodes** (workers): run your applications.
- **Infrastructure nodes** (optional): workers labelled `node-role.kubernetes.io/infra` that host platform services such as the router, the registry and monitoring, so they don't compete with applications for resources.

```text
                          OpenShift Cluster
┌────────────────────────────────────────────────────────────────────┐
│                                                                    │
│   Control Plane (x3, RHCOS)                                        │
│   ┌────────────────────────────────────────────────────────────┐   │
│   │ kube-apiserver   openshift-apiserver   oauth-apiserver     │   │
│   │ etcd (3 members) kube-scheduler        kube-controller-mgr │   │
│   │ openshift-controller-manager           oauth-openshift     │   │
│   │ ───────────────────────────────────────────────────────────│   │
│   │ Cluster Version Operator ──► ~30 ClusterOperators          │   │
│   │ OLM (add-on operators)    Machine Config Operator          │   │
│   └───────────────────────────────┬────────────────────────────┘   │
│                                   │  API (6443)                    │
│        ┌──────────────────────────┼──────────────────────────┐     │
│        ▼                          ▼                          ▼     │
│  ┌───────────────┐        ┌───────────────┐         ┌───────────────┐
│  │ Infra node    │        │ Worker node   │         │ Worker node   │
│  │ router pods   │        │ kubelet       │         │ kubelet       │
│  │ image-registry│        │ CRI-O → runc  │         │ CRI-O → runc  │
│  │ monitoring    │        │ OVN-Kubernetes│         │ OVN-Kubernetes│
│  │ kubelet/CRI-O │        │ MCD           │         │ MCD           │
│  └───────────────┘        │ App Pods      │         │ App Pods      │
│                           └───────────────┘         └───────────────┘
│                                                                    │
│   External access:  api.<cluster>.<domain>:6443   (API, oc, console│
│                                                    backend)        │
│                     *.apps.<cluster>.<domain>     (Routes, console)│
└────────────────────────────────────────────────────────────────────┘
```

**Cluster shapes (topologies):**

| Topology | Nodes | Use |
|---|---|---|
| Standard HA | 3 control plane + 2 or more workers | Production |
| Compact (3-node) | 3 nodes acting as both control plane and workers | Small sites, labs |
| Single Node OpenShift (SNO) | 1 node does everything | Edge sites; no high availability |
| Hosted control planes (HCP) | The control plane runs as Pods on another "management" cluster | Many clusters at lower cost |

**Three DNS names every cluster needs:**

| Name | Points to | Used by |
|---|---|---|
| `api.<cluster>.<domain>` | API load balancer, port 6443 | `oc`, admins, automation |
| `api-int.<cluster>.<domain>` | Internal API load balancer, ports 6443 and 22623 | Nodes talking to the control plane |
| `*.apps.<cluster>.<domain>` (wildcard) | Router load balancer, ports 80/443 | Every application Route and the web console |

---

# 🎯 Control Plane Components

The control plane is the brain of the cluster. OpenShift runs the four standard Kubernetes components plus OpenShift's own API servers and controllers. Each one runs as Pods in its own `openshift-*` namespace and is owned by an operator.

| Component | In plain words | Namespace | Runs as |
|---|---|---|---|
| kube-apiserver | Front desk for everything | `openshift-kube-apiserver` | Static Pod on each control plane node |
| etcd | The record book | `openshift-etcd` | Static Pod on each control plane node |
| kube-scheduler | Room allocator | `openshift-kube-scheduler` | Static Pod |
| kube-controller-manager | Supervisors | `openshift-kube-controller-manager` | Static Pod |
| openshift-apiserver | Front desk for OpenShift-only objects | `openshift-apiserver` | Deployment, one Pod per control plane node |
| oauth-openshift | Login service | `openshift-authentication` | Deployment |
| oauth-apiserver | Keeps users, groups and login tokens | `openshift-oauth-apiserver` | Deployment |
| openshift-controller-manager | Supervisors for OpenShift objects | `openshift-controller-manager` | Deployment |
| route-controller-manager | Turns Ingress objects into Routes | `openshift-route-controller-manager` | Deployment |

> A **static Pod** is a Pod that the kubelet starts straight from a file on the node's disk, without asking the API server. That is how the API server itself can run as a Pod: something has to start it before there is an API. In OpenShift, operators write and update those files for you.

---

## 1. kube-apiserver

**In plain words:** the front desk. Nobody talks to etcd, the scheduler or a node directly; everything goes through here.

Every `oc` command, web console click, CI/CD pipeline, operator and kubelet talks to the kube-apiserver.

Responsibilities:

- Serves the Kubernetes REST API on port 6443
- **Authenticates** each request: who are you? (certificate, service account token, or OAuth token)
- **Authorizes** it with RBAC: are you allowed to do this?
- Runs **admission plugins**: may change or reject the request (SCCs, quotas, defaults, webhooks)
- Validates the object and stores it in etcd
- Forwards requests for OpenShift-only API groups (Routes, Builds, Projects…) to openshift-apiserver and oauth-apiserver. This forwarding is called **API aggregation**.

```bash
oc apply -f deployment.yaml          # always lands at the kube-apiserver first
oc get apiservices | grep openshift  # aggregated OpenShift APIs and whether they are Available
oc get pods -n openshift-kube-apiserver
```

**OpenShift difference:** you never edit API server files on a node. You change the cluster `APIServer` config (`oc edit apiserver cluster`), and the `kube-apiserver` operator creates a new **revision** of the static Pod and rolls it out one control plane node at a time.

---

## 2. etcd

**In plain words:** the record book. If it isn't in etcd, it doesn't exist in the cluster.

etcd is a distributed key-value database that stores every object: Pods, Deployments, Secrets, Routes, users, configuration.

- **3 members** on the 3 control plane nodes. They agree on every write by majority (**quorum**), so the cluster keeps working with 2 of 3, and stops accepting writes with only 1.
- Only the kube-apiserver talks to etcd.
- Very sensitive to disk speed. Slow disks show up as API timeouts and frequent leader elections.
- Managed by the **cluster-etcd-operator**: members, TLS certificates, defragmentation, revisions.

```bash
oc get pods -n openshift-etcd -l app=etcd
oc rsh -n openshift-etcd etcd-<node>  etcdctl endpoint health --cluster
oc rsh -n openshift-etcd etcd-<node>  etcdctl endpoint status -w table
```

Quorum in depth (failure scenarios, leader election, recovery): [etcd quorum explained](etcd-quorum.md). Backup and restore are covered in **Backup and Disaster Recovery**.

---

## 3. kube-scheduler

**In plain words:** the room allocator. It only decides *where* a Pod goes; it doesn't start it.

It watches for Pods with no node assigned, filters out nodes that can't run them, scores the rest and writes the best node name into the Pod. Details in **Scheduler Decision Process**.

**OpenShift difference:** configured through the cluster `Scheduler` resource (`oc edit scheduler cluster`), for example a default node selector or a scheduling profile. Projects can also force their Pods onto certain nodes.

---

## 4. kube-controller-manager

**In plain words:** a team of supervisors, each watching one kind of object and fixing differences.

It runs the standard controllers: Deployment, ReplicaSet, StatefulSet, DaemonSet, Job, Node lifecycle (marks dead nodes and evicts their Pods), ServiceAccount, Endpoints, and the certificate signer for cluster components.

```text
Observe current state → compare with desired state → act → repeat
```

---

## 5. openshift-apiserver

**In plain words:** a second front desk, for objects that only exist in OpenShift.

| API group | Objects |
|---|---|
| `project.openshift.io` | Project, ProjectRequest |
| `route.openshift.io` | Route |
| `build.openshift.io` | BuildConfig, Build |
| `image.openshift.io` | ImageStream, ImageStreamTag |
| `apps.openshift.io` | DeploymentConfig (deprecated since 4.14; use Deployments) |
| `template.openshift.io` | Template |
| `quota.openshift.io` | ClusterResourceQuota |
| `security.openshift.io` | SCC review APIs |

If openshift-apiserver is down, plain Kubernetes objects still work, but `oc get routes`, `oc new-project` and builds fail with **"the server is currently unable to handle the request"**. That message is the classic sign of an aggregated API being unavailable.

---

## 6. oauth-openshift and oauth-apiserver

**In plain words:** the login service and the list of who's who.

- **oauth-openshift** is the OAuth 2.0 server: it shows the login page, checks your password with an identity provider (HTPasswd file, LDAP, OpenID Connect, GitHub…) and hands out access tokens.
- **oauth-apiserver** stores `User`, `Identity`, `Group` and token objects, and confirms tokens for the kube-apiserver on every request.

Full flow in **Authentication Flow**.

---

## 7. openshift-controller-manager and route-controller-manager

**In plain words:** supervisors for OpenShift's own objects.

- **openshift-controller-manager**: turns BuildConfigs into builds, redeploys apps when their image changes (image triggers), imports images, creates registry pull secrets for service accounts.
- **route-controller-manager**: converts Kubernetes `Ingress` objects into Routes so the OpenShift router can serve them.

---

# 🧩 The Operator Layer

**In plain words:** the maintenance crew. Upstream Kubernetes leaves platform upkeep to you; OpenShift hands it to operators.

An **operator** is a controller that manages one piece of software the way an expert admin would: install it, configure it, heal it, upgrade it. It watches a custom object that describes the desired state and reconciles toward it, exactly as a Deployment controller does for Pods.

```text
                Release image (one tested bundle of every platform component, e.g. 4.18.z)
                                     │
                                     ▼
                     Cluster Version Operator (CVO)
                     namespace openshift-cluster-version
                                     │  applies and guards the manifests for
          ┌──────────────┬───────────┼─────────────┬───────────────┐
          ▼              ▼           ▼             ▼               ▼
   kube-apiserver     etcd       ingress      network        machine-config
     operator       operator     operator     operator         operator
          │              │           │             │               │
          ▼              ▼           ▼             ▼               ▼
   static Pods     etcd members  router Pods   OVN-K Pods    RHCOS config
                                                              on every node

   Separately:  OLM (Operator Lifecycle Manager) ──► add-on operators from OperatorHub
                (GitOps, Pipelines, Logging, Data Foundation, Virtualization…)
```

## 1. Cluster Version Operator (CVO)

- Knows which **release image** the cluster should be running. A release image lists every platform component at an exact version that Red Hat tested together.
- Applies all platform manifests in a fixed order and **puts them back if anyone changes or deletes them**.
- Drives upgrades (**Cluster Upgrade Flow**).

```bash
oc get clusterversion
oc adm upgrade                  # current version, channel, available updates
```

## 2. ClusterOperators

Each platform area reports its health through one **ClusterOperator** object with three conditions:

| Condition | Meaning |
|---|---|
| `Available=True` | It works |
| `Progressing=True` | It is rolling out a change (upgrade, new revision, config change) |
| `Degraded=True` | Something is wrong and needs attention |

```bash
oc get clusteroperators        # short: oc get co
```

A healthy cluster shows every operator `AVAILABLE=True, PROGRESSING=False, DEGRADED=False`. **`oc get co` is the first command for any platform problem** — the platform's version of `oc get pods`.

Typical ClusterOperators: `authentication`, `console`, `dns`, `etcd`, `image-registry`, `ingress`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `machine-api`, `machine-config`, `monitoring`, `network`, `node-tuning`, `openshift-apiserver`, `operator-lifecycle-manager`, `service-ca`, `storage`.

## 3. Operator Lifecycle Manager (OLM)

The CVO manages the core platform. **OLM** installs and upgrades *optional* operators that you choose from **OperatorHub**.

```text
CatalogSource        a catalog of available operators (a container image)
        │
        ▼
Subscription         "I want operator X, from update channel Y, in this namespace"
        │
        ▼
InstallPlan          the exact list of what will be installed (auto or manual approval)
        │
        ▼
ClusterServiceVersion (CSV)   the installed operator version: its Deployment, RBAC, CRDs
        │
        ▼
Operator Pod         watches its own custom objects (e.g. ArgoCD, StorageCluster)
```

```bash
oc get catalogsource -n openshift-marketplace
oc get packagemanifests | grep -i gitops
oc get subscription,installplan,csv -n <namespace>
```

Common issue: a Subscription with `installPlanApproval: Manual` waits forever until someone approves its InstallPlan.

---

# ⚙️ Node Components

Every node, control plane or worker, runs the same software stack.

```text
┌───────────────────────────────────────────────┐
│                  RHCOS node                   │
│                                               │
│  kubelet ──CRI──► CRI-O ──► runc / crun       │
│     │                          │              │
│     │                     containers (Pods)   │
│     │                                         │
│  ovnkube-node (OVN-Kubernetes + Open vSwitch) │
│  machine-config-daemon (MCD)                  │
│  node-exporter, dns-default, multus …         │
│                                               │
│  Linux kernel + SELinux (enforcing) + systemd │
│  /usr read-only, OS updated as an image       │
└───────────────────────────────────────────────┘
```

## 1. Red Hat Enterprise Linux CoreOS (RHCOS)

**In plain words:** a locked-down Linux built only to run containers, which the cluster updates by itself.

- **Immutable**: `/usr` is read-only and the whole OS is delivered as one image (updated with `rpm-ostree`). You don't `dnf install` on nodes.
- Configured on first boot by **Ignition** (a first-boot configuration file the node downloads), and after that only through **MachineConfig** objects.
- SELinux is always enforcing; it's a key layer of container isolation.

Access nodes through the API rather than SSH:

```bash
oc debug node/<node>
chroot /host
systemctl status kubelet crio
journalctl -u kubelet --since "15 min ago"
crictl ps
```

## 2. kubelet

**In plain words:** the floor manager. It makes sure the Pods assigned to its node are running and healthy.

- Registers the node with the API server and reports its status every few seconds
- Watches for Pods assigned to its node and asks CRI-O to start them
- Mounts volumes, runs health probes, restarts failed containers
- Evicts Pods when the node runs low on memory or disk

**OpenShift difference:** tuned with a `KubeletConfig` object (max Pods, reserved resources, eviction thresholds), which the Machine Config Operator applies. Hand edits on the node are undone.

## 3. CRI-O

**In plain words:** the engine that actually runs containers when the kubelet asks.

- OpenShift's only supported container runtime. It implements the Kubernetes Container Runtime Interface (CRI) and nothing else, and is versioned in step with Kubernetes.
- Pulls images, creates the Pod sandbox, and calls the low-level runtime (**runc**, or **crun**, the default for new 4.18 clusters) that creates the Linux namespaces and cgroups.
- Tuned with a `ContainerRuntimeConfig` object; debugged with `crictl`. More in [CRI-O container runtime](cri-o-container-runtime.md).

## 4. OVN-Kubernetes

**In plain words:** the network wiring. It gives every Pod an IP address and connects Pods across nodes.

The default and (since 4.17) only network plugin. Details in **OVN-Kubernetes**.

## 5. machine-config-daemon (MCD)

**In plain words:** the on-site technician that applies OS changes to its node and reboots it when needed.

Details in **MachineConfig and Node Update Flow**.

---

# 🔄 End-to-End OpenShift API Request Flow

> **What happens after `oc apply -f deployment.yaml`?**

```text
oc apply -f deployment.yaml
            │
            ▼
   API load balancer → kube-apiserver (6443)
            │
            ▼
   Authentication       (OAuth token checked via oauth-apiserver, or cert / SA token)
            │
            ▼
   Authorization        (RBAC: may this user create Deployments in this project?)
            │
            ▼
   Mutating admission   (defaults added; for Pods, the SCC sets user ID, fsGroup, SELinux label)
            │
            ▼
   Schema validation
            │
            ▼
   Validating admission (SCC check, Pod Security Admission, quota, LimitRange, webhooks)
            │
            ▼
   etcd                 (Deployment stored)
            │
            ▼
   Deployment controller → ReplicaSet → Pod objects
            │
            ▼
   Pod passes SCC admission → annotated openshift.io/scc: restricted-v2
            │
            ▼
   kube-scheduler picks a worker node
            │
            ▼
   kubelet on that node sees the Pod
            │
            ▼
   CRI-O pulls the image (pull secret, mirror config) and creates the sandbox
            │
            ▼
   OVN-Kubernetes (through Multus) attaches the Pod's network interface
            │
            ▼
   runc/crun starts the container as a random UID with SELinux labels
            │
            ▼
   Probes pass → Pod Ready → added to Service endpoints → reachable via Route
```

The two places OpenShift most often stops a Pod that would run on plain Kubernetes:

1. **At admission (SCC):** the Pod asks for root, a host path, privileged mode or a fixed user ID that its service account isn't allowed. No Pod is created; the ReplicaSet shows `FailedCreate ... unable to validate against any security context constraint`.
2. **At runtime:** the Pod is admitted under `restricted-v2` with a random user ID, but the image expects root and crashes with "permission denied" (CrashLoopBackOff). See [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md).

---

# 📌 Key Takeaways — The Platform

- OpenShift is Kubernetes plus an integrated, operator-managed platform around it.
- The kube-apiserver is the only entry point; etcd is the only source of truth.
- OpenShift adds openshift-apiserver, OAuth and its own controllers to the control plane.
- Every platform component is owned by an operator; the CVO owns them all through the release image.
- `oc get co` tells you whether the platform is healthy.
- Nodes run RHCOS, kubelet, CRI-O and OVN-Kubernetes, and are changed only through MachineConfig.

---

# 🎤 Interview Quick Revision — The Platform

### Q1. Which component receives every request?

**kube-apiserver.** Requests for OpenShift-only objects are then forwarded to openshift-apiserver or oauth-apiserver.

---

### Q2. Where is cluster state stored?

**etcd**, 3 members on the control plane nodes, managed by the cluster-etcd-operator.

---

### Q3. What does an operator do?

It watches a custom object describing the desired state of some software and keeps the real state matching it: install, configure, heal, upgrade.

---

### Q4. What is the difference between the CVO and OLM?

The CVO manages the core platform from the release image. OLM installs optional add-on operators from catalogs.

---

### Q5. What does `Degraded=True` on a ClusterOperator mean?

That platform component is in a bad state. Next: `oc describe co <name>` and the operator's Pod logs.

---

### Q6. Which container runtime does OpenShift use?

**CRI-O**, calling runc or crun.

---

### Q7. How do you get a shell on a node without SSH?

`oc debug node/<node>` then `chroot /host`.

---

### Q8. Why "the server is currently unable to handle the request" for `oc get routes`?

The aggregated API that serves Routes (openshift-apiserver) is unavailable. Check `oc get apiservices` and `oc get co openshift-apiserver`.

---

# 🚀 Pod Lifecycle

A **Pod** is the smallest thing OpenShift runs: one or more containers that share an IP address, storage volumes and a lifetime. Most Pods hold one application container, sometimes with a helper ("sidecar") next to it.

Pods are **disposable**. They are never repaired or moved; when one dies, a controller creates a new one with a new name and a new IP. That's why applications are reached through Services, never Pod IPs.

## Pod Lifecycle Phases

```text
        Pod created (object stored in etcd)
                    │
                    ▼
               ┌─────────┐
               │ Pending │  waiting for a node, a volume, or image pull
               └────┬────┘
                    │ scheduled, image pulled, containers started
                    ▼
               ┌─────────┐
               │ Running │  at least one container running
               └────┬────┘
          ┌─────────┴──────────┐
          ▼                    ▼
   ┌───────────┐         ┌────────┐
   │ Succeeded │         │ Failed │
   └───────────┘         └────────┘
   all containers exit 0  a container exited non-zero and won't be restarted

   Unknown — the node stopped reporting, so the Pod's state can't be read
```

### Pending

The Pod exists but isn't running yet. Common reasons:

- No node has enough free CPU or memory for its requests
- Node selectors, taints or affinity rules exclude every node
- Its PVC isn't bound yet
- The image is still being pulled, or the pull failed (`ErrImagePull`, `ImagePullBackOff`)

```bash
oc describe pod <pod>      # the Events section at the bottom says why
```

### Running

The Pod is on a node and at least one container is running. Running is not the same as healthy: a container can be running but not Ready, or restarting in a loop (`CrashLoopBackOff`).

### Succeeded

Every container finished with exit code 0 and won't restart. Normal for Jobs.

### Failed

At least one container exited with an error and the restart policy doesn't allow another try (`restartPolicy: Never` or `OnFailure` after the Job's retry limit).

### Unknown

The control plane can't get the Pod's status, usually because its node is unreachable. After a timeout, the node controller marks the node `NotReady` and Pods are recreated elsewhere (for controller-managed Pods).

**OpenShift difference:** a Pod blocked by an SCC never reaches Pending; it's never created at all. Look at the ReplicaSet's events (`oc describe rs`) instead. All Pod failure states are decoded in [Pod failure states decoder](pod-failure-states-decoder.md).

---

# 📦 Deployment and ReplicaSet Workflow

You almost never create Pods directly. A bare Pod that dies stays dead ([OCP-001](../stories/OCP-001-bare-pod-no-self-heal.md)). Instead you create a **Deployment**, and it keeps the right number of Pods running ([OCP-002](../stories/OCP-002-deployment-self-heal.md)).

```text
Deployment            "run 3 replicas of image app:v1, update them one by one"
     │
     ▼
ReplicaSet            "keep exactly 3 Pods with these labels"
     │
     ▼
Pod  Pod  Pod
```

## Deployment Responsibilities

- Creates a ReplicaSet for the current version of the Pod template
- **Rolling updates:** when you change the image or config, creates a new ReplicaSet and shifts Pods over gradually
- **Rollback:** keeps old ReplicaSets so you can return to a previous version
- Scaling: changes the replica count

```text
oc set image deploy/app app=app:v2
        │
        ▼
New ReplicaSet (v2) created with 0 Pods
        │
        ▼
Scale v2 up by maxSurge   ──►  wait for new Pod Ready
        │
        ▼
Scale v1 down by maxUnavailable
        │
        ▼
Repeat until v2 = 3 Pods, v1 = 0 Pods (v1 ReplicaSet kept for rollback)
```

```bash
oc create deployment app --image=quay.io/example/app:v1 --replicas=3
oc scale deploy/app --replicas=5
oc set image deploy/app app=quay.io/example/app:v2
oc rollout status deploy/app
oc rollout history deploy/app
oc rollout undo deploy/app
```

Strategies: `RollingUpdate` (default, no downtime) or `Recreate` (stop all old Pods, then start new; for apps that can't run two versions at once).

## ReplicaSet Workflow

```text
Desired replicas: 3
        │
        ▼
Count Pods matching the label selector
        │
   ┌────┴─────────────┐
   ▼                  ▼
Fewer than 3       More than 3
create Pods        delete Pods
        │
        ▼
Repeat forever
```

The ReplicaSet doesn't care *why* a Pod disappeared (crash, node failure, someone deleted it); it just replaces it. That's self-healing.

**OpenShift difference — DeploymentConfig:** older OpenShift apps use `DeploymentConfig` (apps.openshift.io), which uses ReplicationControllers and a "deployer" Pod. It's deprecated since 4.14. New work should use Deployments, with image triggers added through an annotation (see Builds). Release strategies such as blue-green and canary are done with Routes ([OCP-017](../stories/OCP-017-blue-green-deployment.md), [OCP-018](../stories/OCP-018-traffic-split-canary.md)).

---

# 🧱 Other Workload Types

| Workload | Use when | Behaviour |
|---|---|---|
| **Deployment** | Stateless apps (web, APIs) | Interchangeable Pods, rolling updates |
| **StatefulSet** | Databases, clustered apps | Stable names (`db-0`, `db-1`), one PVC per Pod, ordered start/stop ([OCP-022](../stories/OCP-022-statefulset-3-replicas.md)) |
| **DaemonSet** | One Pod per node (agents, log collectors) | New node → new Pod automatically ([OCP-014](../stories/OCP-014-daemonset-deployment.md)) |
| **Job** | Run to completion (migration, batch) | Retries until success or `backoffLimit` |
| **CronJob** | Scheduled jobs (backups, reports) | Creates a Job on a cron schedule |

OpenShift itself uses all of these: DNS and the network plugin run as DaemonSets, the router and console as Deployments, and image pruning as a CronJob.

---

# 🎯 Scheduler Decision Process

When a Pod has no node, the scheduler runs two phases.

```text
New Pod (no nodeName)
        │
        ▼
FILTER — remove nodes that cannot run it
   enough CPU / memory for the requests?
   nodeSelector / node affinity match?
   taints tolerated?
   volume zone / topology OK?
   project node selector (OpenShift)?
        │
        ▼
SCORE — rank the remaining nodes
   spread replicas across nodes / zones
   balance resource usage
   prefer nodes that already have the image
        │
        ▼
BIND — write nodeName into the Pod
        │
        ▼
kubelet on that node starts it
```

### The Scheduler Considers

- **Resource requests**, not actual usage: a node is "full" when the sum of requests reaches its allocatable capacity.
- **Node selectors and affinity**: "only nodes with label `disktype=ssd`".
- **Pod affinity / anti-affinity**: "keep replicas of this app on different nodes".
- **Taints and tolerations**: a taint repels Pods unless they tolerate it.
- **Topology spread constraints**: even distribution across zones.

**OpenShift additions:**

- Control plane nodes are tainted `NoSchedule` (except compact and SNO clusters), so applications land on workers.
- Infra nodes are usually tainted too, so only platform Pods with a toleration run there.
- **Project node selector**: the annotation `openshift.io/node-selector` on a project forces all its Pods onto matching nodes, whatever their own spec says. A simple way to give a team its own nodes.
- Cluster-wide defaults and profiles: `oc edit scheduler cluster`.

```bash
oc get nodes --show-labels
oc describe node <node> | grep -A5 Taints
oc get pod <pod> -o wide           # which node it landed on
```

---

# ⚖️ Requests, Limits, Quotas

## Requests

What a container is **guaranteed**. The scheduler uses requests to place Pods.

```yaml
resources:
  requests:
    cpu: 250m        # a quarter of a CPU core
    memory: 256Mi
```

## Limits

The **maximum** a container may use.

```yaml
  limits:
    cpu: 500m
    memory: 512Mi
```

| Resource | Over the limit |
|---|---|
| CPU | Throttled (slowed down), not killed |
| Memory | Killed by the kernel: `OOMKilled`, exit code 137, then restarted |

## Requests vs Limits Summary

| | Requests | Limits |
|---|---|---|
| Purpose | Guaranteed share | Upper ceiling |
| Used by | Scheduler | Kernel (cgroups) at runtime |
| If missing | Pod can land on an already-full node | Pod can starve its neighbours |

**QoS classes** follow from these values: **Guaranteed** (requests = limits for every container), **Burstable** (some requests set), **BestEffort** (nothing set — evicted first when a node runs short).

## Guard rails per project

| Object | Scope | What it does |
|---|---|---|
| **LimitRange** | One project | Default requests/limits for containers that don't set any; min/max per container |
| **ResourceQuota** | One project | Total caps: CPU, memory, Pods, PVCs, storage, Services… |
| **ClusterResourceQuota** (OpenShift) | Many projects | One shared cap across all projects selected by label or owner — e.g. one budget for a whole team |

```bash
oc set resources deploy/app --requests=cpu=250m,memory=256Mi --limits=memory=512Mi
oc create quota team-a --hard=pods=20,requests.cpu=4,requests.memory=8Gi -n team-a
oc create clusterquota team-a --project-label-selector=team=a --hard=pods=50
oc describe quota -n team-a
oc describe appliedclusterresourcequota -n team-a
```

When a quota is full, new Pods are **rejected at admission** (ReplicaSet `FailedCreate ... exceeded quota`), not left Pending.

---

# 📈 Autoscaling

| Autoscaler | Scales | Based on |
|---|---|---|
| **HorizontalPodAutoscaler (HPA)** | Number of Pods | CPU / memory usage vs requests, or custom metrics |
| **VerticalPodAutoscaler (VPA)** — add-on operator | Requests/limits of each Pod | Observed usage over time |
| **Cluster Autoscaler** | Number of nodes | Pods that can't be scheduled (see Machine API) |

```text
HPA every ~15 s:
   read Pod CPU from the Metrics API (served by the monitoring stack)
        │
        ▼
   desired = current replicas × (current usage ÷ target usage)
        │
        ▼
   scale the Deployment between min and max
```

```bash
oc autoscale deploy/app --min=2 --max=5 --cpu-percent=60
oc get hpa -w
```

HPA needs CPU requests set — the percentage is calculated against them. Proven under load in [OCP-023](../stories/OCP-023-hpa-cpu-autoscaling.md).

---

# ❤️ Health Probe Workflow

Probes are how the kubelet knows if a container is alive and ready.

```text
Container starts
      │
      ▼
Startup probe (if defined) ── keeps failing ──► container restarted
      │ passes once
      ▼
Liveness + Readiness probes start, and repeat for the Pod's whole life
      │
 ┌────┴───────────────────────────────┐
 ▼                                    ▼
Liveness fails                      Readiness fails
→ kubelet restarts the container    → Pod removed from Service endpoints
                                      (no traffic) but NOT restarted
```

## Startup Probe

Protects slow-starting apps. Until it passes, liveness and readiness are disabled. Use it instead of a long `initialDelaySeconds`.

## Liveness Probe

"Is the process stuck?" If it fails `failureThreshold` times in a row, the container is restarted. It should check only the app itself, never a database or other dependency — otherwise one database outage restarts every Pod ([RB-S57](../runbooks/RB-S57-liveness-probe-checks-dependency.md)).

## Readiness Probe

"Can it take traffic right now?" Failing readiness just takes the Pod out of the Service and Route until it recovers. This is what makes rolling updates safe.

Probe types: `httpGet`, `tcpSocket`, `exec` (run a command), `grpc`.

```bash
oc set probe deploy/app --readiness --get-url=http://:8080/ready --period-seconds=10
oc set probe deploy/app --liveness  --get-url=http://:8080/healthz --initial-delay-seconds=5
oc set probe deploy/app --startup   --get-url=http://:8080/healthz --failure-threshold=30 --period-seconds=10
```

A liveness probe that's too aggressive for a slow app causes endless restarts: [RB-S56](../runbooks/RB-S56-liveness-probe-kills-slow-starting-app.md).

---

# 🏭 End-to-End Pod Creation Workflow

Putting Part B together — from `oc create deployment` to a Pod serving traffic:

```text
1. oc create deployment app --image=... --replicas=3
2. kube-apiserver: authenticate → RBAC → admission → etcd
3. Deployment controller creates ReplicaSet app-<hash>
4. ReplicaSet controller creates 3 Pod objects
5. Admission for each Pod:
     LimitRange fills in default requests/limits
     ResourceQuota checks the project budget
     SCC picks restricted-v2 and assigns UID / fsGroup / SELinux label
6. Scheduler filters and scores nodes, binds each Pod to a node
7. kubelet on each node:
     mounts volumes (ConfigMaps, Secrets, PVCs)
     asks CRI-O to pull the image and create the sandbox
     OVN-Kubernetes gives the Pod an IP
     CRI-O → runc/crun starts the container
8. Startup probe passes → liveness and readiness begin
9. Readiness passes → Pod added to the Service's EndpointSlices
10. Router sees the new endpoint → Route traffic reaches the Pod
```

---

# 📌 Key Takeaways — Running Applications

- Pods are disposable; controllers (Deployments, StatefulSets, DaemonSets, Jobs) keep them running.
- Deployments manage ReplicaSets; ReplicaSets manage Pods.
- The scheduler places Pods by **requests**, filters, then scores.
- Memory over the limit = OOMKilled; CPU over the limit = throttled.
- LimitRange sets defaults, ResourceQuota caps a project, ClusterResourceQuota caps a group of projects.
- Liveness restarts, readiness removes from traffic, startup protects slow starts.
- In OpenShift, SCC and quota problems stop Pods from being created at all — check the ReplicaSet.

---

# 🎤 Interview Quick Revision — Running Applications

### Q1. Does a Deployment create Pods directly?

No. It creates a ReplicaSet, and the ReplicaSet creates the Pods.

---

### Q2. What happens if one Pod of a Deployment dies?

The ReplicaSet sees fewer Pods than desired and creates a replacement, with a new name and IP.

---

### Q3. What does the scheduler use to decide placement?

Resource requests, node selectors and affinity, taints and tolerations, and spread rules — plus the project node selector in OpenShift.

---

### Q4. What happens when a container exceeds its memory limit?

The kernel kills it (`OOMKilled`, exit 137) and the kubelet restarts it.

---

### Q5. Liveness vs readiness?

Liveness failure restarts the container. Readiness failure only removes the Pod from Service endpoints.

---

### Q6. What is a ClusterResourceQuota?

An OpenShift quota that applies one combined limit across several projects selected by label or requester.

---

### Q7. Why is a Deployment showing 0/3 Pods with no Pending Pods at all?

Pods are being rejected at admission — usually an SCC or a quota. `oc describe rs` shows `FailedCreate` with the reason.

---

### Q8. Is DeploymentConfig still recommended?

No. It's deprecated since 4.14; use Deployments with image trigger annotations.

---

# 🔨 Build and ImageStream Workflow

**In plain words:** OpenShift can take your source code, turn it into a container image inside the cluster, store it, and redeploy your app automatically whenever the image changes.

```text
oc new-app https://git.example.com/app.git      (or oc new-build / oc start-build)
        │
        ▼
BuildConfig        recipe: where the source is, how to build, where to push, what triggers a build
        │   triggers: ConfigChange, ImageChange (new builder image), Git webhook, manual
        ▼
Build object       one run of the recipe: app-1, app-2 …
        │
        ▼
Build Pod          runs buildah inside the cluster
   Strategies:  Source-to-Image (S2I): source code + builder image (e.g. Python, Java) → app image
                Docker: builds from a Dockerfile / Containerfile
                Custom: your own builder image
        │
        ▼
Image pushed to the internal registry
image-registry.openshift-image-registry.svc:5000/<project>/app:latest
        │
        ▼
ImageStreamTag app:latest now points to the new image digest
        │
        ▼
Image trigger (annotation image.openshift.io/triggers on the Deployment)
        │
        ▼
Deployment rolls out the new image
```

## ImageStreams

An **ImageStream** is a named pointer to container images, tracked by **digest** (the image's unique fingerprint), not by a tag that can silently change.

- Workloads reference an **ImageStreamTag** (`app:latest`). When the tag moves to a new digest, triggers fire.
- An ImageStream can point at external images too, and re-import them on a schedule (`oc import-image --scheduled`).
- Gives you history: every digest a tag has pointed to.

```bash
oc get bc,builds,is
oc logs -f bc/app                 # follow the latest build
oc start-build app --follow
oc describe istag app:latest
oc set triggers deploy/app --from-image=app:latest -c app
```

Hands-on: [OCP-007](../stories/OCP-007-own-image-openshift-build.md) (build), [OCP-008](../stories/OCP-008-imagestream-trigger-and-route.md) (rebuild → automatic redeploy).

Newer options for CI-style builds: **OpenShift Pipelines** (Tekton) and **Builds for Red Hat OpenShift** (Shipwright), both installed through OLM.

---

# 📦 Internal Image Registry and Mirroring

## The internal registry

**In plain words:** a built-in image warehouse inside the cluster.

- Run by the `image-registry` operator in `openshift-image-registry`.
- Address inside the cluster: `image-registry.openshift-image-registry.svc:5000`.
- Configured through `configs.imageregistry.operator.openshift.io/cluster`: storage backend (S3, Azure Blob, GCS, Swift or a PVC), replicas, `managementState`.
- On bare metal and other platforms without object storage, it starts as `Removed` and must be given storage first.
- Not reachable from outside by default; set `defaultRoute: true` to publish a Route for `podman push`.

Every project's `builder` and `default` service accounts automatically get pull/push credentials (`<sa>-dockercfg-*` secrets). Pulling from another project needs a role:

```bash
oc policy add-role-to-user system:image-puller system:serviceaccount:team-b:default -n team-a
```

Hands-on: [OCP-009](../stories/OCP-009-copy-images-to-registry.md), [OCP-010](../stories/OCP-010-podman-build-push-internal-registry.md).

## Cluster-wide image settings

| Object | Purpose |
|---|---|
| `image.config.openshift.io/cluster` | Allowed / blocked / insecure registries; extra trusted CAs |
| `pull-secret` in `openshift-config` | Global pull credentials used by every node |
| `ImageDigestMirrorSet` / `ImageTagMirrorSet` | "When anyone pulls from registry A, pull from mirror B instead" |

These end up as files on every node (CRI-O's `registries.conf`, the pull secret), so the Machine Config Operator rolls them out.

## Disconnected (air-gapped) clusters

Many regulated environments have no internet access. Images are copied to a local mirror registry first:

```text
Internet side                              Disconnected side
──────────────                             ─────────────────
ImageSetConfiguration
(release version, operators, extra images)
        │
        ▼
oc-mirror  ─────── archive / direct ─────►  Mirror registry (e.g. Quay, mirror-registry)
                                                    │
                                                    ▼
                                   oc-mirror also generates:
                                   ImageDigestMirrorSet / ImageTagMirrorSet
                                   CatalogSources for OperatorHub
                                                    │
                                                    ▼
                                   Cluster pulls everything from the mirror
```

---

# 🧾 Templates and Helm

Two ways to package a whole application (Deployment + Service + Route + Secret…) and deploy it with parameters:

| | OpenShift Template | Helm chart |
|---|---|---|
| Format | One YAML object with `parameters` | A chart: templates + `values.yaml` |
| Where | Stored in the cluster (`oc get templates -n openshift`) | Chart repositories; the console lists them via `HelmChartRepository` |
| Deploy | `oc new-app --template=mysql-persistent -p MYSQL_USER=app` or `oc process … \| oc apply -f -` | `helm install mydb <chart> -f values.yaml` |
| Upgrade / rollback | Re-process and apply | `helm upgrade`, `helm rollback` |
| Best for | Simple OpenShift-only apps, existing samples | Portable, versioned packages |

```bash
oc get templates -n openshift
oc process --parameters mysql-persistent -n openshift
oc new-app --template=mysql-persistent -p MYSQL_USER=app -p MYSQL_DATABASE=appdb
```

Hands-on: [OCP-012](../stories/OCP-012-mysql-from-openshift-template.md).

Operators are the third option, for software that needs ongoing day-2 care (backups, upgrades, failover), not just installation.

---

# 🖥️ Web Console

**In plain words:** the browser view of the cluster — everything `oc` can do, with dashboards.

```text
Browser → https://console-openshift-console.apps.<cluster>.<domain>
        │
        ▼
Router → console Pods (openshift-console, managed by the console operator)
        │
        ▼
Not logged in? → redirect to oauth-openshift login page → token
        │
        ▼
Console calls the kube-apiserver with YOUR token
(so you see exactly what your RBAC allows — no more)
        │
        ▼
Metrics and alerts pages read from Thanos Querier (monitoring stack)
```

- Two views: **Administrator** (cluster settings, operators, nodes, compute) and **Developer** (topology view of apps, builds, pipelines, Helm).
- Operators can add pages through **ConsolePlugin** objects (for example Virtualization, Data Foundation, GitOps).
- Customisation: `oc edit console.operator.openshift.io cluster` (branding, routes, plugins).

---

# 📌 Key Takeaways — Delivering Applications

- BuildConfigs build images inside the cluster; ImageStreams track images by digest and trigger redeploys.
- The internal registry is managed by an operator and needs storage on platforms without object storage.
- Mirror sets redirect image pulls; `oc-mirror` feeds disconnected clusters.
- Templates and Helm package whole applications; operators manage software that needs ongoing care.
- The web console acts with the user's own token and permissions.

---

# 🎤 Interview Quick Revision — Delivering Applications

### Q1. What is an ImageStream?

A named, digest-tracked pointer to images. When its tag moves, image triggers redeploy the workloads that use it.

---

### Q2. What is Source-to-Image (S2I)?

A build strategy that combines your source code with a language builder image to produce a runnable app image, without writing a Dockerfile.

---

### Q3. How does a Deployment redeploy automatically after a build?

An `image.openshift.io/triggers` annotation (set with `oc set triggers`) links the container to an ImageStreamTag; when the tag gets a new digest, the Deployment's image is updated and it rolls out.

---

### Q4. How do you install OpenShift without internet access?

Mirror the release and operator images to a local registry with `oc-mirror`, then apply the generated ImageDigestMirrorSets and CatalogSources so the cluster pulls from the mirror.

---

### Q5. Template vs Helm?

Templates are OpenShift-specific parameterised object lists stored in the cluster. Helm charts are portable, versioned packages with upgrade and rollback.

---

# 🌐 Service Networking and Service Types

## Why Services?

Pods come and go, and each new Pod gets a new IP. Clients can't chase IPs.

A **Service** gives a set of Pods one stable name and virtual IP, and load-balances across whichever Pods are Ready right now.

```text
Client Pod
    │   http://app.team-a.svc:8080
    ▼
Service "app"  ClusterIP 172.30.45.10   selector: app=web
    │
    │   EndpointSlices: list of Ready Pod IPs matching the selector
    ▼
┌─────────┬─────────┬─────────┐
│ Pod     │ Pod     │ Pod     │   10.128.2.15 · 10.129.0.22 · 10.131.1.8
└─────────┴─────────┴─────────┘
```

The link between a Service and its Pods is only the **label selector**. If the selector doesn't match the Pod labels, the Service has no endpoints and traffic goes nowhere — one of the most common faults ([RCA-003](../rca/RCA-003-route-unreachable-three-faults.md)).

```bash
oc expose deploy/app --port=8080
oc get svc,endpointslices
oc describe svc app             # Endpoints: <none> means the selector matches nothing Ready
```

## Service Types

### ClusterIP (default)

A virtual IP reachable only inside the cluster, from the service network (`172.30.0.0/16` by default). Used for app-to-app traffic.

### NodePort

Opens the same port (30000–32767) on every node, forwarding to the Service. Used for simple external access or non-HTTP traffic when there's no load balancer.

### LoadBalancer

Asks the platform for an external load balancer with its own IP. On clouds the cloud provides it; on bare metal you install the **MetalLB** operator to hand out IPs from a pool. Used for non-HTTP traffic (databases, MQTT, gRPC without TLS routing).

### Headless (`clusterIP: None`)

No virtual IP; DNS returns the Pod IPs directly. Used by StatefulSets so each Pod has its own name (`db-0.db.team-a.svc`).

**OpenShift difference:** for HTTP/HTTPS from outside, you normally don't use NodePort or LoadBalancer at all — you create a **Route**, served by the shared router.

---

# 🔀 OVN-Kubernetes

**In plain words:** the cluster's network. It gives every Pod an IP, carries traffic between nodes, implements Services and firewall rules, and controls traffic leaving the cluster.

Default address ranges (chosen at install, hard to change later):

| Network | Default | Used for |
|---|---|---|
| Cluster (Pod) network | `10.128.0.0/14`, one `/23` per node | Pod IPs |
| Service network | `172.30.0.0/16` | ClusterIP Services |
| Machine network | Your node subnet | Node IPs |

```text
                     OVN-Kubernetes
 ┌──────────────────────────────────────────────────────┐
 │ Control plane: ovnkube-control-plane                 │
 │   assigns each node its Pod subnet                   │
 │                                                      │
 │ Every node: ovnkube-node Pod                         │
 │   local OVN databases (interconnect mode)            │
 │   ovn-controller → programs Open vSwitch (br-int)    │
 │                                                      │
 │  Pod A ──veth──► br-int ──Geneve tunnel──► br-int ──► Pod B
 │                    │             (other node)        │
 │                    ▼                                 │
 │                 br-ex ──► node NIC ──► outside world │
 └──────────────────────────────────────────────────────┘
```

What it does:

- **Pod to Pod:** same node = through the local virtual switch; different nodes = wrapped in a **Geneve** tunnel between the nodes.
- **Services:** load balancing is done by OVN load balancers inside Open vSwitch. **There is no kube-proxy** and no iptables Service rules — don't look for them when troubleshooting.
- **NetworkPolicy:** turned into OVN access-control lists (ACLs).
- **Egress:** EgressIP and EgressFirewall (see NetworkPolicy and Egress Control).
- **Multus** is always present, so a Pod can get extra network interfaces (`NetworkAttachmentDefinition`) for storage, telco or VM networks.

```bash
oc get network.config cluster -o yaml        # CIDRs and network type
oc get pods -n openshift-ovn-kubernetes -o wide
oc get co network
```

Owned by the **Cluster Network Operator** (the `network` ClusterOperator).

---

# 🛣️ Routes and the Ingress Controller

**In plain words:** a Route is a public web address for your Service. The router is the front gate that reads the address on each request and sends it to the right app.

```text
Client → https://app-team-a.apps.ocp.example.com
        │
        ▼
DNS wildcard *.apps → load balancer (or node IPs / VIP on bare metal)
        │
        ▼
Router Pod (HAProxy) in openshift-ingress       ← managed by the Ingress Operator
        │   matches the Host header (or TLS SNI) against every admitted Route
        ▼
TLS handled according to the Route type
        │
        ▼
Traffic sent straight to Ready Pod IPs
(from the Service's EndpointSlices — the ClusterIP is skipped)
        │
        ▼
Application Pod
```

## Route TLS types

| Type | TLS ends at | Router → Pod | Use |
|---|---|---|---|
| Plain HTTP | — | HTTP | Testing only |
| `edge` | Router | HTTP | Most common; the router holds the certificate |
| `passthrough` | The Pod | Encrypted, untouched (routed by SNI) | App owns TLS; end-to-end or mutual TLS |
| `reencrypt` | Router, then a new TLS session | HTTPS | Encrypted inside the cluster too |

Features built into Routes: weighted backends for blue-green and canary (`alternateBackends`), sticky sessions (cookies), per-Route timeouts (`haproxy.router.openshift.io/timeout`), IP allowlists, rate limits.

## The IngressController

The `default` **IngressController** in `openshift-ingress-operator` defines the router: its domain (`apps.<cluster>.<domain>`), replicas, which nodes it runs on (often infra nodes), the default wildcard certificate, and **sharding** — several IngressControllers each serving only Routes with certain labels (e.g. internal vs public).

```bash
oc expose svc/app                                         # simple HTTP Route
oc create route edge app --service=app --hostname=app.apps.ocp.example.com
oc get routes
oc get ingresscontroller -n openshift-ingress-operator
oc get pods -n openshift-ingress -o wide
```

Kubernetes `Ingress` objects work too; the route-controller-manager turns each into a Route ([OCP-016](../stories/OCP-016-ingress-default-controller.md)).

**Classic failure chain** when a Route "doesn't work": wrong host → Route points to the wrong Service → Service selector doesn't match Pod labels → wrong target port → Pods not Ready. Check them in that order ([RCA-003](../rca/RCA-003-route-unreachable-three-faults.md), [OCP-015](../stories/OCP-015-fix-app-unreachable-via-route.md)).

---

# 🌍 DNS Resolution

**In plain words:** the cluster's phone book. Apps call each other by name, and DNS turns the name into the Service IP.

- The **DNS Operator** runs CoreDNS as the `dns-default` DaemonSet in `openshift-dns` (one Pod per node).
- Every Pod's `/etc/resolv.conf` points to `172.30.0.10` (the `dns-default` Service).
- A `node-resolver` DaemonSet adds the internal registry's name to each node's `/etc/hosts`, so CRI-O can pull from it.

Name format:

```text
<service>.<project>.svc.cluster.local      →  Service ClusterIP
<pod>.<service>.<project>.svc.cluster.local →  Pod IP (headless / StatefulSet)
```

```text
Pod asks for mysql.team-a.svc.cluster.local
        │
        ▼
CoreDNS on the node
        │
        ├─► cluster.local name → Service ClusterIP (or Pod IPs if headless)
        │
        └─► anything else      → upstream DNS servers
```

Within the same project, the short name works (`mysql`); across projects use `mysql.team-a`.

Forwarding a company zone to internal DNS servers is done in the operator, not by editing CoreDNS files:

```bash
oc edit dns.operator/default
# spec:
#   servers:
#   - name: corp
#     zones: [corp.example.com]
#     forwardPlugin: { upstreams: [10.0.0.53] }
```

Quick test from inside the cluster:

```bash
oc debug deploy/app -- nslookup mysql.team-a.svc.cluster.local
```

---

# 🧱 NetworkPolicy and Egress Control

By default every Pod can talk to every other Pod in the cluster. **NetworkPolicy** is the in-cluster firewall.

```text
Rule: only Pods labelled app=frontend may reach Pods labelled app=db on port 3306

frontend Pod ──── allowed ────► db Pod :3306
other Pod    ──── dropped ────► db Pod
```

Key behaviour:

- As soon as **any** policy selects a Pod, everything not explicitly allowed to it is denied (for that direction).
- Policies are additive: allowed traffic is the union of all matching policies.
- A common baseline: a **default-deny** policy per project, then allow same-project traffic, the router (`policy-group.network.openshift.io/ingress` namespace label) and monitoring.

```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-from-router
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          policy-group.network.openshift.io/ingress: ""
```

**OpenShift extras (OVN-Kubernetes):**

| Object | Scope | Purpose |
|---|---|---|
| `AdminNetworkPolicy` | Cluster | Rules set by cluster admins that project admins can't override |
| `BaselineAdminNetworkPolicy` | Cluster | Default rules that projects *can* override |
| `EgressFirewall` | Project | Which external IPs / DNS names a project may connect to |
| `EgressIP` | Project | A fixed source IP for a project's outbound traffic (so company firewalls can allow it) |

```bash
oc get networkpolicy -n team-a
oc get adminnetworkpolicy
oc get egressfirewall -n team-a
oc get egressip
```

---

# 📌 Key Takeaways — Networking

- Services give Pods a stable name and IP; the label selector is the only link.
- ClusterIP for inside, Routes for HTTP(S) from outside, LoadBalancer/NodePort for other protocols.
- OVN-Kubernetes does Pod networking, Services and NetworkPolicy — no kube-proxy.
- Routes are served by the HAProxy router, managed by the Ingress Operator; TLS can be edge, passthrough or re-encrypt.
- CoreDNS (`dns-default`) resolves `<svc>.<project>.svc.cluster.local`.
- NetworkPolicy denies by default once a Pod is selected; Admin policies and egress controls add cluster-level control.

---

# 🎤 Interview Quick Revision — Networking

### Q1. Why do we need Services?

Pod IPs change. A Service gives a stable virtual IP and DNS name and balances across Ready Pods.

---

### Q2. Which component load-balances Services in OpenShift?

OVN-Kubernetes, through OVN load balancers in Open vSwitch. There's no kube-proxy.

---

### Q3. Route vs Ingress?

A Route is OpenShift's native object with edge/passthrough/re-encrypt TLS and weighted backends. An Ingress is the upstream object; OpenShift converts it into a Route.

---

### Q4. Edge vs passthrough vs re-encrypt?

Edge: TLS ends at the router. Passthrough: the Pod terminates TLS. Re-encrypt: the router terminates TLS and opens a new TLS connection to the Pod.

---

### Q5. A Route returns "Application is not available". Where do you look?

Route host and target Service, then the Service's endpoints (selector vs labels, target port), then whether the Pods are Ready.

---

### Q6. What DNS server do Pods use?

CoreDNS from the DNS Operator (`dns-default` in `openshift-dns`), at `172.30.0.10` by default.

---

### Q7. How do you give a project a fixed outbound IP?

An `EgressIP` object assigned to the project, with egress-capable nodes labelled.

---

### Q8. What changes once a NetworkPolicy selects a Pod?

All traffic to it in that direction that isn't explicitly allowed is denied.

---

# ⚙️ ConfigMap Workflow

**In plain words:** keep settings outside the image, so the same image runs in dev, test and prod with different configuration.

A **ConfigMap** stores non-secret key-value data or whole files.

```text
ConfigMap "app-config"
   LOG_LEVEL=info
   app.properties (file)
        │
        ├──► as environment variables  (read once, at container start)
        │
        └──► as files in a volume      (/etc/app/app.properties — updated in place
                                         after a short delay, except subPath mounts)
        ▼
      Pod
```

```bash
oc create configmap app-config --from-literal=LOG_LEVEL=info --from-file=app.properties
oc set env deploy/app --from=configmap/app-config
oc set volume deploy/app --add --type=configmap --configmap-name=app-config --mount-path=/etc/app
oc extract configmap/app-config --to=-          # print the contents
```

Things to know:

- Changing a ConfigMap does **not** restart Pods. Environment variables stay old until the Pod restarts (`oc rollout restart deploy/app`); mounted files update after a delay.
- A Pod that references a missing ConfigMap or key won't start: `CreateContainerConfigError` ([RB-S42](../runbooks/RB-S42-createcontainerconfigerror-missing-configmap-key.md)).
- Size limit is 1 MiB per ConfigMap.

**OpenShift extras:** the **service CA** can inject the cluster's CA bundle into any ConfigMap annotated `service.beta.openshift.io/inject-cabundle: "true"`, and the cluster proxy can inject trusted CAs with the label `config.openshift.io/inject-trusted-cabundle: "true"`.

Hands-on: [OCP-021](../stories/OCP-021-message-survives-restarts.md).

---

# 🔐 Secret Workflow

A **Secret** is like a ConfigMap for sensitive data: passwords, tokens, keys, certificates.

```text
oc create secret generic db-cred --from-literal=password=...
        │
        ▼
kube-apiserver → etcd   (base64-encoded; encrypted ONLY if etcd encryption is on)
        │
        ▼
RBAC controls who can read it (view role cannot; edit and admin can)
        │
        ▼
kubelet fetches it only for Pods on its node that use it
        │
        ├──► env var  (MYSQL_PASSWORD)
        └──► tmpfs volume (in memory, never written to the node's disk)
```

Common types:

| Type | Use |
|---|---|
| `Opaque` (generic) | Passwords, API keys |
| `kubernetes.io/tls` | Certificate + private key (Routes, apps) |
| `kubernetes.io/dockerconfigjson` | Registry pull credentials |
| `kubernetes.io/basic-auth`, `ssh-auth` | Git credentials for builds |

```bash
oc create secret generic db-cred --from-literal=user=app --from-literal=password=change-me
oc create secret tls app-tls --cert=tls.crt --key=tls.key
oc create secret docker-registry quay-pull --docker-server=quay.io --docker-username=... --docker-password=...
oc secrets link default quay-pull --for=pull
oc set env deploy/db --from=secret/db-cred --prefix=MYSQL_
```

**Important:** base64 is encoding, not encryption. Anyone who can read the Secret object, or the etcd data, can read the value.

**OpenShift extras:**

- **etcd encryption** for Secrets, ConfigMaps, Routes and OAuth tokens: `oc edit apiserver cluster` → `spec.encryption.type: aescbc` (or `aesgcm`). The operators then re-encrypt existing data.
- Every service account gets a **registry pull secret** (`<sa>-dockercfg-*`) automatically.
- The **service CA** creates TLS Secrets for Services automatically (see Certificates and the Service CA).
- For real secret management, add-ons such as the External Secrets Operator or a Vault integration pull secrets from an external vault.

Hands-on: [OCP-011](../stories/OCP-011-mysql-database-from-docker-image.md).

---

# 💾 Persistent Storage Workflow

Container filesystems are temporary: when a Pod is replaced, anything written inside it is gone ([RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md)). Data that must survive goes on a **persistent volume**.

```text
Pod ──► PVC ──► StorageClass ──► CSI driver ──► real storage
        "I need     "how to make      (controller + node Pods)   cloud disk / vSphere /
         10Gi RWO"   such a volume"                               NFS / Ceph / LVM
```

## Persistent Volume (PV)

A piece of real storage registered in the cluster, with a size, access mode and reclaim policy. Cluster-scoped (not in a project). Created by an admin (static) or automatically (dynamic).

## Persistent Volume Claim (PVC)

A request for storage from inside a project: "10Gi, ReadWriteOnce, StorageClass fast". The cluster binds it to a matching PV; the Pod mounts the PVC, never the PV directly.

## Dynamic Provisioning

```text
PVC created (storageClassName: fast, or the default class)
        │
        ▼
CSI provisioner for that StorageClass creates a real volume on the backend
        │
        ▼
PV created automatically and bound to the PVC
        │
        ▼
Pod scheduled → CSI node plugin attaches and mounts the volume on that node
```

With `volumeBindingMode: WaitForFirstConsumer`, the PVC stays **Pending until a Pod uses it** — so the volume is created in the zone where the Pod lands. Pending here is normal.

## StorageClasses

A StorageClass describes a *kind* of storage: provisioner (CSI driver), parameters (disk type, replication), reclaim policy (`Delete` or `Retain`), expansion allowed or not. One is marked as **default**.

```bash
oc get sc
oc get pvc,pv
oc get csidrivers
oc set volume deploy/app --add --name=data --type=pvc --claim-name=app-data --claim-size=1Gi --mount-path=/var/lib/app
```

## Access Modes

| Mode | Meaning | Typical backend |
|---|---|---|
| RWO — ReadWriteOnce | Read-write from one node | Block disks (EBS, vSphere, Ceph RBD) |
| RWOP — ReadWriteOncePod | Read-write from one Pod only | Strict single-writer databases |
| RWX — ReadWriteMany | Read-write from many nodes | NFS, CephFS |
| ROX — ReadOnlyMany | Read-only from many nodes | Shared content |

## Volume Mount Workflow

```text
Pod with a PVC scheduled to node-2
        │
        ▼
CSI controller: attach the volume to node-2 (VolumeAttachment)
        │
        ▼
kubelet + CSI node plugin: format if new, mount on node-2
        │
        ▼
SELinux relabel + fsGroup ownership applied
        │
        ▼
Bind-mounted into the container at mountPath
        │
        ▼
Pod deleted → new Pod on node-3 → volume detached from node-2, attached to node-3,
             data still there
```

## OpenShift storage specifics

- The **cluster-storage-operator** installs the right CSI driver for the platform (AWS, Azure, GCP, vSphere, OpenStack…) and a default StorageClass automatically.
- On bare metal there is no default: add **OpenShift Data Foundation** (Ceph: block, file and object), **LVM Storage** (local disks, common on SNO), or a vendor CSI driver. NFS static PVs are fine for labs ([OCP-019](../stories/OCP-019-static-pv-pvc-nfs.md)).
- Under `restricted-v2`, the container runs as a random UID but gets the project's **fsGroup**, so the volume is made group-writable. Images that insist on a specific owner for their data directory fail here.
- Snapshots and clones: `VolumeSnapshot` / `VolumeSnapshotClass` through the CSI snapshot controller.

Hands-on: [OCP-020](../stories/OCP-020-dynamic-storage-etherpad.md), [OCP-022](../stories/OCP-022-statefulset-3-replicas.md).

---

# 📌 Key Takeaways — Configuration and Storage

- ConfigMaps hold settings, Secrets hold sensitive values; both can be env vars or files.
- Changing them doesn't restart Pods; env vars need a restart to pick up new values.
- Secrets are base64, not encrypted, unless etcd encryption is enabled.
- Pods use PVCs; PVCs bind to PVs; StorageClasses create PVs on demand.
- `WaitForFirstConsumer` PVCs stay Pending until a Pod uses them — that's expected.
- OpenShift installs CSI drivers through an operator; bare metal needs ODF, LVM Storage or another driver.

---

# 🎤 Interview Quick Revision — Configuration and Storage

### Q1. ConfigMap vs Secret?

Same mechanism; Secrets are for sensitive data, are kept in tmpfs on nodes, are hidden from the `view` role, and can be encrypted at rest.

---

### Q2. Are Secrets encrypted by default?

No — only base64-encoded. Enable etcd encryption in the `apiserver` config.

---

### Q3. You changed a ConfigMap but the app still uses old values. Why?

It reads them as environment variables, which are set only at container start. Restart the rollout.

---

### Q4. PV vs PVC?

A PV is the actual storage resource (cluster-scoped). A PVC is a project's request for storage, bound to a PV.

---

### Q5. Why is my new PVC Pending?

With `WaitForFirstConsumer`, it waits for a Pod. Otherwise: no default StorageClass, no matching PV, or the provisioner is failing (check events).

---

### Q6. What happens to data when a Pod using a PVC is recreated?

It survives: the new Pod mounts the same PVC, even on another node (for RWO, after the volume detaches from the old node).

---

### Q7. Why does a database image fail with "permission denied" on its volume in OpenShift?

It runs as a random UID; the image expects a fixed owner. Use an image that supports arbitrary UIDs (group 0 writable), or a dedicated SCC for that service account.

---

# 🔑 Authentication Flow (`oc login`)

**Authentication** answers "who are you?". In OpenShift it's built in: no extra software needed.

```text
oc login https://api.ocp.example.com:6443 -u dev1
            │
            ▼
   oc discovers the OAuth server address
   (/.well-known/oauth-authorization-server)
            │
            ▼
   oauth-openshift (openshift-authentication)
            │
            ▼
   Identity provider checks the credentials
   (HTPasswd secret / LDAP bind / OpenID Connect redirect)
            │
            ▼
   Identity object + User object created or matched
   (mappingMethod: claim / lookup / add)
            │
            ▼
   OAuthAccessToken issued (starts with sha256~)
   stored by oauth-apiserver; oc saves it in ~/.kube/config
            │
            ▼
   Every later request: kube-apiserver asks oauth-apiserver "is this token valid?"
            │
            ▼
   User + Groups → RBAC decides what they can do
```

Configuration lives in one object:

```bash
oc get oauth cluster -o yaml        # identity providers
oc get users,identities,groups
oc whoami ; oc whoami --show-server ; oc whoami -t
```

Who else authenticates, and how:

| Who | Credential |
|---|---|
| People | OAuth tokens via an identity provider |
| Applications and operators | **Service account** tokens (short-lived, mounted into Pods automatically) |
| Nodes and control plane components | Client certificates |
| Break-glass admin | The installer's `system:admin` kubeconfig (certificate-based, works even if OAuth is broken) |

Points worth knowing:

- `kubeadmin` is a temporary admin created at install. Once a real identity provider and a `cluster-admin` binding exist, remove it: `oc delete secret kubeadmin -n kube-system`.
- After changing the `oauth` config, the `authentication` operator rolls new oauth-openshift Pods — wait for `oc get co authentication` to settle.
- Groups can be synced from LDAP/Active Directory with `oc adm groups sync`.

---

# 🛂 RBAC Authorization Flow

**Authorization** answers "what may you do?". OpenShift uses Kubernetes **Role-Based Access Control (RBAC)**.

```text
Request: user dev1 wants to "delete" "pods" in project team-a
        │
        ▼
Find every RoleBinding in team-a and every ClusterRoleBinding
that names dev1 or one of dev1's groups
        │
        ▼
Collect the rules of the Roles / ClusterRoles they point to
        │
        ▼
Any rule allows verb=delete, resource=pods?  ──► yes → allowed
                                             └─► no  → 403 Forbidden
```

The four building blocks:

| Object | Scope | Says |
|---|---|---|
| **Role** | One project | A set of allowed actions (verbs on resources) |
| **ClusterRole** | Cluster-wide definition | Same, reusable anywhere |
| **RoleBinding** | One project | Gives a Role or ClusterRole to users / groups / service accounts *in that project* |
| **ClusterRoleBinding** | Whole cluster | Gives a ClusterRole everywhere |

RBAC is **allow-only**: there are no deny rules. Anything not allowed is forbidden.

Built-in roles you'll use every day:

| Role | Can |
|---|---|
| `cluster-admin` | Everything, everywhere |
| `cluster-reader` | Read almost everything cluster-wide |
| `admin` | Full control of one project, including its RoleBindings |
| `edit` | Create/change most objects in a project, read Secrets; not roles or quotas |
| `view` | Read most objects in a project, **not** Secrets |
| `basic-user` | See own user and projects |
| `self-provisioner` | Create new projects |

```bash
oc adm policy add-role-to-user edit dev1 -n team-a
oc adm policy add-role-to-group view qa-team -n team-a
oc adm policy add-cluster-role-to-user cluster-reader auditor1
oc auth can-i delete pods -n team-a --as=dev1
oc adm policy who-can delete pods -n team-a
oc get rolebindings -n team-a
```

Service accounts are authorized the same way: `system:serviceaccount:<project>:<name>`.

Hands-on with plain Kubernetes RBAC: kubernetes-labs lab 10.

---

# 🏢 Projects and Namespace Isolation

A **namespace** is a named area inside the cluster with its own objects, permissions and quotas. A **Project** is OpenShift's namespace with extra metadata and a controlled way of creating it.

```text
oc new-project team-a
        │
        ▼
ProjectRequest → openshift-apiserver
        │
        ▼
Project request template applied (default or your own)
        │
        ├─► Namespace with annotations
        │     openshift.io/requester: dev1
        │     openshift.io/sa.scc.uid-range: 1000680000/10000
        │     openshift.io/sa.scc.mcs: s0:c26,c15
        │
        ├─► RoleBinding: requester becomes "admin" of the project
        └─► Service accounts: default, builder, deployer
              (plus anything the template adds: quota, LimitRange, NetworkPolicy)
```

Why those annotations matter: every project gets its **own range of user IDs and its own SELinux category**. Containers from different projects run as different users with different SELinux labels, so even if one escaped its container, it couldn't read another project's files.

What a project isolates — and what it doesn't by itself:

| Isolated per project | Not isolated by default |
|---|---|
| Object names, RBAC, quotas, UID range, SELinux category | Network: Pods can reach other projects until NetworkPolicies are added |
| | Nodes: projects share nodes unless a project node selector is set |

Platform teams usually customise the project template so every new project starts with a quota, LimitRange and default-deny NetworkPolicy:

```bash
oc adm create-bootstrap-project-template -o yaml > template.yaml
oc create -f template.yaml -n openshift-config
oc edit project.config.openshift.io/cluster        # spec.projectRequestTemplate.name
```

Who may create projects is controlled by the `self-provisioner` ClusterRoleBinding. Projects starting with `openshift-` and `kube-` are reserved for the platform.

---

# 🛡️ Security Context Constraints (SCC)

**In plain words:** SCCs are the building rules for Pods — what a container may do on the node (run as root, use the host network, mount host folders, gain extra privileges).

```text
Pod create request (service account: default)
        │
        ▼
SCC admission collects every SCC the user OR the Pod's service account may "use"
        │
        ▼
Sorted by priority, then most restrictive first
        │
        ▼
First SCC that can satisfy the Pod's securityContext wins
        │
        ├─► Mutates the Pod: runAsUser from the project UID range,
        │   fsGroup, SELinux MCS label, capabilities, seccomp profile
        │
        ▼
Pod annotated  openshift.io/scc: <name>
        │
        ▼
No SCC fits → Pod rejected (FailedCreate on the ReplicaSet)
```

Built-in SCCs you'll meet:

| SCC | Allows | Typical use |
|---|---|---|
| `restricted-v2` (default) | Random UID from the project range; no privilege escalation; must drop ALL capabilities (only NET_BIND_SERVICE may be added back); seccomp `RuntimeDefault` | Almost every app |
| `nonroot-v2` | Any non-zero UID, including one fixed in the image | Images that need a specific non-root UID |
| `anyuid` | Any UID, including root | Legacy images that must run as root (use sparingly) |
| `hostnetwork-v2` | Host network and ports | Network agents |
| `hostmount-anyuid` | Host path mounts, any UID | Specific system workloads |
| `privileged` | Everything | Platform components, node agents |

```bash
oc get scc
oc get pod <pod> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
oc create sa legacy-app -n team-a
oc adm policy add-scc-to-user anyuid -z legacy-app -n team-a
oc set serviceaccount deploy/legacy-app legacy-app
oc adm policy scc-subject-review -f pod.yaml        # which SCC would admit this Pod?
```

Good practice:

- Fix the image first: make writable paths owned by group 0 and group-writable, listen on ports above 1024, don't assume a username.
- If an extra SCC is really needed, give it to a **dedicated service account**, never `default`.
- Never edit the built-in SCCs; create your own if needed.

**Pod Security Admission (PSA)**, the upstream mechanism, also runs. OpenShift's label syncer sets `pod-security.kubernetes.io/*` labels on each namespace to match the SCCs its service accounts can use, so the two agree. Warnings like `would violate PodSecurity "restricted:latest"` come from PSA.

Hands-on: [OCP-004](../stories/OCP-004-third-party-image-etherpad.md), [OCP-006](../stories/OCP-006-exec-without-login.md), [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md).

---

# 📜 Certificates and the Service CA

OpenShift runs on TLS everywhere: between users and the API, between components, between nodes and the control plane. The platform creates and **rotates** almost all of these certificates by itself.

| Certificate | Managed by | What you do |
|---|---|---|
| Internal control plane / etcd / kubelet certs | Operators and the kube-controller-manager signer | Nothing — rotated automatically; approve CSRs only for manually added nodes |
| API server certificate (`api.<cluster>`) | Self-signed by default | Replace with a company-signed cert via `oc edit apiserver cluster` (`servingCerts.namedCertificates`) |
| Default wildcard `*.apps` certificate | Ingress Operator, self-signed by default | Replace via `spec.defaultCertificate` on the IngressController |
| Service certificates for your apps | **Service CA operator** | Add one annotation to a Service |

## The Service CA

**In plain words:** free, automatic TLS certificates for app-to-app traffic inside the cluster.

```text
Service "app" annotated
service.beta.openshift.io/serving-cert-secret-name: app-tls
        │
        ▼
service-ca operator creates Secret "app-tls" with a certificate for
app.team-a.svc  (signed by the cluster's service CA, renewed automatically)
        │
        ▼
Pod mounts app-tls and serves HTTPS
        │
        ▼
Clients trust it by mounting a ConfigMap annotated
service.beta.openshift.io/inject-cabundle: "true"
```

This is how re-encrypt Routes and many platform components get their internal certificates.

---

# 📌 Key Takeaways — Security

- Authentication is built in: OAuth server + identity providers for people, service accounts for apps, certificates for components.
- RBAC is allow-only: Roles/ClusterRoles define actions, bindings grant them.
- `admin`, `edit` and `view` are the everyday project roles; `view` can't read Secrets.
- Each project gets its own UID range and SELinux category.
- SCCs control what Pods may do on the node; `restricted-v2` is the default.
- Platform certificates rotate automatically; the Service CA issues app certificates on request.

---

# 🎤 Interview Quick Revision — Security

### Q1. Explain the `oc login` flow.

`oc` finds the OAuth server; the identity provider checks the credentials; User and Identity are created or matched; a `sha256~` token is issued. On every request the kube-apiserver validates the token through oauth-apiserver, then RBAC authorizes.

---

### Q2. How do you check whether a user can do something?

`oc auth can-i <verb> <resource> -n <project> --as=<user>`, or `oc adm policy who-can <verb> <resource>`.

---

### Q3. edit vs admin?

`edit` can change workloads and read Secrets; `admin` can also manage the project's RoleBindings and some project-level settings.

---

### Q4. Why does a container run as UID 1000680000?

`restricted-v2` assigned it from the project's `openshift.io/sa.scc.uid-range` annotation.

---

### Q5. How does OpenShift choose an SCC for a Pod?

It collects the SCCs the user and service account may use, sorts by priority and restrictiveness, and picks the first that admits the Pod. The result is in the `openshift.io/scc` annotation.

---

### Q6. How do you let a legacy image run as root?

Create a dedicated service account, grant it `anyuid` with `oc adm policy add-scc-to-user anyuid -z <sa>`, and set it on the Deployment. Better: fix the image.

---

### Q7. Why remove kubeadmin?

It's a shared, static credential meant only for the first login. Once a real identity provider and named admins exist, it's an unnecessary risk.

---

### Q8. How does an app get a TLS certificate for its Service?

Annotate the Service with `service.beta.openshift.io/serving-cert-secret-name`; the service CA operator creates and renews the Secret.

---

# 🔧 MachineConfig and Node Update Flow

**In plain words:** you never log in to a node to change it. You describe the change once as a MachineConfig, and the cluster applies it to every node in the group, one node at a time, safely.

Anything about the node OS goes through the **Machine Config Operator (MCO)**: files, systemd units, kernel arguments, time sync (chrony), SSH keys, registry config, kubelet and CRI-O settings.

```text
Admin creates a MachineConfig (or KubeletConfig / ContainerRuntimeConfig)
  labelled machineconfiguration.openshift.io/role: worker
        │
        ▼
machine-config-controller merges all MachineConfigs for the pool
into one "rendered-worker-<hash>" config
        │
        ▼
MachineConfigPool "worker" gets the new rendered config as its target
        │
        ▼
Node by node (maxUnavailable, default 1):
   cordon → drain Pods → MCD writes files / updates the OS → reboot if needed → uncordon
        │
        ▼
Node's currentConfig = desiredConfig → next node
        │
        ▼
Pool shows UPDATED=True, UPDATING=False
```

| Component | Where | Job |
|---|---|---|
| machine-config-operator | `openshift-machine-config-operator` | Runs and upgrades the other MCO parts |
| machine-config-controller | Control plane | Renders configs, coordinates pool updates |
| machine-config-daemon (MCD) | Every node | Applies config on its node, reboots |
| machine-config-server (MCS) | Control plane nodes, port 22623 | Serves Ignition to new nodes on first boot |

```bash
oc get mcp                          # pools: master, worker, custom (e.g. infra)
oc get mc                           # all MachineConfigs, including rendered-*
oc describe mcp worker
oc logs -n openshift-machine-config-operator <machine-config-daemon-pod> -c machine-config-daemon
```

What matters in production:

- A pool stuck **UPDATING** usually means a node can't drain: a **PodDisruptionBudget** allows zero disruptions, or a Pod has no controller.
- **DEGRADED=True** means the MCD found files on the node that differ from what it expects (someone edited a managed file by hand), or it couldn't apply the change. Its logs name the file.
- **Pausing** a pool (`spec.paused: true`) batches several changes into one reboot or holds them for a maintenance window. Don't leave it paused for long — certificate updates also travel through MachineConfigs.
- Custom pools (for example `infra`) inherit everything from `worker` plus their own configs.

---

# 🎛️ Node Tuning

The **Node Tuning Operator** (`node-tuning` ClusterOperator) runs the **TuneD** daemon on every node and applies kernel tuning profiles (sysctls, CPU governor, hugepages) through `Tuned` objects selected by node labels — without reboots for most settings.

For latency-sensitive workloads (telco, trading, real-time), a **PerformanceProfile** adds CPU isolation (reserved vs isolated CPUs), hugepages, a real-time kernel option and NUMA alignment — this does go through the MCO and reboots nodes.

```bash
oc get tuned -n openshift-cluster-node-tuning-operator
oc get profile -n openshift-cluster-node-tuning-operator      # which profile each node uses
oc get performanceprofile
```

---

# 🖥️ Machine API and Node Lifecycle

On installer-provisioned clusters (IPI), OpenShift manages the **machines** (VMs or bare-metal hosts), not only the Kubernetes nodes on them.

```text
MachineSet (replicas: 3, instance type, zone)      ← like a ReplicaSet, but for VMs
        │
        ▼
Machine objects (one per VM)
        │   machine-api controllers call the cloud / vSphere / bare-metal API
        ▼
VM created → boots RHCOS → fetches Ignition from the machine-config-server
        │
        ▼
kubelet starts → requests client and serving certificates (CSRs)
        │       approved automatically for Machine API machines
        ▼
Node joins the cluster and its MachineConfigPool
```

```bash
oc get machinesets,machines -n openshift-machine-api
oc scale machineset <name> --replicas=4 -n openshift-machine-api
oc get csr
oc adm certificate approve <csr>
```

Related objects:

- **MachineHealthCheck:** replaces a Machine automatically when its node stays `NotReady` beyond a timeout.
- **ClusterAutoscaler + MachineAutoscaler:** add Machines when Pods can't be scheduled, remove them when nodes are underused.
- **Control plane machine set:** manages the 3 control plane machines (replace one at a time).
- **User-provisioned clusters (UPI):** no Machine API. You create the VMs, boot them with Ignition and approve their CSRs yourself — two rounds per node (client, then serving).

Safe node maintenance (any cluster):

```bash
oc adm cordon <node>                                   # no new Pods
oc adm drain <node> --ignore-daemonsets --delete-emptydir-data
# … maintenance …
oc adm uncordon <node>
```

---

# ⬆️ Cluster Upgrade Flow

**In plain words:** one command upgrades everything — the Kubernetes version, every platform component and the operating system of every node — in a tested order, without stopping applications.

```text
oc adm upgrade --to=4.18.z         (or pick an update in the console)
        │
        ▼
CVO checks the update graph for the chosen channel
(stable-4.18 / fast-4.18 / eus-4.18 / candidate-4.18)
        │
        ▼
Release image downloaded and its signature verified
        │
        ▼
CVO applies new manifests in a fixed order:
   etcd → kube-apiserver → controller-manager / scheduler →
   openshift-apiserver / auth → network → dns / ingress / registry → … → machine-config
        │
        ▼
Each ClusterOperator rolls its Pods: Progressing=True → back to False
        │
        ▼
MCO updates RHCOS on every node:
   control plane pool first, then workers (cordon, drain, reboot, one at a time)
        │
        ▼
clusterversion shows the new version; every ClusterOperator Available
```

Before every upgrade:

- All ClusterOperators healthy, all MachineConfigPools `UPDATED=True`.
- Read `oc adm upgrade` for conditional-update risks, and Red Hat's notes for the target version.
- Take an etcd backup.
- Check PodDisruptionBudgets that would block drains.
- Before a minor version jump, check for removed APIs still in use: `oc get apirequestcounts`. An admin acknowledgement may be required.

Version rules: minor versions go one at a time (4.16 → 4.17 → 4.18), except **EUS-to-EUS** upgrades (4.16 → 4.18), where worker pools can be paused so workers reboot only once.

```bash
oc get clusterversion
oc adm upgrade channel stable-4.18
oc adm upgrade
oc get co ; oc get mcp
```

---

# 🚀 Installation and Bootstrap Flow

Installation methods:

| Method | Who builds the infrastructure | Notes |
|---|---|---|
| IPI (installer-provisioned) | The installer creates VMs, network, load balancers | Easiest; Machine API fully working |
| UPI (user-provisioned) | You build VMs, DNS, load balancers | Most control, for restricted environments |
| Agent-based installer | You boot the nodes from a generated ISO | Disconnected and bare-metal friendly |
| Assisted Installer | A web service generates a discovery ISO | Guided, with pre-flight checks |

What happens during an install:

```text
install-config.yaml           (cluster name, domain, platform, networks, pull secret, SSH key)
        │   openshift-install create manifests / ignition-configs
        ▼
Ignition files: bootstrap.ign, master.ign, worker.ign
        │
        ▼
Bootstrap node boots: runs a temporary control plane and temporary etcd
        │
        ▼
Control plane nodes boot: fetch Ignition from the bootstrap machine-config-server
        │
        ▼
Real etcd forms on the 3 control plane nodes; the control plane moves over
        │
        ▼
Bootstrap complete → bootstrap node removed
        │
        ▼
CVO installs every ClusterOperator; workers join (CSRs approved)
        │
        ▼
openshift-install wait-for install-complete → console URL + kubeadmin password
```

What breaks most installs:

- DNS records for `api`, `api-int` and `*.apps` missing or wrong
- Load balancers not passing 6443 (API), 22623 (machine-config-server) and 80/443 (router)
- Time not in sync between machines
- In disconnected installs: mirror registry or mirror configuration incomplete
- Ignition certificates expire after 24 hours — regenerate if the install is delayed

```bash
openshift-install wait-for bootstrap-complete --log-level=debug
openshift-install gather bootstrap      # logs if bootstrap fails
```

---

# 📊 Monitoring, Logging, Telemetry

## Platform monitoring (installed by default)

```text
node-exporter · kube-state-metrics · every component's /metrics
        │
        ▼
Prometheus (2 replicas, openshift-monitoring) ──► Alertmanager → email / Slack / PagerDuty
        │
        ▼
Thanos Querier ──► web console Observe → Metrics, Dashboards, Alerts
```

- **User workload monitoring** is optional: set `enableUserWorkload: true` in the `cluster-monitoring-config` ConfigMap. Teams then create `ServiceMonitor` / `PodMonitor` and `PrometheusRule` objects in their own projects, and a separate Prometheus in `openshift-user-workload-monitoring` scrapes them.
- Configure the stack only through `cluster-monitoring-config` (retention, storage, node placement); edits to the Prometheus objects are reverted by the operator.

## Logging (add-on)

Not installed by default. Through OLM: the **Red Hat OpenShift Logging** operator (Vector collectors on every node) plus the **Loki** operator for storage, and `ClusterLogForwarder` to send logs to Splunk, Elasticsearch, Kafka or syslog.

## Telemetry and Insights

- **Telemetry** sends a small set of anonymised health metrics to Red Hat, used for update recommendations and support.
- The **Insights Operator** (`openshift-insights`) periodically uploads anonymised configuration data; Red Hat's Insights Advisor checks it against known issues and shows recommendations in the console.
- Both can be disabled (for example in disconnected or highly regulated clusters).

```bash
oc get pods -n openshift-monitoring
oc adm top nodes ; oc adm top pods -n <project>
oc get prometheusrules -A
oc get co insights
```

---

# 💾 Backup and Disaster Recovery

Two separate things need backing up:

| What | Tool | Protects against |
|---|---|---|
| Cluster state (etcd) | `cluster-backup.sh` on a control plane node | Losing the control plane, a bad change to cluster objects |
| Application objects + volume data | **OADP** (OpenShift API for Data Protection, based on Velero) | Deleted projects, corrupted data, moving apps between clusters |

```bash
# etcd backup
oc debug node/<control-plane-node>
chroot /host
/usr/local/bin/cluster-backup.sh /home/core/assets/backup
# produces snapshot_<date>.db and static_kuberesources_<date>.tar.gz
```

- Copy the backup off the cluster. A backup stored only on the node it protects is not a backup.
- Restore (`cluster-restore.sh`) is a documented disaster-recovery procedure for when quorum is lost or the cluster must go back in time — not a routine task.
- Losing **one** control plane node is not a restore case: replace the member, and etcd re-syncs from the other two.
- OADP: install the operator, configure a `DataProtectionApplication` with object storage, then create `Backup` / `Schedule` / `Restore` objects per project.

---

# 🧰 The Add-on Ecosystem

Installed through OLM from OperatorHub, all following the same operator pattern:

| Add-on | What it adds |
|---|---|
| OpenShift GitOps (Argo CD) | Cluster and app configuration from Git |
| OpenShift Pipelines (Tekton) | CI/CD pipelines as Kubernetes objects |
| OpenShift Data Foundation | Ceph-based block, file and object storage |
| OpenShift Logging + Loki | Log collection, storage, forwarding |
| OpenShift Virtualization (KubeVirt) | Run virtual machines next to containers |
| OpenShift AI | Notebooks, model training and serving |
| NVIDIA GPU Operator + Node Feature Discovery | GPU drivers, device plugin and monitoring on GPU nodes |
| Advanced Cluster Management (ACM) | Manage, govern and deploy across many clusters |
| Advanced Cluster Security (ACS) | Image scanning, runtime threat detection, compliance |
| OADP | Backup and restore of applications |
| Service Mesh | mTLS, traffic management and tracing between services |

---

# 📌 Key Takeaways — Running the Platform

- Node OS changes go through MachineConfigs; pools roll them out node by node.
- Stuck pools are usually blocked drains (PDBs); degraded pools are usually manual node edits.
- On IPI clusters, MachineSets manage VMs like ReplicaSets manage Pods.
- Upgrades are driven by the CVO: platform operators first, then node OS, one node at a time.
- Install = bootstrap node → real control plane → operators → workers.
- Platform monitoring is built in; logging, GitOps, storage and more are OLM add-ons.
- Back up etcd for the cluster and use OADP for applications — and keep backups off-cluster.

---

# 🎤 Interview Quick Revision — Running the Platform

### Q1. How do you change a kernel argument on all workers?

A MachineConfig with `kernelArguments`, labelled for the worker pool. The MCO drains and reboots workers one at a time.

---

### Q2. A MachineConfigPool is stuck updating. What do you check?

`oc describe mcp`, which node is not done, the MCD logs on that node, and whether the drain is blocked by a PodDisruptionBudget or an unmanaged Pod.

---

### Q3. What happens during an OpenShift upgrade?

The CVO verifies and applies the new release image; each ClusterOperator rolls out its new version in order; then the MCO updates RHCOS on control plane nodes and then workers, draining and rebooting one at a time.

---

### Q4. A new worker never becomes Ready on a UPI cluster. Why?

Pending CSRs (approve client, then serving), or it couldn't reach the machine-config-server on 22623 for its Ignition.

---

### Q5. What is the bootstrap node?

A temporary machine that runs a temporary control plane during install, serves Ignition to the control plane nodes, and is removed once their etcd and API servers are running.

---

### Q6. How do you back up an OpenShift cluster?

`cluster-backup.sh` for etcd (stored off-cluster), plus OADP for application objects and volume data.

---

### Q7. What replaces a failed worker automatically?

A MachineHealthCheck on its MachineSet deletes the unhealthy Machine, and the MachineSet creates a new one.

---

### Q8. How do teams monitor their own apps?

Enable user workload monitoring, then create ServiceMonitors and PrometheusRules in their projects.

---

# 🚨 Production Troubleshooting Workflow

A repeatable method matters more than memorised commands. In OpenShift, the first decision is **which layer** the problem lives in.

```text
Issue reported
       │
       ▼
Observe symptoms: who is affected, since when, what changed?
       │
       ▼
Is the PLATFORM healthy?
   oc get co · oc get nodes · oc get mcp · oc get clusterversion
       │
   ┌───┴──────────┐
   No             Yes
   │              │
   ▼              ▼
Platform path   Workload path
```

## Platform path

```text
Degraded ClusterOperator?
   oc describe co <name> → its operator Pod logs → oc adm inspect co/<name>
        │
Node NotReady?
   oc describe node → oc debug node → chroot /host → kubelet / crio journals
   (disk full? memory pressure? certificates? network?)
        │
MachineConfigPool degraded or stuck?
   oc describe mcp → MCD logs on the stuck node → PDBs blocking drain
        │
Pending CSRs?
   oc get csr → approve if the node is expected
        │
Upgrade stuck?
   oc adm upgrade → which ClusterOperator is still Progressing
```

## Workload path

```text
oc get pods -n <project>     →  what state?
        │
        ├─ No Pods at all       → oc describe rs / deploy: SCC or quota FailedCreate
        ├─ Pending              → events: resources, taints, node selector, PVC
        ├─ ImagePullBackOff     → image name/tag, pull secret, registry reachability, mirrors
        ├─ CreateContainerConfigError → missing ConfigMap / Secret / key
        ├─ CrashLoopBackOff     → oc logs --previous: app error, permissions (random UID), OOMKilled
        ├─ Running, not Ready   → readiness probe, dependencies
        └─ Ready but unreachable → Service endpoints, Route host/target, NetworkPolicy, router
        │
        ▼
Identify root cause → fix → validate → document (RCA)
```

Useful commands:

```bash
# Platform
oc get co
oc get nodes -o wide
oc get mcp
oc adm upgrade
oc get csr
oc adm top nodes

# Nodes
oc debug node/<node>                # then: chroot /host
oc adm node-logs <node> -u kubelet
oc adm node-logs <node> -u crio
oc adm cordon <node> ; oc adm drain <node> --ignore-daemonsets --delete-emptydir-data

# Workloads
oc get pods -o wide
oc describe pod <pod>
oc logs <pod> --previous
oc get events --sort-by=.lastTimestamp
oc debug deploy/<name>              # copy of the Pod with a shell
oc rsh <pod>
oc get endpointslices -l kubernetes.io/service-name=<svc>
oc get route <route> -o yaml

# Evidence for Red Hat support
oc adm must-gather
oc adm inspect co/<operator>
oc adm inspect ns/<project>
```

`oc adm must-gather` collects logs and resources from every operator into a local folder — the first thing Red Hat support asks for. Product-specific must-gather images exist for ODF, Logging, Virtualization and others.

Every Pod failure state decoded: [Pod failure states decoder](pod-failure-states-decoder.md). Worked examples: [RCAs](../rca/) and [runbooks](../runbooks/README.md).

---

# ⭐ OpenShift Best Practices

## Cluster design

- Three control plane nodes in separate failure domains; etcd on fast, low-latency disks.
- Infra nodes for the router, registry and monitoring, tainted so apps stay off.
- Size the cluster and service networks for growth at install — they're hard to change later.
- Highly available DNS and load balancers for `api`, `api-int` and `*.apps`.

## Security

- Replace `kubeadmin` with an identity provider and group-based RBAC, then delete the `kubeadmin` secret.
- Keep apps on `restricted-v2`; grant extra SCCs only to dedicated service accounts.
- Build images that run as an arbitrary UID.
- A project template with a default-deny NetworkPolicy, quota and LimitRange.
- etcd encryption where compliance requires it; company-signed API and wildcard certificates.

## Reliability

- Requests and limits on every container; probes tuned to real start-up times.
- PodDisruptionBudgets that allow at least one disruption, or drains (and upgrades) hang.
- At least 2 replicas with anti-affinity for anything important.
- MachineHealthChecks on worker MachineSets.

## Storage

- Use dynamic provisioning with a sensible default StorageClass.
- Pick access modes deliberately (RWO for databases, RWX only when really shared).
- `Retain` reclaim policy for data you can't recreate.
- Back up application data with OADP or the database's own tools, and test restores.

## Upgrades and operations

- Stay on a `stable` or `eus` channel, within support windows; upgrade non-production first.
- Check `oc get co`, `oc get mcp` and removed-API usage before every upgrade.
- GitOps for cluster configuration and applications.
- Never change files on RHCOS nodes by hand — use MachineConfig.
- Regular etcd backups stored off-cluster; keep `must-gather` output for every serious incident.

---

# 🎤 Senior Platform Engineer Interview Revision

## OpenShift Architecture

- **What is OpenShift?** A certified Kubernetes distribution plus an integrated, operator-managed platform: RHCOS, OVN-Kubernetes, router, registry, builds, OAuth, monitoring and over-the-air upgrades.
- **Control plane:** kube-apiserver, etcd, scheduler, controller manager + openshift-apiserver, oauth-openshift, oauth-apiserver, openshift-controller-manager — each managed by an operator.
- **What does the CVO do?** Applies and guards the release image's manifests; drives upgrades.
- **CVO vs OLM?** Core platform vs optional add-on operators.
- **First command for platform issues?** `oc get co`.

## Workloads

- **Deployment → ReplicaSet → Pods**; DeploymentConfig is deprecated.
- **Pods not created at all?** SCC or quota rejection — check the ReplicaSet.
- **OOMKilled?** Memory over the limit, exit 137.
- **HPA needs?** CPU requests, and the Metrics API.
- **Liveness vs readiness?** Restart vs remove from traffic.

## Networking

- **CNI?** OVN-Kubernetes; no kube-proxy.
- **Route TLS types?** Edge, passthrough, re-encrypt.
- **Route not working?** Host → Service → selector/labels → port → Pod readiness.
- **DNS?** CoreDNS `dns-default`, `<svc>.<project>.svc.cluster.local`.
- **Fixed outbound IP?** EgressIP.

## Configuration and Storage

- **Secrets encrypted?** Only with etcd encryption enabled.
- **ConfigMap change not applied?** Env vars need a Pod restart.
- **PVC Pending?** `WaitForFirstConsumer`, no default StorageClass, or provisioner errors.
- **Bare-metal storage?** ODF, LVM Storage or a vendor CSI driver.

## Security

- **`oc login` flow?** OAuth server → identity provider → User/Identity → `sha256~` token → validated per request → RBAC.
- **Random UID?** `restricted-v2` assigns it from the project's UID range.
- **Run a root image?** Dedicated service account + `anyuid`, or better, fix the image.
- **App TLS inside the cluster?** Service CA annotation.

## Operations

- **Change node OS settings?** MachineConfig; MCO rolls it out with drain and reboot.
- **Pool stuck?** Drain blocked by PDB; **pool degraded?** Manual node edits.
- **Upgrade order?** Platform operators, then RHCOS on control plane, then workers.
- **Node won't join (UPI)?** Pending CSRs or no access to port 22623.
- **Backup?** `cluster-backup.sh` for etcd, OADP for apps.
- **Support data?** `oc adm must-gather`.
- **Shell on a node?** `oc debug node/<node>` + `chroot /host`.

---

# 📚 Recommended Learning Path

```text
Containers and Kubernetes basics (kubernetes-labs)
        │
        ▼
OpenShift architecture (this document) + OpenShift vs Kubernetes
        │
        ▼
Applications: Deployments, Services, Routes, ConfigMaps, Secrets, storage   (DO180)
        │
        ▼
Builds, ImageStreams, registry, templates, Helm
        │
        ▼
Security: OAuth, RBAC, SCCs, NetworkPolicy, projects, quotas               (DO280)
        │
        ▼
Operators: CVO, ClusterOperators, OLM
        │
        ▼
Nodes: MachineConfig, Machine API, upgrades
        │
        ▼
Day-2 at scale: GitOps, monitoring, logging, backup, multi-cluster          (DO380)
        │
        ▼
Installation and disconnected clusters                                      (DO322)
        │
        ▼
OpenShift Virtualization · OpenShift AI · GPU operator
```

---

# 📕 Glossary

All terms, one line each, with the command to see each one on a cluster: **[OpenShift quick reference](openshift-quick-reference.md)**.

---

# 🏁 Conclusion

OpenShift is Kubernetes in which the platform manages itself. The same API server, etcd, scheduler, controllers and kubelet do the same jobs as in upstream Kubernetes — but every platform piece, down to each node's operating system, is described declaratively and kept in place by an operator, and the whole stack is released, tested and upgraded as one unit.

For an administrator, that changes the daily work:

- You change platform behaviour through cluster configuration objects (`oauth`, `ingresscontroller`, `MachineConfig`, `dns.operator`, `apiserver`) instead of editing files.
- You read platform health from ClusterOperators and MachineConfigPools, and application health from Pods, events and endpoints.
- You design for OpenShift's security defaults — random UIDs, SCCs, SELinux — from the first deployment.

The stories, RCAs and runbooks in this repo are where each part of this document is put into practice on a real multi-node cluster, and where it broke, written up.

---

# 📖 Related Documentation

- [OpenShift vs Kubernetes architecture](openshift-vs-kubernetes-architecture.md) – side-by-side comparison, kubectl vs oc
- [etcd quorum explained](etcd-quorum.md) – quorum, Raft, failure scenarios and recovery
- [oc command bank](oc-command-bank.md) – ~170 commands grouped by task
- [CRI-O container runtime](cri-o-container-runtime.md) – runtime internals and `crictl`
- [Container runtimes overview](container-runtimes-overview.md) – runtimes by layer
- [Pod failure states decoder](pod-failure-states-decoder.md) – every Pod failure state explained
- [OpenShift admin learning path](openshift-admin-learning-path.md) – DO180 / DO280 / DO380 scope
- [Stories](../stories/), [RCAs](../rca/), [runbooks](../runbooks/README.md) – the hands-on work behind this guide
- [Kubernetes Architecture](https://github.com/NookireddiDileep/kubernetes-labs/blob/main/01-kubernetes-foundation/ARCHITECTURE.md) – the upstream version of this guide
