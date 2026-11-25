---
title: "CE-002 – A day in the life of an OpenShift platform engineer"
tags: [openshift, platform-engineering, day-2-operations, core-engineering]
---

# CE-002 – A day in the life of an OpenShift platform engineer

> **Core engineering series · CE-002.** A living article, extended as new findings come in.
> It builds on the control-loop idea from [CE-001](CE-001-what-kubernetes-and-openshift-solve.md).

---

## 0. In plain words

Application teams build the shops. The **platform engineer runs the shopping centre**:
the power, the lifts, the security desk, the loading bays and the rules every shop
follows. Shoppers never think about them, and that's the point. When the centre runs
well, nobody notices; when the lifts stop, everybody does.

On OpenShift that means: keep the cluster healthy, change it safely, recover it fast,
and make it easier and cheaper to run every quarter. Most of the work happens through
the API, Git and change records, not by logging in to servers.

---

## 1. What the platform engineer owns

| Layer | Day-to-day responsibility |
|---|---|
| Cluster lifecycle | Installs, upgrades, update channel, node OS changes through MachineConfigs |
| Control plane | etcd health and backups, API server, certificates |
| Nodes and capacity | Adding and replacing nodes (MachineSets), autoscaling, resource headroom |
| Networking | Ingress routers, DNS, OVN-Kubernetes, egress, load balancers (MetalLB), NetworkPolicy standards |
| Storage | StorageClasses, CSI drivers, ODF/Ceph, snapshots, PVC issues |
| Security | Identity provider (LDAP/SSO), RBAC, SCCs, ACS findings, compliance scans, image policies |
| Tenancy | Project templates, quotas, limit ranges, onboarding new teams |
| Platform services | Monitoring and alerting, logging, internal registry, GitOps, Pipelines, Service Mesh |
| Fleet | ACM policies, multi-cluster upgrades and placement |
| Backup and DR | etcd backups, OADP application backups, restore drills |

The boundary that matters most: **the platform team owns the platform; application
teams own their applications.** A `CrashLoopBackOff` in a team's project is normally
theirs; a Degraded cluster operator is always the platform team's.

---

## 2. A typical day

| When | Activity | What it really involves |
|---|---|---|
| Start of shift | **Health check** | Cluster operators, nodes, MachineConfigPools, firing alerts, failed pods, pending CSRs, etcd. About 10 minutes, mostly scripted (section 4) |
| Morning | **Alert triage** | Separate real problems from noise, and platform alerts from application alerts. `KubePodCrashLooping` in a team project is theirs; `etcdHighFsyncDurations` is the platform's |
| Midday | **Requests** | New project for a team, quota increase, "my pod is Pending", "my Route returns 503", "why was my pod OOMKilled", a certificate for a custom domain |
| Afternoon | **Planned changes** | Inside an approved change window: Operator updates, a MachineConfig (NTP, kernel argument, registry mirror), adding workers, router tuning |
| Ongoing | **Engineering work** | Moving cluster config to GitOps, better alerts, runbooks, the next upgrade plan, onboarding standards |
| On call | **Incidents** | Node NotReady, upgrade stuck, etcd degraded, ingress down, storage full. Run the incident, then write the RCA |

---

## 3. Weekly, monthly, quarterly

| Cadence | Work |
|---|---|
| Weekly | Tune noisy alert rules; review capacity trends (requested vs actually used); review ACS vulnerability reports; clean up abandoned projects and PVCs |
| Monthly | z-stream upgrades (for example 4.19.38 → 4.19.39); Operator updates; restore an etcd backup in a non-production cluster to prove it works; review expiry of custom certificates |
| Quarterly | Minor-version upgrade (for example 4.19 → 4.20): check deprecated APIs and Operator compatibility, upgrade a test cluster first; DR drill; capacity forecast and budget |
| Yearly or as needed | New cluster builds, data-centre or cloud migrations, architecture changes, audits |

---

## 4. The start-of-shift health check

```bash
oc get clusterversion                          # version, Progressing, any failing update
oc get co --no-headers | awk '$3!="True" || $4!="False" || $5!="False"'   # only unhealthy operators
oc get nodes; oc get mcp                       # NotReady nodes; pools Updated / Degraded
oc adm top nodes                               # actual CPU / memory pressure
oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
oc get csr | grep -i pending                   # node certificates waiting for approval
oc get pvc -A | grep -v Bound                  # storage claims stuck Pending
oc get pods -n openshift-etcd -l app=etcd      # every etcd member Running
oc get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20
```

The goal is empty or all-green output. The senior habit is to turn this into a script
or a dashboard, and to alert on it, instead of retyping it every morning.

---

## 5. Incidents a senior engineer handles end to end

