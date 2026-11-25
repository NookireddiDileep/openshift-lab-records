# Lab 1 — Argo CD basics on OpenShift (OpenShift GitOps)

**Level:** Beginner · **Time:** about 2–3 hours · **Series:** GitOps labs, 1 of 8

## What you will learn

By the end of this lab you will have:

1. Installed the **Red Hat OpenShift GitOps** operator. It gives you Argo CD on OpenShift.
2. Logged in to the Argo CD web console.
3. Stored a small web app's YAML in Git.
4. Told Argo CD to deploy it, and watched it work.
5. Seen the three core GitOps behaviours yourself:
   - **Sync:** a change in Git is applied to the cluster.
   - **Self-heal:** a manual change made directly on the cluster is undone.
   - **Prune:** a file removed from Git is removed from the cluster.

## The idea in one paragraph

Normally you run `oc apply -f file.yaml` to change a cluster. With GitOps, **Git is the only place you make changes.** Argo CD runs inside the cluster and keeps comparing two things: what Git says should exist (the *desired state*) and what actually exists (the *live state*). If they differ, the app shows **OutOfSync**. Argo CD can then fix it, either when you click Sync or automatically.

```
  You ──git push──▶  GitHub repo  ◀──watches──  Argo CD (in cluster) ──applies──▶  your namespace
```

---

## Before you start (prerequisites)

| You need | How to check |
| --- | --- |
| An OpenShift 4.x cluster where you have **cluster-admin** (needed to install an operator) | `oc auth can-i '*' '*' --all-namespaces` should print `yes` |
| The `oc` CLI, logged in | `oc whoami` prints your username |
| `git` installed | `git --version` |
| A GitHub account and this repo cloned on your machine | `git remote -v` inside the repo shows the GitHub URL |
| A web browser | — |

> **Shared cluster?** Installing an operator affects everyone on the cluster. Get the cluster owner's OK first. If someone has already installed OpenShift GitOps, skip to Step 3.

---

## Step 1 — Check whether OpenShift GitOps is already installed

```bash
oc get csv -A | grep -i gitops
```

- **No output:** it isn't installed. Go to Step 2.
- **A line ending in `Succeeded`:** it's already installed. Skip to Step 3.

> **What is a CSV?** A *ClusterServiceVersion* is how OpenShift records an installed operator and its version. `Succeeded` means it's installed and healthy.

---

## Step 2 — Install the OpenShift GitOps operator

You can do this in the web console or with YAML. **Use the YAML method.** It's repeatable, and it's GitOps-friendly.

The file `gitops/bootstrap/openshift-gitops-operator.yaml` in this repo contains three objects:

| Object | What it does |
| --- | --- |
| `Namespace openshift-gitops-operator` | A home for the operator itself |
| `OperatorGroup` | Tells the Operator Lifecycle Manager (OLM) the operator may watch all namespaces |
| `Subscription` | "Please install `openshift-gitops-operator` from the `redhat-operators` catalog, channel `latest`, and keep it updated" |

Apply it:

```bash
oc apply -f gitops/bootstrap/openshift-gitops-operator.yaml
```

Expected output:

```
namespace/openshift-gitops-operator created
operatorgroup.operators.coreos.com/openshift-gitops-operator created
subscription.operators.coreos.com/openshift-gitops-operator created
```

Wait 2–5 minutes, then check the install:

```bash
oc get csv -n openshift-gitops-operator
```

Repeat until `PHASE` shows `Succeeded`. The version number will differ from this example:

```
NAME                                DISPLAY                    VERSION   PHASE
openshift-gitops-operator.v1.x.y    Red Hat OpenShift GitOps   1.x.y     Succeeded
```

The operator also creates a **default Argo CD instance** in a namespace called `openshift-gitops`. Check that its pods are running:

```bash
oc get pods -n openshift-gitops
```

You should see pods like these, all `Running`:

```
openshift-gitops-application-controller-0
openshift-gitops-applicationset-controller-...
openshift-gitops-dex-server-...
openshift-gitops-redis-...
openshift-gitops-repo-server-...
openshift-gitops-server-...
```

