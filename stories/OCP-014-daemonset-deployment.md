# OCP-014: Application deployment using a DaemonSet – one Pod per node

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Workloads · DaemonSets · Scheduling (taints, tolerations) |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~25 min |
| **Status** | Done |
| **Related** | [OCP-002 – Deployment self-healing](OCP-002-deployment-self-heal.md) |

## 1. User story / requirement
> As a **platform engineer**, I want to **deploy an application with the DaemonSet strategy**, so that **exactly one copy runs on every node** – the pattern used for node agents (logging, monitoring, security, storage/network plugins).

## 2. Acceptance criteria
- [x] DaemonSet `app-ds` created from a manifest
- [x] One Pod Running on **each** eligible node
- [x] Each Pod identifies the node it runs on
- [x] *(extra)* Showed how DaemonSets differ from Deployments: ownership, per-node self-healing, no scaling, auto-tolerations

## 3. Background / concepts
| | Deployment | DaemonSet |
|---|---|---|
| Pod count | `replicas: N`, placed by the scheduler | **one per eligible node** |
| Controller chain | Deployment → ReplicaSet → Pods | DaemonSet → Pods (no ReplicaSet) |
| Node added | nothing | Pod added on it automatically |
| Pod deleted | replaced anywhere | replaced **on the same node** |
| Scaling | `oc scale` | not applicable – count follows the nodes |
| Typical use | applications | node agents: log shippers, metrics exporters, security/EDR agents, CSI/CNI plugins |

**Eligible node** = matches the DaemonSet's `nodeSelector`/affinity (if any) **and** its Pods tolerate the node's taints. OpenShift also honours a project-level node selector (`openshift.io/node-selector`).

**Downward API**: exposes Pod/node facts (here `spec.nodeName`, `metadata.name`) to the container as env vars – how agents know where they are.

> Relevance to traditional ops: on RHEL servers, agents (EDR, monitoring, APM) are installed per host as packages. On OpenShift the same agents run as **DaemonSets** – rolled out, updated and removed for every node in one object.

## 4. Plan
1. Inspect nodes, roles, taints and any project node selector.
2. Create a hardened DaemonSet "agent" that logs its node name.
3. Verify one Pod per node; check ownership, SCC, tolerations.
4. Delete one Pod – confirm it returns on the same node.
5. Try `oc scale` to show it doesn't apply.
6. **Rollback:** `oc delete ds app-ds`.

## 5. Implementation
Manifest: [`scripts/OCP-014/app-ds.yaml`](../scripts/OCP-014/app-ds.yaml)
```bash
oc apply -f app-ds.yaml --dry-run=server
oc apply -f app-ds.yaml
```

## 6. Validation / evidence
**Cluster nodes (sanitised):**
```
NAME       STATUS   ROLES                         VERSION    OS-IMAGE
master-0   Ready    control-plane,master,worker   v1.32.13   Red Hat Enterprise Linux CoreOS 9.6
worker-1   Ready    worker                        v1.32.13   Red Hat Enterprise Linux CoreOS 9.6

NAME       TAINTS
master-0   <none>          ← control-plane node is schedulable (no NoSchedule taint)
worker-1   <none>
project node-selector: (none)
```
**DaemonSet – one Pod per node:**
```
NAME     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
app-ds   2         2         2       2            2           <none>

nodes: 2   ds pods: 2
POD            NODE       STATUS
app-ds-6hrlm   master-0   Running
app-ds-w7rmn   worker-1   Running
```
**Each Pod knows its node (Downward API):**
```
11:23:25 agent alive on node=master-0 pod=app-ds-6hrlm
11:23:26 agent alive on node=worker-1 pod=app-ds-w7rmn
```
**Owned directly by the DaemonSet; restricted-v2; resources as specified:**
```
DaemonSet / app-ds
restricted-v2
{"limits":{"cpu":"50m","memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}
```
**Tolerations OpenShift added automatically:**
```
node.kubernetes.io/not-ready         NoExecute
node.kubernetes.io/unreachable       NoExecute
node.kubernetes.io/disk-pressure     NoSchedule
node.kubernetes.io/memory-pressure   NoSchedule
node.kubernetes.io/pid-pressure      NoSchedule
node.kubernetes.io/unschedulable     NoSchedule
```
**Per-node self-healing – replacement on the SAME node:**
```
deleting app-ds-6hrlm on master-0
pod "app-ds-6hrlm" deleted
app-ds-b4qdd   1/1   Running   0   15s   master-0      ← new Pod, same node
```
**No scaling:**
```
$ oc scale ds/app-ds --replicas=5
Error from server (NotFound): the server could not find the requested resource    ← DaemonSets have no scale subresource
```

