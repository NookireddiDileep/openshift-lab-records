# etcd Quorum in OpenShift — Explained from Scratch

Nookireddi Dileep · Nov 2026 · Based on OpenShift 4.x (etcd 3.5)

> Concept guide in my own words. Part of the [OpenShift architecture](openshift-architecture.md) series · Commands: [oc command bank](oc-command-bank.md)

> **The one-line answer:** etcd only accepts a change when a **majority** of its members agree. With 3 members, OpenShift survives losing 1 control plane node; lose 2 and the cluster can no longer change anything until a majority is back.

---

## 1. Why this matters

etcd is the database that holds **every** object in the cluster: Pods, Deployments, Secrets, Routes, users, configuration. Every `oc` command, every controller and every operator reads and writes through the kube-apiserver, which talks to etcd.

If etcd can't accept writes, the cluster is frozen. Understanding quorum tells you:

- how many control plane failures the cluster can survive
- why OpenShift uses exactly 3 control plane nodes
- why you must never reboot two control plane nodes at the same time
- what to do when etcd members fail

---

## 2. Quorum in plain words

Think of a **committee of 3 people** that keeps the company's official record book.

- A change to the book is official only when **at least 2 of the 3** sign it.
- If one member is on leave, the other two can still approve changes.
- If two are away, the one remaining person **can't** change the book alone — otherwise two people in different rooms could each write different "official" versions.

That "at least 2 of 3" is the **quorum**: the minimum number of members that must agree.

```text
Quorum = floor(N / 2) + 1        (more than half of all members)
```

---

## 3. How etcd uses quorum (Raft)

etcd uses the **Raft** consensus algorithm. Members have one of three roles:

| Role | Job |
|---|---|
| **Leader** | The only member that accepts writes; sends them to the others; sends heartbeats |
| **Follower** | Copies the leader's log; votes in elections |
| **Candidate** | A follower that stopped hearing heartbeats and is asking for votes |

### A write, step by step

```text
oc apply → kube-apiserver → etcd LEADER
                                │
                                │ 1. append the change to its own log
                                │ 2. send it to both followers
                                ▼
              ┌─────────────────┴─────────────────┐
              ▼                                   ▼
         Follower B                          Follower C
         writes to disk, replies OK          (slow, no reply yet)
              │
              ▼
 Leader has 2 of 3 (itself + B) = quorum
              │
              ▼
 Change COMMITTED → success returned to the API server
 (C catches up later)
```

A write is committed once a **majority has stored it on disk**. That's why a committed change can never be lost while a majority survives: at least one survivor always has it.

### Leader election

```text
Followers stop receiving heartbeats from the leader (election timeout)
        │
        ▼
A follower becomes candidate, increases the "term" number, asks for votes
        │
        ▼
Gets votes from a majority? ── yes ──► new leader for this term
        │
        no (split vote or not enough members reachable)
        ▼
Wait a random time, try again
```

A leader needs majority votes, so there can **never be two leaders** accepting writes at the same time. This is what prevents "split brain".

---

## 4. The quorum table

| Members (N) | Quorum needed | Failures tolerated | Notes |
|---|---|---|---|
| 1 | 1 | 0 | Single Node OpenShift: no HA |
| 2 | 2 | **0** | Worse than 1: two things that can fail, still no tolerance |
| **3** | **2** | **1** | **Standard OpenShift** |
| 4 | 3 | 1 | Same tolerance as 3, but more members to replicate to |
| 5 | 3 | 2 | More tolerance, slower writes |

### Why odd numbers?

Adding a 4th member raises the quorum from 2 to 3 but **still tolerates only 1 failure**. You pay for an extra node and extra write latency (more members to replicate to) and gain nothing. Odd numbers give the best tolerance for the cost.

### Why exactly 3 in OpenShift?

Three is the smallest size that survives a failure, and keeps writes fast. OpenShift's standard HA topology always has 3 control plane nodes, each running one etcd member, managed by the **cluster-etcd-operator**.

---

## 5. What happens when members fail (3-member cluster)

### Lose 1 member — cluster keeps working

```text
 master-0 ✅      master-1 ✅      master-2 ❌
 etcd (leader)    etcd             down

 2 of 3 alive = quorum ✅
```

