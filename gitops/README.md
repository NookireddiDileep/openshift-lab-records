# GitOps labs: OpenShift GitOps (Argo CD)

Hands-on GitOps on OpenShift, from first install to multi-cluster delivery. Each lab is a beginner-friendly, step-by-step guide with commands, expected output, troubleshooting and a self-check.

```
GitHub Actions (CI) → image registry → Git tag bump → Argo CD → dev / prod clusters
```

## Labs

| # | Lab | Status |
|---|---|---|
| 1 | [Argo CD basics: install, sync, self-heal, prune, rollback](labs/lab01-argocd-basics.md) | Guide ready |
| 2 | Kustomize base and overlays (dev / prod) | Planned |
| 3 | Helm chart for the same app | Planned |
| 4 | App-of-apps, sync waves, cluster config in Git | Planned |
| 5 | GitHub Actions CI: build, push, bump tag | Planned |
| 6 | Secrets: Sealed Secrets / External Secrets | Planned |
| 7 | Multi-cluster with ApplicationSets | Planned |
| 8 | Intro to Red Hat ACM and ACS | Planned |

## Layout

```
gitops/
  bootstrap/   operator install (OpenShift GitOps)
  apps/        app manifests Argo CD deploys (one folder per lab)
  argocd/      Argo CD Application / AppProject / ApplicationSet objects
  labs/        step-by-step lab guides
```
