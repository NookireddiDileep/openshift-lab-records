# ND-03 – The Service sends traffic to the wrong port: connection refused

| Quick facts | |
|---|---|
| **Date and duration** | 2026-11-27, 17:34–17:39 (5 minutes) |
| **Platform** | Shared lab OpenShift 4.19, project `netlab` |
| **Symptom** | Outside: `HTTP 503`. Inside the cluster: **`Connection refused`** |
| **Root cause** | The Service forwards to pod port **9999**; Apache listens on **8080** |
| **Fix** | Patch the Service `targetPort` back to 8080 |

---

## 1. Problem statement

The `hello` website returns `HTTP 503`. This time the Service **does** list both pods, and the pods are healthy. Find out why traffic still does not reach the app, and fix it.

---

## 2. Detailed description of the problem

**What happened (the story).** Someone "standardised" the Service definitions and set the `hello` Service to forward traffic to port 9999. The Service still finds the pods, the pods are fine, but every visitor gets the error page.

**In plain words.** The receptionist transfers every call to **extension 9999**. The staff are at their desks, but their phones are on **extension 8080**. Every transferred call rings an empty desk and is rejected straight away.

**What you need to know to understand it:**

A Service has **two** ports:

| Field | Simple meaning | In this app |
|---|---|---|
| `port` | The port **callers** use: `hello:8080` | 8080 (unchanged) |
| `targetPort` | The port **on the pod** that traffic is forwarded to | 8080 → **broken to 9999** |

Callers keep using `hello:8080`; the Service quietly translates it to the `targetPort`. That is why this mistake hides well.

