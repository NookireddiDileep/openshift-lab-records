# OCP-009: Copy container images into my registry (OpenShift internal registry)

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Registries · Image mirroring · ImageStreams |
| **Priority** | Medium |
| **Date** | 2026-11-13 |
| **Time spent** | ~45 min (incl. RCA) |
| **Status** | Done |
| **Related** | [RCA-001 – rootless podman pull fails](../rca/RCA-001-rootless-podman-subuid.md) · [OCP-007](OCP-007-own-image-openshift-build.md) |

## 1. User story / requirement
> As a **platform engineer**, I want to **copy container images from external registries into my project's registry**, so that **my applications don't depend on external registries being reachable, fast or unchanged** (rate limits, outages, deleted tags).

## 2. Acceptance criteria
- [x] At least one external image **fully copied** (all layers) into my project in the internal registry
- [x] Copied image resolves to the **internal** registry address
- [x] An application deployed **from the copy**
- [x] *(extra)* Compared copy methods, including one that does *not* copy
- [x] *(extra)* Root-caused the failed method → [RCA-001](../rca/RCA-001-rootless-podman-subuid.md)

## 3. Background / concepts
**"My registry"** = my project's namespace in OpenShift's internal registry, reached from outside the cluster through the `default-route` of `openshift-image-registry` and from inside at `image-registry.openshift-image-registry.svc:5000/<project>/<image>`. Pushing an image creates/updates an **ImageStream** in the project.

| Method | Copies layers? | Unpacks locally? | Result |
|---|---|---|---|
| `oc image mirror` | ✅ | no – registry → registry | ✅ worked |
| `skopeo copy` | ✅ | no – registry → registry | ✅ worked |
| `podman pull` → `tag` → `push` | ✅ | **yes** – unpacks into local storage | ❌ failed → RCA-001 |
| `oc import-image` | ❌ metadata only (default) | no | ✅ but points to the external registry |

## 4. Plan
1. Find the registry's public route; log in with my OpenShift token.
2. Copy UBI 9 httpd with `oc image mirror`.
3. Copy nginx with podman (pull → tag → push).
4. Contrast with `oc import-image`.
5. Deploy an app from a copied image.
6. **Rollback:** `oc delete is ubi9-httpd nginx busybox` and `oc delete all -l app=app-05`.

## 5. Implementation
Script: [`scripts/OCP-009/copy-images.sh`](../scripts/OCP-009/copy-images.sh)
```bash
REG=$(oc registry info --public); NS=$(oc project -q)
oc registry login --skip-check

oc image mirror registry.access.redhat.com/ubi9/httpd-24:latest \
  $REG/$NS/ubi9-httpd:mirrored --insecure=true --keep-manifest-list=false

skopeo copy docker://docker.io/library/nginx:alpine docker://$REG/$NS/nginx:copied \
  --dest-tls-verify=false --override-os linux --override-arch amd64

oc import-image busybox:imported --from=docker.io/library/busybox:latest --confirm

oc new-app --image-stream=ubi9-httpd:mirrored --name=app-05
```

