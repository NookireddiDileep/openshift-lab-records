# Stories by category

Planned lab stories, each a task completed on a real OpenShift cluster with commands, outputs and verification. The files keep their original IDs and names (other pages link to them); this page groups them by topic for revision. A story that covers two topics appears in both groups.

For everything on one topic in one place (stories, drills, RCAs, runbooks, reference), use **[Revise by category](../README.md#revise-by-category)** in the main README.

## Workloads and self-healing

| ID | Story |
|---|---|
| [OCP-001](OCP-001-bare-pod-no-self-heal.md) | Bare Pod: no self-healing |
| [OCP-002](OCP-002-deployment-self-heal.md) | Deployment: self-healing |
| [OCP-003](OCP-003-scale-deployment.md) | Scale declaratively, plus a configuration-drift demo |
| [OCP-014](OCP-014-daemonset-deployment.md) | DaemonSet: one Pod per node |

## Scaling

| ID | Story |
|---|---|
| [OCP-003](OCP-003-scale-deployment.md) | Manual and declarative scaling |
| [OCP-023](OCP-023-hpa-cpu-autoscaling.md) | Horizontal Pod Autoscaler: 2 to 5 Pods at 60% CPU |

## Images, builds and registries

| ID | Story |
|---|---|
| [OCP-004](OCP-004-third-party-image-etherpad.md) | Third-party image (Etherpad) under restricted-v2 |
| [OCP-005](OCP-005-container-os-vs-node-kernel.md) | Container userland vs node kernel |
| [OCP-007](OCP-007-own-image-openshift-build.md) | Build my own image in OpenShift |
| [OCP-008](OCP-008-imagestream-trigger-and-route.md) | ImageStream trigger: rebuild → automatic redeploy |
| [OCP-009](OCP-009-copy-images-to-registry.md) | Copy images into the internal registry |
| [OCP-010](OCP-010-podman-build-push-internal-registry.md) | podman build and push; `oc new-app` vs `oc create deployment` |

## Security: SCCs and the random UID

| ID | Story |
|---|---|
| [OCP-004](OCP-004-third-party-image-etherpad.md) | Why an image runs (or not) under restricted-v2 |
| [OCP-006](OCP-006-exec-without-login.md) | Exec without login, and who adds the random UID's passwd entry |
| [OCP-021](OCP-021-message-survives-restarts.md) | Immutable containers, SCCs and service accounts |

## Networking, Routes and traffic

| ID | Story |
|---|---|
| [OCP-008](OCP-008-imagestream-trigger-and-route.md) | Expose an app with a Route |
| [OCP-015](OCP-015-fix-app-unreachable-via-route.md) | Fix an app that can't be reached over its Route |
| [OCP-016](OCP-016-ingress-default-controller.md) | Ingress through the default ingress controller |
| [OCP-017](OCP-017-blue-green-deployment.md) | Blue-green deployment |
| [OCP-018](OCP-018-traffic-split-canary.md) | Canary: 80/20 traffic split on one Route |

## Configuration

| ID | Story |
|---|---|
| [OCP-021](OCP-021-message-survives-restarts.md) | A message that survives restarts: ConfigMap mounted at the document root |

## Storage and data

| ID | Story |
|---|---|
| [OCP-011](OCP-011-mysql-database-from-docker-image.md) | MySQL from a Docker image, and testing its data |
| [OCP-012](OCP-012-mysql-from-openshift-template.md) | MySQL from an OpenShift template: persistent, probed, durable |
| [OCP-013](OCP-013-copy-data-pod-to-local.md) | Copy data from Pods; restore-tested database backup |
| [OCP-019](OCP-019-static-pv-pvc-nfs.md) | Static NFS PersistentVolume and PVC |
| [OCP-020](OCP-020-dynamic-storage-etherpad.md) | Dynamic storage, and fixing Etherpad's data loss |
| [OCP-022](OCP-022-statefulset-3-replicas.md) | StatefulSet: 3 replicas, one volume each |

---

Back to the [repository index](../README.md).
