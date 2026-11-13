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
| [OCP-006](stories/OCP-006-exec-without-login.md) | Get /etc/passwd without logging in – CRI-O and the random UID | Troubleshooting · Runtime | Done |
| [OCP-007](stories/OCP-007-own-image-openshift-build.md) | Build my own image in OpenShift and deploy it (app-04) | Builds · ImageStreams | Done |
| [OCP-008](stories/OCP-008-imagestream-trigger-and-route.md) | Rebuild → automatic redeploy (ImageStream trigger) + Route | Builds · Rollouts · Routes | Done |
| [OCP-009](stories/OCP-009-copy-images-to-registry.md) | Copy images into my registry (mirror, skopeo, import-image) | Registries · Mirroring | Done |
| [OCP-010](stories/OCP-010-podman-build-push-internal-registry.md) | podman build → push to internal registry → deploy (new-app vs create deployment) | Image build · Registry | Done |
| [OCP-011](stories/OCP-011-mysql-database-from-docker-image.md) | MySQL from a Docker image – Secret, SQL proof, durability test | Stateful apps · Secrets | Done |
| [OCP-012](stories/OCP-012-mysql-from-openshift-template.md) | MySQL from an OpenShift Template – PVC, probes, data survives | Templates · Storage | Done |
| [OCP-013](stories/OCP-013-copy-data-pod-to-local.md) | Copy data Pod → local: oc cp, oc rsync, DB backup + restore drill | Data movement · Backup | Done |
| [OCP-014](stories/OCP-014-daemonset-deployment.md) | Application deployment using a DaemonSet – one Pod per node | DaemonSets · Scheduling | Done |
| [OCP-015](stories/OCP-015-fix-app-unreachable-via-route.md) | Fix app unreachable over its Route URL (shared cluster) → RCA-003 | Routes · Troubleshooting | Done |
| [OCP-016](stories/OCP-016-ingress-default-controller.md) | Create and access an app through Ingress (default ingress controller) | Networking · Ingress | Done |
| [OCP-017](stories/OCP-017-blue-green-deployment.md) | Blue-Green deployment – Route switch, zero errors, instant rollback | Release strategies · Routes | Done |
| [OCP-018](stories/OCP-018-traffic-split-canary.md) | Split traffic v1 80% / v2 20% – weighted Route (canary) | Release strategies · Routes | Done |
| [OCP-019](stories/OCP-019-static-pv-pvc-nfs.md) | Static 1Gi NFS PV + PVC bound to a Pod | Storage · Static provisioning | Done |
| [OCP-020](stories/OCP-020-dynamic-storage-etherpad.md) | Allocate 1Gi dynamic storage to an app – Etherpad data now survives restarts | Storage · Dynamic provisioning | Done |
| [OCP-021](stories/OCP-021-message-survives-restarts.md) | Required message survives Pod deletes/restarts – ConfigMap (+ RCA-004) | ConfigMaps · SCC | Done |
| [OCP-022](stories/OCP-022-statefulset-3-replicas.md) | StatefulSet, 3 replicas, 1Gi RWO PVC each (default StorageClass) | StatefulSets · Storage | Done |

### RCAs (incidents / break-fix)
| ID | Title | Severity | Root cause |
|---|---|---|---|
| [RCA-001](rca/RCA-001-rootless-podman-subuid.md) | Rootless `podman pull` fails – no subuid/subgid ranges | Sev4 | Single UID/GID user-namespace mapping can't unpack files owned by other IDs |
| [RCA-002](rca/RCA-002-mysql-data-loss-no-persistent-storage.md) | MySQL data lost after Pod replacement | Sev2 (simulated) | Data dir on the container's ephemeral overlay layer – no volume mounted |
| [RCA-003](rca/RCA-003-route-unreachable-three-faults.md) | App unreachable via Route – three config faults | Sev2 | Route host typo + Route→wrong Service name + Service selector ≠ Pod labels |
| [RCA-004](rca/RCA-004-image-tag-and-root-only-httpd.md) | Wrong image tag, then CrashLoopBackOff | Sev3 | Case-sensitive tag `V2.0.0` vs `v2.0.0`; root-only httpd under random-UID restricted-v2 |

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
