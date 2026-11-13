# OCP-010: Build an image with podman, push it to the internal registry, and deploy it (`oc new-app` vs `oc create deployment`)

| Field | Value |
|---|---|
| **Type** | Story |
| **Area** | Image build · Internal registry · ImageStreams · Deployments |
| **Priority** | High |
| **Date** | 2026-11-13 |
| **Time spent** | ~40 min |
| **Status** | Done |
| **Related** | [RCA-001 – rootless podman without subuid](../rca/RCA-001-rootless-podman-subuid.md) · [OCP-007](OCP-007-own-image-openshift-build.md) · [OCP-009](OCP-009-copy-images-to-registry.md) |

## 1. User story / requirement
> As a **developer**, I want to **build a new image myself, push it to the OpenShift internal registry, make it available in my namespace, and create an application from it**, so that **I can ship my own images to OpenShift without an external registry**.

Steps required by the story:
1. Create a new docker image (or use an existing one)
2. Push the image to the OpenShift internal registry
3. Make the image available in the OpenShift namespace
4. Create the application: `oc new-app <name>` and a Deployment with `--image=<registry/image:tag>`

## 2. Acceptance criteria
- [x] New image built from my own Dockerfile (`test-app:1.0`)
- [x] Image pushed to the internal registry
- [x] Image available in my namespace as an ImageStream (plus short-name lookup enabled)
- [x] App created with `oc new-app` (`app-06`)
- [x] App created with `oc create deployment --image=<registry/image:tag>` (`test-app`)
- [x] Both apps serve my page under `restricted-v2`

## 3. Background / concepts
| | `oc new-app --image-stream=…` | `oc create deployment --image=…` |
|---|---|---|
| Image reference written | resolved **`@sha256:` digest** | the **tag exactly as typed** |
| Image-change trigger | ✅ added (redeploys when the tag moves – see OCP-008) | ❌ none |
| Service | ✅ created from the image's `EXPOSE` | ❌ none – add with `oc expose deployment` |
| Labels | `app=`, `deployment=` | `app=` |
| Origin | OpenShift | plain Kubernetes |

**`oc set image-lookup <imagestream>`** sets `lookupPolicy.local: true` so plain Kubernetes resources in the namespace can use the **short name** (`test-app:1.0`) and have it resolved to the ImageStream – otherwise they need the full registry path.

**Pull permission:** pods in the same namespace can pull the namespace's images automatically (the project's service accounts get `system:image-puller` there). Pulling across namespaces needs `oc policy add-role-to-user system:image-puller system:serviceaccount:<other-ns>:default -n <image-ns>`.

## 4. Plan
1. Write a Dockerfile on a small base (busybox httpd on 8080, non-root, group-0 writable).
2. `podman build` → `podman login` (token via stdin) → `podman push` to the registry's route.
3. Verify the ImageStream and enable image lookup.
4. Deploy with `oc new-app` and with `oc create deployment`; compare.
5. **Rollback:** `oc delete all -l app=app-06`, `oc delete deployment test-app`, `oc delete is test-app`.

## 5. Implementation
Files: [`Dockerfile`](../scripts/OCP-010/Dockerfile) · [`index.html`](../scripts/OCP-010/index.html) · [`build-push-deploy.sh`](../scripts/OCP-010/build-push-deploy.sh)
```dockerfile
FROM docker.io/library/busybox:1.36
LABEL maintainer="Nookireddi Dileep" description="test-app: tiny static site on busybox httpd" version="1.0"
COPY index.html /www/index.html
RUN chgrp -R 0 /www && chmod -R g=u /www
USER 1001
EXPOSE 8080
CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
```

## 6. Validation / evidence
**Step 1 – build. First attempt failed (RCA-001 also blocks builds):**
```
STEP 1/7: FROM docker.io/library/busybox:1.36
Error: creating build container: ... unpacking failed ... potentially insufficient UIDs or GIDs available in
user namespace (requested 65534:65534 for /home) ... lchown /home: invalid argument
```
Busybox's `/home` is owned by `nobody` (65534) – not representable with this user's single UID/GID mapping.

