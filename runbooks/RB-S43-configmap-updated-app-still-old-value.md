# RB-S43: ConfigMap updated, but the app still uses the old value

| Field | Value |
|---|---|
| **Scenario** | [S43](../scenarios/DO180-RCA-scenario-bank.md) |
| **Area** | Configuration · ConfigMaps · Env vars vs mounted files · Rollouts |
| **Lab** | 🟢 own project |
| **Status** | 📋 Ready to run (not yet run on my cluster) |
| **Time** | ~30–45 min |

> A runbook is a **plan**, not a record. Once I've run it on my lab and captured real output, it becomes `rca/RCA-0NN-*.md` and this status becomes ✅ Done → RCA-0NN.
>
> **EX280 angle:** injecting ConfigMaps into applications as env vars and as volumes, and knowing how each behaves when the ConfigMap changes, is core application-configuration work.
>
> All command output below is **typical output (illustrative)**, not captured from my cluster.

## 1. The ticket (as it would arrive)

> "We switched the app from `blue` to `green` mode by editing the ConfigMap an hour ago. `oc get configmap` shows the new value, nothing was restarted, and the app still behaves as `blue`. Did the change not apply?"

## 2. Reproduce safely (🟢)

Work only in my own project; every object is named `rca-s43-*`. Helpers are in [`scripts/RB-S43/`](../scripts/RB-S43/) and refuse to run in `default`, `openshift-*` or `kube-*`.

```bash
oc new-project rca-s43-lab        # or reuse my own lab project
./scripts/RB-S43/break.sh         # healthy app + ConfigMap change blue -> green
```

By hand, if I'd rather type it:

```bash
oc create configmap rca-s43-config \
  --from-literal=APP_MODE=blue \
  --from-literal=app.properties="mode=blue"
# Deployment rca-s43-web (ubi9/httpd-24, 1 replica) reads the SAME ConfigMap two ways:
#   env var  APP_MODE          <- configMapKeyRef  rca-s43-config / APP_MODE
#   volume   /config/app.properties <- configMap volume rca-s43-config
oc get configmap rca-s43-config -o yaml > rca-s43-backup.yaml    # backup before the change
oc patch configmap rca-s43-config --type=merge \
  -p '{"data":{"APP_MODE":"green","app.properties":"mode=green"}}'
```

Using one ConfigMap two ways is the point: it lets me see both behaviours side by side.

## 3. What you'll see

```
$ oc get configmap rca-s43-config -o jsonpath='{.data.APP_MODE}{"\n"}'
green

$ oc exec deployment/rca-s43-web -- printenv APP_MODE
blue                                   <- stale, even after hours

$ oc exec deployment/rca-s43-web -- cat /config/app.properties
mode=green                             <- already updated (after up to ~1-2 minutes)
```

Key observations:

- The ConfigMap object is correct; the **pod** is out of date. The change was saved, it just never reached the running process's environment.
- The **same ConfigMap** gives two different answers inside one container: the env var is old, the mounted file is new. That contrast is the whole diagnosis.
- The pod has no restarts and an old `startTime`; nothing in `oc get pods` looks broken. This is a silent failure, which is why it gets reported as "did it apply?".

## 4. Triage, outside-in

| # | Command | What it tells you |
|---|---|---|
| 1 | `oc get configmap rca-s43-config -o yaml` | Is the new value really saved in the object? (It is, so the problem is not the edit.) |
| 2 | `oc get pods -l app=rca-s43-web -o wide` | Pod age and restart count: an old pod with 0 restarts means the container started before the change. |
| 3 | `oc exec deployment/rca-s43-web -- printenv APP_MODE` | What the running process actually sees in its environment. |
| 4 | `oc get deployment rca-s43-web -o jsonpath='{.spec.template.spec.containers[0].env}'` | **How** the value reaches the container: `valueFrom.configMapKeyRef` (or `envFrom`) means env var, read once at container start. |
| 5 | `oc get deployment rca-s43-web -o jsonpath='{.spec.template.spec.volumes}'` | Or is it a `configMap` volume? Those are refreshed by the kubelet while the pod runs. |
| 6 | `oc exec deployment/rca-s43-web -- cat /config/app.properties` | Compare the file with the env var: new file + old env var proves the mechanism. |
| 7 | `oc rollout history deployment/rca-s43-web` | No new revision since the ConfigMap edit. A ConfigMap change does not touch the pod template, so the Deployment sees nothing to roll out. |

Look-alikes to rule out before blaming env vars:

- **`subPath` mounts** never receive updates. If the file is mounted with `subPath`, it is stale for the same reason as an env var, even though it is "a file". Check `volumeMounts[].subPath`.
- **Immutable ConfigMaps** (`immutable: true`) reject edits altogether, so the "change" would have failed with an error rather than been saved.
- The application itself may **read the file only once at startup** (or cache it). The kubelet updates the file, but the app never re-reads it. `ls -l /config/` and the file's modification behaviour won't show that; the app's documentation or logs do.
- Mounted ConfigMap updates are **not instant**: the kubelet syncs periodically and the volume has its own cache, so allow a minute or two before concluding anything.

