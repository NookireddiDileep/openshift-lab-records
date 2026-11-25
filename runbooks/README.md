# Break-fix runbooks (ready to run)

One runbook per scenario from the [DO180 scenario bank](../scenarios/DO180-RCA-scenario-bank.md), added daily.

Each runbook is a **plan for my lab**: how to break it safely, the triage path, the fix, the verification and the interview answer. It is **not** a record of something I've done. When I run it on my OpenShift lab cluster and capture the real output, it graduates to an RCA in [`rca/`](../rca/) and its status here becomes ✅.

**Status:** 📋 ready to run · 🔬 running · ✅ done → RCA

| Runbook | Scenario | Area | Lab | Status |
|---|---|---|---|---|
| [RB-S42](RB-S42-createcontainerconfigerror-missing-configmap-key.md) | [S42](../scenarios/DO180-RCA-scenario-bank.md) – pod won't start after a config change (`CreateContainerConfigError`) | Configuration (Ch 5) | 🟢 | 📋 |
| [RB-S43](RB-S43-configmap-updated-app-still-old-value.md) | [S43](../scenarios/DO180-RCA-scenario-bank.md) – ConfigMap updated but the app still uses the old value (env vars are read only at start) | Configuration (Ch 5) | 🟢 | 📋 |
| [RB-S56](RB-S56-liveness-probe-kills-slow-starting-app.md) | [S56](../scenarios/DO180-RCA-scenario-bank.md) – app restarts forever right after deploy (liveness probe kills a slow starter) | Probes (Ch 6) | 🟢 | 📋 |
| [RB-S57](RB-S57-liveness-probe-checks-dependency.md) | [S57](../scenarios/DO180-RCA-scenario-bank.md) – during a DB outage all frontend pods restarted too (liveness probe checks a dependency) | Probes (Ch 6) | 🟢 | 📋 |
| [RB-S44](RB-S44-secret-password-newline-or-double-base64.md) | [S44](../scenarios/DO180-RCA-scenario-bank.md) – DB login fails with the "correct" password from the Secret (trailing newline or double base64) | Configuration (Ch 5) | 🟢 | 📋 |
