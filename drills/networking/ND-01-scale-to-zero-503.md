# ND-01 – No pods at all: 503 "Application is not available"

| Quick facts | |
|---|---|
| **Date and duration** | 2026-11-27, 17:12–17:17 (5 minutes) |
| **Platform** | Shared lab OpenShift 4.19, project `netlab` |
| **Symptom** | Website returns `HTTP 503` with the page "Application is not available" |
| **Root cause** | The Deployment was scaled to 0, so no pods existed |
| **Fix** | `oc scale deployment hello --replicas=2` |

---

## 1. Problem statement

Users open the `hello` website and get an error page saying **"Application is not available"** (`HTTP 503`). Nobody changed the code, the Route or the Service. Find out why the site is down and bring it back.

---

## 2. Detailed description of the problem

**What happened (the story).** During maintenance, someone scaled the `hello` application down to zero copies "for a moment" and forgot to scale it back up. From that moment, every visitor gets an error page.

**In plain words.** Think of a shop. The front door is open and the phone number still works, but there is **nobody inside**. The receptionist answers every call with "sorry, nobody is available".

**What you need to know to understand it:**

| Term | Simple meaning |
|---|---|
| **Pod** | One running copy of the app (one Apache web server) |
| **Deployment** | The manager that keeps the number of pods you ask for. Ask for 2, it keeps 2. Ask for **0**, it removes every pod and is perfectly "happy" doing so |
| **Service** | A fixed internal address that forwards traffic to the pods |
| **EndpointSlice** | The Service's current list of pods it can send traffic to. No pods → empty list |
| **Route** | The public web address of the app |
| **Router** | OpenShift's built-in web gateway (HAProxy). When it knows the address but has **no pod** to send the request to, it shows its own page: **"Application is not available"** |

**Why this problem is tricky:** nothing crashes, nothing turns red, no error events appear. The platform is doing exactly what it was told. The mistake is in the **instruction** (0 copies), not in the platform.

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
oc new-project netlab                                                     # my own project
oc create deployment hello --image=registry.access.redhat.com/ubi9/httpd-24
oc scale deployment hello --replicas=2                                    # 2 copies
oc expose deployment hello --port=8080                                    # Service on port 8080
oc expose service hello                                                   # Route (public address)
echo '<h1>Hello from my first OpenShift app</h1>' > index.html
oc create configmap hello-page --from-file=index.html                     # the web page
oc set volume deployment/hello --add --name=page --type=configmap \
  --configmap-name=hello-page --mount-path=/var/www/html                  # put the page into Apache
```

**Record the healthy baseline** (always record "good" before breaking anything)

```bash
H=$(oc get route hello -o jsonpath='{.spec.host}'); echo $H              # save the app's address in $H
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H                  # call the app, print only the status
oc get pods -l app=hello                                                  # the pods
oc get endpointslices -l kubernetes.io/service-name=hello                 # the Service's list of pods
```

```text
hello-netlab.apps.ocp.example.com
HTTP 200
NAME                     READY   STATUS    RESTARTS   AGE
hello-77c476ccbb-mhwpg   1/1     Running   0          24h
hello-77c476ccbb-tj7c5   1/1     Running   0          24h
NAME          ADDRESSTYPE   PORTS   ENDPOINTS               AGE
hello-cjx9l   IPv4          8080    10.0.1.191,10.0.0.129   25h
```

Healthy means: **`HTTP 200`**, **2 pods `1/1 Running`**, and the EndpointSlice lists **both pod IPs on port 8080**.

---

## 4. My lab execution summary

| # | Time | What I did | Command |
|---|---|---|---|
| 1 | 17:12 | Recorded the healthy baseline | (section 3) |
| 2 | 17:13 | **Broke it:** asked for 0 copies | `oc scale deployment hello --replicas=0` |
| 3 | 17:13 | Called the website | `curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H` |
| 4 | 17:13 | Read the error page to see who wrote it | `curl -s http://$H \| grep -iE '<h1>\|<p>'` |
| 5 | 17:15 | Walked the path from outside in | `oc get route hello` → `oc get service hello` → `oc get endpointslices …` → `oc get pods -l app=hello` → `oc get deployment hello` |
| 6 | 17:17 | **Fixed:** asked for 2 copies again | `oc scale deployment hello --replicas=2` |
| 7 | 17:17 | Verified | `oc rollout status …`, `oc get endpointslices …`, `curl …` |

---

## 5. Observations

**After breaking it (steps 2–3):**

```text
deployment.apps/hello scaled
HTTP 503
```
The site went from `200` to **`503`** within seconds.

**The error page (step 4):**

```text
<h1>Application is not available</h1>
<p>The application is currently not serving requests at this endpoint. It may not have been started or is still starting.</p>
```
My app never wrote this page. **The router wrote it.** That tells me the request got this far:

