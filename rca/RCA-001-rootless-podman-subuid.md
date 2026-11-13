# RCA-001: Rootless `podman pull` fails – no subuid/subgid ranges for the user

| Field | Value |
|---|---|
| **Date** | 2026-11-13 |
| **Environment** | Lab bastion/terminal host (RHEL), rootless podman; OpenShift 4.x internal registry as the target |
| **Severity** | Sev4 (lab task blocked; workaround available) |
| **Component** | podman (rootless) · user namespaces · `/etc/subuid`, `/etc/subgid` |
| **Status** | Mitigated (workaround) – permanent fix needs host admin |
| **Time to detect / resolve** | immediate / ~15 min to root cause and work around |
| **Related story** | [OCP-009 – copy images to my registry](../stories/OCP-009-copy-images-to-registry.md) |

## 1. Problem statement
Copying `docker.io/library/nginx:alpine` into the internal registry with `podman pull` → `tag` → `push` failed at the **pull** step: podman could not unpack an image layer (`lchown /etc/shadow: invalid argument`), so the tag and push steps also failed.

## 2. Impact
- Could not copy images with podman from the lab terminal.
- Any rootless podman workflow on this host (pull, build, run) fails for images containing files owned by non-root UIDs/GIDs – most real images.
- No data loss; no impact on the cluster.

## 3. Symptoms & detection
Detected immediately from command output:
```
ERRO[0000] cannot find UID/GID for user <me>: no subuid ranges found for user "<me>" in /etc/subuid - check rootless mode in man pages.
WARN[0000] Using rootless single mapping into the namespace. This might break some images.
Login Succeeded!
Trying to pull docker.io/library/nginx:alpine...
Copying blob ... done
Error: unable to copy from source docker://nginx:alpine: copying system image from manifest list: writing blob:
  adding layer with blob "sha256:881fc932…": unpacking failed (error: exit status 1; output: potentially insufficient
  UIDs or GIDs available in user namespace (requested 0:42 for /etc/shadow): Check /etc/subuid and /etc/subgid if
  configured locally and run "podman system migrate": lchown /etc/shadow: invalid argument)
Error: docker.io/library/nginx:alpine: image not known
Error: <registry>/my-apps/nginx:copied: image not known
```

## 4. Timeline
| Time (IST) | Event |
|---|---|
| 15:58 | `podman login` succeeded with an ERRO/WARN about missing subuid ranges |
| 15:58 | `podman pull` downloaded all blobs, then failed while unpacking a layer |
| 15:59 | `tag`/`push` failed as a consequence ("image not known") |
| 16:00 | Confirmed no subuid/subgid entries; confirmed single UID/GID mapping |
| 16:00 | Workaround: `skopeo copy` registry-to-registry – succeeded |
| 16:01 | App deployed from a copied image – service verified |

## 5. Investigation
| # | Hypothesis | Check | Result |
|---|---|---|---|
| 1 | Registry auth / network problem | Blobs downloaded fine; `podman login` succeeded; `oc image mirror` to the same registry worked | **Ruled out** |
| 2 | Docker Hub rate limit | Manifest and all blobs were fetched; error is in local unpacking, not HTTP | **Ruled out** |
| 3 | Corrupt image | Same image copied cleanly with `skopeo copy` | **Ruled out** |
| 4 | Rootless user namespace too small | `grep` subuid/subgid + `podman info` ID mappings | **Confirmed** |

```
$ grep -E "^$(whoami):" /etc/subuid /etc/subgid || echo "no subuid/subgid entries for $(whoami)"
no subuid/subgid entries for <me>

$ podman info --format '{{.Host.IDMappings.UIDMap}} {{.Host.IDMappings.GIDMap}}'
[{0 <my-uid> 1}] [{0 <my-uid> 1}]
        ↑ container ID 0 → my UID, size 1: only ONE uid and ONE gid exist in podman's namespace
```

## 6. Root cause
Rootless podman runs inside a **user namespace**. To represent the many UIDs/GIDs that files in an image belong to, it maps them onto **subordinate ID ranges** assigned to the user in `/etc/subuid` and `/etc/subgid`. This user has **no ranges**, so podman falls back to a **single mapping** (container 0 → my UID). When unpacking the nginx layer, podman must create `/etc/shadow` owned by **GID 42 (`shadow`)**; GID 42 doesn't exist in a single-ID namespace, so `lchown()` returns `EINVAL` and the layer can't be stored.

