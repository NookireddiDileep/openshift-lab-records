# DO180 – Real-World Problem Statements (RCA Scenario Bank)

These are troubleshooting scenarios mapped to the DO180 chapters, written the way they
arrive in real life: as a ticket, an alert, or an interviewer's "walk me through it".
Each one becomes an **RCA** in [`rca/`](../rca/), written with the [RCA template](../templates/RCA-TEMPLATE.md).

**Lab column:**
- 🟢 You can break and fix it yourself in your own namespace.
- 🟡 Partly reproducible: it needs a specific StorageClass, a quota set by an admin, a second user, and so on.
- 🔴 Needs cluster-admin. Write it as an **interview walkthrough RCA** (symptoms → triage commands → likely causes → fix → prevention), without breaking a shared cluster.

**Rules for breaking things safely:**
- Work only in your own project.
- Name the objects after the scenario, for example `rca-s14-*`.
- Back up before every change: `oc get <obj> -o yaml > backup.yaml`.
- Clean up afterwards.

---

## Ch 1–2 · Cluster, nodes, CLI and access

| # | Problem statement (as reported) | What you'll see | Likely root cause(s) | Lab | Status |
|---|---|---|---|---|---|
| S01 | "The cluster is broken after last night's upgrade, and the console won't load." | `oc get co` shows a ClusterOperator `DEGRADED=True` (authentication, ingress, console) | Router pods unschedulable, expired certificate, OAuth misconfiguration, a MachineConfigPool stuck updating | 🔴 | |
| S02 | "One worker shows NotReady, and its pods are being moved." | `oc get nodes` NotReady; node conditions | kubelet or CRI-O stopped, DiskPressure, expired kubelet certificate, network down | 🔴 | |
| S03 | "Two nodes went NotReady after a reboot, though they are powered on." | `oc get csr` shows Pending entries | Kubelet serving or client CSRs not approved after a long downtime | 🔴 | |
| S04 | "Pods on node X keep getting Evicted." | `Evicted` pods; `DiskPressure`/`MemoryPressure` on the node | Node disk filled by logs or images; BestEffort pods evicted first | 🔴 | |
| S05 | "`oc debug node` works but `crictl`/`journalctl` say 'command not found'." | A shell on the node, but no host binaries | Forgot `chroot /host` | 🔴 | |
| S06 | "`oc get pods` shows nothing, yet the app is up." | Empty list | Wrong project or kubeconfig context (`oc project`, `oc config get-contexts`) | 🟢 | |
| S07 | "My `oc` session suddenly says Unauthorized." | `error: You must be logged in` / 401 | Expired token, wrong cluster in the context, kubeadmin removed | 🟢 | |
| S08 | "A new user can log in but can't see the team's project." | `Forbidden: cannot list pods` | No RoleBinding in that namespace (`oc auth can-i`, `oc get rolebinding`) | 🟡 | |
| S09 | "Nobody can log in to the console; an htpasswd user was just added." | Login page error / OAuth pods restarting | Bad htpasswd secret format, the secret name doesn't match the OAuth CR | 🔴 | |

## Ch 3 · Pods, images and security (SCC)