## 6. Validation / evidence
**Registry address and login:**
```
Registry: default-route-openshift-image-registry.apps.<cluster-domain>
Saved credentials for default-route-openshift-image-registry.apps.<cluster-domain> into /run/user/<uid>/containers/auth.json
```
**1) `oc image mirror` – full copy, registry to registry:**
```
<registry-route> my-apps/ubi9-httpd blobs=4 mounts=0 manifests=1 shared=0
uploading: .../my-apps/ubi9-httpd sha256:70fc3e5b… 76.78MiB
uploading: .../my-apps/ubi9-httpd sha256:f5fe264e… 16.66MiB
uploading: .../my-apps/ubi9-httpd sha256:0589973f… 8.634MiB
sha256:cab6ae73… <registry-route>/my-apps/ubi9-httpd:mirrored
info: Mirroring completed in 8.27s (12.94MB/s)

$ oc get istag ubi9-httpd:mirrored -o jsonpath='{.image.dockerImageReference}'
image-registry.openshift-image-registry.svc:5000/my-apps/ubi9-httpd@sha256:cab6ae73…   ← internal
```
**2) podman pull/tag/push – failed** (root cause in [RCA-001](../rca/RCA-001-rootless-podman-subuid.md)):
```
ERRO[0000] cannot find UID/GID for user <me>: no subuid ranges found for user "<me>" in /etc/subuid
Error: ... unpacking failed ... potentially insufficient UIDs or GIDs available in user namespace
(requested 0:42 for /etc/shadow) ... lchown /etc/shadow: invalid argument
```
**2b) `skopeo copy` – full copy, no unpacking:**
```
Copying blob sha256:69d81d55…
Copying blob sha256:da90db50…
Copying config sha256:7cac34a4…
Writing manifest to image destination

$ oc get istag nginx:copied -o jsonpath='{.image.dockerImageReference}'
image-registry.openshift-image-registry.svc:5000/my-apps/nginx@sha256:697b0b15…        ← internal
```
**3) `oc import-image` – metadata only:**
```
imagestream.image.openshift.io/busybox imported
$ oc get istag busybox:imported -o jsonpath='{.image.dockerImageReference}'
docker.io/library/busybox@sha256:f97baa53…                                              ← still external
```
**4) App deployed from the copy:**
```
--> Found image fb7f668 in image stream "my-apps/ubi9-httpd" under tag "mirrored"
deployment "app-05" successfully rolled out
$ oc get deploy app-05 -o jsonpath='{.spec.template.spec.containers[0].image}'
image-registry.openshift-image-registry.svc:5000/my-apps/ubi9-httpd@sha256:cab6ae73…
$ oc exec deploy/app-05 -- curl -s -o /dev/null -w 'HTTP %{http_code}\n' localhost:8080
HTTP 403                                                                                ← httpd up, no index page
```
**My registry now:**
```
NAME         TAGS       SOURCE OF LAYERS
app-04       latest     built in OpenShift (OCP-007)
ubi9-httpd   mirrored   copied – oc image mirror
nginx        copied     copied – skopeo
busybox      imported   NOT copied – points to docker.io
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | **podman pull failed** with `lchown /etc/shadow: invalid argument` | Rootless podman without `/etc/subuid`/`/etc/subgid` ranges → single UID/GID mapping → can't unpack files owned by other IDs. Full RCA: [RCA-001](../rca/RCA-001-rootless-podman-subuid.md) |
| 2 | `oc image mirror` and `skopeo copy` succeeded on the same terminal | They copy **blobs registry-to-registry** and never unpack them – no UID mapping needed |
| 3 | `oc import-image` "worked" but copied nothing | Default import is metadata only; the ImageStream points at `docker.io`, so pods still pull from Docker Hub (rate limits, outages). Use `--reference-policy=local` / `importMode` for local caching, or a real copy |
| 4 | Needed `--insecure` / `--tls-verify=false` | The registry's default route uses a certificate the terminal doesn't trust. **Lab only** – in production, trust the cluster's CA instead of disabling TLS |
| 5 | `podman login -p $(oc whoami -t)` | Puts the token in shell history and the process list. Use `--password-stdin` |
| 6 | `oc registry info` is deprecated | Use `oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}'` (as in the script) |
| 7 | nginx is a multi-arch manifest list | Copied only `linux/amd64` with `--override-os/--override-arch`; `oc image mirror --keep-manifest-list=true` keeps all architectures |

## 8. Production considerations
- **Mirror what you run**: production clusters (especially disconnected/air-gapped) pull only from an internal mirror (Quay / internal registry), populated with `oc-mirror` / `oc image mirror` and **image digest mirror sets**.
- **Avoid direct Docker Hub dependencies** – anonymous pulls are rate-limited.
- Trust the registry CA; never ship `--insecure` / `--tls-verify=false` into scripts used in production.
- Pin by digest after mirroring; scan mirrored images; prune old tags.
- Build machines and CI runners that use rootless podman need **subuid/subgid ranges** – see RCA-001.

## 9. Lessons learned
- A "copy" that unpacks (podman pull) depends on local user-namespace setup; registry-to-registry tools don't.
- Always check `dockerImageReference` to see whether an ImageStream tag is really in your registry.
- When one method fails, root-cause it – then pick the tool that avoids the failure mode, rather than reaching for root.

## 10. Interview talking point
> "I copied external images into my project's internal registry three ways. `oc image mirror` and `skopeo copy` worked – they move blobs registry to registry. Podman pull failed with an lchown error on `/etc/shadow`; I traced it to my rootless user having no subuid/subgid ranges, so podman had a single-ID user namespace and couldn't unpack files owned by other groups. I worked around it without root by using skopeo, and documented the proper fix for build hosts. I also showed `oc import-image` copies only metadata – the ImageStream still pointed at Docker Hub – and deployed an app from the mirrored copy to prove the copy was usable."
