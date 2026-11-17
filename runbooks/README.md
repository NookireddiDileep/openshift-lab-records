# Break-fix runbooks (ready to run)

One runbook per scenario from the [DO180 scenario bank](../scenarios/DO180-RCA-scenario-bank.md), added daily.

Each runbook is a **plan for my lab**: how to break it safely, the triage path, the fix, the verification and the interview answer. It is **not** a record of something I've done. When I run it on my OpenShift training cluster and capture the real output, it graduates to an RCA in [`rca/`](../rca/) and its status here becomes ✅.

**Status:** 📋 ready to run · 🔬 running · ✅ done → RCA

| Runbook | Scenario | Area | Lab | Status |
|---|---|---|---|---|
| [RB-S42](RB-S42-createcontainerconfigerror-missing-configmap-key.md) | [S42](../scenarios/DO180-RCA-scenario-bank.md) – pod won't start after a config change (`CreateContainerConfigError`) | Configuration (Ch 5) | 🟢 | 📋 |
