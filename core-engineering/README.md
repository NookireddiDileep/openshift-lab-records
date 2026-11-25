# Core engineering

First-principles articles on how Kubernetes and OpenShift really work: the problem,
the mechanism that solves it, where that mechanism breaks, and how to prove it on a
cluster. Each article opens with a plain-words layer, so it reads for beginners and
engineers alike.

These are **living articles**: they are extended as new findings come from the labs
in this repo and from real incidents. Lab evidence is linked, not repeated.

| ID | Article | What it covers |
|---|---|---|
| [CE-001](CE-001-what-kubernetes-and-openshift-solve.md) | What Kubernetes and OpenShift actually solve (and how) | Desired state and control loops; 11 operational problems (crash, node loss, scaling, releases, discovery, config, capacity, tenancy, storage, drift, platform lifecycle) with mechanism and limits; a sale-day walkthrough; what it does not solve; troubleshooting checklist; glossary |
| [CE-002](CE-002-day-in-the-life-openshift-platform-engineer.md) | A day in the life of an OpenShift platform engineer | What the platform team owns; daily, weekly, monthly and quarterly work; start-of-shift health check; 7 production incidents with first checks; safe change practice; what makes it senior; mapping from traditional Linux ops |