| # | Problem statement (as reported) | What you'll see | Likely root cause(s) | Lab | Status |
|---|---|---|---|---|---|
| S10 | "A new deployment isn't starting: ImagePullBackOff." | `manifest unknown` in the events | Typo in the tag, or the tag is case-sensitive | 🟢 | Done → [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md) |
| S11 | "The image from our private registry won't pull." | `unauthorized: authentication required` | No pull secret, or the secret isn't linked to the ServiceAccount (`oc secrets link default <s> --for=pull`) | 🟡 | |
| S12 | "The image name works on my laptop but not on the cluster." | `ErrImagePull`, short-name resolution error / registry unreachable | Unqualified image name; registry blocked; proxy | 🟢 | |
| S13 | "Pulls from Docker Hub started failing this morning." | `toomanyrequests` | Docker Hub rate limit → mirror to an internal registry or Quay | 🔴 | |
| S14 | "Works on Docker / plain K8s, CrashLoopBackOff on OpenShift." | `Permission denied` / `bind: port 80` in `logs --previous` | Image assumes root or a fixed UID; restricted-v2 assigns a random UID | 🟢 | Done → [RCA-004](../rca/RCA-004-image-tag-and-root-only-httpd.md) |
| S15 | "The app crashes writing its cache: Permission denied on /var/app." | CrashLoopBackOff; log shows the write failing | Directory not group-writable for GID 0 → fix the image (`chgrp -R 0 && chmod -R g=u`) or mount a volume | 🟢 | |
| S16 | "The pod restarts every few seconds and the logs are empty." | CrashLoopBackOff, exit code 0/1/127 | Wrong `command`/`args`; process exits right away (nothing long-running) | 🟢 | |
| S17 | "The database pod keeps crashing right after deploy." | Logs: `You must specify one of MYSQL_...` | Required env vars or Secret missing | 🟢 | Seen in [OCP-011](../stories/OCP-011-mysql-database-from-docker-image.md) |
| S18 | "The app dies under load with no error in the logs." | `OOMKilled`, exit code 137 in Last State | Memory limit lower than the app's working set (JVM heap vs limit) | 🟢 | |
| S19 | "The container crashes too fast to `oc rsh` into it." | CrashLoopBackOff | Debug technique: `oc debug deploy/x` starts a copy with a shell | 🟢 | |
| S20 | "Someone deleted the pod and the app never came back." | Pod gone, nothing recreated | A bare Pod with no controller → use a Deployment | 🟢 | Seen in [OCP-001](../stories/OCP-001-bare-pod-no-self-heal.md) |
| S21 | "The pod shows 1/2 Ready and `oc logs` shows nothing wrong." | Multi-container pod | Logs were read from the wrong container → `oc logs -c <sidecar>` | 🟢 | |
| S22 | "The pod has been stuck Terminating for an hour." | `Terminating` | Finalizer, node unreachable, a process ignoring SIGTERM | 🟡 | |
| S23 | "`exec format error` on start." | CrashLoopBackOff, that single log line | Image built for arm64 running on amd64 nodes | 🟡 | |
| S24 | "Audit finding: anyuid was granted to the `default` ServiceAccount." | `oc adm policy who-can use scc anyuid` | Over-privilege → dedicated SA + least-privilege SCC | 🔴 | |
| S25 | "Rootless podman can't pull or build on the bastion." | `potentially insufficient UIDs or GIDs` | No subuid/subgid ranges for the user | 🟢 | Done → [RCA-001](../rca/RCA-001-rootless-podman-subuid.md) |

## Ch 4 · Deployments, services, routes and networking

| # | Problem statement (as reported) | What you'll see | Likely root cause(s) | Lab | Status |
|---|---|---|---|---|---|
| S26 | "Application unreachable via its URL." | Route HTTP 503 / 000 | Host typo, Route → wrong Service, selector ≠ pod labels | 🟢 | Done → [RCA-003](../rca/RCA-003-route-unreachable-three-faults.md) |
| S27 | "Route gives 503, pods are Running." | `oc get endpoints` → `<none>` | Service selector doesn't match the pod labels | 🟢 | Part of RCA-003 |
| S28 | "Route gives 502/503, endpoints exist." | Endpoints listed; curl to the pod port fails | Service `targetPort` ≠ container port | 🟢 | |
| S29 | "`curl localhost` inside the pod works, but not through the Service." | Connection refused on the pod IP | App bound to `127.0.0.1` instead of `0.0.0.0` | 🟢 | |
| S30 | "Every 3rd–4th request fails." | Intermittent errors | One replica broken and no readiness probe, so it stays in the endpoints | 🟢 | |
| S31 | "New route returns 503 for a few seconds after creation." | Brief 503, then 200 | Router reload interval (expected) | 🟢 | Seen in [OCP-017](../stories/OCP-017-blue-green-deployment.md) |
| S32 | "Service name doesn't resolve from another project." | `could not resolve host` | Short name only works in the same namespace → `<svc>.<ns>.svc.cluster.local`; or a NetworkPolicy | 🟢 | |
| S33 | "App works over HTTPS but plain HTTP fails / doesn't redirect." | HTTP 503 or no redirect | Edge route with `insecureEdgeTerminationPolicy` unset → `Redirect` | 🟢 | |
| S34 | "Passthrough route fails, edge route works." | TLS handshake error | App doesn't serve TLS itself, or the route points at the HTTP port | 🟢 | |
| S35 | "Re-encrypt route gives 503." | Router can't verify the backend | `destinationCACertificate` missing / service-serving cert not used | 🟢 | |
| S36 | "Deployment shows 0/3, but no pods exist at all." | `FailedCreate` events on the ReplicaSet | Invalid pod spec (e.g. image `" "`), quota exceeded, SCC rejected | 🟢 | Seen during [OCP-008](../stories/OCP-008-imagestream-trigger-and-route.md) |
| S37 | "Users of app A sometimes see app B's page." | Mixed responses | Two Services with overlapping selectors (`app=web`) | 🟢 | |
| S38 | "The nightly CronJob didn't run." | No new Job | Schedule in UTC, `suspend: true`, `concurrencyPolicy: Forbid` with a stuck Job | 🟢 | |
| S39 | "A Job keeps retrying and never completes." | Many failed pods | App exits non-zero; `backoffLimit`; `restartPolicy` | 🟢 | |
| S40 | "After a security change, the frontend can't reach the backend." | Timeouts between pods | NetworkPolicy deny-all without an allow rule | 🟢 | |
| S41 | "An Ingress was created but no Route appeared." | `oc get route` empty | Wrong `ingressClassName`, host outside the apps domain | 🟢 | Related: [OCP-016](../stories/OCP-016-ingress-default-controller.md) |

