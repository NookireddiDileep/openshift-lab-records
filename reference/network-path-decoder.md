# Network path decoder: from "the app is unreachable" to root cause

> Concept note in my own words. Plain-language first, then the real mechanism, then the questions a senior (L4) OpenShift interviewer asks. Use it as the "start here" page when an application cannot be reached. It is the networking twin of the [pod failure states decoder](pod-failure-states-decoder.md): that page answers "why won't my pod run?", this one answers "my pod runs, so why can't anyone reach it?". **New to this? Do the six [network drills](../drills/networking/README.md) first**: each one breaks one hop on a real cluster, and this page will then read as a summary of what you saw. How each component works is explained in [OpenShift architecture](openshift-architecture.md); this page is about what to do when it breaks.

**Contents**

1. [The big picture: the journey of one request](#1-the-big-picture-the-journey-of-one-request)
2. [First split the problem: inside or outside?](#2-first-split-the-problem-inside-or-outside)
3. [The hop-by-hop method](#3-the-hop-by-hop-method)
4. [Symptom → likely layer](#4-symptom--likely-layer)
5. [Name does not resolve (outside)](#5-name-does-not-resolve-outside)
6. [503 "Application is not available"](#6-503-application-is-not-available)
7. [502 Bad Gateway](#7-502-bad-gateway)
8. [504 Gateway Timeout](#8-504-gateway-timeout)
9. [Connection refused](#9-connection-refused)
10. [Connection timed out (silence)](#10-connection-timed-out-silence)
11. [Works sometimes, fails sometimes](#11-works-sometimes-fails-sometimes)
12. [The wrong application answers](#12-the-wrong-application-answers)
13. [TLS problems: edge, passthrough, reencrypt](#13-tls-problems-edge-passthrough-reencrypt)
14. [Inside the cluster: Service DNS and pod-to-pod](#14-inside-the-cluster-service-dns-and-pod-to-pod)
15. [Outbound: the pod cannot reach the outside](#15-outbound-the-pod-cannot-reach-the-outside)
16. [Test toolkit](#16-test-toolkit)
17. [L4 interview drill](#17-l4-interview-drill)

---

## 1. The big picture: the journey of one request

**Plain-language version.** Think of a request as **a phone call to a company**:

1. **Look up the number:** the caller's DNS turns `myapp-myproject.apps.<cluster>` into an address. Every name under `*.apps` points to the same place: the cluster's front desk.
2. **Reach the front desk:** a load balancer (or VIP) passes the call to a **router** pod. The router is HAProxy, run by the Ingress Operator.
3. **The receptionist reads who you asked for:** the router matches the **hostname** (and path) against all **Routes** it knows.
4. **Transferred to the department:** the Route names a **Service**.
5. **The department's current staff list:** the Service's **EndpointSlice** lists the **ready** pod IPs right now.
6. **Through the internal phone system:** **OVN-Kubernetes** carries the packet across nodes to the chosen pod.
7. **Someone picks up:** a process in the container must be **listening on that port**.

Every connectivity failure is **the hop where the call dropped**:

```text
 client ──► DNS (*.apps) ──► load balancer ──► router (HAProxy) ──► Route ──► Service ──► EndpointSlice ──► OVN ──► pod:port
   │            │                  │                 │               │          │             │               │          │
 no name    NXDOMAIN /        timeout /         503 "Application   wrong     selector      empty list     NetworkPolicy  connection
 typed      wrong IP          refused at LB     is not available"  service /  matches no    (no Ready      drops packet   refused /
                                                504 timeout,       port /     pods          pods)          → timeout      502
                                                502 bad response   not                                                    
                                                                   admitted
```

**Rule:** find *which hop* fails and you know *which object or component* to inspect.

| Hop | Object or component | Owned by |
|---|---|---|
| Name → IP | Wildcard DNS `*.apps.<cluster>` | Platform team / DNS team |
| IP → router | Load balancer, VIP or MetalLB | Platform team / network team |
| Router | IngressController, router pods in `openshift-ingress` | Platform team |
| Host → Service | Route | Application team |
| Service → pods | Service selector, ports, EndpointSlice | Application team |
| Packet delivery | OVN-Kubernetes, NetworkPolicy | Platform team (policies: often app team) |
| Port → process | The application, its readiness probe | Application team |

---

## 2. First split the problem: inside or outside?

Before checking hops one by one, cut the path in half with **one test from inside the cluster**:

```bash
# From a throwaway pod in the same project, call the Service directly
oc run nettest --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- \
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://<service>:<port>/
```

| Inside test (Service) | Outside test (Route) | The problem is… |
|---|---|---|
| Works | Works | Not on the server side: the client, its proxy or its DNS |
| Works | Fails | **Outside half:** DNS, load balancer, router, Route, TLS, NetworkPolicy allowing the router |
| Fails | Fails | **Inside half:** Service, endpoints, readiness, ports, the app itself |
| Fails | Works | Rare: the test pod is blocked (NetworkPolicy in its namespace, egress rules) |

This one test usually halves the investigation.

---

## 3. The hop-by-hop method

Walk **outside → in**, one command per hop, and stop at the first hop that is wrong.

| # | Hop | Command | Healthy looks like |
|---|---|---|---|
| 1 | Name resolves | `dig +short <host>` or `getent hosts <host>` | The ingress VIP / load balancer IP |
| 2 | Route admitted | `oc get route <r> -o jsonpath='{.status.ingress[0].conditions[0]}'` | `"type":"Admitted","status":"True"` |
| 3 | Route → Service | `oc get route <r> -o jsonpath='{.spec.to.name} {.spec.port.targetPort}'` | An existing Service, and a port it really has |
| 4 | Service → pods | `oc get svc <s> -o wide` then `oc get pods -l <selector> --show-labels` | The selector matches the pods you expect |
| 5 | Endpoints exist | `oc get endpointslices -l kubernetes.io/service-name=<s>` | Pod IPs and the right port, not empty |
| 6 | Pods Ready | `oc get pods -l <selector>` | `1/1 Running` (Running alone is not enough) |
| 7 | App listening | `oc exec <pod> -- curl -s -o /dev/null -w "%{http_code}" localhost:<port>` | A real HTTP code from inside the pod |
| 8 | Policy allows | `oc get networkpolicy` | No policy, or one that allows the caller (router namespace, other pods) |

**Why outside → in:** the client's error message tells you how far the request got. `NXDOMAIN` never reached the cluster; a router 503 reached the router; `connection refused` reached the pod's network address.

---

## 4. Symptom → likely layer

| What the client sees | How far the request got | Most likely causes | Section |
|---|---|---|---|
| `Could not resolve host`, `HTTP 000` | Nowhere | Typo in host, host outside `*.apps`, client DNS | [§5](#5-name-does-not-resolve-outside) |
| 503 **"Application is not available"** page | The router | Route not admitted, no Ready endpoints, Route → wrong Service | [§6](#6-503-application-is-not-available) |
| 502 Bad Gateway | The pod, which answered badly | HTTP sent to a TLS port (or the reverse), app resets the connection | [§7](#7-502-bad-gateway) |
| 504 Gateway Timeout | The pod, which answered too slowly | Slow app, router timeout (30 s default) | [§8](#8-504-gateway-timeout) |
| `Connection refused` | The pod's IP | Nothing listening on that port, app bound to 127.0.0.1 | [§9](#9-connection-refused) |
| Hangs, then times out | Somewhere packets are silently dropped | NetworkPolicy, firewall, wrong IP | [§10](#10-connection-timed-out-silence) |
| Some requests fail | Some backends are bad | One unhealthy pod still Ready, wrong pods in the selector | [§11](#11-works-sometimes-fails-sometimes) |
| A different app answers | The wrong backend | Selector too broad, host claimed by another Route | [§12](#12-the-wrong-application-answers) |
| Certificate errors, `SSL_ERROR`, redirect loops | The TLS layer | Wrong termination type, certificate, insecure policy | [§13](#13-tls-problems-edge-passthrough-reencrypt) |

---

## 5. Name does not resolve (outside)

**Plain words:** the caller has the wrong phone number, or the phone book has no entry. The request never reaches the cluster.

**Mechanism:** every Route host must sit under the cluster's **wildcard DNS** record, `*.apps.<cluster-domain>`, which points at the ingress load balancer. A host outside that domain resolves to nothing unless someone creates a DNS record for it.

**Check:**
```bash
oc get route <r> -o jsonpath='{.spec.host}{"\n"}'
oc get ingresses.config/cluster -o jsonpath='{.spec.domain}{"\n"}'    # the apps domain
getent hosts <host>
```

**Typical causes:**
- A typo in a hand-written host (`aps` instead of `apps`, a misspelled cluster name). [RCA-003](../rca/RCA-003-route-unreachable-three-faults.md) had four of these at once.
- A custom domain (`shop.example.com`) without a DNS record (CNAME) pointing at the apps domain.
- The client uses a DNS server that cannot see internal cluster names (laptop off VPN).

**Fix:** let OpenShift generate the host (`oc expose service <s>` with no `--hostname`), or create the DNS record for a custom domain.

---

## 6. 503 "Application is not available"

**Plain words:** the receptionist answered but had nobody to transfer the call to.

**Mechanism:** the router (HAProxy) returns its own 503 page when it has **no usable backend** for the host. Three different reasons produce the same page:

| Reason | Check | Fix |
|---|---|---|
| **Route not admitted** (router ignored it) | `oc get route <r> -o yaml` → `status.ingress[].conditions` | Read the reason: `HostAlreadyClaimed` (another namespace owns the host), invalid TLS config, host outside the allowed domain |
| **Route points at a missing Service or port** | `.spec.to.name`, `.spec.port.targetPort` vs `oc get svc` | Correct the name; `targetPort` must match the Service port's **name** or the pod's container port number |
| **No Ready endpoints** | `oc get endpointslices -l kubernetes.io/service-name=<s>` | Fix the selector/labels, or why pods are not Ready ([pod decoder §12](pod-failure-states-decoder.md#12-running-but-not-ready-01)) |

**The classic trap:** pods show `Running`, so "the app is fine". But `Running 0/1` means **not Ready**, and the EndpointSlice leaves not-ready pods out of traffic. A failing readiness probe turns a healthy-looking app into a 503.

**Also 503:** a host the router does not know at all. Check the host spelling against the Route before anything else.

---

## 7. 502 Bad Gateway

**Plain words:** someone picked up the phone but spoke a language the receptionist did not understand, or hung up immediately.

**Mechanism:** the router reached the pod, but the response was invalid or the connection was reset.

**Typical causes:**
- **Protocol mismatch:** an edge Route (router → pod in plain HTTP) pointing at a port where the app expects TLS, or a reencrypt Route pointing at a plain HTTP port.
- The application crashes or closes the connection while handling the request (check `oc logs` and restarts at the same time).
- Response headers too large for the router's buffers.

**Check:** call the pod port directly from inside (`curl -v http://<pod-ip>:<port>` and `curl -vk https://<pod-ip>:<port>`). Whichever one works tells you what the port really speaks.

---

## 8. 504 Gateway Timeout

**Plain words:** the department picked up but kept the caller waiting too long, so the receptionist gave up.

**Mechanism:** the router waits for the backend up to its **server timeout, 30 seconds by default**, then returns 504.

**Check and fix:**
```bash
# Time the request from inside the cluster, bypassing the router
oc run nettest --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- \
  curl -s -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" http://<service>:<port>/<path>

# If a slow endpoint is expected (a report, an export), raise the timeout for that Route only
oc annotate route <r> --overwrite haproxy.router.openshift.io/timeout=120s
```

**L4 point:** raising the timeout treats the symptom. Ask *why* the request takes more than 30 seconds: a slow database, CPU throttling from a low limit, or a long-running job that should be asynchronous.

---

## 9. Connection refused

**Plain words:** the call reached the right desk, but nobody sits there.

**Mechanism:** the packet reached the pod's IP, but no process is listening on that port, so the kernel answers immediately with a reset. Refused is **fast**; a timeout is **slow** (§10). That difference alone tells you which section you are in.

**Typical causes:**
- **Wrong port:** the Service `targetPort` or the Route port does not match the port the app actually listens on (common: the image listens on 8080, the Service says 80).
- **App bound to `127.0.0.1`:** it accepts connections only from inside its own container. It must listen on `0.0.0.0`.
- The app has not finished starting (a startup or readiness probe should cover this window).

**Check inside the pod:**
```bash
oc exec <pod> -- ss -ltnp 2>/dev/null || oc exec <pod> -- cat /proc/net/tcp   # what is listening, and on which address
oc get svc <s> -o jsonpath='{.spec.ports}{"\n"}'
```

---

## 10. Connection timed out (silence)

**Plain words:** the call went into a void. No ringing, no busy tone, nothing.

**Mechanism:** packets are **silently dropped** somewhere. On OpenShift the usual cause is a **NetworkPolicy**: once any policy selects a pod, all traffic not explicitly allowed is dropped, with no error sent back.

**The OpenShift-specific trap:** a project adds a "deny all ingress" policy, then allows only its own pods. Internal calls work, but the **router** lives in another namespace (`openshift-ingress`), so every Route now times out. The fix is a policy allowing the ingress namespaces:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-openshift-ingress
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          policy-group.network.openshift.io/ingress: ""
  policyTypes:
  - Ingress
```

This is the pattern from the [OpenShift network policy documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/network_security/network-policy). The label is set by OpenShift on its ingress namespaces; never add it to your own projects.

**Check:**
```bash
oc get networkpolicy
oc describe networkpolicy <name>      # which pods it selects, and what it allows
```

**Other causes of silence:** a stale IP hard-coded instead of a Service name; external firewalls between the client and the load balancer; a load balancer health check that has marked every router as down.

---

## 11. Works sometimes, fails sometimes

**Plain words:** some of the staff answer well, some don't, and you get whoever is free.

**Mechanism:** the Service and the router spread requests across all Ready endpoints. If one backend is broken but still passes its readiness probe, a share of requests fail.

**Typical causes:**
- A readiness probe that is too shallow (checks that the process is alive, not that it can serve).
- Pods from an **old version** still matching the selector after a manual change.
- A selector that also matches unrelated pods (§12).
- One node with a network problem: compare failing requests with the node of the pod that served them.

**Check:** list endpoints with their pods and nodes, then test each pod IP directly from inside the cluster:
```bash
oc get pods -l <selector> -o wide
# for each IP:
oc run nettest --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://<pod-ip>:<port>/
```

---

## 12. The wrong application answers

**Plain words:** the call was transferred to the wrong department.

**Typical causes:**
- **A selector that is too broad:** `app=web` matches pods of two different Deployments.
- **Two Routes for the same host** in different namespaces: the oldest one wins, the newer one shows `HostAlreadyClaimed`.
- **Path-based Routes** overlapping (`/` and `/api` on the same host): check which Route has the more specific path.

**Check:**
```bash
oc get pods -l <selector> --show-labels
oc get route -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.host,PATH:.spec.path | grep <host>
```

---

## 13. TLS problems: edge, passthrough, reencrypt

**Plain words:** the call is scrambled for privacy, and someone along the line has the wrong key.

| Termination | Who decrypts | Pod port speaks | Common failure |
|---|---|---|---|
| **None** (plain) | Nobody | HTTP | Browser forced to HTTPS by HSTS or a redirect |
| **Edge** | The router | HTTP | Wrong or expired certificate on the Route; `insecureEdgeTerminationPolicy` not set, so plain HTTP gets 503 |
| **Passthrough** | The pod | HTTPS | Router cannot read paths or headers; the client must send SNI; the pod's certificate must match the host |
| **Reencrypt** | Router, then pod again | HTTPS | Router does not trust the pod's certificate: set `destinationCACertificate`, or use a service-serving certificate |

**Check:**
```bash
oc get route <r> -o jsonpath='{.spec.tls}{"\n"}'
curl -vk https://<host>/ 2>&1 | grep -iE 'subject|issuer|expire|HTTP/'
```

**Insecure policy:** `insecureEdgeTerminationPolicy: Redirect` sends HTTP to HTTPS; `Allow` serves both; `None` (default) means plain HTTP to a TLS Route gets nothing useful. Redirect loops usually mean the app also redirects to HTTPS because it cannot see that TLS ended at the router (it should read the `X-Forwarded-Proto` header).

---

## 14. Inside the cluster: Service DNS and pod-to-pod

**Plain words:** two departments of the same company cannot reach each other.

**Mechanism:** each pod's `/etc/resolv.conf` points at the cluster DNS Service (CoreDNS in `openshift-dns`) and carries a search list (`<ns>.svc.cluster.local svc.cluster.local cluster.local`) with `ndots:5`.

**Which name to use:**

| Caller | Name that works |
|---|---|
| Same project | `<service>` |
| Another project | `<service>.<project>` or `<service>.<project>.svc.cluster.local` |
| Anywhere, fastest lookup | `<service>.<project>.svc.cluster.local.` (trailing dot skips the search list) |

**Check:**
```bash
oc run nettest --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- \
  bash -c 'cat /etc/resolv.conf; getent hosts <service>.<project>; timeout 3 bash -c "</dev/tcp/<service>.<project>/<port>" && echo OPEN || echo CLOSED'
```

**Typical causes:** short name used across projects; a NetworkPolicy in the *target* project that allows only its own namespace; a headless Service (`clusterIP: None`) where the caller expected one stable IP.

---

## 15. Outbound: the pod cannot reach the outside

**Plain words:** the department can take calls but cannot call out.

**Typical causes:**
- **EgressFirewall** (OVN-Kubernetes, per project) blocking the destination.
- **NetworkPolicy with `policyTypes: [Egress]`** that forgets to allow DNS (UDP/TCP 53 to `openshift-dns`), so every name lookup fails.
- **Cluster-wide proxy** required: the app ignores `HTTP_PROXY`/`HTTPS_PROXY`, or the destination is missing from `NO_PROXY`.
- A corporate firewall that only allows known **egress IPs**; configure an EgressIP for the project.

**Check:**
```bash
oc get egressfirewall 2>/dev/null; oc get networkpolicy
oc get proxy/cluster -o jsonpath='{.spec}{"\n"}'
oc exec <pod> -- getent hosts <external-host>
```

---

## 16. Test toolkit

| Need | Command |
|---|---|
| Throwaway test pod | `oc run nettest --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- <cmd>` |
| HTTP code only | `curl -s -o /dev/null -w "%{http_code}\n" <url>` |
| Timing breakdown | `curl -s -o /dev/null -w "dns %{time_namelookup} connect %{time_connect} tls %{time_appconnect} total %{time_total}\n" <url>` |
| Test a host without DNS | `curl -s --resolve <host>:80:<router-ip> http://<host>/` |
| Is a TCP port open (no curl, no nc) | `timeout 3 bash -c "</dev/tcp/<host>/<port>" && echo OPEN \|\| echo CLOSED` |
| Name lookup inside a pod | `getent hosts <name>` |
| Bypass Service and Route | `oc port-forward pod/<pod> 8080:<port>` then `curl localhost:8080` |
| Router access log for one host | Ask the platform team; router logs are in `openshift-ingress` and need elevated access |

Use `getent` and `/dev/tcp` because minimal images often have no `nslookup`, `dig` or `nc`.

---

## 17. L4 interview drill

Answer each in under two minutes: symptom → which hop → evidence → fix → prevention.

1. A Route returns 503, the pods are `Running`. Walk me through it. *(§6: readiness, endpoints, admitted)*
2. The app works with `oc port-forward` but not through the Route. Where do you look? *(§2: the outside half)*
3. `Connection refused` vs `connection timed out`: what does each tell you? *(§9, §10)*
4. Everything broke right after a team applied "deny all" NetworkPolicies. Internal calls still work. *(§10: allow the router namespace)*
5. A report endpoint fails after exactly 30 seconds with 504. *(§8: router timeout, but find the slowness)*
6. Two teams' apps answer on the same hostname. *(§12: host claims)*
7. 502 after switching a Route from edge to reencrypt. *(§7, §13: the pod port must speak TLS, and the router must trust it)*
8. One request in four fails. *(§11: one bad backend)*
9. Pods in project A cannot call `api` in project B. *(§14: name, and NetworkPolicy in B)*
10. After a proxy was configured cluster-wide, pods cannot reach an internal service. *(§15: `NO_PROXY`)*
11. How does a request get from a browser to a pod in OpenShift? Name every component. *(§1)*
12. Why is `Running` not enough for a pod to receive traffic? *(§6: readiness and EndpointSlices)*

**What makes an answer L4 rather than L2:** you locate the **hop** before touching anything, use the **error type** (DNS error, 503, 502, 504, refused, timeout) to say how far the request got, prove it with **one test from each side** of the suspected hop, and end with **prevention**: generated hosts, readiness probes that test real dependencies carefully, a standard "allow from ingress" policy in every project template, and alerts on Routes with no endpoints.

See also: [Network drills ND-01 to ND-06](../drills/networking/README.md) · [Pod failure states decoder](pod-failure-states-decoder.md) · [OpenShift architecture: networking](openshift-architecture.md) · [oc command bank](oc-command-bank.md) · [RCA-003: Route unreachable, three faults](../rca/RCA-003-route-unreachable-three-faults.md)
