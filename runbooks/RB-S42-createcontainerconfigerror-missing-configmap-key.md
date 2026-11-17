# RB-S42: Pod won't start after a config change (`CreateContainerConfigError`)

| Field | Value |
|---|---|
| **Scenario** | [S42](../scenarios/DO180-RCA-scenario-bank.md) |
| **Area** | Configuration · ConfigMaps · Secrets · Pod start-up |
| **Lab** | 🟢 own project |
| **Status** | 📋 Ready to run (not yet run on my cluster) |
| **Time** | ~30–45 min |

> A runbook is a **plan**, not a record. Once I've run it on my lab and captured real output, it becomes `rca/RCA-0NN-*.md` and this status becomes ✅ Done → RCA-0NN.
>
> **EX280 angle:** injecting ConfigMaps and Secrets into an application (env vars and volumes) is core application-configuration work; being able to diagnose a broken reference quickly is the practical half of that skill.
>
> All command output below is **typical output (illustrative)**, not captured from my cluster.

## 1. The ticket (as it would arrive)

> "We changed the app's configuration this afternoon and the new version never came up. The pod is stuck, `oc get pods` says `CreateContainerConfigError`, and the release is 'in progress'. The old version is still serving, but we can't finish the rollout."

## 2. Reproduce safely (🟢)

Work only in my own project; every object is named `rca-s42-*`. Helpers are in [`scripts/RB-S42/`](../scripts/RB-S42/) and refuse to run in `default`, `openshift-*` or `kube-*`.

```bash
oc new-project rca-s42-lab            # or reuse my own lab project
./scripts/RB-S42/break.sh a           # builds a healthy app, backs it up, injects fault A
```

What the script does, by hand, if I'd rather type it:

```bash
oc create configmap rca-s42-config --from-literal=APP_MODE=lab
oc create secret generic rca-s42-db --from-literal=DB_PASSWORD=not-a-real-password
# Deployment rca-s42-web (1 replica, ubi9/httpd-24) with two env vars:
#   APP_MODE    <- configMapKeyRef  rca-s42-config / APP_MODE
#   DB_PASSWORD <- secretKeyRef     rca-s42-db     / DB_PASSWORD
oc get deployment rca-s42-web -o yaml > rca-s42-backup.yaml     # backup before breaking
```

Three variants of the same symptom (run one at a time; `fix.sh` resets all three):

| Variant | Fault injected | Command |
|---|---|---|
| A | ConfigMap **name** typo (`rca-s42-confg`) | `./scripts/RB-S42/break.sh a` |
| B | ConfigMap **key** typo (`APP_MODEE`) | `./scripts/RB-S42/break.sh b` |
| C | Secret **name** typo (`rca-s42-dbb`) | `./scripts/RB-S42/break.sh c` |

## 3. What you'll see

```
$ oc get pods -l app=rca-s42-web
NAME                           READY   STATUS                       RESTARTS   AGE
rca-s42-web-6d9c7f8b5-x2k4q    1/1     Running                      0          6m
rca-s42-web-7b5d4c9f6-m8w2z    0/1     CreateContainerConfigError   0          40s

$ oc rollout status deployment/rca-s42-web
Waiting for deployment "rca-s42-web" rollout to finish: 1 old replicas are pending termination...
```

Key observations:

- The **new** pod is scheduled to a node, but its container is never created.
- The **old** pod keeps serving. With one replica and the default rolling-update settings, the Deployment won't remove the old pod until the new one is Ready, so users see no outage, but the rollout hangs. If it stays stuck, the Deployment eventually reports `ProgressDeadlineExceeded` (default 600 s).
- `oc logs` on the new pod shows nothing useful because the container never started. This is the clue that the problem is **before** the application, in how the container is configured.

## 4. Triage, outside-in

