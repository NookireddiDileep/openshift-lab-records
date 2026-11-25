# RB-S44: DB login fails with the "correct" password from the Secret

| Field | Value |
|---|---|
| **Scenario** | [S44](../scenarios/DO180-RCA-scenario-bank.md) |
| **Area** | Configuration · Secrets · base64 · Env vars |
| **Lab** | 🟢 own project |
| **Status** | 📋 Ready to run (not yet run on my cluster) |
| **Time** | ~30–45 min |

> A runbook is a **plan**, not a record. Once I've run it on my lab and captured real output, it becomes `rca/RCA-0NN-*.md` and this status becomes ✅ Done → RCA-0NN.
>
> **EX280 angle:** creating Secrets and injecting them into applications as env vars or volumes, and checking what the pod really receives, is core application-configuration work.
>
> All command output below is **typical output (illustrative)**, not captured from my cluster. The password `S3cr3t-pass` is a lab-only dummy.

## 1. The ticket (as it would arrive)

> "The app can't log in to the database. We copied the password from the vault into the `db` Secret and double-checked it three times. The DB admin says the same password works from his terminal. The Secret looks right. What is going on?"

## 2. Reproduce safely (🟢)

Work only in my own project; every object is named `rca-s44-*`. Helpers are in [`scripts/RB-S44/`](../scripts/RB-S44/) and refuse to run in `default`, `openshift-*` or `kube-*`.

There is no real database here. A small client pod compares `DB_PASSWORD` with the password the "database" expects and logs an `Access denied` line when they differ. That keeps the lab cheap and the failure identical to a real login failure.

```bash
oc new-project rca-s44-lab          # or reuse my own lab project
./scripts/RB-S44/break.sh newline   # fault 1: hidden trailing newline
# later, repeat with the second fault:
# ./scripts/RB-S44/fix.sh && ./scripts/RB-S44/break.sh double
```

By hand, the two classic mistakes look like this:

```bash
# Fault 1: echo adds a newline, so the stored value is "S3cr3t-pass\n"
echo 'S3cr3t-pass' | base64 -w0

# Fault 2: the value is encoded twice (once by me, once more by a tool or template)
printf '%s' 'S3cr3t-pass' | base64 -w0 | base64 -w0
```

The result goes under `data:` in the Secret. Whatever sits under `data:` is decoded exactly once by the API machinery, so the app receives the newline, or the base64 text, as the password.

## 3. What you'll see

```
$ oc get pods -l app=rca-s44-client
NAME                             READY   STATUS    RESTARTS   AGE
rca-s44-client-6d9c7f5b8-x2kqp   1/1     Running   0          2m        <- healthy-looking

$ oc logs deployment/rca-s44-client --tail=2
ERROR 1045 (28000): Access denied for user 'app' (using password: YES)
ERROR 1045 (28000): Access denied for user 'app' (using password: YES)
```

Key observations:

- The pod is `Running` with no restarts. **Nothing in Kubernetes is broken**; the failure is in the application's log, so `oc get pods` alone can't find it.
- "using password: YES" proves a password was sent, so this is not a missing-variable problem (compare [RB-S42](RB-S42-createcontainerconfigerror-missing-configmap-key.md), where the pod never starts).
- Whoever reads the Secret in the console or with a casual `oc get secret -o yaml` sees base64 and assumes it is fine; both faults look like plausible base64.

## 4. Triage, outside-in

