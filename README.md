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
| [OCP-001](stories/OCP-001-bare-pod-no-self-heal.md) | Deploy app-01 as a bare Pod (no self-healing) | Workloads · Security | Done |
| [OCP-002](stories/OCP-002-deployment-self-heal.md) | Deploy app-02 as a Deployment (self-healing) | Workloads · Deployments | Done |
| [OCP-003](stories/OCP-003-scale-deployment.md) | Scale app-02 from 1 to 2 (declarative) + drift demo | Scaling · GitOps practices | Done |
| [OCP-004](stories/OCP-004-third-party-image-etherpad.md) | Deploy a third-party image (Etherpad) under restricted-v2 | Image assessment · Security | Done |
| [OCP-005](stories/OCP-005-container-os-vs-node-kernel.md) | Log in to app-03, check OS – container userland vs node kernel | Troubleshooting · Fundamentals | Done |

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
