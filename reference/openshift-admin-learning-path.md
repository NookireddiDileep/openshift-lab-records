# OpenShift administration learning path: DO180 vs DO280 vs DO380

> Concept guide in my own words, for anyone planning Red Hat OpenShift administration training. Course names, versions and exams as published by Red Hat in **November 2026**; check [Red Hat Training](https://www.redhat.com/en/services/training) before you book, because codes and contents change.

The three courses are one track. Each assumes the previous one.

| | **DO180** | **DO280** | **DO380** |
|---|---|---|---|
| Full name | Red Hat OpenShift Administration I: Operating a Production Cluster | Red Hat OpenShift Administration II: Configuring a Production Cluster | Red Hat OpenShift Administration III: Scaling Deployments in the Enterprise |
| Level | Foundation: **use** a cluster | Administrator: **configure** a cluster | Enterprise: **run clusters at scale** |
| Main topics | Projects, deployments, services, routes, storage, scaling, troubleshooting applications, web console and `oc` | Authentication and RBAC, quotas and limits, network security, SCCs, operators, cluster updates, packaged apps (Helm/Kustomize) | Planning and managing clusters in the enterprise: GitOps, automation, monitoring and logging, node operations, application backups with OADP |
| Exam | No certification of its own (a preliminary exam, PE180, exists) | **EX280**: Red Hat Certified OpenShift Administrator | **EX380**: Red Hat Certified Specialist in OpenShift Automation and Integration |
| Before you start | Linux command-line basics | DO180 or equivalent experience with OpenShift's console and CLI | Red Hat recommends it after EX280 |
| Typical job it maps to | Application support on OpenShift | **OpenShift administrator** (L2/L3 operations) | **Platform engineer** (designing and running the platform for many teams) |

At the time of writing, DO280 is based on OpenShift Container Platform **4.18**.

## Recommended order

```text
DO180 ──► DO280 ──► EX280 ──► DO380 ──► EX380
                       │
                       └──► specialisations (pick by job need)
```

**EX280 is the milestone most job postings ask for.** DO380 is what moves you from administering one cluster to engineering a platform.

## After DO380: specialisations

| Need | Course / exam (verify current codes) |
|---|---|
| Installing clusters (IPI, UPI, agent-based) | DO322: Red Hat OpenShift Installation Lab |
| In-cluster storage (Ceph-based) | DO370 / EX370: OpenShift Data Foundation |
| Virtual machines on OpenShift | OpenShift Virtualization courses (DO156, DO316) |
| Multi-cluster management and security | Advanced Cluster Management and Advanced Cluster Security courses |
| AI/ML platform | Red Hat OpenShift AI courses |

## How I'd use this

1. Do the labs of each course on a real cluster, not just the guided exercises, and **break things on purpose**: that's where the troubleshooting skill comes from. This repo's [stories](../stories/) and [RCAs](../rca/) are examples.
2. Take **EX280** soon after DO280 while the commands are fresh; it's hands-on, so speed with `oc` matters (see the [oc command bank](oc-command-bank.md)).
3. Start DO380 with the [OpenShift vs Kubernetes architecture](openshift-vs-kubernetes-architecture.md) guide in mind: DO380 is mostly about operating OpenShift's operator-managed platform at scale.

## Sources

- Red Hat: [DO380 course page](https://www.redhat.com/en/services/training/do380-red-hat-openshift-administration-iii-scaling-deployments-in-the-enterprise) (description, OADP, recommended next courses)
- Red Hat: [OpenShift skill paths datasheet](https://www.redhat.com/en/resources/openshift-skill-paths-datasheet) (DO380 recommended after EX280; EX380 title)
- Red Hat: [OpenShift skills path brief (PDF)](https://www.redhat.com/rhdc/managed-files/tr-openshift-skills-path-brief-994253pr-202402-en.pdf) (DO180/DO280 titles, PE180)
- Training partner listing for DO280: [course details](https://www.globalknowledge.com/en-ae/courses/red_hat/enterprise_services/do280) (based on OCP 4.18)