| # | Command | What it tells you |
|---|---|---|
| 1 | `oc get pods,deployment -l app=rca-s44-client` | The pod is up, so the problem is inside the application, not scheduling or the image. |
| 2 | `oc logs deployment/rca-s44-client --tail=5` | `Access denied` with a password supplied: the credential reached the app but is wrong. |
| 3 | `oc get deployment rca-s44-client -o jsonpath='{.spec.template.spec.containers[0].env}'` | Which Secret and key feed `DB_PASSWORD` (`secretKeyRef`). Confirms I'm looking at the right object. |
| 4 | `oc get secret rca-s44-db -o jsonpath='{.data.DB_PASSWORD}' \| base64 -d \| od -c` | Decode **once** and look at the raw bytes. A trailing `\n` is fault 1; readable base64 text (ending in `=`) is fault 2. |
| 5 | `oc get secret rca-s44-db -o jsonpath='{.data.DB_PASSWORD}' \| base64 -d \| wc -c` | Length check: 11 is right for `S3cr3t-pass`; 12 means a newline; 16 means it was encoded twice. |
| 6 | `oc exec deployment/rca-s44-client -- sh -c 'printf %s "$DB_PASSWORD" \| wc -c'` | The length of what the **running container** received. Compare it with step 5 and with the real password. |
| 7 | `oc exec deployment/rca-s44-client -- sh -c 'printf %s "$DB_PASSWORD" \| od -c'` | The actual bytes inside the pod, to prove the newline or the base64 text arrived intact. |
| 8 | Try the password by hand against the real DB (from a test pod or the DB host) using the value copied from the vault | Proves the vault value is good and the damage happens between the vault and the Secret. |

Careful with the tools: `printenv` and `echo` add their own newline when printing, which hides the problem. Use `printf %s` and `od -c`. Also avoid pasting decoded passwords into tickets or chat; compare lengths and last bytes instead.

Look-alikes to rule out:

- **Windows line endings (`\r\n`)** from a password file edited on Windows: the stored value ends in `\r`, shown by `od -c` as `\r`.
- **Quotes or spaces** copied along with the value, for example surrounding `"` characters.
- **Wrong key name or wrong Secret.** A missing key gives `CreateContainerConfigError` (S42), not a login failure, but a *similarly named* Secret with an old password gives exactly this symptom.
- **The DB itself was changed** (password rotated) while the Secret still holds the old one. Step 8 separates these cases.
- **Stale env var:** the Secret is already fixed but the pod still has the old value, as in [RB-S43](RB-S43-configmap-updated-app-still-old-value.md).

## 5. Root cause(s)

A Secret's `data:` values must be the base64 of **exactly** the bytes the application expects, and the API decodes them exactly once. Two common ways to get that wrong:

1. **Trailing newline.** `echo secret | base64` encodes `secret` **plus** a newline. The app receives `secret\n`, and a database compares passwords byte for byte, so it is a different password. The fix is `echo -n`, or better `printf '%s'`.
2. **Double encoding.** The value was base64-encoded by hand and then put somewhere that encodes it again (a tool, a template, or `stringData:` holding an already-encoded string). Decoded once, the app receives a base64 string such as `UzNjcjN0LXBhc3M=`.

The underlying mistake in both cases is the same: treating `data:` as "paste here" instead of "base64 of the exact bytes". `stringData:` and `oc create secret generic --from-literal` exist so I never encode by hand.

5 Whys: login fails → the app sent a different byte string than the DB expects → the Secret holds extra bytes (newline) or an extra encoding layer → the value was hand-encoded under `data:` → nothing validated the decoded length or content.

## 6. Fix

Rewrite the value so the API server does the encoding, then restart because env vars are read only at container start.

```bash
# stringData is write-only input; the API stores it base64-encoded under data:
oc patch secret rca-s44-db --type=merge \
  -p '{"stringData":{"DB_PASSWORD":"S3cr3t-pass"}}'
oc rollout restart deployment/rca-s44-client
oc rollout status deployment/rca-s44-client
# or: ./scripts/RB-S44/fix.sh
```

Other safe ways to write the value, and one trap:

```bash
oc create secret generic rca-s44-db --from-literal=DB_PASSWORD='S3cr3t-pass' \
  --dry-run=client -o yaml | oc apply -f -        # encodes correctly, no newline
oc create secret generic rca-s44-db --from-file=DB_PASSWORD=./pw.txt   # file content is used verbatim
```

`--from-file` includes any newline in the file, so create the file with `printf '%s' 'value' > pw.txt` (or `echo -n`). Real passwords come from the vault or a secrets operator and are never typed into shell history; the literal above is for the lab only.

## 7. Verify