| Part of the path | Working? | How I know |
|---|---|---|
| DNS (the address) | ✅ Yes | Otherwise curl would say "Could not resolve host" |
| Router | ✅ Yes | It answered with its own page |
| Route | ✅ Yes | The router recognised the address |
| Behind the Route | ❌ No | The router had nowhere to send the request |

**Walking the path (step 5):**

```text
NAME    HOST/PORT                           PATH   SERVICES   PORT   TERMINATION   WILDCARD
hello   hello-netlab.apps.ocp.example.com          hello      8080                 None

NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
hello   ClusterIP   172.30.100.50   <none>        8080/TCP   25h

NAME          ADDRESSTYPE   PORTS     ENDPOINTS   AGE
hello-cjx9l   IPv4          <unset>   <unset>     25h

No resources found in netlab namespace.

NAME    READY   UP-TO-DATE   AVAILABLE   AGE
hello   0/0     0            0           28h
```

| Hop | What I saw | Verdict |
|---|---|---|
| Route | Address and Service `hello` on 8080 | ✅ Fine |
| Service | Still `172.30.100.50:8080` | ✅ Fine: a Service exists whether or not pods do |
| **EndpointSlice** | **`<unset>` / `<unset>`** | ❌ **First broken hop**: empty list |
| Pods | None | ❌ Why the list is empty |
| Deployment | **`0/0`** | 🎯 **Root cause**: it was asked for 0 copies |

---

## 6. Lab results

**After the fix (step 6–7):**

```text
deployment.apps/hello scaled
deployment "hello" successfully rolled out
NAME          ADDRESSTYPE   PORTS   ENDPOINTS              AGE
hello-cjx9l   IPv4          8080    10.0.1.13,10.0.0.172   25h
HTTP 200
```

| | Before (healthy) | Broken | After fix |
|---|---|---|---|
| Website | `HTTP 200` | **`HTTP 503`** | `HTTP 200` ✅ |
| Pods | 2 × `1/1` | **none** | 2 × `1/1` (new pods) |
| EndpointSlice | 2 IPs, port 8080 | **empty** | 2 **new** IPs, port 8080 |
| Deployment | `2/2` | **`0/0`** | `2/2` |

The EndpointSlice refilled **by itself** with two new IPs, because the pods are new. I never touched the Route or the Service.

---

## 7. Detailed solution explanation (RCA)

**Root cause.** The Deployment's desired replica count was set to **0**.

**How the failure travelled (cause and effect):**

```text
Deployment wants 0 ──► no pods ──► EndpointSlice empty ──► router has no backend ──► 503 "Application is not available"
```

**How I found it.**
1. The error page came from the **router**, so DNS, router and Route were fine. The problem had to be **behind** the Route.
2. I walked the path **from outside in**, one hop at a time.
3. The first wrong thing was the **empty EndpointSlice**.
4. Empty list → are there pods? **None.**
5. No pods → what does the Deployment want? **`0/0`**: zero wanted. Root cause found.

**Why the fix works.** `oc scale deployment hello --replicas=2` changes the instruction back to 2 copies. The Deployment creates 2 pods; as soon as they are Ready, the EndpointSlice lists them automatically, and the router has somewhere to send requests again.

**Why no alarm went off.** Nothing failed. The Deployment, pods and router all did exactly what they were told. Monitoring that only watches for crashing pods would see nothing wrong.

**How to prevent it.**
- Make scaling changes through Git (GitOps), so every scale-down is reviewed and recorded.
- Alert when a Route's Service has **zero ready endpoints**, not only when pods crash.
- For important apps, a PodDisruptionBudget stops voluntary disruptions such as node drains from removing all pods at once (it does not block a manual scale to 0, which is why the alert matters).

---

## 8. Learnings

**In simple words**
- "Application is not available" means the front door works but **nobody is inside**.
- First check whether any pods exist, then find out why not.

**As an engineer**
- The router's 503 page proves DNS, router and Route are fine: **look behind the Route**.
- Walk the path **outside → in**: Route → Service → **EndpointSlice** → pods → Deployment.
- Empty EndpointSlice + **no pods** → check the Deployment's desired count (or why pods fail to start).
- `0/0` is not an error state. Always compare **what is wanted** with **what you expect**.

**Interview questions**

- **Q: A Route returns 503 "Application is not available". What do you check first?**
  The page comes from the router, so DNS and the Route are fine. I check the Service's EndpointSlice. If it is empty, I check whether pods exist and are Ready, then the Deployment's desired replicas. If pods are Ready, I compare the Service selector with the pod labels ([ND-02](ND-02-service-selector-typo-503.md)).
- **Q: Why didn't any alert fire?**
  Because nothing crashed: the platform faithfully kept zero pods. Alerts must also cover "zero ready endpoints behind a Route".

---

Previous: [ND-00 – Lab setup](ND-00-lab-setup.md) · Next: [ND-02 – Service selector typo](ND-02-service-selector-typo-503.md) · [Index](README.md)
