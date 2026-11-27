# ND-04 – A bad health check in a new release: the rollout protects users

| Quick facts | |
|---|---|
| **Date and duration** | 2026-11-27, 17:44–17:51 (7 minutes) |
| **Platform** | Shared lab OpenShift 4.19, project `netlab` |
| **Symptom** | New release stuck: new pod `0/1 Running`, rollout times out. **Users unaffected** (`HTTP 200`) |
| **Root cause** | The new version's readiness probe checks a page that does not exist (`404`), so the new pod never becomes Ready |
| **Fix** | `oc rollout undo deployment/hello` |

---

## 1. Problem statement

A developer released a new version of `hello` that adds a health check. The release **never finishes**: the deployment tool reports a timeout, and one new pod stays at `0/1`. Find out what is wrong, whether users are affected, and get back to a clean state.

---

## 2. Detailed description of the problem

**What happened (the story).** The new version adds a **readiness probe**, a health check that tells OpenShift "only send me traffic when this check passes". The developer typed the wrong URL (`/no-such-page`), so the check **always fails**.

**In plain words.** A new member of staff joins, but the supervisor's "ready to serve customers?" checklist asks them to sign a form that does not exist. They can never pass, so they are never put on the front desk. Meanwhile the experienced staff keep serving everyone as usual.

**What you need to know to understand it:**

| Term | Simple meaning |
|---|---|
| **Readiness probe** | "Is this pod ready for traffic?" If it fails, the pod is **taken out of traffic** but keeps running |
| **Liveness probe** | "Is this pod alive?" If it fails, the pod is **restarted** (not used in this drill) |
| **Rolling update** | How a Deployment releases a new version: start new pods, remove old pods **only after new ones are Ready** |
| **Revision** | Every change to a Deployment's pod template is a numbered release you can roll back to |

With 2 copies and the default settings, a rolling update may add **1** extra pod and may make **0** pods unavailable.

**Why this problem is interesting:** it looks like a failure (a stuck release, a timeout), but the platform is actually **protecting** users. The question is not "how do I fix the outage" but "is there one?".

---

## 3. Lab setup

**Environment**

| Item | Value |
|---|---|
| Cluster | Shared lab OpenShift 4.19 (Kubernetes 1.32), 2 nodes: `master-0`, `worker-1` |
| Access | Normal project user, own project `netlab` |
| App image | `registry.access.redhat.com/ubi9/httpd-24` (Apache, listens on port 8080) |

**Build the app (all commands)**

```bash
oc new-project netlab
oc create deployment hello --image=registry.access.redhat.com/ubi9/httpd-24
oc scale deployment hello --replicas=2
oc expose deployment hello --port=8080
oc expose service hello
echo '<h1>Hello from my first OpenShift app</h1>' > index.html
oc create configmap hello-page --from-file=index.html
oc set volume deployment/hello --add --name=page --type=configmap \
  --configmap-name=hello-page --mount-path=/var/www/html
```

**Healthy baseline**

```bash
H=$(oc get route hello -o jsonpath='{.spec.host}')
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H     # HTTP 200
oc get pods -l app=hello                                      # 2 pods 1/1 Running
oc rollout history deployment/hello                           # 2 revisions so far
```

---

## 4. My lab execution summary

| # | Time | What I did | Command |
|---|---|---|---|
| 1 | 17:44 | **Released** the new version with a bad readiness probe | `oc set probe deployment/hello --readiness --get-url=http://:8080/no-such-page --period-seconds=5` |
| 2 | 17:44 | Waited 30 s, then checked pods, the rollout, the EndpointSlice and the website | `oc get pods -l app=hello` · `oc rollout status deployment/hello --timeout=20s` · `oc get endpointslices …` · `curl …` |
| 3 | 17:48 | Checked which endpoints are Ready | `oc get endpointslices … -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]}{"  ready="}{.conditions.ready}{"\n"}{end}'` |
| 4 | 17:48 | Read the new pod's events | `oc describe pod -l pod-template-hash=5598df8747 \| tail -5` |
| 5 | 17:48 | Listed the release history | `oc rollout history deployment/hello` |
| 6 | 17:51 | **Rolled back** | `oc rollout undo deployment/hello` |
| 7 | 17:51 | Verified | `oc rollout status …` · `oc get pods …` · `curl …` |

---

## 5. Observations

**After the release (steps 1–2):**

```text
deployment.apps/hello probes updated
NAME                     READY   STATUS    RESTARTS   AGE
hello-5598df8747-gg6m7   0/1     Running   0          30s
hello-77c476ccbb-jf4tf   1/1     Running   0          27m
hello-77c476ccbb-v69zs   1/1     Running   0          27m
Waiting for deployment "hello" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
NAME          ADDRESSTYPE   PORTS   ENDPOINTS                         AGE
hello-cjx9l   IPv4          8080    10.0.1.13,10.0.0.172,10.0.1.16    26h
HTTP 200
```

| What I saw | Meaning |
|---|---|
| New pod `5598df8747-…` **`0/1 Running`** | It runs, but fails its readiness check: **not Ready** |
| Old pods `77c476ccbb-…` still `1/1` | The Deployment **refused to remove them**, because no new pod was Ready |
| `rollout status` **timed out** | The release is stuck and will not finish on its own |
| **`HTTP 200`** | Users are still served by the **old** version |
| EndpointSlice shows **3** IPs | That column lists every address, ready or not (next observation) |