| Incident | First checks | Typical causes |
|---|---|---|
| Node NotReady | `oc describe node`; kubelet and CRI-O journal through `oc debug node/<n> -- chroot /host journalctl -u kubelet -n 100` | Memory pressure, disk full, kubelet certificate, network |
| Upgrade stuck | `oc get clusterversion`, `oc get co`, `oc get mcp`, the message on the operator that is Progressing | A PodDisruptionBudget blocking a node drain, a Degraded MachineConfigPool, an incompatible Operator |
| MachineConfigPool Degraded | `oc describe mcp`; machine-config-daemon logs for that node | A bad MachineConfig, or a file changed by hand on the node |
| etcd slow or degraded | etcd operator status; fsync and leader-change alerts | Slow disk, a member down, too many objects (events, secrets) |
| Ingress or Route outage | Router pods, ingress operator, DNS, the external load balancer | Router pods on an unhealthy node, an expired certificate, DNS |
| Mass pod evictions | Node conditions (MemoryPressure, DiskPressure); `oc adm top nodes` | Nodes overcommitted because requests are far below real usage |
| Certificate expiry | `oc get co`; dates on API and ingress certificates | Custom certificates not rotated (the platform rotates its own internal ones) |

**The incident routine:**
1. **Stabilise first:** restore service (cordon a bad node, scale away, roll back), then investigate.
2. **Communicate:** one channel, regular updates, a clear owner.
3. **Find the cause:** which control loop isn't converging (CE-001, "A practical troubleshooting lens").
4. **Write the RCA:** timeline, root cause, fix, and the prevention that stops a repeat.

---

## 6. Changes: how a senior makes them safely

Most outages come from changes, so change discipline is most of seniority:

- **Test the change on a non-production cluster first.** Upgrades and MachineConfigs especially.
- **Know the blast radius.** A MachineConfig reboots every node in its pool, one at a time. A change to the default ingress controller affects every Route.
- **Have a way back.** For upgrades that means a recent etcd backup and a tested restore; minor upgrades cannot be rolled back.
- **Check capacity before draining.** One node out must still fit every workload, and PodDisruptionBudgets must allow the drain.
- **Prefer Git over `oc edit`.** A change through GitOps is reviewed, recorded and repeatable.

---

## 7. What makes the role "senior"

| Skill | What it looks like in practice |
|---|---|
| Change judgement | Knows what can break, tests first, always has a recovery path |
| Design | Tenancy model, node pools (infra, worker, GPU), backup strategy, upgrade cadence, standards for every team |
| Automation | Cluster configuration in Git, alerts as code, scripts that replace repeated manual work |
| Incident leadership | Runs the call, communicates clearly, writes RCAs that prevent repeats |
| Teaching | Runbooks and coaching that make application teams self-sufficient, so fewer tickets reach the platform team |

---

## 8. Coming from traditional Linux operations

Most of the discipline carries over; the tools change.

| Traditional Linux operations | OpenShift platform equivalent |
|---|---|
| Patching each server for a CVE | z-stream upgrades and MachineConfig rollouts across the cluster |
| Change windows and CAB approval | The same process, applied to upgrades, MachineConfigs and Operator updates |
| DR fire drills | etcd restore and OADP restore drills |
| VM backup tools | etcd backups plus OADP (Velero) for applications |
| Monitoring and security agents per server | Operators and DaemonSets doing the same jobs on every node |
| Replacing failed hardware | Replacing nodes through MachineSets, or rebuilding a bare-metal node |
| Config edited on each server | Declarative config in Git, reconciled automatically |

---

## 9. Practising this without a production cluster

- Run the section 4 health check daily for a week and explain every non-green line.
- Read `oc describe co <name>` and `oc describe mcp` until the conditions are familiar.
- Write a runbook for each incident in section 5 before you ever meet it.
- On a cluster you own, break things on purpose: a bad MachineConfig, a blocked drain, an etcd backup and restore.

---

## 10. Interview angle

- **"Walk me through your day."** Health check, alert triage, requests, planned changes, engineering work. Name real commands and real alerts.
- **"How do you upgrade a production cluster?"** Read the release notes and update graph, check deprecated APIs and Operator compatibility, back up etcd, upgrade a test cluster, check PDBs and capacity, upgrade in a change window, watch `clusterversion`, operators and MachineConfigPools.
- **"A node is NotReady. What do you do?"** Stabilise (cordon), check node conditions, kubelet and CRI-O logs through `oc debug node`, then disk, memory, certificates and network.
- **"How do you keep 50 teams from hurting each other?"** Project templates with quotas, limit ranges and default NetworkPolicies; RBAC by group; SCC defaults; onboarding standards in Git.

---

## Hands-on evidence

Related material in this repository:

| Topic | Where |
| --- | --- |
| etcd and quorum, the control plane's most critical component | [etcd quorum explained](../reference/etcd-quorum.md) |
| Every pod failure state, down to its mechanism | [Pod failure states decoder](../reference/pod-failure-states-decoder.md) |
| A Route outage traced through three stacked faults | [RCA-003](../rca/RCA-003-route-unreachable-three-faults.md) |
| Ready-to-run break-fix runbooks | [runbooks/](../runbooks/README.md) |
| Cluster and app configuration through Git | [GitOps labs](../gitops/README.md) |