## 7. Issues hit & observations
| # | Observation | Explanation / impact |
|---|---|---|
| 1 | `DESIRED 2` = 2 nodes, including the control-plane node | `master-0` has **no NoSchedule taint** (compact/lab layout), so it's eligible. On a standard cluster with tainted masters, a DaemonSet skips them unless it tolerates `node-role.kubernetes.io/master` |
| 2 | Auto-toleration **`unschedulable NoSchedule`** | DaemonSet Pods keep running on **cordoned** nodes; `oc adm drain` therefore needs `--ignore-daemonsets` |
| 3 | Auto-tolerations **`not-ready`/`unreachable NoExecute`** with no `tolerationSeconds` | DaemonSet Pods are never evicted from failing nodes – correct for node agents, which must stay with their node |
| 4 | `oc scale ds` → `NotFound` | The Pod count is driven by nodes, not by replicas |
| 5 | Replacement Pod returned on the same node | The DaemonSet controller ensures one Pod **per node**, so a deleted Pod is recreated for that specific node |
| 6 | **Cluster has a single control-plane node** | One etcd member: quorum = ⌊1/2⌋+1 = 1 → **tolerates 0 failures**. If `master-0` fails the API is down. Fine for a lab; production uses 3 control-plane nodes (tolerates 1) – see my quorum notes |
| 7 | Pasted heredoc displayed garbled around `limits:` | Only the terminal echo was affected – verified the live object has the intended requests/limits |

## 8. Production considerations
- Keep agent DaemonSets **small and bounded** (requests/limits) – they run on every node, so their footprint is multiplied by the node count.
- Control placement explicitly: `nodeSelector` / affinity for "workers only", **tolerations** for tainted nodes (control plane, infra, GPU nodes).
- Use `RollingUpdate` with a sensible `maxUnavailable` so an agent update doesn't hit all nodes at once.
- Real agents often need host access (`hostPath`, `hostNetwork`, privileged) → a dedicated service account with a **specific SCC**, reviewed by security – never `privileged` for everything.
- Use `PriorityClass` (e.g. `system-node-critical`) for agents that must not be evicted under pressure.
- Drains: `oc adm drain <node> --ignore-daemonsets --delete-emptydir-data`.

## 9. Lessons learned
- DaemonSet = "one per node", with self-healing **per node** and no replica count.
- Eligibility = node selector + taints/tolerations; OpenShift adds tolerations that keep agents alive on cordoned or failing nodes.
- Looking at nodes first revealed the cluster's own HA posture (single control-plane node).

## 10. Interview talking point
> "I deployed a small node-agent as a DaemonSet that logs its node name through the Downward API. It ran exactly one Pod per node – including the control-plane node, because it had no NoSchedule taint in this lab. Pods were owned directly by the DaemonSet, a deleted Pod came back on the same node, and `oc scale` doesn't apply. I also checked the tolerations OpenShift adds automatically – for example `unschedulable`, which is why drains need `--ignore-daemonsets`. Coming from RHEL ops, this is how agents like EDR, monitoring and log shippers are deployed on OpenShift instead of per-host packages. The node listing also showed the cluster had a single control-plane node – one etcd member, zero fault tolerance."
