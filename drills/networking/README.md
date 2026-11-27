# Network drills: break the path, read the error, find the hop

Six hands-on break-and-fix drills on a real OpenShift 4.19 cluster. Each one breaks **one hop** of the path a request takes from a browser to a pod, records exactly what the user and the engineer see, then walks to the root cause and the fix.

Every drill follows the same eight sections, written so a newcomer can follow it:

1. **Problem statement**
2. **Detailed description of the problem**: the story, the idea in plain words, the terms you need
3. **Lab setup**: environment and every command to build the app
4. **My lab execution summary**: each step with its time and command
5. **Observations**: the real outputs, explained
6. **Lab results**: before / broken / after
7. **Detailed solution explanation (RCA)**: root cause, how it travelled, how I found it, why the fix works, prevention
8. **Learnings**: in simple words, as an engineer, and interview questions

## The path every drill breaks

```text
 browser
    │  hello-netlab.apps.ocp.example.com
    ▼
 DNS (*.apps wildcard) ─────────────────────── ND-06  wrong hostname
    ▼
 router (HAProxy) ─► Route "hello"
    ▼
 Service "hello" ── selector / targetPort ──── ND-02  selector typo · ND-03  wrong port
    ▼
 EndpointSlice (Ready pod IPs) ─────────────── ND-01  no pods · ND-04  pod not Ready
    ▼
 NetworkPolicy ─────────────────────────────── ND-05  deny-all drops packets
    ▼
 pod:8080 (Apache)
```

## The drills

| ID | Drill | What the user sees | Root cause | Key lesson |
|---|---|---|---|---|
| [ND-00](ND-00-lab-setup.md) | Lab setup and healthy baseline | `HTTP 200` | — | Record "good" before breaking anything |
| [ND-01](ND-01-scale-to-zero-503.md) | No pods at all | 503 "Application is not available" | Deployment scaled to 0 | Router 503 = look **behind** the Route; empty EndpointSlice + no pods |
| [ND-02](ND-02-service-selector-typo-503.md) | Healthy pods, Service can't find them | 503 | Selector `app=helo` vs labels `app=hello` | Empty EndpointSlice + pods `1/1` = compare selector and labels |
| [ND-03](ND-03-wrong-targetport-connection-refused.md) | Wrong target port | 503 outside, **connection refused** inside | `targetPort` 9999, app on 8080 | Check the EndpointSlice **PORT**; test from inside to see the real error |
| [ND-04](ND-04-failing-readiness-probe-rollout.md) | Bad readiness probe in a release | **200** (no impact) | Probe URL returns 404 | Readiness stops a bad release safely; `oc rollout undo` |
| [ND-05](ND-05-deny-all-networkpolicy-timeout.md) | Deny-all NetworkPolicy | Inside: **timeout**; outside: 200 | Policy drops pod-to-pod traffic | Timeout = silent drop; same YAML behaves differently on a HostNetwork router |
| [ND-06](ND-06-hostname-typo-dns-vs-router.md) | Hostname typo | DNS error **or** 503 | Wildcard DNS | A 503 can be just a mistyped URL; check the host first |

## The error map I built from these drills

```text
What the client sees                How far the request got          First thing to check
──────────────────────────────────  ───────────────────────────────  ─────────────────────────────────────
Could not resolve host (curl 6)     Nowhere (DNS)                    Hostname spelling, domain part (ND-06)
503 "Application is not available"  The router                       1. Hostname spelling (ND-06)
                                                                     2. EndpointSlice empty? → pods? (ND-01)
                                                                        → selector vs labels? (ND-02)
                                                                     3. EndpointSlice PORT right? (ND-03)
Connection refused (curl 7)         Pod IP, nothing on that port     Service targetPort vs app port (ND-03)
Hangs → timeout (curl 28)           Packets silently dropped         oc get networkpolicy (ND-05)
200, but release stuck at 0/1       Old version still serving        Readiness probe → pod Events (ND-04)
```

**Same 503 to the user, four different causes.** The EndpointSlice and one test from inside the cluster tell them apart.

## How to repeat the drills

1. Build the app with [ND-00](ND-00-lab-setup.md) in a project of your own.
2. For each drill: record the baseline, break **one** thing, observe from outside **and** inside, walk the path from outside in, fix, verify `HTTP 200`.
3. Predict the result before running each break. A wrong prediction is the most useful kind; ND-05 surprised me.

---

All hostnames, IPs and project names are sanitised. Back to the [repository index](../../README.md).
