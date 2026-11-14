# `oc` Command Bank – command → purpose → when to use it

A working reference built from the DO180/DO280 material and my own labs.
🔴 = needs cluster-admin. Everything else works as a normal user in your own project.
Placeholders: `<app>`, `<pod>`, `<ns>`, `<node>`. Pair this with the [RCA scenario bank](../scenarios/DO180-RCA-scenario-bank.md).

**Contents:**
1. [Login, context and projects](#1-login-context-and-projects)
2. [Exploring the API](#2-exploring-the-api)
3. [Getting and shaping output](#3-getting-and-shaping-output)
4. [Pods: run, inspect, debug](#4-pods-run-inspect-debug)
5. [Moving data in and out](#5-moving-data-in-and-out)
6. [Images, registries and ImageStreams](#6-images-registries-and-imagestreams)
7. [Builds](#7-builds)
8. [Deployments and workloads](#8-deployments-and-workloads)
9. [Rollouts and updates](#9-rollouts-and-updates)
10. [Services, Routes, Ingress, networking](#10-services-routes-ingress-networking)
11. [ConfigMaps and Secrets](#11-configmaps-and-secrets)
12. [Storage](#12-storage)
13. [Probes, resources, autoscaling](#13-probes-resources-autoscaling)
14. [Quotas and limits](#14-quotas-and-limits)
15. [Security: SCC, ServiceAccounts, RBAC](#15-security-scc-serviceaccounts-rbac)
16. [Cluster and nodes](#16-cluster-and-nodes-)
17. [Troubleshooting one-liners](#17-troubleshooting-one-liners)

---

## 1. Login, context and projects

| Command | Purpose | When / notes |
|---|---|---|
| `oc login -u <user> https://api.<cluster>:6443` | Log in with a username and password | First thing in any session |
| `oc login --token=<t> --server=<api>` | Log in with a token | Token copied from the console ("Copy login command") |
| `oc whoami` / `oc whoami -t` / `oc whoami --show-server` | Who am I, my token, which cluster | "Unauthorized" or "wrong cluster" suspicion |
| `oc whoami --show-console` | Web console URL | |
| `oc config get-contexts` / `oc config use-context <ctx>` | List and switch kubeconfig contexts | Several clusters or users in one kubeconfig |
| `oc new-project <ns>` | Create a project and switch to it | |
| `oc project` / `oc project <ns>` | Show / switch the current project | "`oc get pods` shows nothing" → wrong project |
| `oc projects` | List the projects you can see | |
| `oc get project <ns> -o yaml` | Requester, creation time, annotations | Who created a project |
| `oc delete project <ns>` | Delete a project and everything in it | Irreversible |

## 2. Exploring the API

| Command | Purpose | When / notes |
|---|---|---|
| `oc api-resources` | All resource types, short names, API groups | "What's the short name for X?" |
| `oc api-resources --namespaced=false` | Cluster-scoped resources only | PV, StorageClass, Node, SCC… |
| `oc api-versions` | API group versions served | Deprecated API checks |
| `oc explain <res>.spec --recursive` | Field documentation from the cluster's schema | Fastest docs in an exam |
| `oc explain deploy.spec.strategy` | One field with its description | Writing YAML without the docs |
| `oc <verb> --help` | Flags and examples | `oc set probe --help`, `oc create route --help` |

## 3. Getting and shaping output

| Command | Purpose | When / notes |
|---|---|---|
| `oc get all` | Pods, services, deployments, ReplicaSets, routes… | First look at a project (it doesn't include PVCs, ConfigMaps or Secrets) |
| `oc get all,pvc,cm,secret,route` | A fuller first look | Triage start |
| `oc get pods -o wide` | Pod IP, node, nominated node | Which node, what IP |
| `oc get pods --show-labels` / `-l app=<app>` | Show / filter by labels | Selector mismatch hunting |
| `oc get <res> -o yaml` / `-o json` | Full object | Compare spec vs status; back up before a change |
| `oc get pods -o name` | `pod/<name>` only | Feed into loops |
| `oc get pods -o jsonpath='{.items[*].metadata.name}'` | Extract specific fields | Scripts, "show only X" |
| `oc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'` | One line per item | Readable custom reports |
| `oc get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP` | Your own columns | Cleaner than awk on default columns (see the OCP-023 lesson) |
| `oc get pods --sort-by=.metadata.creationTimestamp` | Sort by any field | Newest pods last |
| `oc get pods -w` | Watch for changes | Rollouts, scaling, self-healing demos |
| `oc get pods -A` | All namespaces | Cluster-wide view (needs permission) |
| `oc describe <res> <name>` | Human-readable detail plus **Events** | The second step of almost every triage |
| `oc get events --sort-by=.lastTimestamp` | Project events in time order | What happened, and when |
| `oc get events --field-selector type=Warning` | Warnings only | Noise-free triage |
| `oc get <res> <name> -o yaml > backup.yaml` | Save the current state | **Always before changing something** |

## 4. Pods: run, inspect, debug

| Command | Purpose | When / notes |
|---|---|---|
| `oc run <pod> --image=<img> --restart=Never -it -- /bin/bash` | Throwaway interactive pod | Quick tests from inside the cluster |
| `oc run tmp --image=<img> --rm -it --restart=Never -- curl -s http://<svc>:8080` | One-shot test, auto-deleted | Test a Service from inside the cluster |
| `oc logs <pod>` / `-f` / `--tail=50` | Container logs | App errors |
| `oc logs <pod> --previous` | Logs of the **crashed** container | **CrashLoopBackOff**: why did it die? |
| `oc logs <pod> -c <container>` | One container of a multi-container pod | Sidecar issues (S21) |
| `oc logs deploy/<app>` | Logs from one pod of a deployment | No need to look up a pod name |
| `oc logs -l app=<app> --prefix` | Logs from all matching pods | Which replica is failing? |
| `oc rsh <pod>` | Shell in a running container | Inspect files and processes |
| `oc exec <pod> -- <cmd>` | Run one command, no shell | `id`, `cat /etc/os-release`, `env` |
| `oc exec <pod> -- env \| sort` | Environment the container actually got | ConfigMap/Secret injection checks |
| `oc debug deploy/<app>` | **Copy** of the pod with a shell instead of the entrypoint | Container crashes too fast to rsh (S19) |
| `oc debug deploy/<app> --as-root` | Same, as root (if your SCC allows) | Permission experiments |
| `oc debug deploy/<app> -- <cmd>` | Run a command in the debug copy | e.g. `ls -ln /var/www` |
| `oc get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState}'` | Exit code and reason of the last crash | 137 = OOMKilled / SIGKILL, 1 = app error |
| `oc get pod <pod> -o yaml \| grep -i scc` | Which SCC admitted the pod | `openshift.io/scc` annotation |
| `oc delete pod <pod>` | Delete (the controller recreates it) | Self-healing proof, force a restart |
| `oc delete pod <pod> --grace-period=0 --force` | Force-remove a stuck pod | Stuck Terminating. Last resort; understand why first |

## 5. Moving data in and out

| Command | Purpose | When / notes |
|---|---|---|
| `oc cp <pod>:/path ./local` | Copy a file or directory out | Needs `tar` in the image |
| `oc cp ./file <pod>:/path` | Copy in | Test fixtures, configs |
| `oc rsync <pod>:/dir ./local` | Sync a directory | Large trees, repeated copies |
| `oc exec <pod> -- cat /file > local` | Stream out without tar | Minimal images |
| `oc exec -i <pod> -- sh -c 'cat > /tmp/f' < local` | Stream in | Minimal images |
| `oc exec <db-pod> -- mysqldump ... > backup.sql` | Logical DB backup | Backup and restore drill (OCP-013) |
| `oc port-forward pod/<pod> 8080:8080` | Local port → pod | Test an app with no Route |
| `oc port-forward svc/<svc> 8080:8080` | Local port → Service | |

## 6. Images, registries and ImageStreams

| Command | Purpose | When / notes |
|---|---|---|
| `skopeo inspect docker://<registry>/<img>:<tag>` | Image metadata without pulling (user, ports, labels, digest) | Will it run as root? Which port? |
| `skopeo list-tags docker://<registry>/<img>` | Available tags | ImagePullBackOff → does that tag exist? (S10) |
| `skopeo copy docker://src docker://dst` | Registry-to-registry copy | Mirroring (OCP-009) |
| `oc image info <img>` | Metadata via oc | Same purpose as skopeo inspect |
| `oc image mirror <src> <dst>` | Mirror images | Disconnected/internal registry |
| `oc import-image <is>:<tag> --from=<img> --confirm` | Create/update an ImageStream tag | Metadata only, no layers copied |
| `oc import-image <is>:<tag> --from=<img> --confirm --scheduled` | Re-import periodically | Track upstream tag moves |
| `oc tag <src> <is>:<tag>` | Point an ImageStream tag at an image or another tag | Promotion: `oc tag app:dev app:prod` |
| `oc get is,istag` | ImageStreams and their tags | |
| `oc describe is <is>` | Tag history, digests, import errors | ImportError (S77) |
| `oc set image-lookup <is>` | Let Deployments use the ImageStream short name | `lookupPolicy.local=true` |
| `oc registry info` / `oc registry login` | Internal registry host / podman login helper | Pushing to the internal registry |
| `oc create secret docker-registry <s> --docker-server=... --docker-username=... --docker-password=...` | Pull secret | Private registry (S11) |
| `oc secrets link default <s> --for=pull` | Make the SA use the pull secret | "unauthorized" on pull |

## 7. Builds

| Command | Purpose | When / notes |
|---|---|---|
| `oc new-build --name=<app> --binary --strategy=docker` | BuildConfig for a local Dockerfile | Build in the cluster without git (OCP-007) |
| `oc start-build <app> --from-dir=. --follow` | Upload the context and build | |
| `oc new-app <git-url> --name=<app>` | S2I or Docker build from git + deployment | Source-to-image |
| `oc get bc,build` | BuildConfigs and builds | |
| `oc logs build/<app>-1` / `oc logs -f bc/<app>` | Build logs | Build failures |
| `oc cancel-build <build>` | Stop a build | |

## 8. Deployments and workloads

| Command | Purpose | When / notes |
|---|---|---|
| `oc create deployment <app> --image=<img> --replicas=2` | Plain Kubernetes Deployment (tag as typed, no Service) | |
| `oc new-app --name=<app> --image=<img>` | Deployment + Service (+ ImageStream) | Quick app with defaults |
| `oc new-app --template=<tpl> -p KEY=val` | Instantiate a template | mysql-persistent etc. (OCP-012) |
| `oc process <tpl> -p KEY=val \| oc apply -f -` | Render a template, review, then apply | See exactly what will be created |
| `oc create deployment <app> --image=<img> --dry-run=client -o yaml > app.yaml` | Generate YAML without creating anything | Starting point for manifests |
| `oc apply -f <file>.yaml` | Declarative create/update | GitOps-style, repeatable |
| `oc diff -f <file>.yaml` | What would change | Before applying |
| `oc scale deploy/<app> --replicas=3` | Change the replica count | |
| `oc create job <j> --image=<img> -- <cmd>` | Run-to-completion Job | |
| `oc create cronjob <cj> --image=<img> --schedule='*/5 * * * *' -- <cmd>` | Scheduled Job | Schedule is **UTC** by default (S38) |
| `oc create job <j> --from=cronjob/<cj>` | Trigger a CronJob now | Test without waiting |
| `oc get deploy,rs,sts,ds,job,cronjob` | All workload controllers | |
| `oc label <res> <name> key=val [--overwrite]` | Add/change labels | Fix selectors (carefully) |

## 9. Rollouts and updates

| Command | Purpose | When / notes |
|---|---|---|
| `oc set image deploy/<app> <container>=<img>:<tag>` | Change the image → new rollout | |
| `oc rollout status deploy/<app>` | Wait for and report the rollout | Stuck release (S68) |
| `oc rollout history deploy/<app> [--revision=N]` | Past revisions | Before rolling back |
| `oc annotate deploy/<app> kubernetes.io/change-cause="<reason>" --overwrite` | Record why | Useful history (S76) |
| `oc rollout undo deploy/<app> [--to-revision=N]` | Roll back the pod template | Doesn't revert ConfigMaps/Secrets (S69) |
| `oc rollout pause` / `resume deploy/<app>` | Batch several changes into one rollout | "Nothing redeployed" → paused? (S74) |
| `oc rollout restart deploy/<app>` | Restart all pods with the same spec | After a ConfigMap env change (S43) |
| `oc patch deploy/<app> -p '{"spec":{"strategy":{"type":"Recreate"}}}'` | Switch to the Recreate strategy | RWO volumes (S75) |
| `oc set triggers deploy/<app> --from-image=<is>:<tag> -c <container>` | Auto-redeploy when an ImageStream tag moves | (S72) |
| `oc set triggers deploy/<app>` | Show the current triggers | |
| `oc get deploy <app> -o jsonpath='{.spec.template.spec.containers[*].image}'` | Image actually configured | Tag vs digest check |
| `oc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}'` | Digest each pod really runs | "Some replicas have the fix" (S71) |

## 10. Services, Routes, Ingress, networking

| Command | Purpose | When / notes |
|---|---|---|
| `oc expose deploy/<app> --port=8080 [--target-port=8080]` | Create a Service | |
| `oc expose svc/<app> [--hostname=<host>]` | Create an HTTP Route | |
| `oc create route edge <r> --service=<svc> [--insecure-policy=Redirect]` | TLS terminated at the router | HTTP→HTTPS redirect (S33) |
| `oc create route passthrough <r> --service=<svc>` | TLS straight to the pod | App must serve TLS (S34) |
| `oc create route reencrypt <r> --service=<svc> --dest-ca-cert=<ca>` | TLS at the router and again to the pod | (S35) |
| `oc create ingress <i> --rule="<host>/*=<svc>:8080"` | Kubernetes Ingress → OpenShift generates a Route | (OCP-016) |
| `oc set route-backends <r> v1=80 v2=20` | Weighted traffic split | Canary (OCP-018) |
| `oc patch route <r> -p '{"spec":{"to":{"name":"<svc>"}}}'` | Point a Route at another Service | Blue-green switch (OCP-017) |
| `oc get svc,endpoints,route` | The whole traffic chain | **Route 503 → endpoints `<none>`?** (S27) |
| `oc get endpointslices -l kubernetes.io/service-name=<svc>` | Modern endpoints view | |
| `oc describe svc <svc>` | Selector, ports, endpoints | Selector vs pod labels |
| `oc get route <r> -o jsonpath='{.spec.host}'` | Route host | Feed into curl |
| `curl -s -o /dev/null -w '%{http_code}\n' http://<host>/` | Status code only | Outside-in check (RCA-003) |
| `oc exec <pod> -- curl -s http://<svc>.<ns>.svc.cluster.local:8080` | Service-to-service test inside the cluster | DNS and cross-namespace (S32) |
| `oc get networkpolicy` / `oc describe networkpolicy <np>` | Traffic rules in the project | "Frontend can't reach backend" (S40) |

## 11. ConfigMaps and Secrets

| Command | Purpose | When / notes |
|---|---|---|
| `oc create configmap <cm> --from-literal=K=v --from-file=app.conf` | Create a ConfigMap | |
| `oc create secret generic <s> --from-literal=password=<p>` | Create a Secret (base64-encoded, **not** encrypted) | Don't type real passwords in shell history |
| `oc create secret generic <s> --from-literal=PASS="$(openssl rand -base64 12)"` | Random password, never printed | (OCP-011) |
| `oc set env deploy/<app> --from=configmap/<cm>` | All keys → env vars | Env vars need a pod restart to change |
| `oc set env deploy/<app> --from=secret/<s> --prefix=DB_` | Secret keys → prefixed env vars | |
| `oc set env deploy/<app> --list` | Show configured env | Without exec-ing into a pod |
| `oc set env deploy/<app> KEY-` | Remove an env var | Trailing `-` = unset |
| `oc set volumes deploy/<app> --add --type=configmap --configmap-name=<cm> --mount-path=/etc/app` | Mount as files (they update live) | |
| `oc extract secret/<s> --to=-` | Decode and print a Secret | Verify the value (S44); careful where you run it |
| `oc get cm <cm> -o yaml` | ConfigMap contents | |

## 12. Storage

| Command | Purpose | When / notes |
|---|---|---|
| `oc get sc` | StorageClasses; `(default)` marks the default | PVC Pending → is there a default? (S46) |
| `oc get pvc` / `oc describe pvc <pvc>` | Claim status and events | Pending reasons |
| `oc get pv` 🔴 | PersistentVolumes (cluster-scoped) | Static binding (OCP-019) |
| `oc set volumes deploy/<app> --add --name=data --type=pvc --claim-name=<pvc> --claim-size=1Gi --claim-mode=rwo --mount-path=/var/lib/mysql` | Create a PVC and mount it in one step | Fix data loss (RCA-002) |
| `oc set volumes deploy/<app>` | List volumes and mounts | |
| `oc set volumes deploy/<app> --remove --name=<vol>` | Remove a volume | |
| `oc exec <pod> -- df -h /data` | Size seen inside the pod | NFS doesn't enforce capacity (OCP-019) |
| `oc get pvc -l app=<sts>` | StatefulSet per-replica claims | They survive StatefulSet deletion (S54) |
| `oc patch pvc <pvc> -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'` | Expand a claim | Only if the SC has `allowVolumeExpansion` (S53) |

## 13. Probes, resources, autoscaling

| Command | Purpose | When / notes |
|---|---|---|
| `oc set probe deploy/<app> --readiness --get-url=http://:8080/health --initial-delay-seconds=5` | Readiness: out of endpoints on failure | Zero-downtime updates |
| `oc set probe deploy/<app> --liveness --open-tcp=8080` | Liveness: restart on failure | Check the process only, never a dependency (S57) |
| `oc set probe deploy/<app> --startup --get-url=http://:8080/ --failure-threshold=30` | Protect slow starters | Java apps killed at boot (S56) |
| `oc set probe deploy/<app> --remove --liveness` | Remove a probe | |
| `oc set resources deploy/<app> --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi` | Requests (scheduling) and limits (ceiling) | OOMKilled / Pending / HPA |
| `oc adm top pods` / `oc adm top pods --containers` | Live CPU and memory use | Right-size requests and limits |
| `oc autoscale deploy/<app> --min=2 --max=5 --cpu-percent=60` | Create an HPA | Requests must be set (S61) |
| `oc get hpa -w` / `oc describe hpa <app>` | Targets, replicas, scaling events | `<unknown>` = no requests / no metrics |

## 14. Quotas and limits

| Command | Purpose | When / notes |
|---|---|---|
| `oc get quota` / `oc describe quota` | Used vs hard limits in the project | "exceeded quota" (S64) |
| `oc get limitrange` / `oc describe limitrange` | Defaults and max per container | "Limits we never set" (S65) |
| `oc create quota <q> --hard=pods=10,requests.cpu=2` 🔴 | Create a quota (project admin or cluster admin) | |

## 15. Security: SCC, ServiceAccounts, RBAC

| Command | Purpose | When / notes |
|---|---|---|
| `oc get scc` 🔴 | List SCCs | |
| `oc adm policy who-can use scc anyuid` | Who may use an SCC | Audit (S24) |
| `oc create sa <sa>` | Dedicated ServiceAccount | Never grant extra rights to `default` |
| `oc adm policy add-scc-to-user anyuid -z <sa>` 🔴 | Grant an SCC to an SA | Only when the image truly needs it; fix the image first |
| `oc set serviceaccount deploy/<app> <sa>` | Run the deployment as that SA | |
| `oc auth can-i <verb> <res> [-n <ns>]` | Am I allowed? | "Forbidden" triage (S08) |
| `oc auth can-i --list` | Everything I'm allowed to do here | |
| `oc get rolebinding` / `oc describe rolebinding <rb>` | Who has which role in the project | |
| `oc adm policy add-role-to-user edit <user> -n <ns>` | Grant project access | Project admin can do this |

## 16. Cluster and nodes 🔴

| Command | Purpose | When / notes |
|---|---|---|
| `oc get clusterversion` | Version and upgrade status | |
| `oc get co` | Cluster operators: Available / Progressing / Degraded | **First check when "the cluster is broken"** (S01) |
| `oc describe co <name>` | Why an operator is degraded | |
| `oc get nodes -o wide` / `oc describe node <node>` | Status, conditions, allocated resources | NotReady, pressure (S02, S04) |
| `oc adm top nodes` | Node CPU and memory use | Capacity view |
| `oc get csr` / `oc adm certificate approve <csr>` | Pending node certificates | NotReady after a long downtime (S03) |
| `oc adm node-logs <node> -u kubelet` (or `-u crio`) | Node service logs without SSH | |
| `oc debug node/<node>` then `chroot /host` | Shell on an RHCOS node | `crictl ps`, `journalctl` (S05) |
| `oc adm cordon` / `uncordon <node>` | Stop/allow scheduling | Maintenance |
| `oc adm drain <node> --ignore-daemonsets --delete-emptydir-data` | Evict pods for maintenance | Stuck → PDB (S67) |
| `oc get mcp` | MachineConfigPool rollout state | Nodes updating after a config change |
| `oc adm must-gather` | Support data bundle | Red Hat case |

## 17. Troubleshooting one-liners

| Command | Purpose |
|---|---|
| `oc get pods --no-headers \| awk '{split($2,a,"/")} $3=="Completed"{next} a[1]!=a[2] \|\| $3!="Running"'` | Pods that are not healthy |
| `oc get deploy,sts --no-headers -o custom-columns=N:.metadata.name,R:.status.readyReplicas,D:.spec.replicas \| awk '$2!=$3'` | Workloads short of ready replicas |
| `oc get endpoints --no-headers \| awk '$2=="<none>"'` | Services with no backends |
| `oc get pvc --no-headers \| awk '$2!="Bound"'` | Claims not bound |
| `oc get rs --no-headers \| awk '$2!=$4'` | ReplicaSets that can't reach their desired count |
| `oc get events --field-selector type=Warning --sort-by=.lastTimestamp \| tail -20` | Recent warnings |
| `oc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' \| sort -k2 -n` | Restart leaderboard |
| `for r in $(oc get route -o jsonpath='{.items[*].spec.host}'); do echo "$r $(curl -s -o /dev/null -m5 -w '%{http_code}' http://$r/)"; done` | HTTP status of every Route |

**The triage order that answers most scenarios:**
`oc get` → `oc describe` (events) → `oc logs [--previous]` → `oc get endpoints` / `oc get pvc` → `oc debug`.
