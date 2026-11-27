# ND-02 – Healthy pods, but the Service cannot find them (selector typo)

| Quick facts | |
|---|---|
| **Date and duration** | 2026-11-27, 17:22–17:29 (7 minutes) |
| **Platform** | Shared lab OpenShift 4.19, project `netlab` |
| **Symptom** | Website returns `HTTP 503` "Application is not available", while every pod is `1/1 Running` |
| **Root cause** | The Service looks for pods labelled `app=helo`; the pods are labelled `app=hello` |
| **Fix** | Patch the Service selector back to `app=hello` |

---

## 1. Problem statement

Users get **"Application is not available"** (`HTTP 503`) on the `hello` website. When the engineer checks, **both pods are healthy** (`1/1 Running`, no restarts). Find out why healthy pods receive no traffic, and fix it.

---

## 2. Detailed description of the problem

**What happened (the story).** A colleague edited the `hello` Service to "tidy it up" and made a **one-letter typo** in its selector. From that moment users get the error page, yet the pods look perfect.

**In plain words.** The receptionist was told to transfer calls to "the **Helo** team". There is no Helo team; all the staff wear "**Hello**" badges. They sit at their desks ready to work, but no call ever reaches them.

**What you need to know to understand it:**

| Term | Simple meaning |
|---|---|
| **Label** | A name tag on a pod, for example `app=hello` |
| **Selector** | The name tag a Service looks for. It sends traffic **only** to pods whose labels match **exactly** |
| **EndpointSlice** | The Service's list of matching, Ready pods. No match → empty list |
| **`oc patch`** | Changes one field of an object in place, like editing one line of a config file |

**Why this problem is tricky:** the user sees the **same 503** as in [ND-01](ND-01-scale-to-zero-503.md), but this time the pods are fine. An engineer who only checks pods will say "the app is healthy, it must be the network" and lose time. One wrong character means **zero** matches; there is no "close enough".

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
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H
oc get service hello -o wide          # SELECTOR column: the label the Service looks for
oc get pods --show-labels             # LABELS column: the labels the pods carry
```

Healthy means `HTTP 200`, Service `SELECTOR app=hello`, and both pods labelled `app=hello`.

---

## 4. My lab execution summary

| # | Time | What I did | Command |
|---|---|---|---|
| 1 | 17:22 | Confirmed the app works | `curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H` |
| 2 | 17:22 | **Broke it:** changed the selector to `app=helo` | `oc patch service hello -p '{"spec":{"selector":{"app":"helo"}}}'` |
| 3 | 17:22 | Called the website and checked the pods | `curl …` · `oc get pods -l app=hello` |
| 4 | 17:24 | Compared the EndpointSlice, the Service selector and the pod labels | `oc get endpointslices -l kubernetes.io/service-name=hello` · `oc get service hello -o wide` · `oc get pods --show-labels` |
| 5 | 17:29 | **Fixed:** selector back to `app=hello` | `oc patch service hello -p '{"spec":{"selector":{"app":"hello"}}}'` |
| 6 | 17:29 | Verified | `oc get endpointslices …` · `curl …` |

---

## 5. Observations

**Breaking it (steps 1–3):**

```text
HTTP 200
service/hello patched
HTTP 503
NAME                     READY   STATUS    RESTARTS   AGE
hello-77c476ccbb-jf4tf   1/1     Running   0          5m26s
hello-77c476ccbb-v69zs   1/1     Running   0          5m26s
```

- The site went from `200` to **`503`** within 3 seconds.
- The pods are **perfectly healthy**: `1/1 Running`, no restarts. This is the trap.

**Comparing what the Service wants with what the pods have (step 4):**

```text
NAME          ADDRESSTYPE   PORTS     ENDPOINTS   AGE
hello-cjx9l   IPv4          <unset>   <unset>     26h

NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE   SELECTOR
hello   ClusterIP   172.30.100.50   <none>        8080/TCP   26h   app=helo