| Pod | Job |
| --- | --- |
| `application-controller` | Compares Git with the cluster and applies changes. This is the brain. |
| `repo-server` | Clones Git and renders the YAML (plain YAML, Kustomize or Helm) |
| `server` | The web UI and API |
| `redis` | Cache |
| `dex-server` | Lets you log in with your OpenShift account |
| `applicationset-controller` | Generates many apps from one template (used in Lab 7) |

**Troubleshooting:** if the CSV stays `Installing` or `Pending`, run `oc get installplan -n openshift-gitops-operator` and `oc get events -n openshift-gitops-operator --sort-by=.lastTimestamp`.

---

## Step 3 — Open the Argo CD web console

Find the URL:

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}{"\n"}'
```

Open `https://<that-host>` in your browser. There are two ways to log in.

**Option A: log in with OpenShift (recommended)**

Click **LOG IN VIA OPENSHIFT** and use your normal cluster login.

> If you log in but see no permissions or can't create apps, your user isn't in the group that the default instance treats as admin, `cluster-admins`. You can add yourself (cluster-admin only):
> ```bash
> oc adm groups new cluster-admins 2>/dev/null; oc adm groups add-users cluster-admins $(oc whoami)
> ```
> Then log out of Argo CD and log in again.

**Option B: the built-in `admin` user**

```bash
oc extract secret/openshift-gitops-cluster -n openshift-gitops --keys=admin.password --to=-
```

Log in with username `admin` and the printed password.

You should now see the Argo CD dashboard with no applications yet.

---

## Step 4 (optional) — Install the `argocd` CLI

You can do this whole lab in the UI and with `oc`. The CLI is handy, and interviewers expect you to know it.

1. In the OpenShift web console, click **?** (top right) → **Command line tools**. Download `argocd` for your OS if it's listed. If not, use the official Argo CD GitHub releases page.
2. Put it on your PATH, then check it:
   ```bash
   argocd version --client
   ```
3. Log in:
   ```bash
   ARGO_HOST=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
   argocd login $ARGO_HOST --sso --grpc-web
   # or: argocd login $ARGO_HOST --username admin --password '<password>' --grpc-web
   ```
   Add `--insecure` if the lab cluster uses a self-signed certificate.

---

## Step 5 — Look at the app files in Git

The app you'll deploy is in `gitops/apps/lab1-sample-app/`:

| File | What it creates |
| --- | --- |
| `configmap.yaml` | A web page (`index.html`) with the text "version 1" |
| `deployment.yaml` | 1 pod running Red Hat's UBI Apache image, serving that page on port 8080 |
| `service.yaml` | A stable internal address for the pod |
| `route.yaml` | A public URL so you can open it in a browser |

There's no `namespace:` field in these files. Argo CD supplies the namespace (the *destination*) when it deploys them.

Make sure these files are pushed to GitHub, because **Argo CD reads from GitHub, not from your laptop**:

```bash
git status                 # nothing pending?
git log --oneline -1       # your latest commit
git push                   # if not yet pushed
```

Check on github.com that `gitops/apps/lab1-sample-app/` is visible in the repo.

---

## Step 6 — Create the target namespace and let Argo CD manage it

```bash
oc new-project gitops-lab1
oc label namespace gitops-lab1 argocd.argoproj.io/managed-by=openshift-gitops
```

> **Why the label?** For safety, the default Argo CD instance on OpenShift can't deploy into just any namespace. The label `argocd.argoproj.io/managed-by=openshift-gitops` tells the operator to give that Argo CD instance permission in this namespace. **Forgetting this label is the #1 beginner error.** It shows up as a sync failure saying something like *"... is forbidden: User system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller cannot create resource ..."*.

Check it:

```bash
oc get namespace gitops-lab1 --show-labels
```

---

## Step 7 — Create the Argo CD Application

An **Application** is Argo CD's main object. It says: *take this path, in this Git repo, at this branch, and deploy it to this cluster and namespace.*