**5 Whys**
1. Why did the copy fail? → `podman pull` failed, so there was nothing to tag/push.
2. Why did the pull fail? → Unpacking a layer failed on `lchown /etc/shadow` to GID 42.
3. Why couldn't it set GID 42? → Podman's user namespace contains only one GID.
4. Why only one? → No subordinate UID/GID ranges exist for this user.
5. Why none? → The lab host's users weren't provisioned with `/etc/subuid`/`/etc/subgid` entries (e.g. accounts created without them or managed outside `useradd` defaults).

**Why the other methods worked:** `oc image mirror` and `skopeo copy` copy blobs **registry-to-registry as opaque tarballs** – they never unpack files, so file ownership never matters.

## 7. Resolution
**Workaround (no root needed) – copy without unpacking:**
```bash
skopeo copy docker://docker.io/library/nginx:alpine docker://$REG/$NS/nginx:copied \
  --dest-tls-verify=false --override-os linux --override-arch amd64
```
```
Copying blob sha256:69d81d55…
Copying blob sha256:da90db50…
Copying config sha256:7cac34a4…
Writing manifest to image destination
$ oc get istag nginx:copied -o jsonpath='{.image.dockerImageReference}'
image-registry.openshift-image-registry.svc:5000/my-apps/nginx@sha256:697b0b15…
```
**Permanent fix (host administrator, root):**
```bash
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 <user>
podman system migrate          # as the user, to pick up the new mappings
podman info --format '{{.Host.IDMappings.UIDMap}}'   # expect a second entry of size 65536
```
(For users from LDAP/IdM, subordinate IDs are managed centrally, e.g. IdM's subordinate-ID feature, rather than with `usermod`.)

## 8. Preventive actions
| Action | Type | Owner | Status |
|---|---|---|---|
| Use registry-to-registry tools (`oc image mirror`, `skopeo copy`) for image copying | Prevent | me | Done (script in OCP-009) |
| Provision subuid/subgid ranges for every user who builds/pulls with rootless podman | Prevent | host admin | Proposed |
| Add a pre-flight check to build-host onboarding: `grep "^$USER:" /etc/subuid` | Detect | host admin | Proposed |
| Document the error signature (`lchown … invalid argument`, "no subuid ranges") in the runbook | Process | me | Done (this RCA) |

## 9. Lessons learned
- The **first warning** (`no subuid ranges found`) predicted the failure – warnings on login/startup are worth reading.
- Distinguish **network/registry** errors (fetch fails) from **local storage** errors (unpack fails) – here every blob downloaded fine.
- Choose the tool that avoids the failure mode: copying images doesn't need local unpacking at all.

## 10. Interview talking point
> "On a lab bastion, `podman pull` failed with `lchown /etc/shadow: invalid argument`. The blobs had downloaded, so it wasn't network or auth – it was local unpacking. `podman info` showed a single UID/GID mapping and `/etc/subuid` had no entry for my user, so rootless podman couldn't represent GID 42 that `/etc/shadow` needed. I worked around it without root by copying registry-to-registry with skopeo – which never unpacks layers – and documented the permanent fix: assign subordinate ID ranges with `usermod --add-subuids/--add-subgids` and run `podman system migrate`."

## 11. Recurrence – also blocks `podman build` (OCP-010)
On 2026-11-13 the same root cause stopped a **build**, not just a pull:
```
STEP 1/7: FROM docker.io/library/busybox:1.36
Error: creating build container: ... unpacking failed ... potentially insufficient UIDs or GIDs available in
user namespace (requested 65534:65534 for /home) ... lchown /home: invalid argument
```
Even busybox has a non-root-owned path (`/home` → `nobody`, 65534), so practically every base image is affected.

**Second workaround (no root needed):** the rootless storage option `ignore_chown_errors`
```bash
podman --storage-opt ignore_chown_errors=true build -t <image> .
podman --storage-opt ignore_chown_errors=true push <image>
```
It drops ownership that can't be mapped (files become owned by the single mapped user) – fine for images that don't rely on file ownership, **not** for ones that do. In this case the running container still showed `/home` as `nobody:nobody`, most likely because the unchanged base layer was pushed as its original blob. The permanent fix in §7 (subordinate ID ranges) remains the real solution.

| Additional preventive action | Type | Status |
|---|---|---|
| Don't build on shared bastions; use CI / a build host with subuid/subgid | Prevent | Proposed |
