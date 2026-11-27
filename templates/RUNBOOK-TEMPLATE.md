# RB-SXX: <scenario title>

| Field | Value |
|---|---|
| **Scenario** | [SXX](../scenarios/DO180-RCA-scenario-bank.md) |
| **Area** | e.g. Images · SCC · Routes · Storage · Probes |
| **Lab** | 🟢 own project / 🟡 partly reproducible / 🔴 interview walkthrough (needs cluster-admin) |
| **Status** | 📋 Ready to run (not yet run on my cluster) |
| **Time** | ~30–45 min |

> A runbook is a **plan**, not a record. Once I've run it on my lab and captured real output, it becomes `rca/RCA-0NN-*.md` and this status becomes ✅ Done → RCA-0NN.

## 1. The ticket (as it would arrive)
## 2. Reproduce safely (🟢/🟡) or set the scene (🔴)
## 3. What you'll see
## 4. Triage, outside-in (commands and what each one tells you)
## 5. Root cause(s)
## 6. Fix
## 7. Verify
## 8. Prevention (what would stop this happening again)
## 9. Evidence to capture when I run it (for the RCA)
## 10. Interview: "Walk me through how you'd troubleshoot …" (a 60-second answer)
## 11. Clean up

---

## Optional support-case sections (use inside the sections above)

Each runbook is also a mock support case. Add these *inside* the numbered sections, without removing any of them:

- **In section 1 (ticket):** severity (Sev 1–4), environment (OCP version, platform, cluster size), symptom in the customer's words, business impact, what the customer already tried, and a **time box** (target time to root cause, usually 20–30 min).
- **At the start of section 4: "Collect data first"** – a table of artifacts (`oc adm inspect ns/<project>`, `oc get co`, events, `oc logs --previous`, `oc debug node/<node>` + `chroot /host` + `journalctl -u kubelet` / `-u crio`, `oc adm must-gather`, `sos report`), what each one tells me and where to look inside it. Then the triage steps and a hypotheses table (how each is ruled in or out).
- **In section 10: "2-minute case explanation"** – symptom → data collected → root cause → fix → prevention, spoken to a senior support engineer, plus 2 panel follow-up questions with short answers.
- **In section 10: "Customer update"** – 3–4 lines to post on the case: what was found, what was done, next steps.
- **"EX280 angle"** line in the header note, where the scenario maps to an exam objective.