Open `gitops/argocd/lab1-application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app-lab1
  namespace: openshift-gitops          # Applications live in Argo CD's own namespace
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/NookireddiDileep/openshift-lab-records.git
    targetRevision: main               # branch to follow
    path: gitops/apps/lab1-sample-app  # folder to deploy
  destination:
    server: https://kubernetes.default.svc   # "this same cluster"
    namespace: gitops-lab1
```

There's no `syncPolicy` yet. That's on purpose: you'll sync by hand first, so you can see what OutOfSync looks like.

> If your default branch is `master` rather than `main`, change `targetRevision` before applying.

Apply it:

```bash
oc apply -f gitops/argocd/lab1-application.yaml
```

Check it:

```bash
oc get applications -n openshift-gitops
```

```
NAME              SYNC STATUS   HEALTH STATUS
sample-app-lab1   OutOfSync     Missing
```

**What this means:** Argo CD has read Git. It knows 4 objects *should* exist, and none of them do yet. In the UI, the app tile is yellow (OutOfSync). Click it to see the 4 objects in a tree.

---

## Step 8 — Sync (deploy) by hand

Use any one of these three:

- **UI:** open the app → **SYNC** → **SYNCHRONIZE**
- **CLI:** `argocd app sync sample-app-lab1`
- **oc only:**
  ```bash
  oc patch application sample-app-lab1 -n openshift-gitops --type merge \
    -p '{"operation":{"initiatedBy":{"username":"'$(oc whoami)'"},"sync":{"syncStrategy":{"hook":{}}}}}'
  ```

After about 30–60 seconds:

```bash
oc get applications -n openshift-gitops
```

```
NAME              SYNC STATUS   HEALTH STATUS
sample-app-lab1   Synced        Healthy
```

Check the app itself:

```bash
oc get all -n gitops-lab1
curl -s http://$(oc get route sample-app -n gitops-lab1 -o jsonpath='{.spec.host}')
```

You should see your HTML with **"GitOps Lab 1 - version 1"**. You've just done your first GitOps deployment.

> **Synced vs Healthy:** these are two different things. *Synced* means the live state matches Git. *Healthy* means the objects are actually working (pods are running, for example). An app can be Synced but Degraded if Git contains a broken image.

---

## Step 9 — Change Git and watch Argo CD notice

On your machine, edit `gitops/apps/lab1-sample-app/deployment.yaml`. Change `replicas: 1` to `replicas: 2`. Then:

```bash
git add gitops/apps/lab1-sample-app/deployment.yaml
git commit -m "lab1: scale sample-app to 2 replicas"
git push
```

Argo CD checks Git about **every 3 minutes**. To skip the wait, click **REFRESH** in the UI, or run `argocd app get sample-app-lab1 --refresh`.

The app turns **OutOfSync**. In the UI, click **APP DIFF** to see exactly what differs: `replicas: 1 → 2`.

Sync again, the same way as in Step 8. Then check:

```bash
oc get pods -n gitops-lab1
```

There are now 2 pods. **You changed the cluster without touching the cluster. Git did it.**

---

## Step 10 — Turn on automatic sync, self-heal and prune

Now let Argo CD do the syncing itself. Add this under `spec:` in `gitops/argocd/lab1-application.yaml`:

```yaml
  syncPolicy:
    automated:
      prune: true      # delete things that were removed from Git
      selfHeal: true   # undo manual changes made on the cluster
```

Apply it:

```bash
oc apply -f gitops/argocd/lab1-application.yaml
```

Also commit and push the file, so Git keeps matching what you applied:

```bash
git add gitops/argocd/lab1-application.yaml
git commit -m "lab1: enable automated sync with prune and self-heal"
git push
```

| Setting | Without it | With it |
| --- | --- | --- |
| `automated` | You must click Sync | Git changes are applied automatically |
| `selfHeal` | Manual `oc` changes stay until the next sync | Manual changes are reverted within seconds |
| `prune` | Objects removed from Git stay on the cluster as orphans | Objects removed from Git are deleted from the cluster |

---

## Step 11 — Test self-heal (drift correction)

Pretend someone "fixes" production by hand:

