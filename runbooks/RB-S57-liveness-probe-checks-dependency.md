# RB-S57: During a database outage, all the frontend pods restarted too (liveness probe checks a dependency)

| Field | Value |
|---|---|
| **Scenario** | [S57](../scenarios/DO180-RCA-scenario-bank.md) |
| **Area** | Probes · Liveness vs readiness · Blast radius · Pod lifecycle |
| **Lab** | 🟢 own project |
| **Status** | 📋 Ready to run (not yet run on my cluster) |
| **Time** | ~30–45 min |

> A runbook is a **plan**, not a record. Once I've run it on my lab and captured real output, it becomes `rca/RCA-0NN-*.md` and this status becomes ✅ Done → RCA-0NN.
>
> **EX280 angle:** configuring liveness and readiness probes on a Deployment is a standard application-reliability task. Knowing *what each probe should check* (and what it must never check) is the judgement half of that task.
>
> All command output below is **typical output (illustrative)**, not captured from my cluster.

## 1. The ticket (as it would arrive)

> "At 02:10 the database had a 5-minute outage. That was expected and the app was meant to show a 'try again later' page. Instead every frontend pod restarted, some more than once, and the page was completely down until about 10 minutes after the database came back. Why did a database problem take out the frontend?"

## 2. Reproduce safely (🟢)

Work only in my own project; objects are named `rca-s57-*`. Helpers are in [`scripts/RB-S57/`](../scripts/RB-S57/) and refuse to run in `default`, `openshift-*` or `kube-*`.

There is no real database here. An httpd pod behind a Service named `rca-s57-db` stands in for it: from the frontend's point of view, "the database is down" just means that Service has no ready endpoints.

```bash
oc new-project rca-s57-lab        # or reuse my own lab project
./scripts/RB-S57/break.sh         # db stand-in + 2-replica frontend, then scales the db to 0
```

By hand, the mistake is in the frontend's Deployment:

```yaml
containers:
  - name: web
    image: registry.access.redhat.com/ubi9/httpd-24:latest
    livenessProbe:
      exec:
        command:
          - /bin/bash
          - -c
          - "timeout 2 bash -c 'exec 3<>/dev/tcp/rca-s57-db/8080'"   # "is my database reachable?"
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3
```

Then the outage: `oc scale deployment/rca-s57-db --replicas=0`.

I use bash's built-in `/dev/tcp` so the probe does not depend on `curl` or a database client being inside the image. If the image on my cluster lacks bash for some reason, I'll note it and swap in another exec check.

## 3. What you'll see

```
$ oc get pods -l app=rca-s57-front -w
NAME                            READY   STATUS             RESTARTS      AGE
rca-s57-front-6d8f7c5b9-4xk2p   1/1     Running            0             3m
rca-s57-front-6d8f7c5b9-q8r7t   1/1     Running            0             3m
rca-s57-front-6d8f7c5b9-4xk2p   1/1     Running            1 (2s ago)    3m40s
rca-s57-front-6d8f7c5b9-q8r7t   1/1     Running            1 (1s ago)    3m41s
rca-s57-front-6d8f7c5b9-4xk2p   1/1     Running            2 (1s ago)    4m20s
rca-s57-front-6d8f7c5b9-q8r7t   0/1     CrashLoopBackOff   3 (5s ago)    5m10s
```

Key observations:

- The pods were **healthy until the dependency disappeared**. The restarts start about 30–40 s after the outage begins (3 failed checks, 10 s apart).
- **All replicas restart together**, because they all share the same dependency and the same probe. That is the signature of this bug: a one-component failure becomes a whole-tier failure.
- Restarting does not help, because the thing that is broken is not the container. The restart counter keeps growing for as long as the outage lasts, and the kubelet's back-off grows, so recovery after the database returns is **slower** than it needed to be.
- `oc logs` for the frontend looks normal. The app never failed; it was killed from outside.

## 4. Triage, outside-in

