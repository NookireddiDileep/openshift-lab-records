# Before every push – sanitise checklist

- [ ] No real cluster URLs (`api.<cluster>.<domain>`, `*.apps.<domain>`) → use `api.ocp.example.com`
- [ ] No IP addresses → use `10.0.0.x` / `192.0.2.x`
- [ ] No usernames/passwords/tokens (`oc whoami -t`, htpasswd, secrets output)
- [ ] No kubeconfig files
- [ ] No trainer's lab names, Jira URLs or internal ticket numbers → use my own IDs (OCP-001, RCA-001)
- [ ] No copied text from Red Hat course books – my own words only
- [ ] No employer (T-Systems / customer) names, hosts or logs

Quick scan before pushing:
```bash
git diff --cached | grep -nEi 'password|token|secret|BEGIN .*PRIVATE|([0-9]{1,3}\.){3}[0-9]{1,3}|apps\.' || echo "looks clean"
```
