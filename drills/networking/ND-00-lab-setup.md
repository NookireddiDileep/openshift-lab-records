# ND-00 – Lab setup: the "hello" web app used by every drill

> **Network drills series.** All six drills break and repair the same small application. This page builds it, explains every piece in plain words, and records the healthy "baseline" that each drill compares against.

---

## 1. What we build, in plain words

A tiny website: an Apache web server that shows one page. To reach it from a browser, the request travels through four OpenShift objects:

```text
 browser
    │   http://hello-netlab.apps.ocp.example.com
    ▼
 Route "hello"         the front door: a public hostname, served by the cluster's router (HAProxy)
    ▼
 Service "hello"       a fixed internal address that always points at the current pods
    ▼        ▼
  pod 1     pod 2      two copies of Apache, kept alive by a Deployment
    ▲        ▲
    └─ mounted file ─ ConfigMap "hello-page"   the web page itself, stored outside the image
```

| Object | Everyday comparison | Its one job |
|---|---|---|
| **Deployment** | A manager who keeps exactly N staff on shift | Keep 2 copies of Apache running; replace any that disappear |
| **Pod** | One member of staff | Run one copy of Apache |
| **Service** | The company's main phone number | Give one fixed name and IP that forwards to whichever pods exist right now |
| **EndpointSlice** | The receptionist's current staff list | List the pod IPs (and port) the Service may send traffic to; only **Ready** pods get traffic |
| **Route** | The sign and front door on the street | Give the app a public hostname, so traffic from outside reaches the Service |
| **ConfigMap** | A notice pinned on a shared board | Hold the web page as a file, outside the image |

## 2. Environment

| Item | Value |
|---|---|
| Platform | Shared lab OpenShift 4.19 cluster (Kubernetes 1.32), 2 nodes: `master-0` (control plane + worker), `worker-1` |
| Router | Default IngressController, endpoint publishing strategy **HostNetwork** (matters in [ND-05](ND-05-deny-all-networkpolicy-timeout.md)) |
| My access | A normal project user (not cluster-admin), working in my own project |
| Project | `netlab` (sanitised name) |
| Image | `registry.access.redhat.com/ubi9/httpd-24` (Red Hat's Apache image; listens on **8080**, not 80) |

## 3. Build it (my exact commands)

```bash
# 1. A project of my own
oc new-project netlab

# 2. Two copies of Apache, managed by a Deployment
oc create deployment hello --image=registry.access.redhat.com/ubi9/httpd-24
oc scale deployment hello --replicas=2

# 3. A Service in front of the pods (fixed internal address, port 8080)
oc expose deployment hello --port=8080

# 4. A Route: the public hostname
oc expose service hello

# 5. A real web page, from a ConfigMap mounted into Apache's web folder
echo '<h1>Hello from my first OpenShift app</h1>' > index.html
oc create configmap hello-page --from-file=index.html
oc set volume deployment/hello --add --name=page --type=configmap \
  --configmap-name=hello-page --mount-path=/var/www/html
```

## 4. The healthy baseline (what "good" looks like)

Every drill starts by recording this, so there is something to compare against.

```bash
H=$(oc get route hello -o jsonpath='{.spec.host}'); echo $H
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H
oc get pods -l app=hello -o wide
oc get service hello -o wide
oc get endpointslices -l kubernetes.io/service-name=hello
```

```text
hello-netlab.apps.ocp.example.com
HTTP 200
NAME                     READY   STATUS    RESTARTS   AGE   IP          NODE
hello-77c476ccbb-mhwpg   1/1     Running   0          24h   10.0.0.129  master-0
hello-77c476ccbb-tj7c5   1/1     Running   0          24h   10.0.1.191  worker-1
NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE   SELECTOR
hello   ClusterIP   172.30.100.50   <none>        8080/TCP   25h   app=hello
NAME          ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
hello-cjx9l   IPv4          8080    10.0.1.191,10.0.0.129     25h
```

**How to read the baseline:**

| Check | Healthy value | Why it matters |
|---|---|---|
| `curl` from outside | `HTTP 200` | The whole path works |
| Pods | `2` pods, each `1/1 Running` | Both copies are up **and Ready** |
| Service `SELECTOR` | `app=hello` | The label the Service uses to find pods |
| EndpointSlice `ENDPOINTS` | Both pod IPs | The Service found both pods |
| EndpointSlice `PORTS` | `8080` | The port Apache really listens on |

> IPs, hostnames and the project name are sanitised. Pod IPs change every time a pod is replaced; the Service IP and the Route hostname never do.

## 5. Test helpers used in the drills

| Helper | What it does |
|---|---|
| `H=$(oc get route hello -o jsonpath='{.spec.host}')` | Saves the Route's hostname in a shell variable, so commands can say `http://$H` |
| `curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$H` | Calls the app from **outside** the cluster and prints only the HTTP status code |
| `oc run tester --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi -- curl …` | Starts a throwaway pod, runs one command from **inside** the cluster, then deletes the pod |
| `curl -sS` | Silent, but **shows errors** (so the exact failure message is visible) |
| `curl --max-time 10` | Give up after 10 seconds instead of waiting forever |
| `-w "… %{time_total}s"` | Print how long the request took: the key clue in [ND-05](ND-05-deny-all-networkpolicy-timeout.md) |

The `tester` pod prints a **PodSecurity warning** each time it starts. It is a warning, not an error: the test pod does not declare its security settings, and this project only warns about that.

---

Next: [ND-01 – No pods at all](ND-01-scale-to-zero-503.md) · Back to [Network drills index](README.md)
