# OCP-007: Build my own container image in OpenShift and deploy it as app-04

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Builds · ImageStreams · Internal registry · Deployments |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~30 min |
| **Status** | Done |
| **Related** | [OCP-004 – third-party image risks](OCP-004-third-party-image-etherpad.md) |

## 1. User story / requirement
> As a **developer**, I want to **create an OpenShift application from my own container image**, so that **I control what's in the image – base OS, content, permissions – instead of depending on someone else's**.

## 2. Acceptance criteria
- [x] Own `Dockerfile` written, on a supported base image
- [x] Image built and stored in a registry the cluster can pull from
- [x] Application deployed from that image and serving **my** content
- [x] Runs under the default `restricted-v2` SCC (random-UID compatible)
- [x] Deployment references an **immutable image digest**, not a moving tag

## 3. Background / concepts
**Two ways to build "your own image":**
| | Build **in OpenShift** (used here) | Build **outside** (podman/CI) and push |
|---|---|---|
| Tooling | `oc new-build` → **BuildConfig** | `podman build` + `podman push` |
| Stored in | **internal registry**, tracked by an **ImageStream** | Quay / Docker Hub / company registry |
| Credentials | none extra – the build's service account can push | registry login / pull secret |

**Objects involved:**
```
BuildConfig app-04  (Docker strategy, binary input)
   └─ Build app-04-1  → runs the Dockerfile in a build Pod
        └─ pushes to internal registry → ImageStream app-04, tag :latest → sha256 digest
              └─ Deployment app-04 (created by oc new-app) pulls that digest
```
- **Binary build:** source is uploaded from my machine (`--from-dir=.`) instead of cloned from Git – quick for labs; production normally builds from Git.
- **ImageStream:** an OpenShift pointer to images by tag → digest; deployments can be triggered when the tag moves.
- **Random-UID compatibility built into the image:** `chgrp -R 0 … && chmod -R g=u …` (the lesson from OCP-004), then switch back to a non-root `USER`.

## 4. Plan
1. Check tooling and base image availability.
2. Write `index.html` and a `Dockerfile` on **UBI 9 httpd** (supported, Red Hat-maintained base).
3. Create a Docker-strategy binary BuildConfig; start the build from the local directory.
4. Verify build, ImageStream tag and digest.
5. `oc new-app` from the ImageStream; verify rollout, SCC, image reference and content.
6. **Rollback:** `oc delete all -l app=app-04` and `oc delete is/app-04 bc/app-04`.

## 5. Implementation
Files: [`Dockerfile`](../scripts/OCP-007/Dockerfile) · [`index.html`](../scripts/OCP-007/index.html) · [`build-and-deploy.sh`](../scripts/OCP-007/build-and-deploy.sh)
```dockerfile
FROM registry.access.redhat.com/ubi9/httpd-24
LABEL maintainer="Nookireddi Dileep" description="app-04: custom static site on UBI9 httpd" version="1.0"
COPY index.html /var/www/html/index.html
USER 0
RUN chgrp -R 0 /var/www/html && chmod -R g=u /var/www/html
USER 1001
EXPOSE 8080
```
```bash
oc new-build --name=app-04 --strategy=docker --binary
oc start-build app-04 --from-dir=. --follow
oc new-app --image-stream=app-04:latest --name=app-04
oc rollout status deployment/app-04
```

