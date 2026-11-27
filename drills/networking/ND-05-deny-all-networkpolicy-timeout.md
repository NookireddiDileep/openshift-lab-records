# ND-05 – A "deny all" NetworkPolicy: the silent failure (timeout)

| Quick facts | |
|---|---|
| **Date and duration** | 2026-11-27, 17:54–18:09 (15 minutes) |
| **Platform** | Shared lab OpenShift 4.19, project `netlab`, router published as **HostNetwork** |
| **Symptom** | Calls from other pods **hang**, then time out after 10 s. Calls through the Route **still work** (surprise) |
| **Root cause** | A NetworkPolicy silently drops all incoming pod-to-pod traffic that is not explicitly allowed |
| **Fix** | Keep deny-all and add an "allow same project" policy; both deleted after the drill |

---

## 1. Problem statement

After a security change, other applications that call `hello` inside the cluster start **hanging** until they give up. Find out why the calls hang instead of failing quickly, check whether outside users are affected, and restore internal access the right way.

---

## 2. Detailed description of the problem

**What happened (the story).** The security team asks every project to block all incoming traffic by default. Someone applies a **"deny all"** policy to the `netlab` project and forgets to allow anything back in.

**In plain words.** The building installs a new security door that admits nobody. Visitors are not turned away with a "closed" sign; the door simply never opens. They stand and wait until they give up.

**What you need to know to understand it:**

| Term | Simple meaning |
|---|---|
| **NetworkPolicy** | A firewall rule for pods |
| Default behaviour | Every pod accepts traffic from anywhere |
| After a policy selects a pod | Everything **not explicitly allowed** is **silently dropped** |
| Silently dropped | No reply at all, like `iptables -j DROP` (not `-j REJECT`) |
| **HostNetwork router** | The router pods run on the node's own network, not the pod network. On this cluster, that is how the router is published |

**Two kinds of failure that feel different:**

| Failure | Speed | Meaning |
|---|---|---|
| **Connection refused** ([ND-03](ND-03-wrong-targetport-connection-refused.md)) | Instant | Something answered "no": wrong port, nothing listening |
| **Connection timed out** (this drill) | Waits for the full timeout | **Nobody answered**: packets dropped, usually a NetworkPolicy or a firewall |

---

## 3. Lab setup

**Environment**

| Item | Value |
|---|---|
| Cluster | Shared lab OpenShift 4.19 (Kubernetes 1.32), 2 nodes: `master-0`, `worker-1` |
| Router | Default IngressController, endpoint publishing strategy **HostNetwork** |
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
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H      # HTTP 200
oc get networkpolicy                                           # No resources found: project is open
```

**Test helpers used here: timed calls from outside and from inside**

```bash
# outside, through the Route; give up after 20 s; print how long it took
curl -s -o /dev/null --max-time 20 -w "outside: HTTP %{http_code} after %{time_total}s\n" http://$H
# inside, from a throwaway pod straight to the Service; give up after 10 s
oc run tester --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- \
  curl -sS -o /dev/null --max-time 10 -w "inside: HTTP %{http_code} after %{time_total}s\n" http://hello:8080
```

`%{time_total}` prints how long the request took. **That number is the clue in this drill.**

---

## 4. My lab execution summary

| # | Time | What I did | Command |
|---|---|---|---|
| 1 | 17:54–17:57 | **Applied** a deny-all policy | `oc apply -f -` with the `deny-all` YAML (below) |
| 2 | 17:57 | Timed calls from outside and inside | The two test helpers above |
| 3 | 18:01 | Repeated the outside call 6 times, 10 s apart | `for i in 1 2 3 4 5 6; do curl …; sleep 10; done` |
| 4 | 18:01 | Checked how the router is published | `oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.endpointPublishingStrategy.type}{"\n"}'` |
| 5 | 18:07 | **Fixed:** added an "allow same project" policy and tested inside again | `oc apply -f -` with the `allow-same-namespace` YAML · inside test |
| 6 | 18:09 | Cleaned up | `oc delete networkpolicy deny-all allow-same-namespace` |

**The deny-all policy (step 1):**

