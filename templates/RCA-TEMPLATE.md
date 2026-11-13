# RCA-XXX: <Short incident title>

| Field | Value |
|---|---|
| **Date** | YYYY-MM-DD |
| **Environment** | Lab OpenShift 4.x cluster (sanitised) |
| **Severity** | Sev1 / Sev2 / Sev3 / Sev4 |
| **Component** | e.g. Pod · Route · PVC · Node · Operator · etcd |
| **Status** | Resolved / Mitigated |
| **Time to detect / resolve** | e.g. 5 min / 40 min |

## 1. Problem statement
One or two sentences: **what** was broken, **where**, and **how it showed up**.
> e.g. "Application `web` in project `shop` returned HTTP 503 via its Route; pods were Running."

## 2. Impact
- Who/what was affected (users, apps, namespaces)
- Duration
- Data loss? Yes / No

## 3. Symptoms & detection
- How it was noticed (alert, user report, monitoring, `oc get` output)
- Key error messages:
```
<exact error lines>
```

## 4. Timeline
| Time | Event |
|---|---|
| HH:MM | Issue detected |
| HH:MM | Investigation started – first checks |
| HH:MM | Root cause identified |
| HH:MM | Fix applied |
| HH:MM | Service verified healthy |

## 5. Investigation (troubleshooting steps)
| # | Hypothesis | Check (command) | Result |
|---|---|---|---|
| 1 | | `oc ...` | Ruled out / Confirmed |
| 2 | | | |

```bash
# key commands + trimmed output
```

## 6. Root cause
The **technical** root cause, stated plainly.
**5 Whys:**
1. Why did X fail? → because …
2. Why …? → because …
3. Why …? → because …
4. …
5. Underlying cause → …

## 7. Resolution
```bash
# exact fix applied
```
Verification that it is fixed:
```bash
# commands + output
```

## 8. Preventive actions
| Action | Type | Owner | Status |
|---|---|---|---|
| e.g. add readiness probe | Prevent | me | Done |
| e.g. alert on endpoints = 0 | Detect | | |
| e.g. document in runbook | Process | | |

## 9. Lessons learned
- What went well
- What was slow / confusing
- What I'll check first next time

## 10. Interview talking point
> "In my lab I reproduced <issue>. I diagnosed it by <steps>, the root cause was <cause>, I fixed it by <fix>, and prevented recurrence with <action>."