```bash
oc scale deployment sample-app -n gitops-lab1 --replicas=5
oc get pods -n gitops-lab1 -w
```

You'll see pods start, and then, within a few seconds, get terminated back down to **2**. Press `Ctrl+C` to stop watching.

To see what happened in the UI, open the app → **HISTORY AND ROLLBACK**, or look at the app's events:

```bash
oc describe application sample-app-lab1 -n openshift-gitops | tail -20
```

> Compare this with the manual drift demo in [OCP-003](../../stories/OCP-003-scale-deployment.md). There, nothing corrected the drift until someone re-applied the YAML. Here, Argo CD corrects it on its own.

> **Interview point:** "With self-heal on, `oc edit` in production is pointless. Argo CD reverts it. Every change has to go through Git, which gives us review, audit and easy rollback."

---

## Step 12 — Test a content change and prune

**Content change.** Edit `configmap.yaml` and change `version 1` to `version 2`. Commit and push. Within about 3 minutes (or straight away after a Refresh), Argo CD updates the ConfigMap. After another minute or so, the mounted file inside the pod updates too. Check it:

```bash
curl -s http://$(oc get route sample-app -n gitops-lab1 -o jsonpath='{.spec.host}')
```

**Prune.** Delete the Route from Git:

```bash
git rm gitops/apps/lab1-sample-app/route.yaml
git commit -m "lab1: remove route to test prune"
git push
```

After a refresh or sync, check:

```bash
oc get route -n gitops-lab1
```

You get `No resources found`. Prune deleted it. Now put it back, to prove Git is the source of truth:

```bash
git revert --no-edit HEAD
git push
```

The Route comes back. **Rollback in GitOps is just `git revert`.**

---

## Step 13 — Clean up

```bash
oc delete application sample-app-lab1 -n openshift-gitops
oc delete project gitops-lab1
```

Because the Application has the `resources-finalizer.argocd.argoproj.io` finalizer, deleting it also deletes everything it deployed. Without the finalizer, the app's objects would be left behind.

**Leave the operator installed.** Labs 2–8 use it.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Sync fails with `... is forbidden: User "system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller" cannot ...` | The namespace is missing the managed-by label | `oc label namespace gitops-lab1 argocd.argoproj.io/managed-by=openshift-gitops`, then sync again |
| App shows `Unknown` with `repository not found` or an auth error | Wrong `repoURL`, or the repo is private | Check the URL. For a private repo, add credentials under **Settings → Repositories** |
| `app path does not exist` | Wrong `path` or branch, or the files aren't pushed | Check the folder on github.com, at the branch in `targetRevision` |
| Git change not picked up | Argo CD only polls every ~3 minutes | Click **REFRESH**, or run `argocd app get <app> --refresh` |
| Synced but `Degraded` | The app itself is broken (image pull, crash) | `oc get pods -n gitops-lab1`, then `oc describe pod ...` and `oc logs ...` |
| Can log in to the UI but can't create or sync apps | Your user doesn't have the admin role in this Argo CD instance | Add yourself to the `cluster-admins` group (Step 3), or use the `admin` user |
| CSV stuck at `Installing` | Catalog or install-plan problem | `oc get installplan,subscription -n openshift-gitops-operator`, and check events |

---

## Check yourself

Answer these without looking:

1. What's the difference between *Synced* and *Healthy*?
2. Why did `oc scale --replicas=5` not stick?
3. What would happen in Step 12 if `prune` were `false`?
4. What does the `argocd.argoproj.io/managed-by` label do?
5. How do you roll back a bad change in GitOps?

---

## Lab record (fill in after you finish)

Copy this into `gitops/labs/records/lab01-record.md`:

```markdown
# Lab 1 record — Argo CD basics

- Date:
- Cluster / OpenShift version:   (oc version)
- OpenShift GitOps version:      (oc get csv -n openshift-gitops-operator)

## What I did
## What broke and how I fixed it (problem → investigation → root cause → fix → prevention)
## Screenshots / command output
## What I would do differently in production
```

**Next:** Lab 2 — Kustomize base and overlays (dev and prod from one set of files).