```bash
oc get secret rca-s44-db -o jsonpath='{.data.DB_PASSWORD}' | base64 -d | wc -c    # 11
oc exec deployment/rca-s44-client -- sh -c 'printf %s "$DB_PASSWORD" | wc -c'    # 11
oc logs deployment/rca-s44-client --tail=3                                        # login OK
./scripts/RB-S44/verify.sh                                                        # runs the above
```

Typical output (illustrative):

```
== Length of the value stored in the Secret after ONE base64 decode (expect 11 for S3cr3t-pass)
11
== Last byte of the decoded value (a trailing newline prints as \n)
 s
== Length of DB_PASSWORD as the running container sees it (expect 11)
11
== Latest client log lines
login OK
login OK
login OK
```

## 8. Prevention (what would stop this happening again)

- **Never hand-encode.** Create Secrets with `oc create secret generic --from-literal/--from-file`, or put plain text under `stringData:` and let the API do the base64. If I must encode, `printf '%s' value | base64 -w0`, never plain `echo`.
- **Source the secret from a vault or secret store** (an operator such as External Secrets, or a sealed/encrypted-in-Git workflow) so a human never copies the password through a shell.
- **Add a smoke test after every credential change**: a short Job or init step that logs in with the mounted credentials and fails the deploy if it can't.
- **Log safe diagnostics at startup**: credential length and a hash prefix, never the value, so "is the Secret what I think it is?" has a one-command answer.
- **Remember the restart.** Env vars from a Secret update only when the pod restarts, so make "change credential" and "rollout restart" one step ([RB-S43](RB-S43-configmap-updated-app-still-old-value.md)). Mounted Secret files refresh without a restart if the app re-reads them.
- **Review rights:** `oc get secret -o yaml` exposes the value to anyone with `get` on Secrets; keep that RBAC tight.

## 9. Evidence to capture when I run it (for the RCA)

- [ ] The ticket symptom: `oc get pods` healthy and `oc logs` showing `Access denied`
- [ ] The decoded-once `od -c` output showing the trailing `\n` (fault 1), with the lengths 12 vs 11
- [ ] Repeat with `./break.sh double`: the decoded-once value is base64 text, length 16
- [ ] Container-side `printf %s "$DB_PASSWORD" | od -c` matching the Secret (proof the bytes travelled unchanged)
- [ ] The fix command, the rollout, and `login OK` in the logs
- [ ] Bonus: mount the same Secret as a **volume** and compare the file bytes with the env var
- [ ] Bonus: reproduce with a real MySQL/MariaDB pod and record the genuine `ERROR 1045` text
- [ ] Time to detect, time to fix, and which command found the cause fastest
- [ ] Redact any real password and sanitise per the [checklist](../SANITISE-CHECKLIST.md) before committing

## 10. Interview: "The app can't log in with the 'correct' password from the Secret. Walk me through it." (a 60-second answer)

"First I check the pod is running and read its log. 'Access denied' with a password supplied tells me the credential arrived but it's wrong, so it isn't a scheduling or image problem. Then I compare bytes, not eyes. I decode the Secret value once and look at it with `od -c` and `wc -c`, and I compare that with what the running container sees using `printf %s` rather than `echo`, which would hide a newline. The two usual culprits are a trailing newline from `echo | base64`, and double base64 encoding, where the app gets a base64 string as its password. The fix is to rewrite the value through `stringData` or `oc create secret --from-literal`, so the API does the encoding, and then restart the pods, because env vars are only read at start. To prevent it I'd never hand-encode secrets, I'd source them from a vault, and I'd add a login smoke test after each credential change."

## 11. Clean up

```bash
oc delete deployment rca-s44-client
oc delete secret rca-s44-db
# or, if the project was only for this: oc delete project rca-s44-lab
```

## Sources

- Kubernetes docs: [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) (`data` holds base64 values, `stringData` is a write-only convenience that is stored as base64)
- Kubernetes docs: [Managing Secrets using kubectl](https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/) (`--from-literal`, `--from-file`, and the note that `echo` adds a trailing newline)
- Kubernetes docs: [Distribute credentials securely using Secrets](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) (env vars vs volumes)
- Red Hat OpenShift Container Platform 4.18 documentation: [docs.redhat.com](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18) (working with Secrets, `oc create secret`)
