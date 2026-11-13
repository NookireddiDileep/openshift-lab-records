# OCP-017: Deploy an application with the Blue-Green deployment strategy

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Release strategies · Routes · Zero-downtime switching |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~25 min |
| **Status** | Done |
| **Related** | [OCP-008 – rolling update via ImageStream trigger](OCP-008-imagestream-trigger-and-route.md) · [OCP-016 – Ingress](OCP-016-ingress-default-controller.md) |

## 1. User story / requirement
> As a **release manager**, I want to **deploy a new version alongside the current one and switch all users to it at once**, so that **I can test the new version in production conditions first, release with zero downtime, and roll back instantly**.

## 2. Acceptance criteria
- [x] Two complete versions running side by side (blue = v1, green = v2)
- [x] Users served by blue while green is reachable on a private test URL
- [x] Traffic switched from blue to green with **zero failed requests**
- [x] **Instant rollback** to blue demonstrated, then final switch to green
- [x] Browser shows the live version

## 3. Background / concepts
| | Rolling update (default) | **Blue-Green** |
|---|---|---|
| Versions during release | old and new mixed | both complete, side by side |
| Test new version before users see it | no | **yes** – separate test URL |
| Switch | gradual, Pod by Pod | **instant, all at once** |
| Rollback | another rollout | **repoint – seconds** |
| Resource cost | ~1× | **~2×** while both run |

On OpenShift the switch is a **Route backend change**:
```
                 ┌──► Service bg-blue  ──► Deployment bg-blue  (v1)   ← live first
Route bg ────────┤        (oc patch route bg spec.to.name)
 (public URL)    └──► Service bg-green ──► Deployment bg-green (v2)   ← live after switch
Route bg-green-test ──► Service bg-green   (private test URL)
```
Both versions use the same UBI httpd image; each serves its own page from a **ConfigMap** – a fast way to create two visibly different versions without building images.

## 4. Plan
1. Deploy blue and green (2 replicas each, readiness probes, hardened), each with its own Service.
2. Public Route `bg` → blue; test Route `bg-green-test` → green.
3. Smoke-test green on the test URL.
4. Switch the public Route to green while a background loop sends a request every 0.5 s.
5. Roll back to blue, then switch to green again.
6. **Rollback / cleanup:** repoint the Route to blue; later `oc delete all,cm,route -l app=bg`.

## 5. Implementation
Manifests: [`scripts/OCP-017/bluegreen.yaml`](../scripts/OCP-017/bluegreen.yaml) · safe switch script: [`scripts/OCP-017/switch.sh`](../scripts/OCP-017/switch.sh)
```bash
oc apply -f bluegreen.yaml
oc expose service/bg-blue  --name=bg               # public route → blue
oc expose service/bg-green --name=bg-green-test    # private test route → green
oc patch route bg --type=merge -p '{"spec":{"to":{"name":"bg-green"}}}'   # the switch
oc patch route bg --type=merge -p '{"spec":{"to":{"name":"bg-blue"}}}'    # rollback
```

## 6. Validation / evidence
**Both versions running, each Service with its own endpoints:**
```
deployment.apps/bg-blue    2/2     2     2
deployment.apps/bg-green   2/2     2     2
endpoints/bg-blue    <ip>:8080,<ip>:8080
endpoints/bg-green   <ip>:8080,<ip>:8080
```
**Live = blue; test URL just after creation:**
```
$ curl -s http://$LIVE/ | grep -o '<h1>.*</h1>'
<h1>BLUE - version 1</h1>
$ curl -s http://$TEST/ | grep -o '<h1>.*</h1>'
<h1>Application is not available</h1>       ← router hadn't loaded the new test route yet (see §7)
```
**The switch – one request every 0.5 s during the change:**
```
12:54:28.329 BLUE
...
12:54:31.381 BLUE
12:54:31.894 GREEN        ← switched between two requests
12:54:32.403 GREEN
...
12:54:38.001 GREEN
errors during switch: 0
ROUTE   SERVICE
bg      bg-green
```
**Rollback and final switch:**
```
$ oc patch route bg ... bg-blue     →  <h1>BLUE - version 1</h1>
$ oc patch route bg ... bg-green    →  (2 s later) <h1>BLUE - version 1</h1>   ← still blue: router reload interval
```
**Final state (re-checked):**
```
live route -> bg-green
live: GREEN   test: GREEN    (× 5)
RELOAD_INTERVAL=5s           ← router-default setting
```
All four Pods ran throughout (2 blue + 2 green, spread across both nodes).

## 7. Issues hit & observations
| # | Observation | Explanation / impact |
|---|---|---|
| 1 | **Zero failed requests** during the switch | Both versions were fully running and ready; the Route change only changes which backend the router uses |
| 2 | Test route answered `Application is not available` right after `oc expose` | The router applies config changes in batches – **`RELOAD_INTERVAL=5s`**. The new route wasn't loaded yet, so **green wasn't really smoke-tested before the switch** in this run |
| 3 | Final check showed BLUE 2 s after switching to green | Same reload interval – route changes take **up to ~5 s** to apply. The first switch looked instant only because the patch happened just before a reload |
| 4 | 2× resources while both versions run | Accepted cost of Blue-Green; scale the old colour to 0 once the new one is confirmed (keep it for fast rollback until then) |
| 5 | Pasted heredoc display garbled again | Terminal echo only; all objects were created correctly (dry-run and apply output confirm) |

**Fix for #2/#3, built into [`switch.sh`](../scripts/OCP-017/switch.sh):** check the target has ready endpoints, **retry the smoke test until the test route answers** (covers the reload delay), then switch, then verify over ~10 s.

## 8. Production considerations
- **Stateful dependencies**: both colours usually share one database – schema changes must be backward-compatible (expand/contract), or rollback breaks.
- Sessions: long-lived connections/sessions may stay on blue briefly; drain or use sticky-session-aware design.
- Use readiness probes (done here) so the "green" backend is only used when it can serve.
- Automate in a pipeline/GitOps (switch = a change to the Route manifest), with smoke tests gating the switch.
- **Canary / A-B alternative**: the same Route can split traffic by weight (`oc set route-backends bg bg-blue=90 bg-green=10`) to release gradually instead of all at once.
- Scale down the idle colour after a soak period to recover resources.

## 9. Lessons learned
- Blue-Green on OpenShift = two Deployments + two Services + one Route repointed with `oc patch`.
- Router changes are **eventually applied** (~5 s here) – never conclude "it's broken" or "it worked" from a check made 1–2 s after a route change.
- A smoke test only counts if it actually reached the new version.

## 10. Interview talking point
> "I implemented Blue-Green with two Deployments and Services and one public Route. Green had its own private test route; the release was a single `oc patch` of the Route's backend. With a request every half second during the switch there were zero errors, and rollback was the same command back to blue. I also found the router applies route changes on a 5-second reload interval – my test route returned 'Application is not available' right after creation, so green hadn't truly been smoke-tested. I scripted the switch to wait for the test route to answer, check endpoints, switch, then verify. For gradual releases the same Route supports weighted backends for canaries."
