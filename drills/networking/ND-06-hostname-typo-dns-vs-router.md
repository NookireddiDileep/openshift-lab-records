# ND-06 – A typo in the hostname: two typos, two completely different errors

| Quick facts | |
|---|---|
| **Date and duration** | 2026-11-27, 18:10 (1 minute) |
| **Platform** | Shared lab OpenShift 4.19, project `netlab` |
| **Symptom** | Typo in the domain part: `Could not resolve host`. Typo in the app part: `HTTP 503` "Application is not available" |
| **Root cause** | Wildcard DNS `*.apps.<cluster-domain>`: a wrong domain does not exist at all; a wrong app name reaches the router, which has no Route for it |
| **Fix** | Use the exact hostname from `oc get route` |

---

## 1. Problem statement

Two users report that the `hello` app "is down". One gets **"site can't be reached"**. The other gets **"Application is not available"**. The app is healthy. Find out what each user did wrong and why their errors look so different.

---

## 2. Detailed description of the problem

**What happened (the story).** Both users typed the app's address by hand and made a typo, in different parts of the address. Nothing in the cluster changed.

**In plain words.** One caller dialled a **wrong area code**, so the phone network could not even connect the call. The other dialled the **right company** but asked for a department that does not exist, so the receptionist answered and said "nobody here by that name".

**What you need to know to understand it:**

| Term | Simple meaning |
|---|---|
| **Route hostname** | Looks like `<route>-<project>.apps.<cluster-domain>`, for example `hello-netlab.apps.ocp.example.com` |
| **Wildcard DNS** | One DNS record, `*.apps.<cluster-domain>`, points **every** name ending in `.apps.<cluster-domain>` at the router, even names that do not exist as Routes |
| **Router** | Receives the request, then looks for a Route with that **exact** hostname. No match → its standard 503 page |

**Why this problem is tricky:** the second error is **identical** to the 503 page from [ND-01](ND-01-scale-to-zero-503.md), [ND-02](ND-02-service-selector-typo-503.md) and [ND-03](ND-03-wrong-targetport-connection-refused.md), where the app really was broken. A user's "Application is not available" can mean a broken app **or** just a mistyped URL.

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
H=$(oc get route hello -o jsonpath='{.spec.host}'); echo $H     # the real hostname
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H         # HTTP 200
```

---

## 4. My lab execution summary

Nothing was broken in the cluster. I only called the app with two misspelled hostnames.

| # | Time | What I did | Command |
|---|---|---|---|
| 1 | 18:10 | Made a typo in the **domain** part (`.apps.` → `.aps.`) | `WRONG1=${H/.apps./.aps.}` |
| 2 | 18:10 | Made a typo in the **app** part (`hello-` → `helo-`) | `WRONG2=${H/hello-/helo-}` |
| 3 | 18:10 | Called both, and read the second error page | `curl -sS … http://$WRONG1` · `curl -sS … http://$WRONG2` · `curl -s http://$WRONG2 \| grep -i '<h1>'` |

`${H/.apps./.aps.}` is bash search-and-replace on a variable: it takes the real hostname and swaps one part.

```bash
WRONG1=${H/.apps./.aps.}
WRONG2=${H/hello-/helo-}
echo "$WRONG1"; echo "$WRONG2"
curl -sS -o /dev/null --max-time 10 -w "wrong domain: HTTP %{http_code}\n" http://$WRONG1
curl -sS -o /dev/null --max-time 10 -w "wrong app name: HTTP %{http_code}\n" http://$WRONG2
curl -s http://$WRONG2 | grep -i '<h1>'
```

---

## 5. Observations

```text
hello-netlab.aps.ocp.example.com
helo-netlab.apps.ocp.example.com
curl: (6) Could not resolve host: hello-netlab.aps.ocp.example.com
wrong domain: HTTP 000
wrong app name: HTTP 503
      <h1>Application is not available</h1>
```

| Typo | Error | How far the request got | Why |
|---|---|---|---|
| **Domain part** (`.aps.`) | `curl: (6) Could not resolve host`, `HTTP 000` | **Nowhere**: it never left my terminal | No DNS record exists for that name |
| **App part** (`helo-`) | **`HTTP 503` "Application is not available"** | **The router** | Wildcard DNS sent it to the router; the router has no Route with that host |

