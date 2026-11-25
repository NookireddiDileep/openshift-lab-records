# RB-S56: App restarts forever right after deploy (liveness probe kills a slow starter)

| Field | Value |
|---|---|
| **Scenario** | [S56](../scenarios/DO180-RCA-scenario-bank.md) |
| **Area** | Probes · Liveness · Startup probe · Pod lifecycle |
| **Lab** | 🟢 own project |
| **Status** | 📋 Ready to run (not yet run on my cluster) |
| **Time** | ~30–45 min |

> A runbook is a **plan**, not a record. Once I've run it on my lab and captured real output, it becomes `rca/RCA-0NN-*.md` and this status becomes ✅ Done → RCA-0NN.
>
> **EX280 angle:** configuring liveness, readiness and startup probes on a Deployment is a standard application-reliability task; being able to read a restart loop and pick the right probe is the practical half of it.
>
> All command output below is **typical output (illustrative)**, not captured from my cluster.

## 1. The ticket (as it would arrive)

> "We deployed the new Java service and it just restarts forever. `oc get pods` shows `Running` for a few seconds, then the restart count goes up again. There's nothing in the logs except the start-up banner. The same image works fine on a developer's laptop."

## 2. Reproduce safely (🟢)

Work only in my own project; the object is named `rca-s56-slow`. Helpers are in [`scripts/RB-S56/`](../scripts/RB-S56/) and refuse to run in `default`, `openshift-*` or `kube-*`.

I don't need a real Java app: a web server that waits 45 seconds before it starts listening behaves the same way from the kubelet's point of view.

```bash
oc new-project rca-s56-lab        # or reuse my own lab project
./scripts/RB-S56/break.sh         # slow-start app + an over-eager liveness probe
```

By hand, the interesting part of the Deployment is:

```yaml
containers:
  - name: web
    image: registry.access.redhat.com/ubi9/httpd-24:latest
    args: ["/bin/sh", "-c", "echo 'simulating slow start'; sleep 45; exec /usr/bin/run-httpd"]
    livenessProbe:
      httpGet: { path: /, port: 8080 }
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3        # first check at 5 s, then fails at 5/10/15 s -> killed at ~15-20 s
```

The app needs about 45 s; the probe gives up after roughly 20 s. That gap is the whole bug.

> I use `args` (not `command`) so the image's own entrypoint is kept. If the image on my cluster behaves differently, I check `oc get pod <pod> -o yaml` and adjust. I'll note whichever form actually worked.

## 3. What you'll see

```
$ oc get pods -l app=rca-s56-slow -w
NAME                            READY   STATUS    RESTARTS      AGE
rca-s56-slow-5c7d9b6f8d-k4t2m   0/1     Running   0             12s
rca-s56-slow-5c7d9b6f8d-k4t2m   0/1     Running   1 (3s ago)    28s
rca-s56-slow-5c7d9b6f8d-k4t2m   0/1     Running   2 (2s ago)    55s
rca-s56-slow-5c7d9b6f8d-k4t2m   0/1     CrashLoopBackOff   3 (1s ago)   80s
```

Key observations:

- The pod is `Running` but never `Ready` (0/1), and the **restart counter climbs on a regular rhythm** (about every 20–25 s here), not randomly.
- `oc logs` shows only the start-up banner; with `--previous` it shows the *same* banner. The app never got to the point of failing; it was **killed during start-up**.
- After several loops the status flips to `CrashLoopBackOff`: that is just the kubelet's growing back-off between restarts, not a new problem.
- The route (if there were one) would give 503, because the pod never becomes Ready.

## 4. Triage, outside-in

| # | Command | What it tells you |
|---|---|---|
| 1 | `oc get pods -w` | Running but 0/1, with a steady restart rhythm: something is killing a healthy-looking container on a timer. |
| 2 | `oc describe pod <pod>` → **Events** | The decisive step: `Unhealthy … Liveness probe failed …` followed by `Killing … failed liveness probe, will be restarted`. |
| 3 | `oc describe pod <pod>` → **Last State** | `Terminated`, `Reason: Error`, exit code `137` or `143` (the process was sent a signal). **Not** `OOMKilled`; that reason would point to memory instead. |
| 4 | `oc logs <pod> --previous` | The previous container's output: banner only, so the app was alive but still starting. |
| 5 | `oc get deployment rca-s56-slow -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'` | The numbers: `initialDelaySeconds`, `periodSeconds`, `failureThreshold`. Work out the budget: `initialDelay + period × failureThreshold`. |
| 6 | Compare that budget with real start-up time (from logs: banner → "listening") | If start-up is longer than the budget, that is the root cause. |
| 7 | `oc debug deployment/rca-s56-slow` (or `oc rsh` into a running copy) and `curl -s localhost:8080/` | Proves the endpoint works once the app is up, so the probe path and port are right and only the timing is wrong. |

