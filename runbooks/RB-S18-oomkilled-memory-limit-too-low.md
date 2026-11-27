# RB-S18: The app dies under load with no error in the logs (OOMKilled, memory limit lower than the working set)

| Field | Value |
|---|---|
| **Scenario** | [S18](../scenarios/DO180-RCA-scenario-bank.md) |
| **Area** | Resources · Memory limits · cgroups · Pod lifecycle · Node-level Linux |
| **Lab** | 🟢 own project (the node-level steps in section 4 need cluster-admin; I read them as a walkthrough if I don't have it) |
| **Status** | 📋 Ready to run (not yet run on my cluster) |
| **Time** | ~30–45 min · **target time to root cause: 20 min** |

> A runbook is a **plan**, not a record. Once I've run it on my lab and captured real output, it becomes `rca/RCA-0NN-*.md` and this status becomes ✅ Done → RCA-0NN.
>
> **EX280 angle:** setting requests and limits on a Deployment (`oc set resources`) and reading quota/limit-range effects is a standard resource-management task. Here I add the diagnosis half: proving a container was killed for memory.
>
> All command output below is **typical output (illustrative)**, not captured from my cluster.

## 1. The ticket (as it would arrive)

| Field | Value |
|---|---|
| **Case** | Support case drill (mock) |
| **Severity** | **Sev 2**: a production-facing service is degraded; users see errors during peak hours, no full outage |
| **Environment** | OpenShift Container Platform 4.18, bare-metal UPI, 3 control-plane + 3 worker nodes (each 16 vCPU / 32 GiB), RHCOS, OVN-Kubernetes |
| **Time box** | **20 min to root cause**, 30 min including the customer update. Start a timer. |

**Symptom, in the customer's words:**

> "Our report-generator service falls over a few minutes after the morning batch starts. The pod restarts, the batch is lost, and users get 502s for about a minute. We looked at `oc logs` and there is no error, the log just stops. It worked fine in the test cluster last month."

**Business impact:** nightly/morning reports are late; the customer-facing portal shows 502s for roughly a minute at every restart.

**What the customer already tried:** read `oc logs` (nothing useful), deleted the pod (it came back and failed again), raised the replica count from 1 to 2 (both replicas fail, just a bit later each), and checked that the nodes are `Ready` (they are).

## 2. Reproduce safely (🟢)

Work only in my own project; objects are named `rca-s18-*`. Helpers are in [`scripts/RB-S18/`](../scripts/RB-S18/) and refuse to run in `default`, `openshift-*` or `kube-*`.

```bash
oc new-project rca-s18-lab        # or reuse my own lab project
./scripts/RB-S18/break.sh         # deploys a small "report generator" that needs ~200 MiB, with a 128 MiB limit
```

There is no real application. A UBI Python container stands in for it: it allocates memory in 10 MiB steps (one step per second, like a batch loading data), then holds it. The mistake is only in the Deployment's resources:

```yaml
containers:
  - name: report
    image: registry.access.redhat.com/ubi9/python-311:latest
    resources:
      requests: { cpu: 50m, memory: 64Mi }
      limits:   { cpu: 500m, memory: 128Mi }   # the working set is ~200Mi, so the kernel kills it near 128Mi
```

If my cluster's image is not pullable, I note it and use any image that has `python3`.

## 3. What you'll see

```
$ oc get pods -l app=rca-s18-report -w
NAME                              READY   STATUS             RESTARTS      AGE
rca-s18-report-7c9d5b8f6d-k2m4x   1/1     Running            0             20s
rca-s18-report-7c9d5b8f6d-k2m4x   0/1     OOMKilled          0             28s
rca-s18-report-7c9d5b8f6d-k2m4x   1/1     Running            1 (3s ago)    31s
rca-s18-report-7c9d5b8f6d-k2m4x   0/1     OOMKilled          1 (14s ago)   42s
rca-s18-report-7c9d5b8f6d-k2m4x   0/1     CrashLoopBackOff   1 (9s ago)    50s
```

Key observations:

- The **pod, not the node**, is the thing that fails: the node stays `Ready`.
- The log simply **stops**. A process killed by SIGKILL has no chance to print an error, which is why "no error in the logs" is the classic clue.
- The restart count climbs and the back-off grows (10 s, 20 s, 40 s …), so the outage per restart gets longer.
- With a limit **lower than the working set**, it fails *every* time at about the same point. If it failed only sometimes, I'd suspect a leak or a load spike instead.

## 4. Triage, outside-in

### Collect data first (before I change anything)

Goal: capture the evidence while the failing pod still exists, so the case can be reviewed later. Time spent: about 5 minutes.

| # | Artifact | Command | What it tells me / where to look |
|---|---|---|---|
| 1 | Targeted inspect of the project (my first choice for a one-project problem; small and quick) | `oc adm inspect ns/rca-s18-lab` | Writes an `inspect.local.*` folder. Look in `namespaces/rca-s18-lab/pods/<pod>/<pod>.yaml` → `status.containerStatuses[].lastState.terminated` (reason, exit code, timestamps), and in `…/<container>/<container>/logs/previous.log` for the last output before the kill. `namespaces/rca-s18-lab/core/events.yaml` has the event history. |
| 2 | Cluster-wide health | `oc get co` | If all operators are `Available=True, Degraded=False`, I rule out a cluster-level cause early (an unhealthy cluster would make me suspect the platform first). |
| 3 | Events | `oc get events --sort-by=.lastTimestamp` | `BackOff`, `Killing`, and (for node pressure) `Evicted` or `SystemOOM`. Tells me which of the two OOM types I have. |
| 4 | Previous-container logs | `oc logs <pod> --previous` | The last lines before the kill. Cut-off mid-line with no error means SIGKILL. |
| 5 | Node-level view (needs admin; only when the project data doesn't explain it, or events mention the node) | `oc debug node/<node>` → `chroot /host` → `journalctl -k --since "-30min" \| grep -iE 'oom\|killed process'` | The kernel's own record: `Memory cgroup out of memory: Killed process <pid> (python3) … oom_memcg=…/kubepods…` proves a **cgroup (container) OOM**. A `Out of memory: Killed process` line without "Memory cgroup" would mean the whole node ran out of memory. |
| 6 | Kubelet and CRI-O journals | `chroot /host` → `journalctl -u kubelet --since "-30min"`, `journalctl -u crio --since "-30min"` (or without a shell: `oc adm node-logs <node> -u kubelet`) | Kubelet shows the container's death and restart decisions and any eviction. CRI-O shows the container exit with exit code 137. |
| 7 | Full bundle, only if the problem may be broader or a vendor asks | `oc adm must-gather` | Large (minutes, hundreds of MB). In it: `cluster-scoped-resources/core/nodes/<node>.yaml` (conditions: MemoryPressure), `namespaces/<ns>/…` as above, `cluster-scoped-resources/…/clusteroperators/`, and host service logs for control-plane nodes under `host_service_logs/`. For a worker I use `oc adm node-logs`, as it isn't always in the bundle. |
| 8 | Node bundle for a support case (when it may be node-level) | `oc debug node/<node>` → `chroot /host` → `toolbox` → `sos report` | The sosreport collects the OS view: kernel logs, `free`, `ps`, cgroup state, CRI-O and kubelet config. Needed if a node-level fault is suspected or the case is escalated. Not needed for a plain container OOM. |

I would **not** start with a full `must-gather` for a single-pod restart: it is slow and mostly irrelevant. I go for `oc adm inspect` first, and escalate to must-gather or sosreport only if the evidence points beyond the pod.

### Triage steps

| # | Command | What it tells you |
|---|---|---|
| 1 | `oc get pods -l app=rca-s18-report` | `RESTARTS` growing, status `OOMKilled` / `CrashLoopBackOff`. Confirms a container-level failure, not Pending or image problems. |
| 2 | `oc describe pod <pod>` → **Last State** | `Terminated`, `Reason: OOMKilled`, `Exit Code: 137`. This is the key line: the kernel killed it for memory. |
| 3 | `oc get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'` | The same data, scriptable, with `finishedAt` to line up against the customer's "a few minutes after the batch starts". |
| 4 | `oc get deployment rca-s18-report -o jsonpath='{.spec.template.spec.containers[0].resources}'` | The limit in force: `memory: 128Mi`. Compare it with what the app needs. |
| 5 | `oc adm top pod -l app=rca-s18-report --containers` | Usage right before the kill (it may only catch the pod briefly). Close to the limit confirms it. |
| 6 | `oc get limitrange,resourcequota` | Rules out a LimitRange *injecting* the limit and a quota that would block raising it. See [S64/S65](../scenarios/DO180-RCA-scenario-bank.md). |
| 7 | `oc get node <node> -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'` | `MemoryPressure=False` on the node: the node had room, so the limit (not the node) was the cause. |

**Hypotheses and how each is ruled in or out:**

| Hypothesis | Rule in | Rule out |
|---|---|---|
| **A. Container hit its own memory limit (cgroup OOM)** | Last State `OOMKilled`, exit 137; usage near the limit; kernel log says `Memory cgroup out of memory` | None of this present |
| B. Node ran out of memory (global OOM or kubelet eviction) | Node `MemoryPressure=True`; pods show `Evicted` ("The node was low on resource: memory"); kernel log without "Memory cgroup"; many pods on that node affected | Node healthy, only this workload affected |
| C. Liveness probe killing it (also exit 137/143) | `Unhealthy`/`Killing … failed liveness probe` events | Reason is `OOMKilled`, and no probe events. See [S56](../scenarios/DO180-RCA-scenario-bank.md). |
| D. Memory leak (usage grows without bound) | Usage keeps rising even with a much larger limit; kill time keeps moving later | Usage plateaus at a fixed level under a bigger limit (a **fixed working set**) |
| E. The application crashed by itself | A stack trace or error in `--previous` logs, exit code 1 or similar | Log is cut off with no error and the reason is `OOMKilled` |

Experiment to separate A from D: raise the limit (see the fix) and watch the curve. A plateau means A. Steady growth means D, and it needs the developers (heap dump, profile), not just a bigger limit.

## 5. Root cause(s)

The container's **memory limit (128Mi) was lower than the application's real working set (~200Mi)**. The kernel enforces the limit through the container's cgroup: when usage cannot be reclaimed below the limit, the cgroup OOM killer sends SIGKILL to the process. The kubelet then reports `OOMKilled` with exit code 137 and restarts the container, and the cycle repeats with growing back-off.

Contributing causes:

1. The limit was copied from a small test workload or set by guess; nobody measured the real peak.
2. No `requests` close to real usage, so the scheduler placed the pod without regard to what it truly needs (this affects node pressure and QoS class).
3. Replicas were increased as a "fix", which only multiplied the failures (each replica has the same limit).
4. The log stops without an error because SIGKILL gives the process no chance to log; the evidence is in the pod status and the kernel log, not the app log.

5 Whys: users get 502 → pod restarted → container killed by the kernel → memory exceeded the cgroup limit → limit set below the working set → limit was never sized from measured usage.

## 6. Fix

Size the memory from **measured peak usage plus headroom**, and set a request that matches typical use.

```bash
./scripts/RB-S18/fix.sh
# by hand, the same thing:
oc set resources deployment/rca-s18-report \
  --requests=cpu=50m,memory=256Mi --limits=cpu=500m,memory=384Mi
oc rollout status deployment/rca-s18-report
```

Notes:

- My rule of thumb in the lab: limit around 1.5× the observed peak (here ~200Mi → 384Mi), request near the typical use. In real life I'd base it on a week of metrics (the monitoring console, or `container_memory_working_set_bytes`), not a single reading.
- Memory is **not compressible**: unlike CPU, which is throttled, memory over the limit means a kill. So memory limits deserve more care than CPU limits.
- Quota check: raising the limit must still fit the project's `ResourceQuota` (`oc describe quota`).
- Not a fix: adding replicas (same limit), or removing the limit entirely (the pod can then take node memory and cause evictions of neighbours, and it also changes its QoS class).

If the data suggested a leak (hypothesis D): raise the limit only as a **temporary mitigation**, and open an application bug with evidence (usage graph, kill timestamps, heap dump request).

## 7. Verify

```bash
./scripts/RB-S18/verify.sh                         # checks limits, restart count, last state
oc get pods -l app=rca-s18-report -w               # 1/1 Running, RESTARTS stops growing (watch 3-5 min)
oc adm top pod -l app=rca-s18-report --containers  # usage ~200Mi, well under the 384Mi limit
oc get pod -l app=rca-s18-report -o jsonpath='{.items[0].status.qosClass}{"\n"}'   # Burstable
```

Typical output (illustrative):

```
>> Memory limit now: 384Mi (request 256Mi)
>> Pod restarts: 0 (new pod, stable)
rca-s18-report-5f8b7d9c64-q7w2n   1/1   Running   0   4m
NAME                              CPU(cores)   MEMORY(bytes)
rca-s18-report-5f8b7d9c64-q7w2n   2m           202Mi
```

## 8. Prevention (what would stop this happening again)

- **Right-size from data:** measure peak working set in a load test and in production metrics, then set limit = peak + headroom and request = typical use. Review it after every major release.
- **Alert on early warning**, not after the kill: working set above ~85% of the limit for several minutes, and any increase in container restarts with `OOMKilled` as the last reason (`kube_pod_container_status_last_terminated_reason`).
- **Project guard-rails:** a `LimitRange` with sensible default requests/limits and a `ResourceQuota`, so unconfigured workloads don't run unbounded.
- **Runtime-aware settings:** for JVM, Node.js or other runtimes with their own heap, set the heap in proportion to the container limit (not to the node's RAM), and leave room for non-heap memory.
- **Load-test in a lab project** with the production limits before go-live; the "worked in the test cluster" gap is usually a lighter test dataset.
- **Runbook note for on-call:** "log just stops + restarts → check Last State before anything else".

## 9. Evidence to capture when I run it (for the RCA)

- [ ] `oc get pods -w` showing the OOMKilled → restart → CrashLoopBackOff sequence, with timestamps.
- [ ] `oc describe pod` Last State: `Reason: OOMKilled`, `Exit Code: 137`, start/finish times.
- [ ] `oc logs --previous`: the log ends abruptly.
- [ ] The resources JSON before and after the fix.
- [ ] `oc adm top pod --containers` just before a kill and after the fix.
- [ ] If I have admin: the kernel `Memory cgroup out of memory` line from `journalctl -k` on the node (with the node name sanitised) and the cgroup path in it.
- [ ] Optional: from `oc debug node` → `chroot /host`, the container's limit in the cgroup (`memory.max` under the pod's slice, cgroup v2), to connect the YAML limit to the kernel setting.
- [ ] The `oc adm inspect` folder listing (I look at it, I don't commit it: it can hold sensitive data).
- [ ] How long it took me to get to the root cause with the timer on.
- [ ] Any difference from the illustrative output above (image name, exact timings, wording).

## 10. Interview: "Walk me through how you'd troubleshoot …" (a 60-second answer)

> "The app restarts under load and the logs show nothing. First I check `oc get pods` for restarts, then `oc describe pod` and look at Last State: `OOMKilled`, exit code 137, so the kernel killed it for memory, and that is why the log just stops. Then I decide whose memory ran out: the node's or the container's. The node shows no MemoryPressure and the kernel log says 'Memory cgroup out of memory', so it was the container's own limit. I compare the limit with real usage from `oc adm top` and the metrics: limit 128Mi, working set around 200Mi. I fix it by sizing the limit from the measured peak with headroom and a request near typical use, then verify the restarts stop. If usage grew without bound under a bigger limit, I'd treat it as a leak and escalate to the developers. To prevent it, I use right-sizing from load tests, alerts at 85% of the limit, and a LimitRange and quota in the project."

### The 2-minute case explanation (to a senior support engineer)

- **Symptom:** a report service restarted a few minutes into a batch run, causing 502s; `oc logs` showed nothing; both replicas behaved the same way; nodes were `Ready`.
- **Data collected:** a targeted `oc adm inspect` of the project, events, `oc get co` to rule out cluster health, previous-container logs, and Last State of the pod. For the node view I used `oc debug node` → `chroot /host` → `journalctl -k` for OOM lines, and `journalctl -u kubelet` / `-u crio` for the restart decisions. I did not need a full must-gather or sosreport because nothing pointed beyond one workload.
- **Root cause:** Last State said `OOMKilled`, exit 137; the kernel log said `Memory cgroup out of memory`; the node had no memory pressure; the memory limit was 128Mi against a working set of about 200Mi. It was a container-level OOM from an undersized limit. Liveness-probe kills were ruled out because there were no `Unhealthy` events.
- **Fix:** raised the limit to 384Mi and the request to 256Mi (peak plus headroom) and checked the quota; rolled out and watched restarts stay at zero for several minutes while usage plateaued near 200Mi.
- **Prevention:** right-size from load-test and production metrics, alert at 85% of the limit and on `OOMKilled` restarts, project LimitRange and quota defaults, and set runtime heap settings relative to the container limit.

**Follow-up questions a panel might ask:**

1. *"How do you tell a container OOM from a node-level OOM?"* A container OOM shows `OOMKilled` in the pod's Last State and a `Memory cgroup out of memory` kernel message, and the node is healthy. A node-level problem shows `MemoryPressure=True`, kubelet evictions (`Evicted: The node was low on resource: memory`), a plain `Out of memory` kernel message, and usually several pods on the same node affected. BestEffort pods and pods using more than their request go first.
2. *"Why does the kernel kill the process instead of slowing it down like CPU?"* CPU is compressible: the scheduler can throttle a process with CFS quota. Memory is not: pages in use cannot be taken back without losing data, so once reclaim fails and the cgroup is at its limit, the only option is the OOM killer.

### Customer update (to post on the case)

> **Update:** We found the cause of the restarts. The report-generator container was killed by the kernel for exceeding its 128Mi memory limit (reason `OOMKilled`, exit 137), which is why the log stopped without an error. The nodes were healthy and not under memory pressure.
> **Done:** we raised the memory limit to 384Mi and the request to 256Mi, based on the observed ~200Mi peak. The pods have run without restarts since the rollout.
> **Next:** please re-run the morning batch and confirm. We recommend sizing limits from load-test data and adding an alert at 85% of the limit. If memory keeps growing without levelling off, we'd treat it as an application leak and need a heap profile from your developers.

## 11. Clean up

```bash
oc delete deployment rca-s18-report
# or, if the project was only for this: oc delete project rca-s18-lab
rm -rf inspect.local.*      # the oc adm inspect output, if I collected it
```

## Sources

- Kubernetes docs: [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) (memory limits are enforced by the kernel; exceeding the limit can get the container OOM-killed; memory is not compressible like CPU)
- Kubernetes docs: [Assign Memory Resources to Containers and Pods](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) (the `OOMKilled` reason when a container exceeds its limit)
- Kubernetes docs: [Node-pressure Eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/) (kubelet eviction versus kernel OOM kill, the `Evicted` message)
- Red Hat OpenShift Container Platform 4.18 documentation, Support: [Gathering data about your cluster](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/support/gathering-cluster-data) (`oc adm must-gather`, `oc adm inspect`, `oc adm node-logs`, sosreport/toolbox on RHCOS nodes)
- Red Hat Customer Portal: [How to provide a sos report from a RHEL CoreOS OpenShift 4 node](https://access.redhat.com/solutions/5065411) (login may be required)
- The kernel log wording (`Memory cgroup out of memory`) and the exact paths inside `oc adm inspect` output are from my own working knowledge and can vary by version; I'll replace them with what my cluster actually shows.
- The 1.5× headroom is my own rule of thumb for a lab, not a Red Hat rule.