## Ch 5 · Configuration and storage

| # | Problem statement (as reported) | What you'll see | Likely root cause(s) | Lab | Status |
|---|---|---|---|---|---|
| S42 | "The pod won't start after a config change." | `CreateContainerConfigError` | ConfigMap/Secret or a key missing (name typo) | 🟢 | |
| S43 | "The ConfigMap was updated but the app still uses the old value." | Old value in `env` | Env vars are read only at start → `oc rollout restart` (mounted files do update) | 🟢 | |
| S44 | "DB login fails with the 'correct' password from the Secret." | Auth error | Double base64 encoding, or a trailing newline (`echo` vs `echo -n`) | 🟢 | |
| S45 | "A mounted config file wiped the other files in the directory." | App can't find its default files | ConfigMap mounted over the whole directory → use `subPath` | 🟢 | |
| S46 | "PVC stuck in Pending." | `no persistent volumes available` / no SC | No default StorageClass, SC name typo | 🟢 | |
| S47 | "PVC Pending with an RWX request." | Provisioner error | SC doesn't support ReadWriteMany | 🟡 | |
| S48 | "PVC Pending, but nothing is wrong?" | `WaitForFirstConsumer` | Expected: it binds when a pod is scheduled | 🟡 | |
| S49 | "After scaling to 2, the new pod is stuck in ContainerCreating." | `Multi-Attach error` | RWO block volume + replicas on different nodes → Recreate / StatefulSet | 🟡 | |
| S50 | "All DB data was lost after a pod restart." | Empty DB | Data on the container layer / emptyDir, no PVC | 🟢 | Done → [RCA-002](../rca/RCA-002-mysql-data-loss-no-persistent-storage.md) |
| S51 | "Permission denied writing to the NFS volume." | Write fails; files owned by `nobody` | root_squash / GID squash on the export, export permissions | 🟡 | Seen in [OCP-019](../stories/OCP-019-static-pv-pvc-nfs.md) |
| S52 | "The static PV won't bind to my PVC." | PVC Pending, PV Available | Mismatch in size / accessMode / `storageClassName` / claimRef | 🟡 | |
| S53 | "The app crashes with 'No space left on device'." | Write errors | PVC full → expand the PVC (if `allowVolumeExpansion`) or clean up | 🟡 | |
| S54 | "We deleted the StatefulSet and the storage bill didn't drop." | PVCs still Bound | StatefulSet PVCs are retained by design | 🟢 | |
| S55 | "Only web-0 is running; web-1 and web-2 never start." | web-0 not Ready | OrderedReady policy waits for each pod to be Ready | 🟢 | |

## Ch 6 · Reliability: probes, resources and scaling

