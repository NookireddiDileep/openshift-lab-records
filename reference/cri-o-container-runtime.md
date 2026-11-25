# CRI-O: the container runtime in OpenShift

> Concept note in my own words. Quick reference for interviews and node-level troubleshooting.

## Full form

**CRI-O = Container Runtime Interface (CRI) + Open Container Initiative (OCI).**

| Part | Meaning |
|---|---|
| **CRI**: Container Runtime Interface | The standard gRPC API the **kubelet** uses to ask a runtime to pull images and create, start, stop and remove containers |
| **O**: Open Container Initiative (OCI) | Open standards for **container images** (format) and **runtimes** (how a container is run) |

So CRI-O is a lightweight runtime that implements Kubernetes' CRI using OCI-compliant images and low-level runtimes. It's built **only for Kubernetes**, and its versions track Kubernetes versions. That's why OpenShift uses it instead of Docker or containerd.

## Where it sits

```text
kubelet ──CRI (gRPC)──► CRI-O ──► conmon (monitors each container)
                                    └──► OCI runtime (runc or crun) ──► Linux namespaces + cgroups
                         └── pulls images from registries (containers/image library)
```

- **conmon:** a small process per container that holds its stdio/logs and reports its exit code.
- **runc / crun:** the low-level OCI runtimes that actually create the container. Which one is used depends on the OpenShift version and `ContainerRuntimeConfig`.
- Images and container storage live under `/var/lib/containers/storage` on the node.

## Commands on an OpenShift node

```bash
oc debug node/<node>
chroot /host
crictl ps -a                  # all containers (including exited)
crictl pods                   # pod sandboxes
crictl images                 # images on the node
crictl inspect <container-id> # full details (mounts, PID, runtime)
crictl logs <container-id>    # container logs (works even if the API server is down)
crictl rmi --prune            # remove unused images (disk pressure)
systemctl status crio
journalctl -u crio -f         # runtime logs
journalctl -u kubelet -f      # kubelet side of the conversation
```

`crictl` talks to CRI-O directly, so it still works when the API server or `oc` doesn't: useful during node or control-plane failures.

## Configuration on OpenShift

- Don't edit `/etc/crio/crio.conf` by hand: the Machine Config Operator manages node files and will mark the node degraded on drift.
- Change runtime settings with a **`ContainerRuntimeConfig`** CR (for example `pidsLimit`, `logSizeMax`, `defaultRuntime`) targeted at a MachineConfigPool. The MCO rolls it out node by node with a reboot.
- Registry mirrors and allowed/blocked registries are set cluster-wide (`ImageDigestMirrorSet`, `image.config.openshift.io/cluster`), which the MCO writes into the node's container configuration.

## Common issues

| Symptom | Check |
|---|---|
| Pods stuck `ContainerCreating` on one node | `journalctl -u crio`, `crictl pods`; disk full under `/var/lib/containers`; CNI errors |
| `ImagePullBackOff` only on some nodes | `crictl pull <image>` on that node; mirror/registry config, proxy, DNS, disk space |
| Node `NotReady` with `PLEG is not healthy` | CRI-O slow or hung (too many containers, disk I/O); `systemctl status crio`, node load |
| `oc logs` fails but the pod runs | API/kubelet path issue; use `crictl logs` on the node |

## Interview one-liners

- **Why not Docker?** Kubernetes removed dockershim in 1.24; OpenShift 4 has used CRI-O from the start: smaller, Kubernetes-only, no daemon doing extra jobs.
- **CRI vs OCI?** CRI is the kubelet ↔ runtime API; OCI defines image and runtime standards underneath.
- **How do you debug a container when the API server is down?** `oc debug node` isn't available either, so SSH/console to the node and use `crictl`.

See also: [Container runtimes overview](container-runtimes-overview.md) · [OpenShift vs Kubernetes architecture](openshift-vs-kubernetes-architecture.md) (runtime layer) · [oc command bank](oc-command-bank.md)