- API reads and writes continue; you might see one short leader election if the lost member was the leader.
- `oc get co etcd` shows `Degraded=True`; alerts such as `etcdMembersDown` fire.
- **You now have zero tolerance left.** One more failure freezes the cluster. Fix the lost member quickly, and don't start any maintenance on another control plane node.

### Lose 2 members — quorum lost

```text
 master-0 ✅      master-1 ❌      master-2 ❌
 etcd             down             down

 1 of 3 alive = NO quorum ❌
```

| Still works | Stops working |
|---|---|
| Containers already running on nodes keep running (the kubelet doesn't need etcd to keep a container alive) | Any change: create, update, delete, scale |
| Existing network paths usually keep passing traffic | The API: most `oc` commands hang or fail (even reads use quorum reads by default) |
| | Scheduling, self-healing, rolling updates, autoscaling |
| | `oc login`, the web console, operators, builds |

The cluster is "frozen": whatever was running stays running, but nothing can be repaired or changed. If a Pod dies now, nobody replaces it.

### Network partition — why no split brain

```text
 ┌──────────────┐   network cut   ┌──────────────────────────┐
 │ master-0     │ ──────╳──────── │ master-1      master-2   │
 │ (old leader) │                 │                          │
 │ 1 of 3       │                 │ 2 of 3                   │
 └──────────────┘                 └──────────────────────────┘
   no quorum:                       quorum: elects a new leader,
   can't commit writes,             keeps accepting writes
   steps down
```

The isolated side can't reach a majority, so it can't commit anything. Only one side can ever have a majority, so the cluster never ends up with two different versions of the truth.

---

## 6. OpenShift-specific behaviour

### The cluster-etcd-operator

Owns etcd in `openshift-etcd`: runs one etcd static Pod per control plane node, manages member membership, TLS certificates, defragmentation and revisions. Its health is the `etcd` ClusterOperator.

### Quorum protection during maintenance

OpenShift actively avoids taking out two members at once:

- The **master MachineConfigPool** updates control plane nodes **one at a time** (`maxUnavailable: 1`). Don't raise it.
- The operator runs **etcd-guard** Pods with a PodDisruptionBudget in `openshift-etcd`, so a drain of a second control plane node is blocked while an etcd member is not healthy.
- During upgrades, the CVO and MCO keep this order: one control plane node rebooted, etcd healthy again, then the next.

**Rule:** never reboot, drain or power off two control plane nodes at the same time — including at the hypervisor or hardware level, where OpenShift can't stop you.

### Performance: quorum needs fast disks and networks

Every write waits for a majority to **write to disk (fsync)**. Slow disks or slow links between control plane nodes make every API call slow and can cause repeated leader elections.

- Use low-latency SSD/NVMe storage for control plane nodes; a commonly used target is p99 WAL fsync under 10 ms.
- Keep the 3 control plane nodes close together in network terms; stretching them across distant sites adds latency to every write.
- Signs of trouble: alerts `etcdHighFsyncDurations`, `etcdHighNumberOfLeaderChanges`, slow `oc` commands.

---

## 7. Checking etcd and quorum health

```bash
# Platform view
oc get co etcd
oc get pods -n openshift-etcd -l app=etcd -o wide

# Inside an etcd Pod (etcdctl container)
oc rsh -n openshift-etcd etcd-<control-plane-node>
etcdctl member list -w table                     # 3 members, all started
etcdctl endpoint health --cluster                # each member healthy?
etcdctl endpoint status --cluster -w table       # who is leader, DB size, raft term
```

In `endpoint status`, exactly one member shows `IS LEADER = true`. A raft term that keeps climbing means repeated elections (disk or network trouble).

Alerts to know:

| Alert | Meaning |
|---|---|
| `etcdMembersDown` | One or more members unreachable — tolerance reduced |
| `etcdInsufficientMembers` | Quorum lost or about to be lost — critical |
| `etcdNoLeader` | A member has no leader — elections failing |
| `etcdHighNumberOfLeaderChanges` | Frequent elections — usually disk or network latency |
| `etcdHighFsyncDurations` | Disk too slow for etcd |

---

## 8. Recovery paths

```text
                    Which situation?
                          │
        ┌─────────────────┴──────────────────┐
        ▼                                    ▼
 1 member lost, quorum intact         Quorum lost (2 of 3 down)
        │                                    │
        ▼                                    ▼
 Bring the node back if possible.     Can the down nodes come back
 If the member is broken for good:    with their data intact?
 replace the unhealthy member          │            │
 (documented procedure: remove the    yes           no
 member, clean up its secrets, let     │            │
 the operator re-add it). The new      ▼            ▼
 member re-syncs from the other   Start them —   Disaster recovery:
 two. No backup restore needed.   quorum returns  restore from an etcd
                                  automatically   backup on ONE recovery
                                                  control plane node
                                                  (cluster-restore.sh),
                                                  then re-add the others
```

Key points:

- Losing **one** member is a repair, not a restore.
- A **restore** takes the cluster back to the moment of the backup — changes made after it are lost. Use it only when quorum can't be recovered any other way.
- This is why regular, off-cluster etcd backups matter (`cluster-backup.sh`, see [OpenShift architecture → Backup and Disaster Recovery](openshift-architecture.md)).

---

## 9. Common misunderstandings

| Myth | Reality |
|---|---|
| "More etcd members = always safer" | 4 is no safer than 3; 5 tolerates 2 failures but slows every write |
| "If etcd is down, all apps go down" | Running containers keep running; you lose the ability to change or heal anything |
| "Two control plane nodes are fine for HA" | Two members tolerate zero failures |
| "Quorum is about how many nodes are running" | It's about how many **etcd members can reach each other** — a network cut counts too |
| "Losing one member means restoring a backup" | No — replace the member; it re-syncs from the healthy two |

---

## 10. Interview questions

### Q1. What is etcd quorum?

The minimum number of members that must agree before a change is committed: more than half, `floor(N/2)+1`. For 3 members, that's 2.

---

### Q2. How many control plane failures can a standard OpenShift cluster survive?

One. Three etcd members need a quorum of 2.

---

### Q3. Why not 2 or 4 control plane nodes?

Two members need both to agree, so they tolerate no failure. Four tolerate only one failure, like three, while adding cost and write latency.

---

### Q4. What happens if two of three control plane nodes go down?

etcd loses quorum and stops accepting writes. The API stops working, nothing can be created, changed, scheduled or healed, but containers already running on workers keep running.

---

### Q5. How does etcd prevent split brain?

A leader needs votes from a majority, and a write needs a majority to commit. Only one side of a network split can have a majority, so only one side can make changes.

---

### Q6. How do you find the etcd leader in OpenShift?

`oc rsh -n openshift-etcd etcd-<node>` then `etcdctl endpoint status --cluster -w table` and look at `IS LEADER`.

---

### Q7. Why is disk speed so important for etcd?

Every write waits for a majority of members to fsync it to disk. Slow disks slow every API request and can trigger repeated leader elections.

---

### Q8. One etcd member is permanently broken. Do you restore from backup?

No. Quorum is intact, so you replace the unhealthy member and it re-syncs from the other two. Restore is only for lost quorum.

---

### Q9. How does OpenShift stop you from breaking quorum during maintenance?

The master MachineConfigPool updates one node at a time, and etcd-guard Pods with a PodDisruptionBudget block draining another control plane node while a member is unhealthy.

---

### Q10. Can a node-level change still break quorum?

Yes — rebooting two control plane VMs at the hypervisor, or a storage or network outage hitting two of them, bypasses OpenShift's protections. That's why control plane nodes belong in separate failure domains.

---

## 11. Lab ideas (only on a cluster you own)

| Exercise | What to observe |
|---|---|
| Run `etcdctl endpoint status --cluster -w table` | Which member is leader, DB size, raft term |
| Reboot **one** control plane node | API keeps working; `oc get co etcd` goes Degraded then recovers; possible leader change |
| Watch `etcdMembersDown` fire and clear in Observe → Alerting | Alert lifecycle during a single-member outage |
| Try to drain a second control plane node while one is down | Drain blocked by the etcd-guard PDB |
| Take a backup with `cluster-backup.sh` | Snapshot and static Pod resources produced |

Never test quorum loss on a shared or production cluster.

---

## 12. 30-second summary

etcd commits a change only when a majority of members store it. OpenShift runs 3 members, so it survives one control plane failure; losing two freezes the cluster, though running apps keep running. Odd numbers give the best tolerance per node, majority voting prevents split brain, and fast disks keep it all quick. Lose one member: replace it. Lose quorum: bring members back or restore from backup.
