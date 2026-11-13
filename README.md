# OpenShift Lab Records

Hands-on OpenShift / Kubernetes work, written up the way it's done in production:
**Jira-style stories** (planned work) and **RCAs** (incidents / break-fix), each with
commands, evidence, and lessons learned.

> Lab environment: multi-node OpenShift 4.x training cluster.
> All hostnames, IPs, URLs, usernames and tokens are **sanitised**.
> These are my own write-ups – not Red Hat course material.

## Index

### Stories (planned work)
| ID | Title | Area | Status |
|---|---|---|---|
| – | _first story goes here_ | | |

### RCAs (incidents / break-fix)
| ID | Title | Severity | Root cause |
|---|---|---|---|
| – | _first RCA goes here_ | | |

## Structure
```
stories/     Jira-style tasks: requirement → plan → implementation → validation
rca/         Incident write-ups: problem → impact → timeline → root cause → fix → prevention
scripts/     Reusable scripts/manifests created during the labs
templates/   Blank templates used for every record
```

## Skills covered
OpenShift administration · RBAC & authentication · networking & routes · storage ·
operators · troubleshooting · upgrades · automation (Bash / Ansible / Python)