NAME                     READY   STATUS    RESTARTS   AGE    LABELS
db-6f6f69b6b9-lt6vw      0/1     Pending   0          21h    app=db,pod-template-hash=6f6f69b6b9
hello-77c476ccbb-jf4tf   1/1     Running   0          7m7s   app=hello,pod-template-hash=77c476ccbb
hello-77c476ccbb-v69zs   1/1     Running   0          7m7s   app=hello,pod-template-hash=77c476ccbb
```

| What | Value |
|---|---|
| EndpointSlice | **Empty** (`<unset>`) |
| The Service looks for | `app=hel`**`o`** |
| The pods carry | `app=hel`**`lo`** |
| Pods matched | **0** |

(The `db` pod is unrelated to this drill: a database from another exercise, waiting for storage.)

---

## 6. Lab results

**After the fix (steps 5–6):**

```text
service/hello patched
NAME          ADDRESSTYPE   PORTS   ENDPOINTS              AGE
hello-cjx9l   IPv4          8080    10.0.0.172,10.0.1.13   26h
HTTP 200
```

| | Healthy | Broken | After fix |
|---|---|---|---|
| Website | `HTTP 200` | **`HTTP 503`** | `HTTP 200` ✅ |
| Service selector | `app=hello` | **`app=helo`** | `app=hello` |
| Pods | 2 × `1/1` | 2 × `1/1` (unchanged!) | 2 × `1/1` |
| EndpointSlice | 2 IPs | **empty** | 2 IPs |

The pods were **never touched**. Correcting the Service alone restored the site within seconds.

---

## 7. Detailed solution explanation (RCA)

**Root cause.** A typo in the Service's label selector (`app=helo` instead of `app=hello`).

**How the failure travelled:**

```text
selector typo (app=helo) ──► no pod label matches ──► EndpointSlice empty ──► router has no backend ──► 503
```

**How I found it.**
1. The 503 page came from the router, so the problem was behind the Route.
2. The EndpointSlice was **empty**.
3. But pods **existed and were Ready**, so it was not ND-01 (no pods).
4. Empty list + healthy pods → the Service is not finding them → compare its **SELECTOR** with the pods' **LABELS**.
5. `app=helo` vs `app=hello`: one missing letter.

**How to tell ND-01 and ND-02 apart (both show 503 and an empty EndpointSlice):**

| Drill | Do Ready pods exist? | Cause |
|---|---|---|
| [ND-01](ND-01-scale-to-zero-503.md) | ❌ No | The Deployment wants 0 pods |
| **ND-02** | ✅ **Yes** | **Selector does not match the labels** |

**Why the fix works.** With the selector back to `app=hello`, the EndpointSlice controller immediately finds both Ready pods and lists them; the router can send traffic again.

**How to prevent it.**
- Generate the Service selector and the pod labels from **one** value (a Helm value or Kustomize common labels), so they cannot drift apart.
- Deliver through Git with review; question any selector change.
- Alert on "Service with zero endpoints while its Deployment is available".

---

## 8. Learnings

**In simple words**
- Healthy staff are useless if the receptionist looks for the wrong name tag.
- Always compare the name the Service looks for with the name tags the pods wear.

**As an engineer**
- **Empty EndpointSlice + pods `1/1 Running` = compare selector and labels.**
- Use `oc get svc -o wide` (SELECTOR) and `oc get pods --show-labels` (LABELS) side by side.
- "The pods are healthy" is not the same as "the app is reachable".

**Interview questions**
- **Q: Pods are Running and Ready, but the Service has no endpoints. Why?**
  The Service selector does not match the pod labels: a typo, a renamed label, or a selector requiring an extra label the pods lack. Less common: the pods are in a different namespace from the Service.
- **Q: How do you stop this happening again?**
  One source for selector and labels (Helm/Kustomize), GitOps with review, and an alert on Services with zero endpoints.

---

Previous: [ND-01 – No pods at all](ND-01-scale-to-zero-503.md) · Next: [ND-03 – Wrong target port](ND-03-wrong-targetport-connection-refused.md) · [Index](README.md)
