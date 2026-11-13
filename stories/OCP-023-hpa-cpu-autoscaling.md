# OCP-023: Horizontal Pod Autoscaler – min 2, max 5 Pods, scale at 60% CPU

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Autoscaling · HPA · Resource requests · Metrics |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~25 min (incl. ~9 min load test) |
| **Status** | Done |
| **Related** | [OCP-003 – manual scaling](OCP-003-scale-deployment.md) |

## 1. User story / requirement
> As an **application owner**, I want my application to **scale automatically between 2 and 5 Pods based on CPU**, scaling out when CPU utilization reaches **60%**, so that **it handles load spikes without wasting resources when idle**.

## 2. Acceptance criteria
- [x] Application with CPU **requests** (required for CPU-% autoscaling)
- [x] HPA: **min 2, max 5, target 60% CPU**
- [x] Under load: **scaled up** (2 → 4 → 5, capped at max)
- [x] After load: **scaled down** back to **2** (min)
- [x] Evidence from HPA events with timings

## 3. Background / concepts
```
desired = ceil( currentReplicas × currentCPU% / targetCPU% )     (evaluated every ~15 s)
CPU% = Pod CPU usage ÷ Pod CPU REQUEST  (averaged over the Pods)
```
- **No CPU request → no CPU %** → HPA shows `<unknown>/60%` and never scales.
- **Scale-up** reacts within one or two 15 s cycles (default policy may add up to 100% or 4 Pods per 15 s).
- **Scale-down** waits for a **stabilization window of 300 s**: the HPA uses the highest recommendation of the last 5 minutes, which prevents flapping.
- Metrics come from the cluster monitoring stack via the resource-metrics API (`oc adm top pods` works = metrics available).

## 4. Plan
1. Check metrics are available.
2. Deployment with `requests: cpu 50m`, `limits: cpu 200m`, 2 replicas.
3. `oc autoscale --min=2 --max=5 --cpu-percent=60`; confirm the HPA reads metrics.
4. Burn CPU in **one** Pod for 180 s (`timeout 180 sha256sum /dev/zero`): one Pod at its 200 m limit ≈ (200+1)/2 ≈ 100 m average = **≈200% of request** → desired = ceil(2×200/60) = 7 → **capped at 5**.
5. Watch ~9 min; read the HPA events.
6. **Rollback:** `oc delete hpa hpa-app` (replicas stay where they are) → `oc scale deploy/hpa-app --replicas=N`.

## 5. Implementation
Declarative version: [`scripts/OCP-023/hpa-app.yaml`](../scripts/OCP-023/hpa-app.yaml) · load test: [`scripts/OCP-023/load-and-watch.sh`](../scripts/OCP-023/load-and-watch.sh)
```bash
oc adm top pods | head -3
oc create deployment hpa-app --image=registry.access.redhat.com/ubi9/httpd-24 --replicas=2
oc set resources deployment/hpa-app --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi
oc autoscale deployment/hpa-app --min=2 --max=5 --cpu-percent=60
```

## 6. Validation / evidence
**Metrics available; HPA active:**
```
NAME      REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS
hpa-app   Deployment/hpa-app   cpu: 2%/60%   2         5         2

Metrics:  resource cpu on pods (as a percentage of request):  2% (1m) / 60%
Conditions:
  AbleToScale     True    ScaleDownStabilized  recent recommendations were higher than current one ...
  ScalingActive   True    ValidMetricFound     ... calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  False   DesiredWithinRange
Events (first seconds):
  Warning  FailedGetResourceMetric  ... did not receive metrics for targeted pods (pods might be unready)   ← normal right after Pods (re)start
```
**Load test – HPA events turned into a timeline** (load started 13:34:48, stopped 13:37:48):
```
Normal  SuccessfulRescale  New size: 4; reason: cpu resource utilization (percentage of request) above target   ~13:35:03
Normal  SuccessfulRescale  New size: 5; reason: cpu resource utilization (percentage of request) above target   ~13:35:18
Normal  SuccessfulRescale  New size: 3; reason: All metrics below target                                        ~13:42:34
Normal  SuccessfulRescale  New size: 2; reason: All metrics below target                                        ~13:42:49
```
| Phase | Time from trigger | Result |
|---|---|---|
| Scale-up | ~15 s → 4 Pods, ~30 s → **5 (max)** | ✅ |
| Hold at max | while load ran (3 min) | ✅ never above 5 |
| Scale-down | **~4 min 45 s** after load stopped (5-min window measured from the last high recommendation) → 3, then 2 15 s later | ✅ |
| Final | **2 Pods** Running | ✅ never below min |

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | Early `FailedGetResourceMetric … pods might be unready` | `oc set resources` rolled out new Pods; metrics hadn't been collected yet. Resolved within ~15 s (`ValidMetricFound`) |
| 2 | `oc set resources` triggered a rollout | Changing requests/limits changes the Pod template. Put resources in the manifest from the start |
| 3 | **My watch loop printed `replicas=5` the whole time** | Bug in my script: `TARGETS` (`cpu: 2%/60%`) contains a space, so `awk '{print $6}'` printed **MAXPODS**. Recovered the real behaviour from HPA **events**; the script now uses **jsonpath** fields (`status.currentReplicas`, `currentMetrics`) |
| 4 | Scale-up in two steps (4, then 5) | First evaluation computed 4 from early metrics; the next 15 s cycle hit the max |
| 5 | Scale-down only after ~5 min, then 5→3→2 | 300 s **stabilization window**; then recommendations drop and the HPA follows in 15 s steps |
| 6 | `Exit 124` from the load command | `timeout` ended the burner after 180 s – intended |
| 7 | One busy Pod drove scaling of all | HPA uses the **average** across Pods; new Pods were idle, which is why it stopped at max rather than staying high per Pod |

## 8. Production considerations
- **Right-size requests** – they define 100% for the HPA; too low → constant over-scaling, too high → never scales.
- Tune `behavior` (scale-up/down policies, stabilization) to the app's start-up time and traffic pattern.
- Make Pods **ready fast** (readiness probes, small images) – scale-up only helps once new Pods serve traffic.
- Ensure **cluster capacity** (or the cluster autoscaler) for `maxReplicas`; set a **ResourceQuota** so autoscaling can't starve the namespace.
- Don't combine an HPA with a hard-coded `replicas` in GitOps without ignoring that field (drift, OCP-003).
- Consider custom/external metrics (requests per second, queue length) via KEDA when CPU isn't the real bottleneck.

## 9. Lessons learned
- HPA = requests + metrics + min/max + target – missing requests is the #1 failure.
- Scale-up is fast, scale-down is deliberately slow.
- Parse Kubernetes output with **jsonpath**, not column positions – and when monitoring fails, **events** are the audit trail.

## 10. Interview talking point
> "I configured an HPA for 2 to 5 replicas at 60% CPU – after setting CPU requests, because utilization is measured against the request. I loaded one Pod for three minutes: the HPA scaled to 4 within about 15 seconds and to the maximum of 5 on the next cycle. After the load stopped, it held for about five minutes – the default scale-down stabilization window – then went to 3 and back to 2. My watch script actually printed the wrong column because the HPA's TARGETS field contains a space, so I reconstructed the timeline from the HPA's events and switched the script to jsonpath."