**"Connection refused"** means the request reached the computer (the pod's IP), but nothing was listening on that port, so the operating system said "no" **immediately**. On any Linux server, `curl localhost:9999` gives the same error.

**Why this problem is tricky:** the EndpointSlice is **not empty** this time, so the checks from ND-01 and ND-02 look fine. And the router hides the real error behind its generic 503 page.

---

## 3. Lab setup

**Environment**

| Item | Value |
|---|---|
| Cluster | Shared lab OpenShift 4.19 (Kubernetes 1.32), 2 nodes: `master-0`, `worker-1` |
| Access | Normal project user, own project `netlab` |
| App image | `registry.access.redhat.com/ubi9/httpd-24` (Apache, listens on port **8080**) |

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
oc get endpointslices -l kubernetes.io/service-name=hello     # PORTS column should say 8080
```

**Test helper used here: a call from inside the cluster** (no router in the path)

```bash
oc run tester --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- \
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" http://hello:8080
```

`oc run tester --rm` starts a throwaway pod, runs one command and deletes the pod. `curl -sS` hides the progress bar but **shows errors**.

---

## 4. My lab execution summary

| # | Time | What I did | Command |
|---|---|---|---|
| 1 | 17:34 | **Broke it:** set `targetPort` to 9999 | `oc patch service hello --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":9999}]'` |
| 2 | 17:34 | Called the website and checked the EndpointSlice | `curl …` · `oc get endpointslices -l kubernetes.io/service-name=hello` |
| 3 | 17:35 | Called the Service from **inside** the cluster | `oc run tester … curl -sS … http://hello:8080` |
| 4 | 17:39 | **Fixed:** `targetPort` back to 8080 | `oc patch service hello --type=json -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'` |
| 5 | 17:39 | Verified | `oc get endpointslices …` · `curl …` |

`--type=json` lets `oc patch` replace one exact field inside a list (here, the first port's `targetPort`).

---

## 5. Observations

**From outside, and the EndpointSlice (steps 1–2):**

```text
service/hello patched
HTTP 503
NAME          ADDRESSTYPE   PORTS   ENDPOINTS              AGE
hello-cjx9l   IPv4          9999    10.0.1.13,10.0.0.172   26h
```

| | ND-01 and ND-02 | **ND-03** |
|---|---|---|
| User sees | 503 | **503** (same) |
| EndpointSlice IPs | Empty | **Both pods listed** |
| EndpointSlice PORTS | `<unset>` | **`9999`** ← the clue |

The selector is fine: the Service found both pods. **"The EndpointSlice has IPs" is not the end of the check**; the port must be right too.

**From inside the cluster (step 3):**

```text
Warning: would violate PodSecurity "restricted:latest": … (harmless warning for the test pod)
curl: (7) Failed to connect to hello port 8080: Connection refused
HTTP 000
pod "tester" deleted
pod netlab/tester terminated (Error)
```

| Line | Meaning |
|---|---|
| `curl: (7) … Connection refused` | The request reached the pod, but nothing listens on 9999. The pod said "no" **instantly** |
| `hello port 8080` | The caller used the Service port 8080; the Service translated it to 9999 without telling anyone |
| `HTTP 000` | No HTTP answer at all: Apache never saw the request |
| `terminated (Error)` | curl exited with an error, so the test pod ended as Error. Expected |

**The router hides the real error.** From outside, the router turned "connection refused" into its generic 503 page. From inside, with no router in the path, the true cause is visible.

---

## 6. Lab results

**After the fix (steps 4–5):**

```text
service/hello patched
NAME          ADDRESSTYPE   PORTS   ENDPOINTS              AGE
hello-cjx9l   IPv4          8080    10.0.1.13,10.0.0.172   26h
HTTP 200
```

| | Healthy | Broken | After fix |
|---|---|---|---|
| Website (outside) | `HTTP 200` | **`HTTP 503`** | `HTTP 200` ✅ |
| Inside test | `HTTP 200` | **`Connection refused`** | `HTTP 200` |
| EndpointSlice IPs | 2 | 2 (unchanged) | 2 |
| EndpointSlice PORTS | 8080 | **9999** | 8080 |

---

## 7. Detailed solution explanation (RCA)

**Root cause.** The Service's `targetPort` was 9999, but Apache in the pods listens on 8080.

**How the failure travelled:**

```text
targetPort 9999 ──► traffic sent to pod:9999 ──► nothing listening ──► connection refused ──► router shows 503
```

**How I found it.**
1. 503 from the router → the problem is behind the Route.
2. EndpointSlice **not empty**: both pods listed, so it is not ND-01 or ND-02.
3. But its **PORTS** column said **9999**, while the image listens on 8080.
4. A call from inside the cluster confirmed it: instant **`Connection refused`**.

**Why the fix works.** With `targetPort: 8080`, the Service forwards to the port Apache really listens on, so connections succeed and the router gets real answers.

**How to prevent it.**
- Use **named ports**: name the container port `http` in the Deployment and set `targetPort: http` in the Service. A port number change in one place then cannot silently break the other.
- Keep the Service and the Deployment in the same template and review them together.
- Run an end-to-end check (a `curl` through the Route) after every change. A readiness probe proves the app listens on its port, but it does **not** catch a wrong Service `targetPort`.

---

## 8. Learnings

**In simple words**
- The receptionist found the right people but dialled the wrong extension.
- Check not only **who** the calls go to, but **which extension**.

**As an engineer**
- Read the EndpointSlice **PORTS** column, not just the IPs.
- **Connection refused = instant "no" = wrong port, or app not listening** (or listening only on 127.0.0.1).
- **Test from inside** the cluster to remove the router and see the real error.
- Same 503 to the user, three different causes so far (ND-01, ND-02, ND-03). The EndpointSlice tells them apart.

**Interview questions**
- **Q: What is the difference between `port` and `targetPort` in a Service?**
  `port` is what clients connect to on the Service; `targetPort` is the port on the pod that traffic is forwarded to. A wrong `targetPort` gives "connection refused" even though the Service has endpoints.
- **Q: The Route gives 503 but the Service has endpoints. Next step?**
  Compare the EndpointSlice port with the port the container listens on, and test from a pod inside the cluster: "connection refused" means a port problem; a timeout points to a NetworkPolicy ([ND-05](ND-05-deny-all-networkpolicy-timeout.md)).

---

Previous: [ND-02 – Selector typo](ND-02-service-selector-typo-503.md) · Next: [ND-04 – Failing readiness probe](ND-04-failing-readiness-probe-rollout.md) · [Index](README.md)
