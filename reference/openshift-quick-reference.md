# OpenShift quick reference: every term in one line

> Look-up page: one plain-words line per term, the command to see it on a cluster, and its area. For the full explanation of how the pieces fit together, read [OpenShift architecture](openshift-architecture.md); for troubleshooting, the [pod failure states decoder](pod-failure-states-decoder.md) and the [network path decoder](network-path-decoder.md). 176 terms. Commands assume `oc` logged in to your own project; some (nodes, cluster config) need wider read access.

**Jump to:** [A](#a) · [B](#b) · [C](#c) · [D](#d) · [E](#e) · [F](#f) · [G](#g) · [H](#h) · [I](#i) · [J](#j) · [K](#k) · [L](#l) · [M](#m) · [N](#n) · [O](#o) · [P](#p) · [Q](#q) · [R](#r) · [S](#s) · [T](#t) · [U](#u) · [V](#v) · [W](#w)

**Areas:** Access (8) · Basics (11) · Config (3) · Images (13) · Monitoring (1) · Networking (29) · Nodes (17) · Platform (25) · Release (10) · Scaling (2) · Security (8) · Storage (11) · Troubleshooting (14) · Workloads (24)

---

## A

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Access mode (RWO, RWX, ROX, RWOP)** | How a volume may be mounted: one node read-write, many nodes read-write, many read-only, or one pod only | `oc get pvc` (ACCESS MODES) | Storage |
| **ACM** | Advanced Cluster Management: manages many clusters (policies, upgrades, placement) from a hub | `oc get managedclusters` (on the hub) | Platform |
| **ACS** | Advanced Cluster Security: image scanning, runtime threat detection, security policies | — | Security |
| **Admission** | API server step that can change or reject a request after authorization (SCCs, quotas, defaults, webhooks) | — | Platform |
| **Affinity / anti-affinity** | Rules to place pods near, or away from, other pods or certain nodes | `oc get deploy <d> -o yaml` (affinity) | Workloads |
| **Annotation** | Free-form key/value note on an object; not used for selecting objects | `oc get <obj> -o jsonpath='{.metadata.annotations}'` | Basics |
| **anyuid** | SCC that lets a pod run as the user the image asks for, even root | `oc get scc anyuid` | Security |
| **API aggregation** | The kube-apiserver forwarding some API groups to another server (e.g. Routes to openshift-apiserver) | `oc get apiservices` | Platform |
| **API resource / group** | A kind of object (pods, routes) and its API group and version (apps/v1, route.openshift.io/v1) | `oc api-resources` | Platform |
| **API server (kube-apiserver)** | The cluster's single front door; every `oc` command goes here (port 6443) | `oc whoami --show-server` | Platform |
| **Apps domain** | The wildcard domain every Route hostname sits under (`*.apps.<cluster-domain>`) | `oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'` | Networking |
| **Argo CD / OpenShift GitOps** | Keeps the cluster in sync with manifests in Git | `oc get applications -A` | Release |

## B

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **BestEffort** | QoS class of a pod with no requests or limits; evicted first under pressure | `oc get pod <p> -o jsonpath='{.status.qosClass}'` | Workloads |
| **Binary build** | A build from local files uploaded by `oc start-build --from-dir` | `oc start-build <bc> --from-dir=. --follow` | Images |
| **BuildConfig (bc)** | Recipe for building an image inside the cluster: source, strategy, output image | `oc get bc` | Images |
| **Burstable** | QoS class of a pod with requests lower than its limits | `oc get pod <p> -o jsonpath='{.status.qosClass}'` | Workloads |

## C

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Canary** | Sending a small share of traffic to a new version (weighted Route backends) | `oc get route <r> -o yaml` (alternateBackends) | Release |
| **CatalogSource** | Where OLM finds installable Operators | `oc get catalogsource -n openshift-marketplace` | Platform |
| **Cluster** | A group of nodes working as one platform | `oc get nodes` | Basics |
| **ClusterIP** | Default Service type: a virtual IP reachable only inside the cluster | `oc get svc` | Networking |
| **ClusterOperator (co)** | Health report of one platform component: Available / Progressing / Degraded | `oc get co` | Platform |
| **ClusterRole / ClusterRoleBinding** | A set of permissions usable cluster-wide / who it is granted to | `oc get clusterrolebinding` | Access |
| **ClusterVersion** | The cluster's version, channel and upgrade progress | `oc get clusterversion` | Platform |
| **ConfigMap (cm)** | Non-secret settings or files kept outside the image | `oc get cm` | Config |
| **Container** | An application packed with what it needs; runs as ordinary processes on the node's kernel | `oc get pod <p> -o jsonpath='{.spec.containers[*].name}'` | Basics |
| **Control plane** | API server, etcd, scheduler and controllers: the cluster's brain | `oc get nodes -l node-role.kubernetes.io/master` | Platform |
| **Controller** | A loop that watches objects and acts until actual state matches desired state | — | Platform |
| **CoreDNS (dns-default)** | The cluster's DNS server for Service names | `oc get svc -n openshift-dns` | Networking |
| **CrashLoopBackOff** | Container keeps exiting; the kubelet waits longer between restarts (10 s doubling to 5 min) | `oc logs <p> --previous` | Troubleshooting |
| **CRD** | CustomResourceDefinition: adds a new kind of object to the API | `oc get crd` | Platform |
| **CreateContainerConfigError** | A referenced ConfigMap, Secret or key does not exist | `oc describe pod <p>` (Events) | Troubleshooting |
| **CRI-O** | OpenShift's container runtime; starts containers when the kubelet asks | `oc debug node/<n> -- chroot /host crictl ps` | Nodes |
| **CronJob** | Runs a Job on a schedule | `oc get cronjob` | Workloads |
| **CSI** | Container Storage Interface: the plug-in standard storage drivers use | `oc get csidrivers` | Storage |
| **CSR** | Certificate signing request; nodes use them to get their certificates | `oc get csr` | Nodes |
| **CSV** | ClusterServiceVersion: one installed version of an Operator | `oc get csv` | Platform |
| **CVO** | Cluster Version Operator: applies the release image and drives upgrades | `oc get clusterversion` | Platform |

## D

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **DaemonSet (ds)** | Runs one pod on every (matching) node | `oc get ds` | Workloads |
| **Default storage class** | The class used when a PVC names none; shown as `(default)` | `oc get sc` | Storage |
| **Deployment (deploy)** | Keeps N identical pods running and updates them gradually | `oc get deploy` | Workloads |
| **DeploymentConfig (dc)** | Older OpenShift-only version of Deployment; deprecated, still created by some templates | `oc get dc` | Workloads |
| **Desired state** | What you declared you want; controllers work to make it true | `oc get <obj> -o yaml` (spec) | Basics |
| **Digest** | An image's unique fingerprint (`sha256:…`); unlike a tag it never changes | `oc get istag <is>:<tag>` | Images |
| **Drain** | Safely moving all pods off a node before maintenance | `oc adm drain <n> --ignore-daemonsets --delete-emptydir-data` | Nodes |

## E

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Edge (TLS)** | Route TLS type: the router decrypts; router to pod is plain HTTP | `oc get route <r> -o jsonpath='{.spec.tls.termination}'` | Networking |
| **EgressFirewall / EgressIP** | Limits where a project's pods may connect out / a fixed source IP for its outbound traffic | `oc get egressfirewall` | Networking |
| **emptyDir** | A scratch volume that lives exactly as long as its pod | `oc get pod <p> -o yaml` (volumes) | Storage |
| **EndpointSlice** | The Service's list of pod IPs and ports; only Ready ones receive traffic | `oc get endpointslices -l kubernetes.io/service-name=<svc>` | Networking |
| **Environment variable** | A setting passed into a container when it starts; never updated in a running pod | `oc set env deploy/<d> --list` | Config |
| **ErrImagePull / ImagePullBackOff** | The image cannot be pulled (wrong name/tag, auth, network); retries slow down | `oc describe pod <p>` (Events) | Troubleshooting |
| **etcd** | The database holding all cluster state; needs a quorum of members | `oc get pods -n openshift-etcd -l app=etcd` | Platform |
| **Event** | Timestamped record of what happened to an object; first stop when troubleshooting | `oc get events --sort-by=.lastTimestamp` | Troubleshooting |
| **Evicted** | Pod removed by the kubelet because the node ran short of memory or disk | `oc get pods` · `oc describe node <n>` | Troubleshooting |
| **Exit code** | How a container ended: 0 success, 1 app error, 137 killed (OOM/SIGKILL), 143 SIGTERM | `oc get pod <p> -o jsonpath='{.status.containerStatuses[0].lastState}'` | Troubleshooting |

## F

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Finalizer** | A cleanup step that must finish before an object is deleted; can leave it stuck Terminating | `oc get <obj> -o jsonpath='{.metadata.finalizers}'` | Troubleshooting |

## G

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Gateway API** | Newer Kubernetes routing API, successor to Ingress | `oc get gateway -A` | Networking |
| **Geneve** | The tunnel protocol OVN-Kubernetes uses to carry pod traffic between nodes | — | Networking |
| **GitOps** | Desired state kept in Git; the cluster is synced to it automatically | — | Release |
| **Group** | A set of users granted roles together (often synced from LDAP) | `oc get groups` | Access |
| **Guaranteed** | QoS class where every container's requests equal its limits; evicted last | `oc get pod <p> -o jsonpath='{.status.qosClass}'` | Workloads |

## H

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **HAProxy** | The software inside the OpenShift router | — | Networking |
| **Headless Service** | Service with `clusterIP: None`; DNS returns the pod IPs directly | `oc get svc` (CLUSTER-IP None) | Networking |
| **Helm** | Package manager for Kubernetes applications (charts, releases) | `helm list` | Release |
| **HostNetwork** | Pod uses the node's own network; also a way the router can be published | `oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.endpointPublishingStrategy.type}'` | Networking |
| **HPA** | HorizontalPodAutoscaler: changes replica count based on a metric such as CPU | `oc get hpa` | Scaling |

## I

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Identity provider (IdP)** | Where logins are checked: HTPasswd, LDAP, OIDC… | `oc get oauth cluster -o yaml` | Access |
| **Ignition** | First-boot configuration an RHCOS node downloads | — | Nodes |
| **Image** | Read-only template a container starts from | `oc image info <image>` | Images |
| **Image lookup (local)** | Lets pods in a project use an ImageStream's short name | `oc set image-lookup <is>` | Images |
| **imagePullPolicy** | When the node pulls: IfNotPresent (cached copy wins), Always, Never | `oc get pod <p> -o jsonpath='{.spec.containers[0].imagePullPolicy}'` | Images |
| **ImageStream (is) / ImageStreamTag (istag)** | OpenShift pointer to images, tracked by digest; can trigger redeploys | `oc get is` · `oc get istag` | Images |
| **Infra node** | A worker reserved for platform services (router, registry, monitoring) | `oc get nodes -l node-role.kubernetes.io/infra` | Nodes |
| **Ingress** | Kubernetes object for HTTP routing; OpenShift turns it into Routes | `oc get ingress` | Networking |
| **IngressController** | Defines a router: domain, replicas, placement, certificate | `oc get ingresscontroller -n openshift-ingress-operator` | Networking |
| **Init container** | Runs to completion before the app containers start; shows as `Init:` status | `oc get pod <p>` | Workloads |
| **Internal registry** | The image registry inside the cluster | `oc get route -n openshift-image-registry` (if exposed) | Images |

## J

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Job** | Runs pods until a task completes | `oc get jobs` | Workloads |
| **jsonpath** | Picks exact fields out of `oc` output | `oc get pod <p> -o jsonpath='{.status.podIP}'` | Basics |

## K

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **kubeconfig** | File holding cluster URLs, users and tokens | `oc config view --minify` | Access |
| **kubelet** | The agent on every node that runs and watches its pods | `oc debug node/<n> -- chroot /host systemctl status kubelet` | Nodes |
| **Kustomize** | Customises manifests with overlays, without templates | `oc apply -k <dir>` | Release |

## L

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Label** | key=value tag used to select objects | `oc get pods --show-labels` | Basics |
| **Lease (node)** | Heartbeat object each kubelet renews about every 10 s | `oc get lease -n kube-node-lease` | Nodes |
| **LimitRange** | Default and maximum resources per container in a project | `oc get limitrange` | Scaling |
| **Limits** | Maximum CPU (throttled above it) and memory (killed above it) for a container | `oc set resources deploy/<d> --limits=memory=256Mi` | Workloads |
| **Liveness probe** | "Is it alive?" Failure restarts the container | `oc set probe deploy/<d> --liveness …` | Workloads |
| **LoadBalancer Service** | Service with an external IP from a cloud load balancer or MetalLB | `oc get svc` (EXTERNAL-IP) | Networking |

## M

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Machine / MachineSet** | A VM or host object / keeps N machines, like a ReplicaSet for nodes | `oc get machinesets -n openshift-machine-api` | Nodes |
| **MachineConfig (mc) / MCO** | Declarative node OS configuration / the operator that applies it | `oc get mc` | Nodes |
| **MachineConfigPool (mcp)** | Group of nodes receiving the same MachineConfigs; Updated or Degraded | `oc get mcp` | Nodes |
| **maxSurge / maxUnavailable** | How many extra or missing pods a rolling update allows (25% / 25% by default) | `oc get deploy <d> -o jsonpath='{.spec.strategy}'` | Release |
| **MetalLB** | Gives LoadBalancer Services real IPs on bare metal | `oc get ipaddresspool -A` | Networking |
| **Multus** | Attaches extra network interfaces to pods | `oc get network-attachment-definitions` | Networking |
| **must-gather** | Collects a diagnostic bundle for support | `oc adm must-gather` | Troubleshooting |

## N

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Namespace (ns)** | A named area for objects, permissions and quotas; see Project | `oc get ns` | Basics |
| **ndots** | Pod DNS option (5): short names try the search domains first | `cat /etc/resolv.conf` (inside a pod) | Networking |
| **NetworkPolicy** | Firewall rules for pods; once a pod is selected, anything not allowed is dropped | `oc get networkpolicy` | Networking |
| **Node** | A server (VM or physical) in the cluster | `oc get nodes -o wide` | Nodes |
| **Node selector** | Runs pods only on nodes with given labels | `oc get deploy <d> -o jsonpath='{.spec.template.spec.nodeSelector}'` | Workloads |
| **NodePort** | Service exposed on a fixed port of every node | `oc get svc` (PORT(S) 8080:3xxxx) | Networking |
| **NotReady** | A node that stopped reporting or is unhealthy | `oc describe node <n>` (Conditions) | Nodes |

## O

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **OADP** | OpenShift API for Data Protection: backup and restore of apps (Velero) | `oc get backup -n openshift-adp` | Storage |
| **OAuth server** | OpenShift's built-in login server; issues tokens | `oc whoami` | Access |
| **oc** | The OpenShift CLI; does everything kubectl does, plus OpenShift objects | `oc version` | Basics |
| **oc debug** | Starts a copy of a pod with a shell, or a shell on a node | `oc debug pod/<p>` · `oc debug node/<n>` | Troubleshooting |
| **OLM** | Operator Lifecycle Manager: installs and upgrades add-on Operators | `oc get subscriptions -A` | Platform |
| **OOMKilled** | Container killed for using more memory than its limit (exit 137) | `oc describe pod <p>` (Last State) | Troubleshooting |
| **Operator** | Software that runs other software the way an expert administrator would | `oc get csv` | Platform |
| **OperatorHub** | The catalogue of installable Operators in the web console | — | Platform |
| **OVN-Kubernetes** | OpenShift's network plugin, built on Open vSwitch | `oc get network.config cluster -o jsonpath='{.spec.networkType}'` | Networking |
| **ownerReferences** | Link from an object to the controller that owns it (pod → ReplicaSet → Deployment) | `oc get pod <p> -o jsonpath='{.metadata.ownerReferences[0].kind}'` | Workloads |

## P

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Passthrough (TLS)** | Route TLS type: the router forwards encrypted traffic; the pod decrypts | `oc get route <r> -o jsonpath='{.spec.tls.termination}'` | Networking |
| **PDB** | PodDisruptionBudget: how many pods of an app may be down during drains and upgrades | `oc get pdb` | Workloads |
| **Pending** | Pod not yet placed on a node, or waiting for its volume | `oc describe pod <p>` (FailedScheduling) | Troubleshooting |
| **PersistentVolume (PV)** | A piece of storage in the cluster | `oc get pv` | Storage |
| **PersistentVolumeClaim (PVC)** | A project's request for storage; `Pending` until bound | `oc get pvc` | Storage |
| **Pod (po)** | One or more containers sharing an IP and storage; the smallest unit OpenShift runs | `oc get pods -o wide` | Basics |
| **Pod network** | Address range for pod IPs, split into a block per node | `oc get network.config cluster -o jsonpath='{.spec.clusterNetwork}'` | Networking |
| **Pod Security Admission** | Namespace labels that warn about or enforce pod security standards | `oc get ns <ns> --show-labels` | Security |
| **port / targetPort** | Service port that callers use / the pod port traffic is forwarded to | `oc get svc <s> -o jsonpath='{.spec.ports}'` | Networking |
| **port-forward** | Tunnels a local port to a pod through the API server, for testing | `oc port-forward pod/<p> 8080:8080` | Troubleshooting |
| **PriorityClass** | How important a pod is when the scheduler must choose or preempt | `oc get priorityclass` | Workloads |
| **Probe** | A health check the kubelet runs: startup, liveness, readiness | `oc describe pod <p>` (Liveness/Readiness) | Workloads |
| **Project** | A namespace plus OpenShift extras: template defaults, quotas, its own UID range | `oc projects` | Basics |
| **Project template** | Objects automatically created in every new project (quotas, policies) | `oc get project.config cluster -o yaml` | Platform |
| **Prometheus / Alertmanager** | Cluster metrics collection / alert routing | `oc get pods -n openshift-monitoring` | Monitoring |
| **Pull secret** | Credentials used to pull images from registries | `oc get secret pull-secret -n openshift-config` | Images |

## Q

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **QoS class** | Guaranteed, Burstable or BestEffort; decides eviction order | `oc get pod <p> -o jsonpath='{.status.qosClass}'` | Workloads |
| **Quorum** | Majority of etcd members (2 of 3) needed to write | `oc get pods -n openshift-etcd -l app=etcd` | Platform |

## R

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **RBAC** | Role-based access control: who may do which actions | `oc auth can-i <verb> <resource>` | Access |
| **Readiness probe** | "Ready for traffic?" Failure removes the pod from endpoints, without restarting it | `oc set probe deploy/<d> --readiness …` | Workloads |
| **Reclaim policy** | What happens to a volume after its PVC is deleted: Delete or Retain | `oc get sc` (RECLAIMPOLICY) | Storage |
| **Reconciliation** | The observe → compare → act loop every controller and operator runs | — | Platform |
| **Reencrypt (TLS)** | Route TLS type: router decrypts, then encrypts again to the pod | `oc get route <r> -o jsonpath='{.spec.tls.termination}'` | Networking |
| **Registry** | Server storing images: quay.io, registry.redhat.io, the internal registry | `skopeo inspect docker://<image>` | Images |
| **Release image** | One tested bundle of every platform component for a version | `oc adm release info` | Platform |
| **ReplicaSet (rs)** | Keeps an exact number of matching pods; created by a Deployment | `oc get rs` | Workloads |
| **Requests** | CPU and memory reserved for a container; the scheduler uses them | `oc describe node <n>` (Allocated resources) | Workloads |
| **restricted-v2** | Default SCC: random non-root UID from the project range, group 0, no extra privileges | `oc get scc restricted-v2` | Security |
| **RHCOS** | Red Hat Enterprise Linux CoreOS: the image-based node OS | `oc get nodes -o wide` (OS-IMAGE) | Nodes |
| **Role / RoleBinding** | A set of permissions in one project / who it is granted to | `oc get rolebinding` | Access |
| **Rolling update** | Replaces pods gradually; old ones go only after new ones are Ready | `oc rollout status deploy/<d>` | Release |
| **Rollout history / revision** | Numbered versions of a Deployment's pod template | `oc rollout history deploy/<d>` | Release |
| **Rollout undo** | Returns a Deployment to its previous revision | `oc rollout undo deploy/<d>` | Release |
| **Route** | OpenShift object exposing a Service at a hostname | `oc get route` | Networking |
| **Router** | HAProxy pods that receive outside traffic and forward it by hostname | `oc get pods -n openshift-ingress` | Networking |
| **Running 0/1** | Container runs but is not Ready (failing readiness probe or still starting) | `oc describe pod <p>` (Events) | Troubleshooting |

## S

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **S2I (Source-to-Image)** | Build strategy that turns source code into an image using a builder image | `oc new-app <builder>~<git-url>` | Images |
| **SCC** | Security Context Constraint: what a pod may do on its node (user, privileges, volumes) | `oc get pod <p> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'` | Security |
| **Scheduler** | Chooses a node for each new pod | `oc describe pod <p>` (Scheduled event) | Platform |
| **Secret** | Sensitive settings (passwords, keys); base64-encoded, not encrypted | `oc get secret` | Config |
| **Selector** | A label query used by Services, Deployments and `-l` | `oc get svc <s> -o wide` (SELECTOR) | Basics |
| **SELinux / MCS label** | Kernel labels (e.g. `s0:c26,c15`) that keep projects' containers apart | `oc describe project <p>` (sa.scc.mcs) | Security |
| **Service (svc)** | Stable name and virtual IP in front of a changing set of pods | `oc get svc` | Networking |
| **Service account (sa)** | An identity for pods, apps and operators | `oc get sa` | Access |
| **Service CA** | Built-in certificate authority that issues TLS certificates for Services | — | Security |
| **Service network** | Address range for Service virtual IPs | `oc get network.config cluster -o jsonpath='{.spec.serviceNetwork}'` | Networking |
| **skopeo** | Inspects or copies images without pulling them | `skopeo inspect docker://<image>` | Images |
| **SNO** | Single Node OpenShift: control plane and worker on one machine | — | Platform |
| **Startup probe** | Holds liveness and readiness checks off while a slow app starts | `oc set probe deploy/<d> --startup …` | Workloads |
| **StatefulSet (sts)** | Runs pods with stable names and their own volumes | `oc get sts` | Workloads |
| **Static pod** | Pod the kubelet runs from a file on disk; used for control plane components | — | Nodes |
| **StorageClass (sc)** | A kind of storage PVCs can request; enables dynamic provisioning | `oc get sc` | Storage |
| **Subscription (sub)** | OLM: which Operator and update channel to keep installed | `oc get sub -A` | Platform |

## T

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Tag** | A movable image name (`:latest`, `:v2`) that can point at a different image later | `oc get istag` | Images |
| **Taint / toleration** | A node marking that repels pods / a pod's permission to ignore it | `oc describe node <n>` (Taints) | Nodes |
| **Template (OpenShift)** | Parameterised set of objects, processed into real objects | `oc get templates -n openshift` | Release |
| **Terminating (stuck)** | Pod or object waiting on finalizers or a process that will not exit | `oc get <obj> -o yaml` (finalizers) | Troubleshooting |
| **tolerationSeconds** | How long a pod stays on a NotReady or unreachable node before eviction (300 s default) | `oc get pod <p> -o yaml` (tolerations) | Nodes |
| **Topology spread** | Spreads a workload's pods across nodes or zones | `oc get deploy <d> -o yaml` (topologySpreadConstraints) | Workloads |

## U

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **UID range** | Each project's block of user IDs for restricted-v2 pods | `oc describe project <p> \| grep uid-range` | Security |
| **Update channel** | Which upgrade stream the cluster follows (stable-4.x, fast-4.x, eus-4.x) | `oc get clusterversion -o jsonpath='{.items[0].spec.channel}'` | Platform |

## V

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Volume / volumeMount** | Storage attached to a pod / where it appears inside a container | `oc set volume deploy/<d>` | Storage |
| **VolumeBindingMode** | Immediate (create the volume at once) or WaitForFirstConsumer (when a pod is scheduled) | `oc get sc` (VOLUMEBINDINGMODE) | Storage |

## W

| Term | Meaning | See it with | Area |
|---|---|---|---|
| **Wildcard DNS** | The `*.apps.<cluster-domain>` record pointing every app hostname at the router | `getent hosts <any-name>.apps.<cluster-domain>` | Networking |
| **Worker node** | A node that runs applications | `oc get nodes -l node-role.kubernetes.io/worker` | Nodes |

---

**Status words at a glance:** `Pending` (not placed yet) · `ContainerCreating` (pulling image, mounting volumes) · `Running 0/1` (not Ready) · `CrashLoopBackOff` (keeps exiting) · `ErrImagePull` / `ImagePullBackOff` (image problem) · `OOMKilled` (memory limit) · `Evicted` (node pressure) · `Terminating` (being deleted) · `Completed` (finished, for Jobs). Full guide: [pod failure states decoder](pod-failure-states-decoder.md).

See also: [OpenShift architecture](openshift-architecture.md) · [oc command bank](oc-command-bank.md) · [OpenShift vs Kubernetes architecture](openshift-vs-kubernetes-architecture.md)