| # | Command | What it tells you |
|---|---|---|
| 1 | `oc get pods` | Status `CreateContainerConfigError` (not `CrashLoopBackOff`): the container was never created, so the app itself is not the problem. |
| 2 | `oc rollout status deployment/rca-s42-web` | Confirms it's a rollout that's stuck, and that the old pod is still up. |
| 3 | `oc describe pod <new-pod>` → **Events** | The decisive step: the Warning event names the exact missing object or key (see below). |
| 4 | `oc get events --sort-by=.lastTimestamp` | Same messages project-wide, in order; useful if the pod has already been replaced. |
| 5 | `oc get configmap,secret` | Does the object named in the event exist **in this project**? References are namespace-local. |
| 6 | `oc get configmap rca-s42-config -o yaml` (or `oc describe`) | Does the **key** named in the event exist under `data:`? Keys are case-sensitive. |
| 7 | `oc get deployment rca-s42-web -o jsonpath='{.spec.template.spec.containers[0].env}'` | What the pod template actually references, to compare with step 5/6. |
| 8 | `oc logs <new-pod>` | Expected: empty or "container is waiting to start". Confirms the app never ran. |

Typical events (illustrative), one per variant:

```
# Variant A – ConfigMap name wrong
Warning  Failed  kubelet  Error: configmap "rca-s42-confg" not found

# Variant B – ConfigMap exists, key wrong
Warning  Failed  kubelet  Error: couldn't find key APP_MODEE in ConfigMap rca-s42-lab/rca-s42-config

# Variant C – Secret name wrong
Warning  Failed  kubelet  Error: secret "rca-s42-dbb" not found
```

Two look-alikes to rule out, because they give different symptoms:

- A **volume** mount of a missing ConfigMap/Secret does *not* give `CreateContainerConfigError`. The pod sits in `ContainerCreating` with a `FailedMount` event (`MountVolume.SetUp failed … configmap "x" not found`). Same root idea, different status.
- `CreateContainerConfigError` also appears for other config problems, for example a `runAsNonRoot` security setting combined with an image whose user is non-numeric. The **event text** tells them apart, which is why step 3 is always `describe`, never a guess.

## 5. Root cause(s)

A pod-template reference points at a ConfigMap or Secret (or a key inside it) that does not exist **in the pod's namespace**. Before it can create the container, the kubelet has to resolve every `configMapKeyRef`/`secretKeyRef` into a concrete value to build the container's environment; if that lookup fails, it reports `CreateContainerConfigError` and retries.

Typical reasons behind a "config change":

1. A **typo** in the object name or the key (keys are case-sensitive).
2. The ConfigMap/Secret was created in a **different project** (wrong `oc project` at the time).
3. The object was **renamed or deleted** but the Deployment still references the old name.
4. The Deployment was applied **before** the ConfigMap/Secret (ordering in a manifest set or pipeline).

5 Whys: stuck rollout → new pod never starts → kubelet can't build the environment → referenced key/object not found → the config change and the object it refers to weren't validated together.

## 6. Fix

Pick the one that matches what the event said.

**Missing object or key (the reference is right, the object is wrong):** create it and the kubelet's retry picks it up; no need to recreate the pod.

```bash
oc create configmap rca-s42-config --from-literal=APP_MODE=lab        # if the ConfigMap is missing
oc create secret generic rca-s42-db --from-literal=DB_PASSWORD=...     # if the Secret is missing
oc patch configmap rca-s42-config -p '{"data":{"APP_MODE":"lab"}}'     # if only the key is missing
```

**Wrong reference in the Deployment (the object is right, the reference is wrong):** correct the reference; that changes the pod template, so a new ReplicaSet rolls out.

```bash
oc edit deployment rca-s42-web            # fix the name/key in env[].valueFrom
# or put everything back:
./scripts/RB-S42/fix.sh
# or, if the previous revision was good and I just want service restored:
oc rollout undo deployment/rca-s42-web
```

If the key is genuinely optional, say so explicitly instead of letting the pod fail: `configMapKeyRef: { name: ..., key: ..., optional: true }`. A missing optional key simply leaves the variable unset. Use this only when the app really works without it.

## 7. Verify