| # | Problem statement (as reported) | What you'll see | Likely root cause(s) | Lab | Status |
|---|---|---|---|---|---|
| S56 | "A Java app restarts forever right after deploy." | Liveness failures before startup completes | No startupProbe / `initialDelaySeconds` too short | 🟢 | |
| S57 | "During a DB outage, all frontend pods restarted too." | Mass restarts | Liveness probe checks a dependency → it should check only the process itself | 🟢 | |
| S58 | "Pods are Running but 0/1 Ready and the route gives 503." | Readiness failing | Wrong probe path or port | 🟢 | |
| S59 | "The new pod has been Pending for 20 minutes." | `Insufficient cpu/memory` | Requests larger than free capacity on any node | 🟢 | |
| S60 | "Pod Pending: `didn't match node selector`." | `0/N nodes are available` | nodeSelector/affinity with no matching node; taints without tolerations | 🟢 | |
| S61 | "HPA isn't scaling: TARGETS shows `<unknown>`." | `<unknown>/60%` | No CPU requests on the containers / metrics not available yet | 🟢 | |
| S62 | "Load dropped an hour ago, but there are still 5 replicas." | HPA not scaling down | 5-minute scale-down stabilization (expected) | 🟢 | Seen in [OCP-023](../stories/OCP-023-hpa-cpu-autoscaling.md) |
| S63 | "The app is slow but CPU usage looks low." | High latency | CPU throttling at the limit | 🟢 | |
| S64 | "The deployment can't create pods: `exceeded quota`." | `FailedCreate` forbidden | ResourceQuota full, or pods missing requests while the quota requires them | 🟡 | |
| S65 | "Pods got resource limits we never set." | Unexpected limits / rejected pods | LimitRange defaults/max in the project | 🟡 | |
| S66 | "During node maintenance the whole app went down." | All replicas on one node | No anti-affinity / topology spread, no PDB | 🟡 | |
| S67 | "Node drain has been stuck for 30 minutes." | `Cannot evict pod` | PDB `minAvailable` = replicas | 🔴 | |

## Ch 7 · Application updates and rollouts

| # | Problem statement (as reported) | What you'll see | Likely root cause(s) | Lab | Status |
|---|---|---|---|---|---|
| S68 | "The release has been 'in progress' for 30 minutes." | `rollout status` waiting; new pods not Ready | Bad image/tag, failing readiness, quota | 🟢 | |
| S69 | "We rolled back, but the bug is still there." | `rollout undo` succeeded | The cause was a ConfigMap/Secret change, which undo doesn't revert | 🟢 | |
| S70 | "We pushed a new image to the same tag; pods still run the old code." | Old digest in the pod | Mutable tag + `IfNotPresent`, no image trigger → use digests / ImageStream triggers | 🟢 | |
| S71 | "Replicas behave differently: some have the fix, some don't." | Different digests per pod | `:latest` pulled at different times on different nodes | 🟢 | |
| S72 | "The ImageStream updated but the Deployment didn't redeploy." | No new ReplicaSet | Trigger missing, or wrong container name in `oc set triggers` | 🟢 | Related: [OCP-008](../stories/OCP-008-imagestream-trigger-and-route.md) |
| S73 | "Users saw errors during a 'zero-downtime' update." | 5xx during the rollout | No readiness probe; `maxUnavailable` too high | 🟢 | |
| S74 | "Our changes were applied, but nothing redeployed." | No new pods | Deployment is paused (`oc rollout resume`) | 🟢 | |
| S75 | "Rolling update deadlocked on the DB deployment." | New pod ContainerCreating (Multi-Attach) | RWO volume + RollingUpdate → use the Recreate strategy | 🟡 | |
| S76 | "Rollout history is useless; no change reasons are recorded." | `CHANGE-CAUSE <none>` | No `kubernetes.io/change-cause` annotation | 🟢 | Seen in [OCP-008](../stories/OCP-008-imagestream-trigger-and-route.md) |
| S77 | "`oc import-image` fails / the ImageStream tag shows an error." | `ImportError` in `oc describe is` | Registry auth, wrong reference, insecure registry | 🟡 | |

---

## How to turn a scenario into an RCA

1. **Break it** (🟢/🟡) in your own project, or for 🔴 write the walkthrough from documentation and logic.
2. **Capture the symptom** exactly as a user would see it (curl output, `oc get` status, events).
3. **Triage outside-in:** `oc get` → `oc describe` → events → `oc logs [--previous]` → `oc debug`.
4. **Root cause in one sentence**, then the fix, the verification, and prevention.
5. Add the interview line: *"Walk me through how you'd troubleshoot X."*

**Suggested order:** 🟢 Ch 3–4 first (most asked in interviews), then Ch 6 probes and resources, then Ch 5 storage, then Ch 7 rollouts, and finally the 🔴 cluster walkthroughs.