| # | Command | What it tells you |
|---|---|---|
| 1 | `oc get pods -l app=rca-s57-front` | Every replica has restarts, all at about the same time. A synchronised pattern points to a shared cause, not a bad pod. |
| 2 | `oc describe pod <front-pod>` → **Events** | `Unhealthy … Liveness probe failed …` then `Killing … failed liveness probe, will be restarted`. This confirms the kubelet restarted a running container. |
| 3 | `oc describe pod <front-pod>` → **Last State** | `Terminated`, `Reason: Error`, exit code `137` or `143`. Not `OOMKilled`. |
| 4 | `oc logs <front-pod> --previous` | Normal httpd start-up and nothing else: the app itself was fine. |
| 5 | `oc get deployment rca-s57-front -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'` | The key step: **read what the probe actually does**. Here it connects to `rca-s57-db`, which is not this container's own health. |
| 6 | `oc get endpoints rca-s57-db` | `<none>`: the database Service has no ready pods. This is the trigger. |
| 7 | `oc get events --sort-by=.lastTimestamp` (project-wide) | The database outage and the frontend `Unhealthy` events sit in the same time window, which gives you the timeline for the RCA. |
| 8 | `oc rsh <front-pod>` (a pod that is up for a moment) and `curl -s localhost:8080/` | The frontend answers on its own port while the database is down, which proves it could have kept serving. |

Typical event (illustrative; exact wording varies by version):

```
Warning  Unhealthy  kubelet  Liveness probe failed: bash: connect: Connection refused ... (or: command timed out)
Normal   Killing    kubelet  Container web failed liveness probe, will be restarted
```

Look-alikes to rule out:

- **Slow start-up** ([S56](../scenarios/DO180-RCA-scenario-bank.md)): the restarts begin right after deploy and happen with the database healthy. Here the pods ran fine for minutes first.
- **OOMKilled** ([S18](../scenarios/DO180-RCA-scenario-bank.md)): the reason says so and there are no `Unhealthy` events.
- **Readiness failing** ([S58](../scenarios/DO180-RCA-scenario-bank.md)): the pod goes 0/1 but is **not restarted**. If the pods had only gone un-Ready, nothing would have been killed.

## 5. Root cause(s)

The **liveness probe was asked a question the container cannot fix by restarting**. Liveness means "is this process stuck so that only a restart helps?". The probe instead asked "is every dependency reachable?". When the database went away, every replica failed that check at once, so the kubelet restarted all of them, repeatedly, for the duration of the outage.

Contributing causes:

1. A "deep health check" (database, cache, other services) was reused as the liveness probe because it was already there for monitoring.
2. All replicas share the same dependency, so the failure is correlated and no replica is left to serve a friendly error page.
3. Restarts add load at the worst moment: every restart re-opens connections, re-warms caches, and when the database returns all pods stampede it together. The growing CrashLoopBackOff delay also keeps the app down after the database has recovered.
4. No separate readiness probe, so there was no gentler way to say "I'm degraded".

5 Whys: frontend down → all pods restarted → liveness failed → probe checked the database → the database was down → the probe conflated "my dependency is down" with "my process is hung".

## 6. Fix

Make **liveness shallow**: it should test only the container's own process, for example `httpGet` on its own port (or `tcpSocket`). A dependency being down must not cause a restart.

```bash
./scripts/RB-S57/fix.sh
# by hand, the same thing:
oc set probe deployment/rca-s57-front --liveness --get-url=http://:8080/ \
  --initial-delay-seconds=10 --period-seconds=10 --timeout-seconds=3 --failure-threshold=3
oc set probe deployment/rca-s57-front --readiness --get-url=http://:8080/ \
  --period-seconds=5 --timeout-seconds=2 --failure-threshold=3
```

What goes where:

| Probe | Question it answers | What it may check | If it fails |
|---|---|---|---|
| **liveness** | Is the process stuck? | Only the app itself (own port, a cheap in-process endpoint) | Container restarted |
| **readiness** | Should this pod receive traffic right now? | Own health; a dependency check is *possible* but needs care | Pod removed from the Service endpoints, not restarted |
| **startup** | Has it finished booting? | Same as liveness, with a generous budget | Container restarted after the budget |

On whether readiness should check the database: it is the safer place for a dependency check than liveness, because the worst outcome is a 503 rather than a restart storm. But if every replica fails readiness at once, the Service has no endpoints and users see errors anyway. A common approach is to keep readiness shallow too, and have the app return its own "try again later" page when the database is down.

Quick (cruder) alternatives:

- Raise `failureThreshold` on the dependency-checking liveness probe. It only delays the restart storm for a longer outage.
- Remove the liveness probe. It stops the storm but loses self-healing for genuine hangs.

## 7. Verify

With the database **still scaled to 0**, the frontend must now survive:

```bash
./scripts/RB-S57/verify.sh                 # checks restart counts, probes and events
oc get pods -l app=rca-s57-front -w        # 1/1 Running, RESTARTS stops growing (watch for 2-3 min)
oc get endpoints rca-s57-db                # still <none>: the outage is still in place
```

Then test the recovery path:

```bash
oc scale deployment/rca-s57-db --replicas=1
oc rollout status deployment/rca-s57-db
oc get pods -l app=rca-s57-front           # unchanged: still 1/1, no new restarts
```

Typical output (illustrative):

```
>> Database replicas (expect 0 before the recovery step, so the outage is still in place)
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
rca-s57-db   0/0     0            0           12m
>> Restart counts per pod
rca-s57-front-5b9d8c6f7-7hn4z restarts=0
rca-s57-front-5b9d8c6f7-xw2mc restarts=0
```

## 8. Prevention (what would stop this happening again)

- **Review rule:** a liveness probe may only look at the container itself. No database, cache, queue or other-service calls.
- Give every app **two endpoints**: a cheap `/healthz` (process only) for liveness and, if needed, a separate `/ready` for readiness. Keep any deep dependency check for monitoring and alerting, not for probes.
- Add a **startupProbe** for slow starters so liveness can stay tight (see [RB-S56](RB-S56-liveness-probe-kills-slow-starting-app.md)).
- **Chaos-test dependencies** in a non-production project: scale the database to 0 and check the frontend shows a graceful error and its restart count stays at 0.
- Alert on pod **restart rate** by tier, so a synchronised restart across all replicas pages someone before the users do.
- Make the app handle a lost dependency itself (retry with back-off, a degraded page) rather than relying on the platform to restart it.

## 9. Evidence to capture when I run it (for the RCA)

- [ ] `oc get pods -l app=rca-s57-front` before the outage (0 restarts) and during it (restarts climbing on both pods).
- [ ] The timestamps: when I scaled the db to 0, and when the first `Killing` event appeared (expect ~30–40 s).
- [ ] `oc describe pod` Events with the `Unhealthy` and `Killing` lines, and Last State with its exit code.
- [ ] `oc logs --previous` showing a healthy app.
- [ ] `oc get endpoints rca-s57-db` showing `<none>`.
- [ ] The liveness probe JSON before the fix.
- [ ] After the fix with the db still down: restart count stable for 2–3 minutes, and `curl` against the frontend still answering.
- [ ] What the exec probe's real failure message was on my cluster (connection refused vs timeout).
- [ ] Whether `bash` and `/dev/tcp` worked in the image, or what I had to change.
- [ ] Any difference from the illustrative output above.

## 10. Interview: "Walk me through how you'd troubleshoot …" (a 60-second answer)

> "All the frontend pods restarted during a database outage. I first see the pattern: every replica restarting at the same time points to a shared cause, not one bad pod. `oc describe pod` shows `Unhealthy` liveness events and `Killing … will be restarted`, and `--previous` logs look healthy, so the app wasn't failing; the kubelet was killing it. Then I read the probe: it was checking the database, so when the database went down every replica failed liveness together. The root cause is that liveness was answering 'are my dependencies up?' instead of 'is my process stuck?', and a restart can't fix a dependency. The fix is to make liveness shallow, on the container's own port, optionally add a shallow readiness probe, and let the app show a degraded page. To prevent it I put a review rule in place that liveness never calls other services, use a startup probe for slow starters, and test dependency failures by scaling the database to zero in a lab."

## 11. Clean up

```bash
oc delete deployment rca-s57-front rca-s57-db
oc delete service rca-s57-db
# or, if the project was only for this: oc delete project rca-s57-lab
```

## Sources

- Kubernetes docs: [Liveness, Readiness, and Startup Probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/) (what each probe does, and that a failed liveness probe restarts the container while a failed readiness probe only removes the pod from Service endpoints)
- Kubernetes docs: [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) (exec, HTTP and TCP probes; probe parameters)
- Red Hat OpenShift Container Platform 4.18 documentation: [docs.redhat.com](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18) (applications → health checks, `oc set probe`)
- The advice "keep liveness shallow, never check dependencies" is widely used engineering practice rather than a hard rule in the docs; I state it as my own reasoning.
- The exact event and `describe` wording varies slightly between versions; I'll replace the illustrative output with what my cluster actually prints.