**Second attempt with `ignore_chown_errors` – succeeded:**
```
$ podman --storage-opt ignore_chown_errors=true build -t <registry-route>/my-apps/test-app:1.0 .
STEP 6/7: EXPOSE 8080
STEP 7/7: CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
Successfully tagged <registry-route>/my-apps/test-app:1.0
<registry-route>/my-apps/test-app   1.0   fe3051e094c4   4.66 MB
```
**Step 2 – push** (token passed via stdin, not on the command line):
```
$ oc whoami -t | podman login -u <me> --password-stdin <registry-route> --tls-verify=false
Login Succeeded!
$ podman --storage-opt ignore_chown_errors=true push <registry-route>/my-apps/test-app:1.0 --tls-verify=false
Copying blob sha256:40c7d2c1…
Copying config sha256:fe3051e0…
Writing manifest to image destination
```
**Step 3 – available in the namespace:**
```
NAME       TAGS   UPDATED
test-app   1.0    Less than a second ago
$ oc get istag test-app:1.0 -o jsonpath='{.image.dockerImageReference}'
image-registry.openshift-image-registry.svc:5000/my-apps/test-app@sha256:5f009bd8…
$ oc set image-lookup test-app
imagestream.image.openshift.io/test-app image lookup updated
$ oc get is test-app -o jsonpath='{.spec.lookupPolicy.local}'
true
```
**Step 4 – two applications from the same image:**
```
$ oc new-app test-app:1.0 --name=app-06
warning: Cannot check if git requires authentication.
--> Found image fe3051e (30 seconds old) in image stream "my-apps/test-app" under tag "1.0"
    deployment.apps "app-06" created
    service "app-06" created
$ oc create deployment test-app --image=image-registry.openshift-image-registry.svc:5000/my-apps/test-app:1.0
deployment.apps/test-app created

NAME       IMAGE                                                                            READY
app-06     image-registry.openshift-image-registry.svc:5000/my-apps/test-app@sha256:5f009bd8…   1
test-app   image-registry.openshift-image-registry.svc:5000/my-apps/test-app:1.0                1

NAME     TYPE        PORT(S)
app-06   ClusterIP   8080/TCP
Error from server (NotFound): services "test-app" not found
```
**Both serve my page, under restricted-v2:**
```
$ oc exec deploy/app-06   -- wget -qO- localhost:8080 | grep h1
<body><h1>Hello from test-app</h1><p>Built with podman, pushed to the OpenShift internal registry. Version 1.0</p></body></html>
$ oc exec deploy/test-app -- wget -qO- localhost:8080 | grep h1
<body><h1>Hello from test-app</h1><p>Built with podman, pushed to the OpenShift internal registry. Version 1.0</p></body></html>
$ oc get pod -l app=test-app -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'
restricted-v2
```
**File ownership inside the running container:**
```
$ oc exec deploy/test-app -- ls -ld /home /www
drwxr-xr-x    2 nobody   nobody    6 May 18  2023 /home     ← original ownership preserved in the cluster
drwxrwxr-x    1 root     root     24 Nov 13 10:37 /www      ← my layer: root-owned, group-writable
```

## 7. Issues hit & observations
| # | Observation | Explanation |
|---|---|---|
| 1 | `podman build` failed on `lchown /home` (65534) | Same root cause as [RCA-001](../rca/RCA-001-rootless-podman-subuid.md) – it affects **builds**, not only pulls. My assumption that busybox was all root-owned was wrong |
| 2 | `--storage-opt ignore_chown_errors=true` made the build work | Rootless storage option: ownership it can't map is dropped and files become owned by the single mapped user. A **workaround** – unsafe for images whose apps depend on file ownership |
| 3 | `/home` still `nobody:nobody` in the **running** container | Most likely the unchanged busybox base layer was pushed as its **original blob** (reused) rather than re-packed from local storage, so the registry kept upstream ownership; only my new layer came from local storage. Not proven – worth confirming with `skopeo inspect` of the layer digests |
| 4 | Local image ID `fe3051e…` ≠ registry digest `5f009bd8…` | Image ID = hash of the image **config**; registry digest = hash of the **manifest**. Both are expected |
| 5 | `app-06` uses a **digest**, `test-app` uses the **tag** | `oc new-app` resolves the ImageStream tag to a digest (+ trigger); `oc create deployment` writes what you type. A moving `:1.0` tag would change `test-app` on its next Pod restart without any rollout – reproducibility risk |
| 6 | `test-app` has **no Service** | `oc create deployment` only creates the Deployment. `oc expose deployment test-app --port=8080` adds one |
| 7 | `warning: Cannot check if git requires authentication` | `oc new-app test-app:1.0` is ambiguous (could be a Git source). `oc new-app --image-stream=test-app:1.0` is explicit |
| 8 | Image is only **4.66 MB** | Busybox base – tiny attack surface, but no package manager, no `curl` (used `wget`) |

## 8. Production considerations
- Build images in **CI** (Tekton/OpenShift Pipelines or a build host with proper subuid/subgid), not on a shared bastion with storage workarounds.
- **Deploy by digest**: either `oc new-app` from an ImageStream, or pin `@sha256:` in manifests; never rely on a mutable tag in a plain Deployment.
- Use proper TLS trust for the registry route instead of `--tls-verify=false`.
- Prefer a supported, scanned base (UBI) for production apps; busybox is fine for tooling/demos.
- Grant cross-namespace pulls explicitly with `system:image-puller` – least privilege.

## 9. Lessons learned
- "Make the image available in the namespace" = an ImageStream exists (created by the push) – plus `image-lookup` if plain Kubernetes objects should use short names.
- `oc new-app` and `oc create deployment` look similar but differ in digest pinning, triggers and Services.
- Verify assumptions about base images: even busybox has non-root-owned files.

## 10. Interview talking point
> "I built an image with podman on a bastion, pushed it to OpenShift's internal registry and deployed it two ways. The first build failed on `lchown /home` because rootless podman had no subuid ranges – the same root cause as an earlier RCA – so I used the `ignore_chown_errors` storage option as a lab workaround and documented why it's not a production fix. After the push, the ImageStream appeared in my namespace and I enabled image lookup. `oc new-app` pinned the Deployment to the sha256 digest and created a Service and a trigger; `oc create deployment` used the mutable tag exactly as typed and created no Service – so I'd use digest pinning for anything that matters."