---

## 6. Lab results

| Address used | Result | Meaning |
|---|---|---|
| `hello-netlab.apps.ocp.example.com` (correct) | `HTTP 200` | App healthy |
| `hello-netlab.aps.ocp.example.com` (domain typo) | **curl error 6**, `HTTP 000` | DNS failure: request never sent |
| `helo-netlab.apps.ocp.example.com` (app-name typo) | **`HTTP 503`** "Application is not available" | Reached the router; unknown host |

The app was healthy the whole time; only the addresses were wrong.

---

## 7. Detailed solution explanation (RCA)

**Root cause.** Mistyped hostnames. The two typos fail at different places because of how Route DNS works.

**How each failure travelled:**

```text
wrong domain   ──► DNS: no such name ──► curl error 6 ──► request never sent
wrong app name ──► wildcard DNS ──► router ──► no Route for this host ──► 503 "Application is not available"
```

**How I found it.**
1. curl error **6** says the name could not be resolved: a DNS problem on the client side; the cluster never saw the request.
2. The 503 page for the second name came from the router, so DNS worked. The router simply had no Route with that exact hostname.
3. Comparing each address with the real one from `oc get route` showed the typo in seconds.

**Why the fix works.** With the exact hostname, DNS resolves it to the router, and the router finds the matching Route.

**How to prevent it.**
- Publish application URLs from the cluster (`oc get route`) or a service catalogue, not by hand.
- For custom domains, create the DNS record (a CNAME to the apps domain) and test it before announcing it.
- In incident triage, **check the hostname spelling first**: it takes ten seconds.

---

## 8. Learnings

**In simple words**
- "Can't find the site" means the address does not exist at all.
- "Application is not available" means you reached the cluster's front desk; then check whether the app is broken **or** the name is simply wrong.

**As an engineer**
- curl error **6** (`Could not resolve host`) = DNS; the request never left the client.
- Wildcard DNS makes **every** `*.apps` name resolve, so a wrong app name reaches the router and shows the same 503 as a broken app.
- First step for any "Application is not available": compare the URL with `oc get route`.

**Interview questions**
- **Q: A user gets "Application is not available", but the app is healthy and the Service has endpoints. What could it be?**
  The hostname does not match any Route: a typo, an old URL, or a Route that was not admitted (for example `HostAlreadyClaimed`). Wildcard DNS sends any `*.apps` name to the router, which returns 503 for unknown hosts.
- **Q: How does a Route hostname get resolved?**
  A wildcard DNS record `*.apps.<cluster-domain>` points at the ingress load balancer or VIP; the router then matches the HTTP `Host` header (or TLS SNI) against Routes.

---

## All six drills on one page

| Drill | What broke | Outside | Inside | The clue | Find it with |
|---|---|---|---|---|---|
| [ND-01](ND-01-scale-to-zero-503.md) | Replicas = 0 | 503 | — | EndpointSlice **empty**, no pods | `oc get deployment` (0/0) |
| [ND-02](ND-02-service-selector-typo-503.md) | Selector typo | 503 | — | EndpointSlice **empty**, pods `1/1` | `svc -o wide` vs `pods --show-labels` |
| [ND-03](ND-03-wrong-targetport-connection-refused.md) | targetPort 9999 | 503 | **refused** (instant) | EndpointSlice has IPs, **wrong PORT** | EndpointSlice PORTS column |
| [ND-04](ND-04-failing-readiness-probe-rollout.md) | Bad readiness probe | **200** | — | New pod `0/1`, `ready=false`, rollout stuck | `oc describe pod` Events |
| [ND-05](ND-05-deny-all-networkpolicy-timeout.md) | Deny-all NetworkPolicy | 200 (HostNetwork router) | **timeout** (10 s) | Hang, curl error 28 | `oc get networkpolicy` |
| ND-06 | Hostname typo | DNS error **or** 503 | — | curl error 6, or 503 for an unknown host | `oc get route` (real host) |

Previous: [ND-05 – Deny-all NetworkPolicy](ND-05-deny-all-networkpolicy-timeout.md) · [Index](README.md)