```bash
oc get pods -l app=rca-s42-web                       # 1/1 Running, only one pod
oc rollout status deployment/rca-s42-web             # "successfully rolled out"
oc exec deployment/rca-s42-web -- printenv APP_MODE  # lab
oc get events --field-selector type=Warning          # nothing new for the pod
./scripts/RB-S42/verify.sh                           # runs all of the above
```

Typical output (illustrative):

```
deployment "rca-s42-web" successfully rolled out
lab
```

## 8. Prevention (what would stop this happening again)

- **Create config before the workload** that uses it, in the same change set and in that order (or the same Helm/Kustomize release).
- **Generate ConfigMaps with a content hash in the name** (for example Kustomize `configMapGenerator`) so a config change is also a pod-template change and typos in references are caught at render time.
- **Pre-flight check in CI/CD:** after rendering manifests, assert that every referenced ConfigMap/Secret and key exists. A client-side or server-side dry run does *not* check this; the API accepts a reference to something that doesn't exist yet.
- **Deploy with `oc rollout status --timeout=…`** and fail the pipeline if it times out; the stuck-rollout behaviour is what keeps users safe, so the pipeline must notice it.
- Watch for pods in `CreateContainerConfigError` in alerting (kube-state-metrics exposes waiting reasons), so a failed release pages someone instead of sitting there.
- Keep `optional: true` for genuinely optional settings only; don't use it to silence errors.

## 9. Evidence to capture when I run it (for the RCA)

- [ ] `oc get pods` showing the old pod `Running` and the new pod `CreateContainerConfigError`
- [ ] `oc describe pod <new-pod>` Events for each variant A, B and C (exact wording)
- [ ] `oc rollout status` stuck message; note how long it waited
- [ ] `oc get configmap rca-s42-config -o yaml` next to the failing reference (typo visible)
- [ ] The fix command and `oc rollout status` success
- [ ] `oc exec deployment/rca-s42-web -- printenv APP_MODE` showing the value
- [ ] Bonus: mount the missing ConfigMap as a **volume** instead and record the `ContainerCreating` / `FailedMount` difference
- [ ] Bonus: set `optional: true` on the key and record what changes
- [ ] Time to detect, time to fix, and which command found the cause fastest
- [ ] Sanitise per the [checklist](../SANITISE-CHECKLIST.md) before committing

## 10. Interview: "Walk me through how you'd troubleshoot a pod stuck in CreateContainerConfigError" (a 60-second answer)

"`CreateContainerConfigError` means the kubelet couldn't even build the container's configuration, so the application never ran and `oc logs` will be empty. I go straight to `oc describe pod` and read the Events: the message names exactly what's missing, either a ConfigMap or Secret that doesn't exist in that namespace, or a key inside one that does. Then I compare it with `oc get configmap,secret` in the same project and the env references in the Deployment, looking for typos, case differences, or an object created in the wrong project. If the reference is right I create the missing object or key and the kubelet retries on its own; if the reference is wrong I fix the Deployment, or `oc rollout undo` to restore service. Because it's a rolling update, the old pod usually keeps serving, so there's no outage but the rollout is stuck. To prevent it, I create config before the workload, use hashed ConfigMap names, and check references and rollout status in the pipeline. I'd also tell it apart from a missing *volume*, which shows up as `ContainerCreating` with a `FailedMount` event instead."

## 11. Clean up

```bash
oc delete deployment rca-s42-web
oc delete configmap rca-s42-config
oc delete secret rca-s42-db
rm -f rca-s42-backup.yaml
# or, if the project was only for this: oc delete project rca-s42-lab
```

## Sources

- Kubernetes docs: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) (including `optional` references and namespace scope) and [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- Kubernetes docs: [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- Kubernetes docs: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) (rolling update behaviour, progress deadline)
- Red Hat OpenShift Container Platform 4.18 documentation: [docs.redhat.com](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18) (nodes / pods and config maps sections)
- The exact event wording varies slightly between Kubernetes versions; I'll replace the illustrative messages with what my cluster actually prints.