Typical events (illustrative):

```
Warning  Unhealthy  kubelet  Liveness probe failed: Get "http://10.0.0.x:8080/": dial tcp 10.0.0.x:8080: connect: connection refused
Normal   Killing    kubelet  Container web failed liveness probe, will be restarted
```

`connection refused` is the giveaway: nothing was listening *yet*. Compare with a probe that gets an answer but the wrong one (`HTTP probe failed with statuscode: 404/500`), which would mean a wrong path or an unhealthy app rather than a slow start.

Look-alikes to rule out:

- **OOMKilled** (exit 137, `Reason: OOMKilled`): also 137, but the reason differs and there are no `Unhealthy` events. That is [S18](../scenarios/DO180-RCA-scenario-bank.md).
- **App crashes on its own** (non-zero exit, error in `--previous` logs): `Reason: Error` but the logs show a stack trace or config error, and no liveness events.
- **Readiness probe failing** ([S58](../scenarios/DO180-RCA-scenario-bank.md)): pod stays 0/1 but is **not restarted**. Liveness restarts; readiness only removes the pod from the Service.

## 5. Root cause(s)

The **liveness probe starts judging the container before the application can answer**. Its total patience (`initialDelaySeconds + periodSeconds × failureThreshold`, about 20 s here) is shorter than the real start-up time (about 45 s). The kubelet sees three failures, concludes the container is dead and restarts it, so the app is killed every time just before it would have been ready, and it can never get through its start-up. The same image looked fine on a laptop because nothing was watching the clock.

Typical reasons behind a "restarts forever after deploy" ticket:

1. A Java (or other heavy) app whose start-up takes longer than the probe budget, often worse on a cluster with CPU limits and a cold node than on a laptop.
2. `initialDelaySeconds` was set once, for a fast version, and the app has since got slower (more beans, bigger cache warm-up, a migration on boot).
3. CPU **limit** too low, so start-up is throttled and takes several times longer than expected.
4. Using one probe for two jobs: "is it still starting?" and "has it hung?".

5 Whys: restarts forever → container killed by kubelet → liveness failed 3×  → app wasn't listening yet → budget (≈20 s) < start-up time (≈45 s) → the probe was tuned without measuring start-up and there was no separate way to express "still starting".

## 6. Fix

The right tool is a **startupProbe**. While it hasn't succeeded, liveness and readiness checks are held off; once it succeeds, the tight liveness probe takes over. So start-up can be allowed a generous budget without making hang detection slow.

```bash
./scripts/RB-S56/fix.sh
# by hand, the same thing:
oc set probe deployment/rca-s56-slow --startup --get-url=http://:8080/ \
  --period-seconds=5 --failure-threshold=30           # 30 x 5 s = up to 150 s to start
oc set probe deployment/rca-s56-slow --liveness --initial-delay-seconds=0
```

Size the startup budget as `periodSeconds × failureThreshold` ≥ the **worst-case** start-up time with some margin (here 150 s for a 45 s app). If the app still hasn't started after that budget, the kubelet kills it, which is the correct behaviour for a truly stuck start.

Quick (but cruder) alternatives:

- Raise `initialDelaySeconds` on the liveness probe. It works, but then a hang **after** start-up is also detected late, and a slow node can still exceed it.
- Remove the liveness probe. This stops the restarts but also removes self-healing; only acceptable as a short-term mitigation.

Also check whether the real cause is resources: if `oc adm top pod` shows the container pinned at its CPU limit during start-up, raising the limit (or the request) shortens the start-up itself.

## 7. Verify

```bash
oc get pods -l app=rca-s56-slow -w        # one pod, goes 0/1 Running -> 1/1 Running, RESTARTS stays 0
oc rollout status deployment/rca-s56-slow # successfully rolled out
oc describe pod -l app=rca-s56-slow | grep -E 'Startup|Liveness|Restart Count'
./scripts/RB-S56/verify.sh                # runs the checks above
```