## 6. Validation / evidence
**BuildConfig created:**
```
* A Docker build using binary input will be created
  * The resulting image will be pushed to image stream tag "app-04:latest"
imagestream.image.openshift.io "app-04" created
buildconfig.build.openshift.io "app-04" created
```
**Build log (trimmed) – my 7 steps, plus 2 that OpenShift adds:**
```
Pulling image registry.access.redhat.com/ubi9/httpd-24 ...
STEP 1/9: FROM registry.access.redhat.com/ubi9/httpd-24
STEP 2/9: LABEL maintainer="Nookireddi Dileep" ...
STEP 3/9: COPY index.html /var/www/html/index.html
STEP 4/9: USER 0
STEP 5/9: RUN chgrp -R 0 /var/www/html && chmod -R g=u /var/www/html
STEP 6/9: USER 1001
STEP 7/9: EXPOSE 8080
STEP 8/9: ENV "OPENSHIFT_BUILD_NAME"="app-04-1" "OPENSHIFT_BUILD_NAMESPACE"="my-apps"      ← added by OpenShift
STEP 9/9: LABEL "io.openshift.build.name"="app-04-1" "io.openshift.build.namespace"="my-apps" ← added by OpenShift
Pushing image image-registry.openshift-image-registry.svc:5000/my-apps/app-04:latest ...
Successfully pushed image-registry.openshift-image-registry.svc:5000/my-apps/app-04@sha256:6bada123…
Push successful
```
**ImageStream tag → immutable digest:**
```
NAME            IMAGE REFERENCE
app-04:latest   image-registry.openshift-image-registry.svc:5000/my-apps/app-04@sha256:6bada123…
```
**Deployed from my image:**
```
--> Found image 8409022 (8 seconds old) in image stream "my-apps/app-04" under tag "latest"
    deployment.apps "app-04" created
    service "app-04" created
deployment "app-04" successfully rolled out

NAME                     READY   UP-TO-DATE   AVAILABLE   IMAGES
deployment.apps/app-04   1/1     1            1           image-registry.openshift-image-registry.svc:5000/my-apps/app-04@sha256:6bada123…

NAME             TYPE        CLUSTER-IP     PORT(S)
service/app-04   ClusterIP   172.30.x.x     8080/TCP,8443/TCP
```
**SCC, image reference and my content:**
```
$ oc get pod $POD -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
restricted-v2
$ oc exec $POD -- curl -s localhost:8080 | grep -E "<h1>|Version"
  <h1>Hello from app-04</h1>
  <p>Version: 1.0</p>
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | OpenShift added **build steps 8–9** (`OPENSHIFT_BUILD_*` env + `io.openshift.build.*` labels) | Traceability – every image records the build and namespace that produced it |
| 2 | The Deployment uses **`@sha256:` digest**, not `:latest` | `oc new-app` resolves the ImageStream tag to its digest → immutable, reproducible. Fixes the `:latest` risk from OCP-004 |
| 3 | `oc get builds` showed **Running** right after "Push successful" | Status update lag – queried a moment before the build Pod finished; re-checking shows `Complete` |
| 4 | `oc get … -l app=app-04` listed the Deployment and Service but **no Pods** | `oc new-app` labels resources `app=app-04`, but the **Pod template** uses `deployment=app-04`. Use `-l deployment=app-04` for Pods |
| 5 | Service exposes **8080 and 8443** | Inherited from the base image's `EXPOSE`; my app only serves 8080. In production, define the Service explicitly with only the ports in use |
| 6 | App not exposed outside the cluster | `oc new-app` creates a ClusterIP Service only – a Route is a separate step (follow-up) |
| 7 | `podman` is available on the lab terminal | Enables the "build outside and push to Quay" variant as a follow-up |

## 8. Production considerations
- **Build from Git, not binary uploads** – source-controlled, reviewable, triggered by webhooks (or Tekton / OpenShift Pipelines).
- Use **supported base images** (UBI) and rebuild regularly to pick up base-image security fixes; scan images before deploy.
- **Version tags + digests**: tag releases (`app-04:1.0`) and deploy by digest; avoid `:latest` in production promotion.
- Keep random-UID compatibility in the Dockerfile (`chgrp 0` / `chmod g=u`, non-root `USER`).
- Set build **resource limits** and keep build Pods off critical nodes; use a pull-through cache/mirror for base images.

## 9. Lessons learned
- `oc new-build --binary` + `oc start-build --from-dir` is the fastest way to turn a local Dockerfile into a deployable image in OpenShift.
- ImageStreams map tags to digests – deployments created from them are pinned to exact image content.
- Check labels before filtering: `oc new-app` uses different labels on Pods vs. other resources.

## 10. Interview talking point
> "I wrote my own Dockerfile on Red Hat's UBI 9 httpd base, made it random-UID compatible with `chgrp 0` and `chmod g=u`, and built it inside OpenShift with a Docker-strategy binary BuildConfig. The image was pushed to the internal registry and tracked by an ImageStream, and `oc new-app` deployed it pinned to the exact sha256 digest rather than `latest`. It ran under `restricted-v2` and served my page. I also noticed details like OpenShift injecting build metadata into the image, and the Service inheriting an unused port from the base image."

## Follow-ups
- [ ] Expose app-04 with a Route
- [ ] Change the page to v1.1, rebuild, and watch the ImageStream change roll out the Deployment
- [ ] Variant: build with `podman` and push to Quay, then deploy from the external registry with a pull secret