**Which endpoints are Ready (step 3):**

```text
10.0.1.13  ready=true
10.0.0.172  ready=true
10.0.1.16  ready=false
```
Traffic goes only to the two `ready=true` endpoints. The new pod is listed but skipped.

**The new pod's events (step 4):**

```text
Normal   Pulling    4m39s                   kubelet  Pulling image "registry.access.redhat.com/ubi9/httpd-24"
Normal   Pulled     4m27s                   kubelet  Successfully pulled image … in 12.696s. Image size: 309686553 bytes.
Normal   Created    4m27s                   kubelet  Created container: httpd-24
Normal   Started    4m27s                   kubelet  Started container httpd-24
Warning  Unhealthy  2m33s (x25 over 4m26s)  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 404
```
The exact cause: the check failed **25 times** (every 5 seconds), because `/no-such-page` returns **404**.

**The release history (step 5):**

```text
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>
```

| Revision | What changed |
|---|---|
| 1 | Original Deployment |
| 2 | Web page (ConfigMap) mounted |
| 3 | **The bad readiness probe** |

Only changes to the pod template create revisions; scaling and Service edits do not. `CHANGE-CAUSE` is empty because no reason was recorded.

---

## 6. Lab results

**After the rollback (steps 6–7):**

```text
deployment.apps/hello rolled back
deployment "hello" successfully rolled out
NAME                     READY   STATUS        RESTARTS   AGE
hello-5598df8747-gg6m7   0/1     Terminating   0          7m42s
hello-77c476ccbb-jf4tf   1/1     Running       0          34m
hello-77c476ccbb-v69zs   1/1     Running       0          34m
HTTP 200
```

| | Before release | During bad release | After rollback |
|---|---|---|---|
| Website | `HTTP 200` | `HTTP 200` (old version) | `HTTP 200` ✅ |
| Old pods | 2 × `1/1` | 2 × `1/1`, kept | 2 × `1/1`, **same pods, never restarted** |
| New pod | — | `0/1`, failing probe | Terminating |
| Rollout | complete | **stuck** | complete |

Why no new pods after the rollback: `undo` pointed the Deployment back to the previous pod template. Its ReplicaSet (`77c476ccbb`) already ran 2 healthy pods with exactly that template, so nothing new had to start. The history now has a **revision 4**, a copy of revision 2: undo adds history, it never deletes it.

---

## 7. Detailed solution explanation (RCA)

**Root cause.** The new version's readiness probe requested `/no-such-page`, which returns `404`, so the new pod could never become Ready.

**How the failure travelled:**

```text
probe URL wrong ──► 404 ──► new pod never Ready ──► rolling update will not remove old pods ──► release stuck, users still on old version
```

**How I found it.**
1. New pod `0/1 Running` and a stuck rollout → something stops the pod becoming Ready.
2. `HTTP 200` and `ready=true` on the old endpoints → **no user impact**.
3. The pod's **Events** gave the exact reason: `Readiness probe failed … statuscode: 404`.
4. The release history showed the probe arrived in revision 3.

**What went right.** The readiness probe is exactly what stopped a broken release from reaching users. With no readiness probe at all, the new pod would have counted as Ready the moment it started, the old pods would have been removed, and a broken version would have taken all traffic.

**Why the fix works.** `oc rollout undo` restores the previous pod template (without the bad probe). The stuck pod is removed and the old, healthy pods carry on. Then the developer corrects the probe (for example `--get-url=http://:8080/`) and releases again.

**How to prevent it.**
- Test probe paths in a lower environment before production.
- Set `progressDeadlineSeconds` and alert when a Deployment reports `Progressing=False`.
- Record a reason for every release (an annotation, or Git commit history with GitOps).

---

## 8. Learnings

**In simple words**
- A new staff member who never passes the readiness check is never put on the front desk, and the old staff are not sent home. Customers never notice.

**As an engineer**
- **Readiness failure = taken out of traffic, not restarted.**
- A rolling update removes old pods only after new ones are Ready, so a good readiness probe makes releases fail **safely**.
- `0/1 Running` → `oc describe pod` → **Events** shows the exact probe failure.
- The EndpointSlice `ENDPOINTS` column also lists not-ready addresses; check `conditions.ready`.
- `oc rollout history` and `oc rollout undo` are the release safety net.

**Interview questions**
- **Q: A deployment is stuck; one new pod is `0/1 Running`. Are users affected?**
  Usually not: with default rolling-update settings, old pods are only removed after new ones are Ready. I confirm with the EndpointSlice ready flags and a request through the Route, then read the pod events.
- **Q: Readiness vs liveness: what happens when each fails?**
  Readiness: removed from Service endpoints, keeps running. Liveness: the container is restarted. A liveness probe that checks a dependency can restart every pod during a dependency outage, so liveness should check only the process itself.
- **Q: How do you roll back?**
  `oc rollout undo deployment/<name>` (optionally `--to-revision=N`), then fix forward through the normal release process.

---

Previous: [ND-03 – Wrong target port](ND-03-wrong-targetport-connection-refused.md) · Next: [ND-05 – Deny-all NetworkPolicy](ND-05-deny-all-networkpolicy-timeout.md) · [Index](README.md)
