# Container runtimes: the complete map

> Concept note in my own words (November 2026). "Container runtime" can mean the tool you type commands into, the daemon the kubelet talks to, or the small program that actually creates the container. This note sorts them by layer.

## The layers

```text
You / kubelet
   │
   ▼
① Engines & CLIs        Docker, Podman, nerdctl, Apptainer…      (build, run, manage images; user-facing)
   │
   ▼
② High-level runtimes   containerd, CRI-O                         (images, storage, lifecycle; Kubernetes talks CRI to these)
   │
   ▼
③ Low-level runtimes    runc, crun, youki, gVisor, Kata…          (OCI runtime spec: actually create the container)
   │
   ▼
Linux kernel            namespaces, cgroups, seccomp, SELinux/AppArmor  (or a VM/sandbox kernel)
```

## ① Container engines and CLIs (user-facing)

| Tool | What it is | Where you'll meet it |
|---|---|---|
| **Docker Engine** (`dockerd`) | The original all-in-one engine; uses containerd + runc underneath | Developer laptops, CI, older servers. Kubernetes dropped direct support (dockershim) in 1.24; `cri-dockerd` exists to bridge it |
| **Podman** | Daemonless, rootless-friendly, Docker-compatible CLI; runs pods locally | RHEL's default container tool; same image/storage libraries as CRI-O |
| **Buildah / Skopeo** | Build images without a daemon / copy and inspect images between registries | RHEL, CI pipelines, mirroring for disconnected OpenShift |
| **nerdctl** | Docker-style CLI for containerd | K3s and containerd hosts |
| **Apptainer** (formerly Singularity) | Runs containers as the calling user, single-file images (SIF), no daemon | **HPC clusters**, Slurm jobs, MPI and GPU workloads |
| **Enroot** (NVIDIA) | Turns container images into unprivileged sandboxes for HPC | NVIDIA HPC/DGX clusters, often with Slurm via Pyxis |
| **LXC / Incus (LXD)** | **System** containers: a full OS with init, like a light VM | Hosting, labs; not used by Kubernetes |

## ② High-level runtimes (Kubernetes talks to these through CRI)

| Runtime | Notes | Used by |
|---|---|---|
| **containerd** | CNCF graduated; general purpose; manages images, snapshots and containers; extended through "shims" | Most Kubernetes distros: EKS, GKE, AKS, K3s, kubeadm, Docker underneath |
| **CRI-O** | Kubernetes-only, versioned with Kubernetes, minimal ([details](cri-o-container-runtime.md)) | **OpenShift**, some kubeadm setups |
| *Mirantis Container Runtime* | Commercial Docker Engine with CRI support | Mirantis Kubernetes Engine |
| *rkt* | CoreOS runtime, **archived** | Historical: know the name only |

## ③ Low-level OCI runtimes (actually create the container)

**Standard (shared kernel)**

| Runtime | Language | Notes |
|---|---|---|
| **runc** | Go | The OCI reference implementation; the default almost everywhere |
| **crun** | C | Faster start, lower memory, good cgroup v2 support; used by Podman and in recent OpenShift releases |
| **youki** | Rust | Newer, memory-safe alternative; less common in production |

**Sandboxed / stronger isolation** (picked per pod with Kubernetes **RuntimeClass**)

| Runtime | How it isolates | Trade-off |
|---|---|---|
| **gVisor** (`runsc`) | User-space kernel that intercepts syscalls | Strong isolation; some syscall/IO performance cost |
| **Kata Containers** | Each pod in a lightweight VM with its own kernel | VM-level isolation; more startup time and memory. OpenShift ships it as **OpenShift sandboxed containers** |
| **Firecracker** (via firecracker-containerd / Kata) | Lightweight microVMs | Multi-tenant serverless platforms |
| **Confidential containers** (Kata + TEE such as AMD SEV-SNP, Intel TDX) | Encrypted memory, attestation | Sensitive data on infrastructure you don't fully trust |

**Special purpose**

| Runtime | Purpose |
|---|---|
| **NVIDIA Container Toolkit** (`nvidia-container-runtime`) | Wraps runc to inject GPU devices and drivers; installed by the **NVIDIA GPU Operator** on Kubernetes/OpenShift |
| **WebAssembly shims** (runwasi: Wasmtime, WasmEdge, Spin; crun's Wasm handler) | Run Wasm modules instead of Linux containers; tiny and fast to start |
| **Windows**: containerd + `runhcs`/hcsshim | Windows Server containers and Hyper-V isolated containers |

## How Kubernetes chooses

- The node's high-level runtime (containerd or CRI-O) is set when the cluster is built.
- A **RuntimeClass** lets individual pods use a different low-level handler:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: kata }
handler: kata          # configured in containerd/CRI-O on the nodes
---
apiVersion: v1
kind: Pod
metadata: { name: untrusted-app }
spec:
  runtimeClassName: kata
  containers: [{ name: app, image: registry.example.com/app:1.0 }]
```

## One-line answers for interviews

- **Docker vs containerd vs CRI-O?** Docker is an engine for people; containerd and CRI-O are runtimes for Kubernetes; all of them end in runc/crun.
- **What does OpenShift use?** CRI-O, with runc or crun underneath; Kata for sandboxed containers; the NVIDIA toolkit for GPUs.
- **How would you isolate untrusted workloads?** A sandboxed RuntimeClass (gVisor or Kata), plus SCCs and NetworkPolicy.
- **What runs containers on HPC clusters?** Apptainer or Enroot, not Docker: they run as the user, with no root daemon on shared nodes.

See also: [CRI-O container runtime](cri-o-container-runtime.md) · [OpenShift vs Kubernetes architecture](openshift-vs-kubernetes-architecture.md)
