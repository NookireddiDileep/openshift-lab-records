# OpenShift Career Ladder: L1 to Architect

_As of 27 Nov 2026. A general guide for OpenShift aspirants: roles, responsibilities, skills, courses, certifications and interviews at each level. For what DO180, DO280 and DO380 each cover in detail, see the [OpenShift admin learning path](openshift-admin-learning-path.md)._

OpenShift careers move from keeping applications running (L1) to designing and rescuing whole platforms (architect). Each level adds **wider scope** (one app → one cluster → many clusters → the company's platform strategy) and **deeper troubleshooting** (pod → node → control plane → design).

## The ladder at a glance

| Level | Typical titles | Typical experience | Scope | Main question at this level |
| --- | --- | --- | --- | --- |
| L1 | OpenShift Support Engineer, Platform Operator, NOC/L1 Support | 0–3 years (often from Linux support) | Applications and alerts on existing clusters | Is it broken, and who should fix it? |
| L2 | OpenShift Administrator, Platform Engineer | 3–6 years | Day-2 admin of one or more clusters | Can I administer and fix the cluster? |
| L3 | Senior OpenShift Admin, Senior Platform Engineer, L3 SME | 6–10 years | Production clusters end to end: upgrades, backup, security, escalations | Can I run production safely and solve the hard cases? |
| L4 | Lead Platform Engineer, OpenShift SME / Technical Lead | 8–12 years | Many clusters, a team, platform standards | Can I make the platform reliable at scale through others? |
| Expert / Architect | OpenShift Architect, Platform Architect, Principal Engineer | 10+ years | Platform design across data centres and clouds | What should we build, why, and how will it fail? |

Years are rough guides from Indian and global job posts; skill and evidence matter more than years. Many people move up faster by doing hands-on labs, writing RCAs and passing hands-on exams.

**Before L1:** Linux basics, networking basics (IP, DNS, ports, TLS), containers (Podman or Docker), Git and YAML. Free practice: [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox) and OpenShift Local (CRC) on a laptop.

## L1: OpenShift support / platform operator

L1 keeps applications and alerts under control on clusters someone else built, and escalates clearly when a fix is beyond the runbook.

**Responsibilities**

- Monitor dashboards and alerts; acknowledge and triage incidents within the SLA.
- Check pod, deployment and route status; restart, scale or roll back by runbook.
- Collect first data for escalation: events, logs, `oc describe`, screenshots.
- Create projects and handle simple access requests by procedure.
- Raise and update tickets (ServiceNow or similar) with clear notes.

**Skills to have**

- Linux basics: processes, logs, disk, networking commands.
- Container basics: image, container, registry, pod.
- `oc` / `kubectl` basics: `get`, `describe`, `logs`, `events`, `rollout`.
- Reading common pod states: `CrashLoopBackOff`, `ImagePullBackOff`, `Pending`, `OOMKilled` (see the [pod failure states decoder](pod-failure-states-decoder.md)).
- Clear written communication in tickets.

**How to move up to L2:** stop at "what is broken" less often and reach "why". Practise every failure in a lab, write short RCAs, and complete DO180-level hands-on work.

## L2: OpenShift administrator

L2 administers the cluster itself: who can log in, what they can do, how traffic gets in, and how much each team may use.

**Responsibilities**

- Configure identity providers, users, groups and RBAC.
- Manage application security: service accounts, security context constraints (SCCs), secrets.
- Configure routes with TLS, ingress, network policies and load balancer services.
- Set quotas, limit ranges and project templates for teams.
- Install and update operators; deploy apps with YAML, Kustomize, Helm and templates.
- Do health checks on cluster operators, nodes and storage; run z-stream updates under supervision.
- Resolve most incidents L1 escalates; write RCAs.

**Skills to have**

- Fast, accurate `oc` work without notes (`oc adm policy`, `oc set`, `--dry-run=client -o yaml`, `oc explain`).
- The pod-start chain: image → SCC → service account → RBAC → quota → scheduling.
- Network path: route → service → endpoints → pod, plus network policies.
- Persistent storage basics: storage classes, PV/PVC, access modes.
- Reading must-gather output and cluster operator conditions.

**How to move up to L3:** own production changes end to end (plan, run, verify, roll back), not just tickets. Learn upgrades, backup and restore, node configuration and monitoring in depth. Pass EX280.

## L3: Senior administrator / platform engineer

L3 owns production: upgrades, backups, security and the hardest incidents, and is the last line before the vendor.

**Responsibilities**

- Plan and run minor and z-stream upgrades across environments; recover stuck updates and degraded MachineConfigPools.
- Manage nodes: MachineConfigs, node pools, RHCOS configuration, draining, certificate rotation.
- Back up and restore: etcd backup, application backup with OADP/Velero, DR tests.
- Fix CVEs and keep the platform compliant; work with security teams.
- Run monitoring, alerting and logging (Prometheus, Alertmanager, Loki/Vector); tune alerts.
- Integrate enterprise identity (LDAP, SSO/OIDC, group sync).
- Handle L3 escalations; open and drive vendor (Red Hat) support cases with must-gather data.
- Automate repeat work with Ansible, scripts and GitOps (Argo CD).

**Skills to have**

- Troubleshooting below Kubernetes: kubelet, CRI-O, SELinux, cgroups, `oc debug node`, `journalctl`.
- Control plane health: etcd, API server, OAuth, cluster operators and their dependencies.
- Networking depth: OVN-Kubernetes basics, ingress controller, DNS operator, egress.
- Workload placement: taints, tolerations, affinity, pod disruption budgets.
- Change management: risk, rollback plans, maintenance windows.

**How to move up to L4:** start designing, not only running. Write standards and runbooks others use, mentor L1/L2, and lead incident reviews. Pass EX380.

## L4: Lead platform engineer / OpenShift SME

L4 makes many clusters reliable through standards, automation and a team, rather than by fixing each problem personally.

**Responsibilities**

- Own platform standards: cluster baselines, naming, security policies, onboarding process for app teams.
- Run fleets: multi-cluster management (ACM), policy and compliance (ACS), GitOps for cluster configuration.
- Lead major incidents and blameless postmortems; track action items to closure.
- Plan capacity, upgrades and lifecycle across all clusters for the year.
- Build self-service for app teams (templates, pipelines with Tekton or GitLab CI, golden paths).
- Mentor L1–L3; review changes and runbooks; interview candidates.
- Work with architects, security, network and storage teams; explain trade-offs to managers.

**Skills to have**

- Fleet thinking: consistency, drift detection, policy as code.
- SRE practice: SLOs, error budgets, alert quality, toil reduction.
- Storage and data: ODF/Ceph basics, CSI, snapshots, DR design.
- Infrastructure as code: Terraform and Ansible at production quality.
- Communication: writing clear standards, leading a room during an outage.

**How to move up to Architect:** make design decisions and defend them in writing (options, trade-offs, cost, risk). Learn installation and platform variants (bare metal, VMware, cloud, virtualization, OpenShift AI).

## Expert / OpenShift architect

The architect decides what platform to build and why, and designs it so that failures are expected, contained and recoverable.

**Responsibilities**

- Design platforms: cluster topology, install method (IPI, UPI, agent-based), bare metal vs. VMware vs. cloud, hosted control planes.
- Write high-level and low-level designs (HLD/LLD); choose between options with clear trade-offs.
- Design for resilience: multi-zone and multi-site layouts, DR strategy, backup policy, upgrade strategy.
- Set the security architecture: identity, network segmentation, supply chain (image signing, scanning), compliance and data sovereignty.
- Plan capacity and cost: node sizing, overcommit policy, licence and hardware cost.
- Bring in new workloads: VMs on OpenShift (OpenShift Virtualization), AI/GPU workloads (OpenShift AI, GPU Operator), edge clusters.
- Advise leadership; review designs from other teams; guide L3/L4 engineers.

**What separates the top 1%**

- They can debug any layer: kernel, node, network packet path, etcd, API, operators, application.
- They predict how a design will fail before it is built, and design the runbook with it.
- They explain complex systems simply, in writing and in meetings.
- They have production scars: real outages handled and real RCAs written.
- They keep learning: Kubernetes releases, new OpenShift versions, AI and platform trends.

## Cloud and multi-cloud OpenShift track

The same OpenShift skills apply on every cloud; what changes is who runs the control plane and how much cloud networking, identity and cost work sits with you. Many enterprises now run OpenShift in their own data centre **and** on one or more public clouds, so engineers who handle both are in demand.

**Where OpenShift runs on public clouds**

| Option | Cloud | Who manages the platform | What you still own |
| --- | --- | --- | --- |
| Red Hat OpenShift Service on AWS (ROSA) | AWS | Red Hat and AWS jointly | Apps, projects, access, AWS networking and IAM around the cluster, cost |
| Azure Red Hat OpenShift (ARO) | Azure | Red Hat and Microsoft jointly | Apps, projects, access, Azure networking and identity, cost |
| Red Hat OpenShift Dedicated (OSD) | Google Cloud, AWS | Red Hat | Apps, projects, access, cloud account setup |
| Red Hat OpenShift on IBM Cloud | IBM Cloud | IBM, with Red Hat support | Apps, projects, access, IBM Cloud services |
| Self-managed OpenShift Container Platform | AWS, Azure, Google Cloud and others | You | Everything: install, upgrades, nodes, backup, plus the cloud infrastructure |

**How the work changes by level on this track**

- **L1–L2:** run and support apps on managed clusters; manage projects, access, routes and quotas; know the shared-responsibility split (what the provider fixes vs. what you fix).
- **L3:** cloud networking for clusters (VPC/VNet, private clusters, load balancers, DNS, private links); cloud identity (IAM roles, workload identity such as AWS STS or Azure/GCP equivalents); storage classes on cloud disks; backup to object storage; self-managed installs on cloud (IPI).
- **L4:** run fleets across clouds and data centres with ACM, ACS and GitOps; standard cluster baselines; cost control and capacity across accounts; infrastructure as code (Terraform) for cloud landing zones.
- **Architect:** choose managed vs. self-managed per workload; design hybrid and multi-cloud layouts (connectivity, identity, DR across clouds, data residency and sovereignty); compare cost and risk.

**Skills to add for this track:** one cloud in depth first (networking, IAM, storage, cost), then a second; Terraform; ACM for multi-cluster; GitOps for consistent configuration everywhere.

**Learning path:** Red Hat offers an intro course for ROSA (DO120) and a free 8-hour ROSA hands-on experience; pair OpenShift certifications with one cloud certification (for example an AWS, Azure or Google Cloud associate-level admin or architect exam) that matches your employer's cloud. Sources: [OpenShift editions (Red Hat docs)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/overview/openshift-editions), [OpenShift product editions](https://redhat.com/openshift/docs), [Red Hat OpenShift on IBM Cloud](https://www.ibm.com/cloud/openshift/sla).

## Where OpenShift is heading: OpenShift 5 and beyond

OpenShift 5 (generally available November 2026, based on Kubernetes 1.36) is the first major version in seven years. It focuses on easier upgrades, AI-assisted operations, security for AI-era workloads, and running VMs and containers on one platform.

**Real-world problems OpenShift 5 targets**

| IT problem | What OpenShift 5 does |
| --- | --- |
| Major upgrades turn into migration projects | Clusters on 4.22 update in place; Red Hat says no migration plan is needed. Upgraded clusters stay on RHEL CoreOS 9; new clusters default to RHEL CoreOS 10. |
| Platform lifecycle does not match budget and app cycles | A major release every 3 years; Extended Life Cycle (ELC) releases with 5 years of enterprise support, also covering ACS, Service Mesh, Pipelines and GitOps. |
| Hard to know if operators are safe to update | An update planner shows operator lifecycle status, compatibility and update options in one view. |
| Incident triage takes too long | Supervised agentic troubleshooting (OpenShift Lightspeed) collects findings and waits for an admin to confirm before acting; update guidance maps conflicts and blast radius before a change window. |
| AI agents need safe access to the platform | The MCP server and MCP gateway are generally available, giving AI agents governed access to platform APIs. |
| AI models and agent-written code create new attack surfaces | Confidential containers protect model weights; an Agent Sandbox (tech preview) runs agent workloads in VMs; post-quantum-ready TLS and centrally enforced TLS settings. |
| VMs and containers run in separate silos | OpenShift Virtualization 5: one platform for both, incremental VM backup that copies only changed blocks, memory-aware load balancing for live migration, an "autopilot" for drift prevention and node-failure recovery. |

**Where it is heading next (stated direction and clear trends)**

- **Node OS changes without a platform upgrade:** Red Hat plans RHEL CoreOS 9 and 10 side by side in one cluster in a future release.
- **From assisted to autonomous operations:** autonomous troubleshooting and an update agent are in tech preview today. Expect more "AI proposes, human approves" automation in day-2 work.
- **Platform for AI and agents:** governed agent access (MCP), sandboxing and confidential computing point to OpenShift as the place where companies run and control AI workloads, not only apps.
- **One platform for VMs, containers and AI:** organisations moving off older virtualization stacks are consolidating onto Kubernetes-based platforms.
- **Security and sovereignty:** post-quantum cryptography, stricter defaults and regulated-cloud requirements keep rising.

**What this means for engineers, by level**

- **L1–L2:** core admin skills do not change; learn the new console views and how Lightspeed suggestions work, but always verify them.
- **L3:** RHEL 10 / RHCOS 10 node skills, update planning with the new planner, OpenShift Virtualization operations, judging whether an AI-proposed fix is safe.
- **L4 / Architect:** governance for AI agents (identity, permissions, audit), confidential and sandboxed workloads, VM migration strategy, lifecycle planning around 3-year majors and ELC releases.

As AI takes over routine triage, the engineers who stay valuable are those who understand the system deeply enough to check the AI's answer. Sources: [Announcing Red Hat OpenShift 5 (Red Hat blog)](https://redhat.com/en/blog/announcing-red-hat-openshift-5), [OpenShift 5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes).

## Certifications and courses by level

Red Hat exams are hands-on (tasks on a live cluster), so they prove skill better than multiple-choice tests. Use them to pass the CV filter; interviews still test real troubleshooting.

| Level | Red Hat courses | Exams | Others that help |
| --- | --- | --- | --- |
| L1 | DO180 (OpenShift Administration I) | Optional preliminary exam PE180 | RHCSA |
| L2 | DO280 (OpenShift Administration II) | **EX280**, Certified OpenShift Administrator (3 hours, hands-on) | CKA |
| L3 | DO380 (OpenShift Administration III) | **EX380**, Advanced System Administrator in OpenShift (4 hours, hands-on) | RHCE (Ansible), CKS |
| L4 | DO322 (installation), DO432 (ACM), DO430 (ACS), DO370 (ODF) | Specialist exams such as EX432, EX430, EX370 | Terraform Associate |
| Architect | DO316 (OpenShift Virtualization), AI267 (OpenShift AI) | RHCA in OpenShift (several specialist exams together) | One cloud architect certification |

Check current exam versions and objectives on Red Hat's site before booking; they change with OpenShift releases. Sources: [EX280 page](https://www.redhat.com/en/services/training/red-hat-certified-openshift-administrator-exam), [EX380 page](https://www.redhat.com/en/services/training/ex380-certified-specialist-openshift-automation-exam), [OpenShift skill paths](https://redhat.com/en/resources/openshift-skill-paths-brief).

**Full OpenShift course path: what to take and when**

Take the core three in order; pick specialisations by the jobs you target. Do each course with hands-on labs before starting the next.

| Order | Course | Topic | Level | When to take it |
| --- | --- | --- | --- | --- |
| 1 | DO180 | OpenShift Administration I: run and fix applications | L1 | Start here |
| 2 | DO280 | OpenShift Administration II: cluster administration | L2 | After DO180 hands-on; then EX280 |
| 3 | DO380 | OpenShift Administration III: enterprise scale, backup, scheduling, GitOps, logging | L3 | After EX280; then EX380 |
| 4 | DO322 | Installation: IPI, UPI, bare metal, Assisted; optional agent-based and hosted control planes | L3 | After DO280, before you own production clusters |
| 5 | DO282 | Advanced networking | L3 | After DO280; useful for L3 support and network-heavy roles |
| 6 | DO370 | Enterprise storage (OpenShift Data Foundation) | L3–L4 | When your platform runs stateful workloads or ODF |
| 7 | DO316 | Virtualization, advanced virtualization and VM migration | L3–L4 | When your company moves VMs onto OpenShift |
| 8 | DO432 | Advanced Cluster Management: multi-cluster and fleet management | L4 | When you run many clusters |
| 9 | DO430 | Advanced Cluster Security | L4 | When you own platform security and compliance |
| 10 | DO505 | Hosted control plane installation (new or existing host inventory, over OpenShift Virtualization) | L4–Architect | After DO322 and DO316 |
| 11 | AI267 | OpenShift AI / ML | L4–Architect | After the core three, when you move toward AI platforms |
| Cloud | DO120 | Introduction to ROSA (OpenShift on AWS) | Any | Alongside DO280–DO380 if your employer uses AWS |

Course codes and titles change over time; check the current Red Hat catalogue (or your training provider's) before enrolling. In Red Hat's catalogue, DO432 is Advanced Cluster Management and DO430 is Advanced Cluster Security.

## Kubernetes foundation

OpenShift is Kubernetes plus enterprise extras (routes, SCCs, OAuth, operators, the console), so every Kubernetes skill carries straight over, and strong Kubernetes basics make every OpenShift level easier. See also [OpenShift vs Kubernetes architecture](openshift-vs-kubernetes-architecture.md) and the [kubernetes-labs](https://github.com/NookireddiDileep/kubernetes-labs) repo.

| Kubernetes certification (CNCF) | What it proves | Best time on the OpenShift ladder |
| --- | --- | --- |
| KCNA | Cloud-native and Kubernetes concepts | Optional, before or during DO180 |
| CKAD | Building and running apps on Kubernetes | Optional, useful for L1–L2 and app-facing roles |
| CKA | Kubernetes cluster administration | L2, after EX280; opens roles on EKS, AKS, GKE and vanilla Kubernetes |
| CKS | Kubernetes security | L3, after CKA; pairs with ACS and platform security work |

**Tip:** DO180 and DO280 already teach most of the Kubernetes needed for CKA. Practising on plain Kubernetes as well (kind, K3s or kubeadm) shows what OpenShift adds and what it does for you, which interviewers often ask about.

## How interviews test each level, and advice for aspirants

Interviews test whether you can do the work live, so practise by doing, not by memorising answers.

| Level | What the panel usually asks |
| --- | --- |
| L1 | Pod states and what they mean; basic `oc` commands; how you would escalate an incident |
| L2 | Live tasks: create a TLS route, fix a pod blocked by an SCC, write a network policy, set a quota; "walk me through a 503 on a route" |
| L3 | Upgrade stuck at a degraded MachineConfigPool; etcd backup and restore; node NotReady; a must-gather walkthrough; your hardest production incident |
| L4 | Running many clusters: standards, GitOps, ACM/ACS; leading a major incident; mentoring and process |
| Architect | Design a platform for a scenario (sites, DR, security, cost); defend the trade-offs; explain how it fails |

**Advice for aspirants**

1. **Get lab access and use it every day.** Confidence comes only from hands-on practice on a real multi-node cluster.
2. **Break things on purpose, then fix them.** Every feature has a common failure; learn both.
3. **Write an RCA for every fix:** symptom, evidence, root cause, fix, prevention. It becomes your interview story.
4. **Climb level by level.** DO180 → DO280 → DO380. Weak basics make the next level feel impossible.
5. **Time yourself.** Hands-on exams and live interviews are timed; speed comes from repetition.
6. **Use your past experience.** Linux, networking, storage and ITIL support skills carry straight over to OpenShift operations.
7. **Show your work.** A public GitHub repo of lab records and RCAs says more than a list of courses on a CV.

**Rough timeline with steady hands-on practice (10–15 hours a week)**

| Starting point | Target | Rough time |
| --- | --- | --- |
| Fresher | L1-ready (DO180 level) | 4–6 months |
| Fresher | L2-ready (EX280 passed) | 12–18 months |
| Experienced Linux / support engineer | L2-ready (EX280 passed) | 3–6 months |
| L2 in a job | L3 (EX380, production upgrades and backup) | 1–2 years of production work |
| L3 | L4 / Architect | 3–5 more years, with design and leadership work |

These are estimates, not rules: hands-on hours and production exposure matter more than calendar time.

**Career tips**

- **Portfolio:** keep a public GitHub repo of lab records and RCAs (symptom, evidence, root cause, fix, prevention). Remove company names, IPs and secrets.
- **CV:** show evidence, not a list of courses: "fixed a route returning 503 caused by a NetworkPolicy" beats "completed DO280". Put hands-on exams and a link to the portfolio near the top.
- **LinkedIn:** use the job titles you are targeting in your headline, share short posts about what you learned in labs, and connect with OpenShift engineers and recruiters. Ask for referrals; they work far better than cold applications.