## 5. Root cause(s)

Environment variables are resolved **once, when the container is created**. The kubelet copies the ConfigMap value into the container's environment at that moment and never touches it again; a running process's environment cannot be changed from outside. Editing the ConfigMap changes an API object but not the pod template, so the Deployment controller sees no difference and creates no new pods.

A ConfigMap mounted as a **volume** behaves differently: the kubelet periodically refreshes the files (via a symlink swap), so the file changes without a restart. That is true only if there is no `subPath`, and the application still has to re-read it.

5 Whys: app shows old value → pod still has the old environment → env was built at container start → nothing triggered a new pod → a ConfigMap edit doesn't change the pod template.

## 6. Fix

Make the pods restart so they read the current values:

```bash
oc rollout restart deployment/rca-s43-web
oc rollout status deployment/rca-s43-web
# or: ./scripts/RB-S43/fix.sh
```

`rollout restart` stamps a `restartedAt` annotation into the pod template, which creates a new ReplicaSet and does a normal rolling update, so a Deployment with several replicas and a working readiness probe restarts without downtime. Deleting pods by hand also works but skips the rolling-update safeguards.

If the app can re-read its config file, a restart isn't needed for **mounted** values; reload the app instead (a signal, an endpoint, or whatever the app supports).

## 7. Verify

```bash
oc exec deployment/rca-s43-web -- printenv APP_MODE          # green
oc exec deployment/rca-s43-web -- cat /config/app.properties # mode=green
oc get pods -l app=rca-s43-web                               # new pod, recent AGE
oc rollout history deployment/rca-s43-web                    # a new revision exists
./scripts/RB-S43/verify.sh                                   # runs the above
```

Typical output (illustrative):

```
== Env var as seen inside the running container
green
== Mounted file as seen inside the running container
mode=green
```

## 8. Prevention (what would stop this happening again)

- **Make the config change a pod-template change.** Generate ConfigMaps with a content hash in the name (for example Kustomize `configMapGenerator`) so that editing the config produces a new name, which changes the Deployment and rolls it out automatically. Helm charts commonly do the same with a checksum annotation.
- **Make "edit config" and "restart" one pipeline step**, so nobody has to remember the second half.
- **Document, per application, which settings are env vars (restart needed) and which are files (hot reload, if the app supports it).**
- **Use `immutable: true` ConfigMaps** with versioned names for production config, so in-place edits can't silently diverge from what is running.
- **Expose the running config** (a version or config-hash line in the logs or a status endpoint) so "which value is live?" has a one-command answer.
- Avoid `subPath` for config that is expected to change at runtime.

## 9. Evidence to capture when I run it (for the RCA)

- [ ] `oc get configmap rca-s43-config -o yaml` showing the new value
- [ ] `printenv APP_MODE` still showing the old value, with the pod age
- [ ] `cat /config/app.properties` showing the new value, and roughly how long the file took to update
- [ ] `oc rollout history` showing no new revision after the ConfigMap edit
- [ ] The `rollout restart` command, new ReplicaSet/pod, and the corrected `printenv`
- [ ] Bonus: change the volume to use `subPath` and record that the file now stays stale too
- [ ] Bonus: switch the env var to `envFrom` and confirm it behaves the same
- [ ] Bonus: set `immutable: true` and record what the next edit does
- [ ] Time to detect, time to fix, and which command found the cause fastest
- [ ] Sanitise per the [checklist](../SANITISE-CHECKLIST.md) before committing

## 10. Interview: "The ConfigMap is updated but the app still uses the old value. Walk me through it." (a 60-second answer)

"First I confirm the ConfigMap really holds the new value, so I know the edit isn't the problem. Then I look at how the app consumes it. If it's an environment variable, whether `configMapKeyRef` or `envFrom`, the value was copied into the container when it started and never refreshes, and editing a ConfigMap doesn't change the pod template, so the Deployment doesn't roll. I prove it by comparing `printenv` inside the pod with the ConfigMap. The fix is `oc rollout restart` on the Deployment, which does a normal rolling update. If it's a mounted file, the kubelet does refresh it, within a minute or two, unless it's a `subPath` mount, which never updates, or the app only reads the file at startup. To prevent it, I'd put a hash in the ConfigMap name or a checksum annotation so config changes trigger a rollout, and I'd treat production ConfigMaps as immutable and versioned."

## 11. Clean up

```bash
oc delete deployment rca-s43-web
oc delete configmap rca-s43-config
rm -f rca-s43-backup.yaml
# or, if the project was only for this: oc delete project rca-s43-lab
```

## Sources

- Kubernetes docs: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) (mounted ConfigMaps are updated automatically; env vars and `subPath` mounts are not; immutable ConfigMaps)
- Kubernetes docs: [Configure a Pod to use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- Kubernetes docs: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) (a rollout is triggered only by a change to the pod template; `kubectl rollout restart`)
- Red Hat OpenShift Container Platform 4.18 documentation: [docs.redhat.com](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18) (config maps, and `oc rollout restart` in the CLI reference)
- Mounted-file refresh timing depends on the kubelet sync period and cache; I'll record the real delay on my cluster.