Typical output (illustrative):

```
NAME                            READY   STATUS    RESTARTS   AGE
rca-s56-slow-7f6c8d5b9-q9x2v    1/1     Running   0          58s

Liveness:   http-get http://:8080/ delay=0s timeout=1s period=5s #success=1 #failure=3
Startup:    http-get http://:8080/ delay=0s timeout=1s period=5s #success=1 #failure=30
Restart Count:  0
```

The test of success is time: leave it for several minutes and confirm the restart count does **not** move.

## 8. Prevention (what would stop this happening again)

- **Measure start-up time** (logs, or `oc get pod -o yaml` timestamps) in the real environment, with the real limits, and size the probes from that number rather than a guess.
- **Use a startupProbe for anything that takes more than a few seconds to start** (JVMs, apps with warm-up or migrations), and keep liveness short and cheap.
- **Keep the three probes in their lanes:** startup = "has it finished booting?", readiness = "can it take traffic now?", liveness = "is it hung beyond recovery?". Liveness should check only the process itself, not dependencies (that is [S57](../scenarios/DO180-RCA-scenario-bank.md)).
- **Roll out with `oc rollout status --timeout=…` in the pipeline** so a restart loop fails the release instead of sitting there.
- **Alert on restarts**, for example a rising `kube_pod_container_status_restarts_total`, so a loop pages someone.
- Re-measure after any change that affects start-up: bigger dependency set, lower CPU limit, new base image.

## 9. Evidence to capture when I run it (for the RCA)

- [ ] `oc get pods -w` showing 0/1 Running, the restart counter climbing, and later `CrashLoopBackOff`
- [ ] `oc describe pod` Events: the exact `Unhealthy` and `Killing` messages
- [ ] `oc describe pod` Last State (reason, exit code) to show it is **not** OOMKilled
- [ ] `oc logs --previous` showing banner only
- [ ] The liveness probe numbers and my budget calculation next to the measured start-up time
- [ ] The fix applied (`startupProbe`) and the pod reaching 1/1 with `RESTARTS 0`
- [ ] Several minutes later: restart count still 0
- [ ] Bonus: set the startup budget too small (for example `failureThreshold: 3`) and record that the kubelet still kills the container, proving the budget matters
- [ ] Bonus: break the probe path (`/nope`) instead and record the different event (`HTTP probe failed with statuscode: 404`) versus `connection refused`
- [ ] Time to detect, time to fix, and which command found the cause fastest
- [ ] Sanitise per the [checklist](../SANITISE-CHECKLIST.md) before committing

## 10. Interview: "A Java app restarts forever right after deploy. How do you troubleshoot it?" (a 60-second answer)

"First I look at *how* it's restarting: `oc get pods` shows Running but not Ready with a regular restart rhythm, which says something is killing it on a timer rather than the app crashing by itself. `oc describe pod` confirms it: `Liveness probe failed … connection refused` followed by `failed liveness probe, will be restarted`, and Last State shows a signal exit, not OOMKilled. The logs, including `--previous`, show only the start-up banner, so the app was killed while still booting. Then I do the arithmetic: initial delay plus period times failure threshold against the real start-up time. If the budget is shorter, the probe is killing a healthy but slow app. The fix is a startupProbe with a generous budget, for example 30 failures at 5 seconds, and a short liveness probe that only takes over once start-up succeeds; I'd also check whether a low CPU limit is slowing the start. To prevent it, I measure start-up in the real environment, keep liveness cheap and process-only, and fail the pipeline if the rollout doesn't complete."

## 11. Clean up

```bash
oc delete deployment rca-s56-slow
# or, if the project was only for this: oc delete project rca-s56-lab
```

## Sources

- Kubernetes docs: [Liveness, Readiness, and Startup Probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/) (a startup probe holds off the other probes until it succeeds; probe parameters and defaults)
- Kubernetes docs: [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) (protecting slow-starting containers with startup probes)
- Red Hat OpenShift Container Platform 4.18 documentation: [docs.redhat.com](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18) (applications → health checks, `oc set probe`)
- The exact event and `describe` wording varies slightly between versions; I'll replace the illustrative output with what my cluster actually prints.