```bash
cat <<'EOF' | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

| YAML line | Meaning |
|---|---|
| `podSelector: {}` | Empty braces = **every pod** in this project |
| `policyTypes: [Ingress]` | The policy is about **incoming** traffic |
| (no `ingress:` list) | **Nothing** is allowed in |

`cat <<'EOF' | oc apply -f -` feeds the YAML straight into `oc apply` without saving a file.

**The fix (step 5):**

```bash
cat <<'EOF' | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
EOF
```

`from: - podSelector: {}` = allow traffic **from any pod in this same project**.

---

## 5. Observations

**Timed calls after deny-all (step 2):**

```text
outside: HTTP 200 after 0.007222s
Warning: would violate PodSecurity "restricted:latest": … (harmless warning for the test pod)
inside: HTTP 000 after 10.001168s
curl: (28) Connection timed out after 10001 milliseconds
pod "tester" deleted
pod netlab/tester terminated (Error)
```

| Path | Result | Meaning |
|---|---|---|
| **Inside** (pod → Service) | `curl: (28) Connection timed out` after the **full 10 s** | Textbook: the request was not refused, it was **ignored** |
| **Outside** (Route) | `HTTP 200` in **7 ms** | **Surprise**: the router's request got through |

**Investigating the surprise instead of guessing (steps 3–4).** Two possible explanations: (1) the router was reusing a connection opened before the policy, or (2) the router's traffic is treated differently because of how it is deployed.

```text
try 1: HTTP 200 after 0.002018s
try 2: HTTP 200 after 0.002090s
try 3: HTTP 200 after 0.002449s
try 4: HTTP 200 after 0.002401s
try 5: HTTP 200 after 0.001961s
try 6: HTTP 200 after 0.002138s
HostNetwork
```

- Six tries over a minute, all `200` in about 2 ms: **not** a single leftover connection.
- The router is published as **`HostNetwork`**: its traffic reaches application pods from the node, not from the pod network.

**Recorded as observed behaviour:** on this HostNetwork-published cluster, a deny-all ingress policy blocked pod-to-pod traffic but **not** traffic from the router. A normal project user cannot inspect OVN-Kubernetes internals to prove the exact mechanism. Red Hat documents a separate `allow-from-hostnetwork` policy for host-network traffic, which shows the platform treats it as a distinct source.

---

## 6. Lab results

**After adding `allow-same-namespace` (step 5):**

```text
networkpolicy.networking.k8s.io/allow-same-namespace created
NAME                   POD-SELECTOR   AGE
allow-same-namespace   <none>         0s
deny-all               <none>         10m
inside: HTTP 200 after 0.005329s
pod "tester" deleted
```

- `POD-SELECTOR <none>` is how `podSelector: {}` is displayed: the policy applies to **all** pods.
- Policies **add up**: deny-all + allow-same-namespace = project pods can talk to each other; pods from other projects are dropped.

| | No policy | deny-all only | deny-all + allow-same-namespace |
|---|---|---|---|
| Inside (same project) | `200` fast | **timeout (10 s)** | `200` in 5 ms ✅ |
| Outside (Route, HostNetwork router) | `200` | `200` (not blocked here) | `200` |
| Pods from other projects | allowed | dropped | dropped |

**Clean-up (step 6):** both policies deleted; the project is open again.

---

## 7. Detailed solution explanation (RCA)

**Root cause.** A NetworkPolicy that selects every pod but allows no incoming traffic, so all pod-to-pod connections were silently dropped.

**How the failure travelled:**

```text
deny-all selects every pod ──► incoming pod-to-pod packets not allowed ──► silently dropped ──► caller waits ──► timeout
router on HostNetwork ──► traffic arrives from the node ──► not blocked on this cluster ──► Route keeps working
```

**How I found it.**
1. The inside call **hung** for the whole 10 seconds (curl error 28) instead of failing instantly → packets dropped, not refused.
2. `oc get networkpolicy` showed `deny-all` selecting all pods with no allow rules.
3. The outside result did not match expectations, so I tested it repeatedly and checked the router's publishing strategy instead of assuming.

**Why the fix works.** Policies are additive. Adding `allow-same-namespace` opens exactly one door (same-project pods) while the deny-all keeps everything else out. That is the standard production pattern: **deny by default, then allow what is needed**.

**On a cloud cluster** (router on the pod network), the same deny-all would also have broken the Route. The fix there is an extra policy allowing ingress from the router's namespaces:

```yaml
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          policy-group.network.openshift.io/ingress: ""
```

**How to prevent it.**
- Ship a standard policy set in the project template: deny-all + allow-same-namespace + allow-from-ingress (+ allow-from-monitoring).
- After any network policy change, test **both** paths: inside (pod to Service) and outside (through the Route).
- Document how the cluster's router is published; it changes how policies behave.

---

## 8. Learnings

**In simple words**
- An instant "no" means someone answered and refused.
- Waiting until you give up means nobody answered at all: look for a firewall rule.

**As an engineer**
- **Timeout (curl 28) = silent drop = check `oc get networkpolicy` first.**
- Policies add up: write deny-all, then explicit allows.
- **The same YAML can behave differently on different clusters.** Here, how the router is published decided whether the Route broke. Never assume; test.
- "Deny all" did not mean "deny all" for router traffic on this cluster. A security team relying on it for isolation from outside would be wrong here.

**Interview questions**
- **Q: Connection refused vs connection timed out?**
  Refused is instant: the destination answered "nothing here". Timed out means no answer at all: packets dropped by a NetworkPolicy, firewall or routing problem.
- **Q: After applying deny-all policies, every Route broke but internal calls still work. Why, and the fix?**
  The router lives in another namespace, so its traffic is now denied. Allow ingress from namespaces labelled `policy-group.network.openshift.io/ingress: ""`. (On my HostNetwork lab cluster the Route was not affected at all, which is why testing both paths matters.)
- **Q: How do you design network policies for a multi-tenant cluster?**
  Default deny in every project via the project template, allow same-namespace, allow from ingress and monitoring, then explicit cross-project allows reviewed like firewall changes.

---

Previous: [ND-04 – Failing readiness probe](ND-04-failing-readiness-probe-rollout.md) · Next: [ND-06 – Hostname typo](ND-06-hostname-typo-dns-vs-router.md) · [Index](README.md)
