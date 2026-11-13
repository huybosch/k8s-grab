# Grab Mini - Command Reference (Phase 0 → Phase 24 + Final Project + Production Simulation)

Nhật ký lab: mỗi **Scenario** = lệnh đã chạy thật + code liên quan + kết quả đã verify + bài học, theo đúng thứ tự làm. Giáo trình (học gì, vì sao) nằm ở [../Roadmap.md](../Roadmap.md).

> **⚠️ Git (`github.com/huybosch/k8s-grab`, nhánh `main`) là nguồn sự thật của namespace `default`** - Argo CD sync `charts/` + `helm-values/` vào cluster (Phase 24). **Deploy app = `./ci/pipeline.ps1 -Service <svc>`** (commit tag + `git push`); sửa hạ tầng = sửa file + `git push`. Các lệnh `kubectl apply -f k8s/...` (Scenario 0-20), `helm upgrade`/`helm rollback` (Scenario 22-23) là **lịch sử** - chạy lại sẽ bị Argo CD selfHeal đè lại (hoặc tạo field lạ mà Argo CD không quản lý). Muốn dựng lại môi trường: dùng [🔁 Dựng lại toàn bộ cluster](#rebuild). Kịch bản demo cuối khoá: [DEMO.md](DEMO.md).

## 📊 Trạng thái hiện tại (11/11/2026)

| Thành phần | Chi tiết | Quản lý bởi |
|---|---|---|
| Cluster | `kind` v0.33, `grab-mini`, 1 control-plane (port 80/443 ra host) + 2 worker - `kind-multi-node.yaml` | `kind` |
| Code | `grab-mini/` = repo `github.com/huybosch/k8s-grab` (public, nhánh `main`); mỗi lần deploy = 1 commit `deploy(<svc>): <sha>`, rollback = commit `Revert ...` | `git` + GitHub Actions `ci.yaml` (test + build + chạy thử container) |
| GitOps | Argo CD 3.6.1 (namespace `argocd`): `root` → AppProject `grab-mini`, ApplicationSet `grab-services` (booking/payment/user), `grab-platform`; poll Git 60s, selfHeal | Helm: `argocd` (`k8s/argocd/values.yaml`) + `kubectl apply -f argocd/root.yaml` (1 lần) |
| Registry | `registry:2.8.3` container `kind-registry`, `localhost:5001` (trong cluster: `http://kind-registry:5000`) | `ci/setup-local-registry.ps1` |
| App | `booking` (HPA 3-20), `payment` (HPA 3-10), `user` x3, `driver` x3, `notification` x2 - image `localhost:5001/<svc>-service:<git-sha>` (tag đang chạy: `helm-values/<svc>-image.yaml`); probe, PDB, topologySpread (`matchLabelKeys`), preStop 10s, keepAliveTimeout 65s, requests/limits, không mount ServiceAccount token, failover 30s | `ci/pipeline.ps1` → Git → Argo CD: ApplicationSet `grab-services` (chart `grab-service`) |
| Platform | ConfigMap `booking-config`, Ingress `/users` `/booking` `/payment` `/payments` `/drivers`, 12 NetworkPolicy (default-deny + 4 luồng ingress + 5 `egress-<app>`), Ingress retry (`proxy-connect-timeout 1s`, `next-upstream`), CronJob `settlement-job`, StatefulSet `postgres` (bảng `payments`, role `payment`), Job `db-init` (PostSync), Deployment `redis` (toleration 30s) | Git → Argo CD: `grab-platform` (không prune) |
| Secret | `postgres-superuser` (superuser Postgres), `payment-db` (user DB `payment`) - cả 2 password ngẫu nhiên | `kubectl create secret` (cố ý ngoài Git) |
| Hạ tầng | `ingress-nginx` (+ patch nodeSelector), `metrics-server` (+ patch insecure-tls) | `kubectl apply` từ URL upstream |
| Monitoring | `kube-prometheus-stack` 93.1.1, Loki 7.5.0, Alloy 1.15.0 (namespace `monitoring`) | Helm: `monitoring`, `loki`, `alloy` |
| Monitoring config | ServiceMonitor, PrometheusRule (8 alert: error rate, p95, no pods, restarting, OOMKilled, memory near limit, memory leak, target down), `alert-webhook`, dashboard Grafana | `kubectl apply -f k8s/monitoring/` |

## 📋 Menu

- [Scenario 0 - Tạo cluster (Phase 0 / Lab 0)](#scenario-0)
- [Scenario 1 - Scaffold + build + load 5 service image (Phase 2 / Lab 2)](#scenario-1)
- [Scenario 2 - Deploy + Service + scale test (Phase 3 / Lab 3)](#scenario-2)
- [Scenario 3 - Service discovery booking → payment (Phase 4 / Lab 4)](#scenario-3)
- [Scenario 4 - ConfigMap + Secret (Phase 5)](#scenario-4)
- [Scenario 5 - Probes + fake failure test (Phase 6 / Lab 5)](#scenario-5)
- [Scenario 6 - Rolling update v1 → v2, zero-downtime (Phase 7 / Lab 6)](#scenario-6)
- [Scenario 7 - Rollback khi deploy lỗi (Phase 8)](#scenario-7)
- [Scenario 8 - Pod Replacement vs Container Restart (Phase 9)](#scenario-8)
- [Scenario 9 - Resource requests/limits + stress test (Phase 10)](#scenario-9)
- [Scenario 10 - HorizontalPodAutoscaler (Phase 11)](#scenario-10)
- [Scenario 11 - Graceful Shutdown (Phase 12)](#scenario-11)
- [Scenario 12 - Ingress + Ingress Controller (Phase 13)](#scenario-12)
- [Scenario 13 - PostgreSQL + Persistent Storage (Phase 14)](#scenario-13)
- [Scenario 14 - Deployment → StatefulSet (Phase 15)](#scenario-14)
- [Scenario 15 - Job + CronJob (Phase 16)](#scenario-15)
- [Scenario 16 - Multi-node + Node Failure (Phase 17)](#scenario-16)
- [Scenario 17 - topologySpreadConstraints: spread Pod đều qua node (Phase 18)](#scenario-17)
- [Scenario 18 - High Availability: PodAntiAffinity + PDB + failover nhanh (Phase 19)](#scenario-18)
- [Scenario 19 - NetworkPolicy: zero-trust trong namespace (Phase 20)](#scenario-19)
- [Scenario 20 - Observability: Prometheus + Grafana + app metrics (Phase 21)](#scenario-20)
- [Scenario 21 - Logs (Loki + Alloy) + Alert (PrometheusRule + Alertmanager) (Phase 21)](#scenario-21)
- [Scenario 22 - Helm: chart dùng chung + chuyển resource đang chạy sang Helm (Phase 22)](#scenario-22)
- [Scenario 23 - CI/CD: pipeline local + local registry + tag theo git SHA (Phase 23)](#scenario-23)
  - [23b - CD qua self-hosted runner, chặn PR từ fork](#scenario-23b)
- [Scenario 24 - GitOps: Argo CD + app-of-apps, deploy = git push (Phase 24)](#scenario-24)
- [Scenario 25 - Final Project: ráp đủ Grab Mini Platform (5 service + Redis + PostgreSQL)](#scenario-25)
- [Scenario 26 - Production Simulation: Incident 1-7 (gây sự cố thật, đo, xử lý, vá)](#scenario-26)
- [Cleanup - xoá image Docker cũ không dùng](#cleanup)
- [🔁 Dựng lại toàn bộ cluster từ đầu](#rebuild)
- [🧠 Tổng hợp bài học](#bai-hoc)
- [Việc còn thiếu](#con-thieu)

---

<a id="scenario-0"></a>
## Scenario 0 - Tạo cluster (Phase 0 / Lab 0)

```powershell
docker info   # đảm bảo Docker Desktop đã chạy xong, retry nếu lỗi npipe

kind create cluster --name grab-mini
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

**Nếu gặp "node(s) already exist"** (container cũ bị crash/exited):

```powershell
docker ps -a --filter "name=grab-mini"
kind delete cluster --name grab-mini
kind create cluster --name grab-mini
```

---

<a id="scenario-1"></a>
## Scenario 1 - Scaffold + build + load 5 service image (Phase 2 / Lab 2)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

docker build -t user-service:v1 ./user-service
docker build -t driver-service:v1 ./driver-service
docker build -t booking-service:v1 ./booking-service
docker build -t payment-service:v1 ./payment-service
docker build -t notification-service:v1 ./notification-service

kind load docker-image user-service:v1 --name grab-mini
kind load docker-image driver-service:v1 --name grab-mini
kind load docker-image booking-service:v1 --name grab-mini
kind load docker-image payment-service:v1 --name grab-mini
kind load docker-image notification-service:v1 --name grab-mini
```

Test 1 service local trước khi đưa vào K8s (đổi tên/port theo service muốn test):

```powershell
docker run --rm -d -p 3003:3003 --name booking-test booking-service:v1
curl -X POST http://localhost:3003/booking -H "Content-Type: application/json" -d '{\"from\":\"A\",\"to\":\"B\"}'
docker stop booking-test
```

**📄 Code liên quan:**

`booking-service/Dockerfile` (giống hệt cho cả 5 service, chỉ đổi `PORT`):

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
ENV PORT=3003
EXPOSE 3003
CMD ["node", "server.js"]
```

`user-service/server.js` (mẫu service đơn giản nhất, route `GET /users`):

```javascript
const PORT = process.env.PORT || 3001;
const VERSION = process.env.VERSION || "v1";

app.get("/health", (req, res) => res.status(200).send("ok"));

app.get("/users", (req, res) => {
  res.json({ service: "user-service", version: VERSION, users: ["alice", "bob"] });
});
```

> Lỗi từng gặp: `package.json` của cả 5 service bị copy-paste nên `name` đều là `"booking-service"` - nhớ sửa lại field `name` cho đúng từng service.

---

<a id="scenario-2"></a>
## Scenario 2 - Deploy + Service + scale test (Phase 3 / Lab 3)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

kubectl apply -f k8s/booking-deployment.yaml
kubectl apply -f k8s/booking-service.yaml
kubectl apply -f k8s/user-deployment.yaml
kubectl apply -f k8s/user-service.yaml
kubectl apply -f k8s/payment-deployment.yaml
kubectl apply -f k8s/payment-service.yaml

kubectl get deploy,pods,svc -l "app in (booking,user,payment)"

# Lab 3 - scale test
kubectl scale deployment booking --replicas=5
kubectl get pods -l app=booking -w
kubectl scale deployment booking --replicas=2
kubectl get pods -l app=booking -w
kubectl scale deployment booking --replicas=3
```

**📄 Code liên quan:**

`k8s/booking-deployment.yaml` (Deployment - 3 replicas, selector `app: booking`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: booking
spec:
  replicas: 3
  selector:
    matchLabels:
      app: booking
  template:
    metadata:
      labels:
        app: booking
    spec:
      containers:
        - name: booking
          image: booking-service:v1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 3003
```

`k8s/booking-service.yaml` (Service ClusterIP, `port 80` → `targetPort 3003`):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: booking-service
spec:
  selector:
    app: booking
  ports:
    - port: 80
      targetPort: 3003
```

`k8s/user-deployment.yaml` / `k8s/payment-deployment.yaml` theo đúng cấu trúc trên, chỉ đổi `name`, `image`, `containerPort` (3001 cho user, 3004 cho payment).

---

<a id="scenario-3"></a>
## Scenario 3 - Service discovery booking → payment (Phase 4 / Lab 4)

`booking-service/server.js` gọi payment qua DNS (`http://payment-service`) - đã sửa sẵn trong code. Rebuild + reload + test:

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

docker build -t booking-service:v1 ./booking-service
kind load docker-image booking-service:v1 --name grab-mini
kubectl rollout restart deployment/booking
kubectl rollout status deployment/booking

# Test end-to-end (port-forward CHỈ dùng cho test đơn giản, không dùng khi rollout đang chạy)
kubectl port-forward svc/booking-service 8080:80
# terminal khác:
curl -X POST http://localhost:8080/booking -H "Content-Type: application/json" -d '{\"from\":\"A\",\"to\":\"B\"}'

# Test load-balancing thật của payment-service (5 replicas) - KHÔNG dùng port-forward/fetch keep-alive
# vì cả 2 đều pin vào 1 connection/pod. Dùng exec + wget (connection mới mỗi lần):
kubectl scale deployment payment --replicas=5
$booking_pod = kubectl get pod -l app=booking -o jsonpath="{.items[0].metadata.name}"
kubectl exec $booking_pod -- sh -c 'for i in $(seq 1 10); do wget -qO- --header="Content-Type: application/json" --post-data="{\"amount\":100}" http://payment-service/payment; echo; done'
```

**📄 Code liên quan:**

`booking-service/server.js` - gọi `payment-service` qua tên DNS của Service, không hard-code IP:

```javascript
app.post("/booking", async (req, res) => {
  const payment = await fetch("http://payment-service/payment", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ amount: 100 }),
  }).then((r) => r.json());

  res.json({ service: "booking-service", version: VERSION, payment });
});
```

`payment-service/server.js` - log `HOSTNAME` (= tên Pod) để thấy rõ load-balancing giữa các replica:

```javascript
app.post("/payment", (req, res) => {
  console.log("handled by pod:", process.env.HOSTNAME);
  res.json({ service: "payment-service", version: VERSION, body: req.body, pod: process.env.HOSTNAME });
});
```

---

<a id="scenario-4"></a>
## Scenario 4 - ConfigMap + Secret (Phase 5)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

kubectl apply -f k8s/booking-configmap.yaml

kubectl create secret generic booking-secret `
  --from-literal=DB_USERNAME=admin `
  --from-literal=DB_PASSWORD=<random>

kubectl rollout restart deployment/booking
kubectl rollout status deployment/booking
kubectl exec -it deploy/booking -- env | Select-String "DB_"
```

> `booking-secret` chỉ tồn tại trong cluster (tạo bằng lệnh imperative) - không commit vào Git/YAML.

**📄 Code liên quan:**

`k8s/booking-configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: booking-config
data:
  DB_HOST: "postgres"
  DB_PORT: "5432"
  DB_NAME: "grabmini"
```

`k8s/booking-deployment.yaml` - wiring ConfigMap + Secret vào container qua `envFrom`:

```yaml
          envFrom:
            - configMapRef:
                name: booking-config
            - secretRef:
                name: booking-secret
```

---

<a id="scenario-5"></a>
## Scenario 5 - Probes + fake failure test (Phase 6 / Lab 5)

`booking-deployment.yaml` đã có `readinessProbe`/`livenessProbe` trỏ `/health`; `server.js` có `/toggle-health`. Áp dụng + test:

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

docker build -t booking-service:v1 ./booking-service
kind load docker-image booking-service:v1 --name grab-mini
kubectl apply -f k8s/booking-deployment.yaml
kubectl rollout status deployment/booking

# --- Test READINESS (mất traffic, KHÔNG restart) ---
kubectl port-forward svc/booking-service 8080:80
# terminal khác:
curl -X POST http://localhost:8080/toggle-health
Start-Sleep -Seconds 15
kubectl get pods -l app=booking          # READY giảm, vd 0/1
kubectl get endpoints booking-service    # pod biến mất khỏi endpoints
curl -X POST http://localhost:8080/toggle-health   # bật lại healthy

# --- Test LIVENESS (restart) ---
curl -X POST http://localhost:8080/toggle-health   # tắt healthy lần nữa
Start-Sleep -Seconds 40                             # đợi qua initialDelay + periodSeconds*failureThreshold
kubectl get pods -l app=booking -w                  # cột RESTARTS tăng
kubectl describe pod -l app=booking | Select-String "Liveness|Restart"
```

**📄 Code liên quan:**

`booking-service/server.js` - `/health` đọc biến `healthy`, `/toggle-health` đảo trạng thái để giả lập sự cố:

```javascript
let healthy = true;
app.get("/health", (req, res) => res.status(healthy ? 200 : 500).send(healthy ? "ok" : "fail"));
app.post("/toggle-health", (req, res) => { healthy = !healthy; res.json({ healthy }); });
```

`k8s/booking-deployment.yaml` - readiness/liveness probe cùng trỏ `/health` nhưng khác timing (readiness phản ứng nhanh hơn liveness):

```yaml
          readinessProbe:
            httpGet:
              path: /health
              port: 3003
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 3003
            initialDelaySeconds: 10
            periodSeconds: 10
```

---

<a id="scenario-6"></a>
## Scenario 6 - Rolling update v1 → v2, zero-downtime (Phase 7 / Lab 6)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

docker build -t booking-service:v2 ./booking-service
kind load docker-image booking-service:v2 --name grab-mini

# Đảm bảo đang ở v1 trước khi test (baseline)
kubectl set image deployment/booking booking=booking-service:v1
kubectl set env deployment/booking VERSION=v1
kubectl rollout status deployment/booking
```

Test zero-downtime - **PHẢI chạy traffic loop + rollout trong CÙNG 1 script/terminal call**
(port-forward pin vào 1 pod và sẽ chết khi pod đó bị rotate giữa rollout → dùng `kubectl exec` + `wget` từ trong 1 pod khác qua Service DNS thay vì port-forward):

```powershell
$pod = kubectl get pod -l app=user -o jsonpath="{.items[0].metadata.name}"

$job = Start-Job -ScriptBlock {
  param($pod)
  kubectl exec $pod -- sh -c 'i=0; while [ $i -lt 150 ]; do i=$((i+1)); OUT=$(wget -qO- --header="Content-Type: application/json" --post-data="{\"from\":\"A\",\"to\":\"B\"}" http://booking-service/booking 2>&1); if [ $? -ne 0 ]; then echo "FAILED: $OUT"; else echo "$OUT"; fi; sleep 0.2; done'
} -ArgumentList $pod

Start-Sleep -Seconds 2
kubectl set image deployment/booking booking=booking-service:v2
kubectl set env deployment/booking VERSION=v2
kubectl rollout status deployment/booking

$result = Receive-Job -Job $job -Wait
$result | Out-File zero-downtime-log.txt

(Select-String -Path zero-downtime-log.txt -Pattern "FAILED").Count                                            # phải = 0
(Select-String -Path zero-downtime-log.txt -Pattern '"service":"booking-service","version":"v1"').Count        # số response v1
(Select-String -Path zero-downtime-log.txt -Pattern '"service":"booking-service","version":"v2"').Count        # số response v2
```

**Kết quả đã verify**: 150/150 request thành công, 0 FAILED, 73 response v1 + 77 response v2 - đúng chuẩn zero-downtime rolling update.

**📄 Code liên quan:**

`booking-service/server.js` - `VERSION` đọc từ biến môi trường, không hard-code, nên `kubectl set env` đổi được version hiển thị ra response mà không cần sửa code:

```javascript
const VERSION = process.env.VERSION || "v1";
...
app.listen(PORT, () => console.log(`booking-service ${VERSION} listening on ${PORT}`));
```

---

<a id="scenario-7"></a>
## Scenario 7 - Rollback khi deploy lỗi (Phase 8)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# Giả lập 1 bản deploy có bug (BUGGY=true khiến /booking luôn trả 500)
docker build -t booking-service:v3 ./booking-service
kind load docker-image booking-service:v3 --name grab-mini
kubectl set image deployment/booking booking=booking-service:v3
kubectl set env deployment/booking VERSION=v3 BUGGY=true
kubectl rollout status deployment/booking --timeout=60s

# Phát hiện lỗi (test qua Service DNS từ 1 pod khác, KHÔNG dùng port-forward)
$pod = kubectl get pod -l app=user -o jsonpath="{.items[0].metadata.name}"
kubectl exec $pod -- sh -c 'wget -qO- --header="Content-Type: application/json" --post-data="{\"from\":\"A\",\"to\":\"B\"}" http://booking-service/booking; echo EXIT:$?'
# -> HTTP 500, EXIT:1

# Rollback - CHÚ Ý: undo mặc định chỉ lùi lại ĐÚNG 1 revision
kubectl rollout undo deployment/booking
kubectl rollout status deployment/booking --timeout=60s
# Kiểm tra lại: image có thể VẪN LÀ v3 (vì set image + set env là 2 revision riêng biệt)
kubectl get deployment booking -o jsonpath="{.spec.template.spec.containers[0].image}"

# Nếu chưa về đúng bản sạch: tìm revision tốt cuối cùng rồi nhảy thẳng tới đó
kubectl rollout history deployment/booking
kubectl rollout history deployment/booking --revision=<N>   # xem chi tiết từng revision
kubectl rollout undo deployment/booking --to-revision=<N>   # rollback đúng revision mong muốn
kubectl rollout status deployment/booking --timeout=60s
kubectl get deployment booking -o jsonpath="{.spec.template.spec.containers[0].image}"   # phải là v2
```

**📄 Code liên quan:**

`booking-service/server.js` - feature-flag `BUGGY` giả lập bug thật (không cần sửa code mỗi lần test, chỉ cần đổi env):

```javascript
const BUGGY = process.env.BUGGY === "true";

app.post("/booking", async (req, res) => {
  if (BUGGY) {
    return res.status(500).json({ service: "booking-service", version: VERSION, error: "internal error" });
  }
  // ... gọi payment-service như bình thường
});
```

> **Bài học quan trọng**: `kubectl set image` và `kubectl set env` chạy riêng lẻ tạo ra **2 revision khác nhau**. `kubectl rollout undo` (không chỉ định `--to-revision`) chỉ lùi lại **đúng 1 revision** - nếu bản lỗi được tạo ra qua nhiều lệnh imperative liên tiếp, 1 lần `undo` có thể chưa về bản sạch hoàn toàn (ví dụ: env đã đúng nhưng image vẫn còn là bản lỗi). Luôn `kubectl rollout history --revision=N` để xác nhận đúng bản muốn quay về, rồi dùng `--to-revision=N` thay vì undo nhiều lần mò mẫm.

---

<a id="scenario-8"></a>
## Scenario 8 - Pod Replacement vs Container Restart (Phase 9)

```powershell
# --- Case A: xoá cả Pod -> ReplicaSet tạo Pod MỚI HOÀN TOÀN (tên khác) ---
kubectl get pods -l app=booking -o wide
kubectl delete pod <ten-pod-cu>
kubectl get pods -l app=booking -o wide   # tên Pod khác, AGE reset về gần 0

# --- Case B: kill process bên trong container qua `kubectl exec` -> KHÔNG có tác dụng! ---
kubectl exec <ten-pod> -- sh -c 'kill 1; echo EXIT:$?'       # SIGTERM -> bị bỏ qua
kubectl exec <ten-pod> -- sh -c 'kill -9 1; echo EXIT:$?'    # SIGKILL -> VẪN bị bỏ qua (xem giải thích bên dưới)
kubectl get pods -l app=booking -o wide   # RESTARTS vẫn = 0, container không hề chết

# --- Case C: kill container từ RUNTIME/HOST (ancestor namespace) -> restart TẠI CHỖ (same Pod name) ---
docker exec grab-mini-control-plane crictl ps | Select-String booking    # tìm containerID
docker exec grab-mini-control-plane crictl stop <containerID>
kubectl get pods -l app=booking -o wide   # RESTARTS tăng lên 1, Pod TÊN KHÔNG ĐỔI, IP không đổi
kubectl describe pod <ten-pod> | Select-String "Restart Count|Started:|Last State" -Context 0,1
```

**📄 Code liên quan:**

`booking-service/Dockerfile` - `node server.js` chạy trực tiếp làm **PID 1**, không qua `tini`/shell wrapper:

```dockerfile
CMD ["node", "server.js"]
```

> **Bài học quan trọng (PID 1 signal nuance)**: theo `man pid_namespaces`, tín hiệu gửi tới PID 1 của 1 PID namespace **từ bên trong chính namespace đó** sẽ bị bỏ qua nếu process không tự đăng ký handler - kể cả **SIGKILL** cũng bị miễn trừ trong trường hợp này. `kubectl exec` chạy BÊN TRONG namespace của container, nên `kill 1`/`kill -9 1` qua `kubectl exec` **không giết được** app Node chạy trực tiếp làm PID 1. Chỉ tín hiệu từ **namespace cha** (container runtime ở host, ví dụ `crictl stop`) mới áp dụng hành vi mặc định và giết được container thật. Ý nghĩa production: luôn dùng `tini`/`dumb-init` làm PID 1, hoặc tự `process.on('SIGTERM', ...)` trong code - nếu không, graceful shutdown sẽ không hoạt động như mong đợi cho tới khi hết `terminationGracePeriodSeconds` và bị SIGKILL cưỡng bức từ host.

---

<a id="scenario-9"></a>
## Scenario 9 - Resource requests/limits + stress test (Phase 10)

```powershell
# --- Bước 1: thêm resources.requests/limits vào Deployment, apply ---
kubectl apply -f k8s/booking-deployment.yaml
kubectl rollout status deployment/booking --timeout=60s
kubectl describe pod -l app=booking | Select-String "Limits:|Requests:|cpu:|memory:"

# --- Bước 2: demo OOMKilled THẬT - memory limit (100Mi) < mức pod cố chiếm (200M) ---
kubectl apply -f k8s/stress-mem.yaml
kubectl get pod stress-mem -w   # chờ STATUS chuyển OOMKilled, exit code 137
kubectl describe pod stress-mem | Select-String "Reason|Exit Code|Limits|Requests" -Context 0,1
kubectl delete pod stress-mem

# --- Bước 3: demo CPU throttling (KHÔNG bị kill, chỉ bị giới hạn tốc độ) ---
kubectl apply -f k8s/stress-cpu.yaml
kubectl get pod stress-cpu            # vẫn Running (CPU vượt limit chỉ bị throttle, không OOMKilled)
kubectl exec stress-cpu -- sh -c "cat /sys/fs/cgroup/cpu.max; echo ---; cat /sys/fs/cgroup/cpu.stat"
kubectl delete pod stress-cpu
```

**📄 Code liên quan:**

`k8s/booking-deployment.yaml` - thêm block `resources` giữa `envFrom` và `readinessProbe`:

```yaml
          envFrom:
            - configMapRef:
                name: booking-config
            - secretRef:
                name: booking-secret
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          readinessProbe:
            ...
```

`k8s/stress-mem.yaml` - pod cố chiếm 200Mi RAM nhưng limit chỉ 100Mi:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: stress-mem
spec:
  restartPolicy: Never
  containers:
    - name: stress
      image: polinux/stress
      resources:
        requests:
          memory: "50Mi"
        limits:
          memory: "100Mi"
      args: ["stress", "--vm", "1", "--vm-bytes", "200M", "--vm-hang", "0", "--timeout", "30s"]
```

`k8s/stress-cpu.yaml` - pod cố dùng 2 core nhưng limit chỉ 200m:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: stress-cpu
spec:
  restartPolicy: Never
  containers:
    - name: stress
      image: polinux/stress
      resources:
        requests:
          cpu: "100m"
        limits:
          cpu: "200m"
      args: ["stress", "--cpu", "2", "--timeout", "60s"]
```

**✅ Kết quả thật đã verify:**

- `stress-mem`: `kubectl describe pod` cho thấy `State: Terminated`, `Reason: OOMKilled`, `Exit Code: 137`, `Limits: memory: 100Mi`, `Requests: memory: 50Mi` - **OOM thật**, không phải giả lập.
- `stress-cpu`: pod vẫn `Running` hết `--timeout 60s` bình thường (không hề bị kill). `cpu.max` bên trong container = `20000 100000` (tức 20ms/100ms period = đúng 200m đã set). `cpu.stat` cho thấy `nr_periods 230`, `nr_throttled 230` (100% period bị throttle), `throttled_usec ~33.4s` - chứng minh CPU vượt limit chỉ bị **throttle (chậm lại)**, khác hẳn hành vi của memory limit (bị **kill**).

> **Bài học quan trọng**: `resources.limits.memory` và `resources.limits.cpu` có **cơ chế enforcement khác nhau**. Memory là tài nguyên không nén được (incompressible) - vượt limit = container bị kernel OOM-killer giết ngay (`OOMKilled`, exit 137). CPU là tài nguyên nén được (compressible) - vượt limit chỉ bị cgroup CFS bandwidth controller **throttle** (process vẫn sống, chỉ chạy chậm lại theo chu kỳ 100ms), không bao giờ bị kill vì CPU vượt limit.

---

<a id="scenario-10"></a>
## Scenario 10 - HorizontalPodAutoscaler (Phase 11)

```powershell
# --- Bước 1: cài metrics-server (kind không có sẵn) ---
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s
kubectl top nodes            # chạy được = metrics-server đã sẵn sàng
kubectl top pods -l app=booking

# --- Bước 2: tạo HPA cho booking, target CPU 50% (so với resources.requests.cpu) ---
kubectl autoscale deployment booking --cpu-percent=50 --min=1 --max=10
kubectl get hpa booking

# --- Bước 3: tạo tải thật từ TRONG cluster để đẩy CPU lên (không dùng port-forward vì nó chỉ pin vào 1 pod) ---
kubectl apply -f k8s/load-gen.yaml
kubectl top pods -l app=booking     # quan sát CPU tăng dần
kubectl get hpa booking -w          # quan sát TARGETS vượt 50%, REPLICAS tăng dần tới 10

# --- Bước 4: ngừng tải, quan sát scale-down (mặc định cần ~5 phút stabilization window) ---
kubectl delete pod load-gen --wait=false
kubectl top pods -l app=booking     # CPU rơi dần về thấp
kubectl get hpa booking -w          # sau vài phút REPLICAS giảm dần về minReplicas (1)
```

**📄 Code liên quan:**

`k8s/load-gen.yaml` - pod sinh tải: 40 vòng lặp song song liên tục gọi `POST /booking` qua Service DNS (load-balance thật qua nhiều booking pod, khác với port-forward chỉ pin 1 pod):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: load-gen
spec:
  restartPolicy: Never
  containers:
    - name: load-gen
      image: curlimages/curl
      command: ["/bin/sh", "-c"]
      args:
        - |
          for i in $(seq 1 40); do
            (while true; do
              curl -s -X POST -H "Content-Type: application/json" \
                -d '{"from":"A","to":"B"}' \
                http://booking-service/booking -o /dev/null
            done) &
          done
          sleep 300
```

**✅ Kết quả thật đã verify:**

- Trước tải: `booking` HPA `cpu: 1%/50%`, REPLICAS = 3 (từ Deployment cũ).
- Sau ~107s có tải: `cpu: 71%/50%`, REPLICAS tăng thật từ 3 → **10** (chạm `maxReplicas`), xác nhận qua `kubectl get pods -l app=booking` thấy 10 pod `Running`.
- Sau khi `kubectl delete pod load-gen`: pod load-gen kẹt ở `Terminating` một lúc rồi mới biến mất hẳn - cùng nguyên nhân PID 1 signal nuance đã gặp ở Phase 9: shell (PID 1) nhận SIGTERM nhưng không forward xuống các tiến trình `curl` chạy nền (`&`), phải đợi hết `terminationGracePeriodSeconds` để kubelet gửi SIGKILL cưỡng bức cả cgroup.
- ~3 phút sau khi tải thật sự dừng hẳn: `cpu: 1%/50%`, HPA tự động scale-down thật từ 10 → **1** (đúng `minReplicas`), xác nhận qua `kubectl get pods -l app=booking` chỉ còn 1 pod.

> **Bài học quan trọng**: HPA mặc định có `stabilizationWindowSeconds: 300` (5 phút) cho **scale-down** để tránh flapping (scale up/down liên tục) - scale-UP phản ứng gần như ngay (trong vài chu kỳ ~15s), nhưng scale-DOWN luôn chậm hơn nhiều, cần kiên nhẫn chờ đủ thời gian trước khi kết luận HPA "không hoạt động". Sau khi bật HPA, `spec.replicas` trong `booking-deployment.yaml` trên đĩa (vẫn ghi `3`) **không còn là nguồn sự thật** cho số pod nữa - HPA Controller ghi đè trực tiếp lên `replicas` của Deployment object mỗi chu kỳ reconcile; muốn biết số pod hiện tại phải `kubectl get hpa`/`kubectl get deployment`, không phải đọc file YAML.

---

<a id="scenario-11"></a>
## Scenario 11 - Graceful Shutdown (Phase 12)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1: rebuild + reload image sau khi thêm /slow + SIGTERM handler vào server.js ---
docker build -t booking-service:v1 ./booking-service
kind load docker-image booking-service:v1 --name grab-mini

# --- Bước 2: apply Deployment đã thêm terminationGracePeriodSeconds + preStop, rollout ---
kubectl apply -f k8s/booking-deployment.yaml
kubectl rollout restart deployment/booking
kubectl rollout status deployment/booking --timeout=60s

# --- Bước 3: lab - gọi /slow (10s) rồi xoá NGAY pod đang xử lý request đó ---
$pod = kubectl get pods -l app=booking -o jsonpath="{.items[0].metadata.name}"
kubectl port-forward pod/$pod 8080:3003   # chạy ở terminal/async riêng, giữ sống

# terminal khác - chạy job + xoá pod gần như đồng thời, ghi kết quả ra file để tránh mất output:
$job = Start-Job {
  $t0 = Get-Date
  try { $body = (Invoke-WebRequest -Uri "http://localhost:8080/slow" -UseBasicParsing -TimeoutSec 25).Content }
  catch { $body = "ERROR: $_" }
  "$body | elapsed=$([math]::Round(((Get-Date)-$t0).TotalSeconds,1))s" | Out-File slow-result.txt -Encoding utf8
}
Start-Sleep -Milliseconds 800
kubectl delete pod $pod --wait=false     # xoá pod khi request mới chạy được ~0.8s / 10s
kubectl get pod $pod -w                  # quan sát Terminating -> biến mất sau ~10s (preStop 5s + chờ request xong)
Get-Content slow-result.txt              # phải in "done after 10s | elapsed=10.1s" - KHÔNG lỗi kết nối
```

**📄 Code liên quan:**

`booking-service/server.js` - thêm endpoint chậm + xử lý SIGTERM đúng cách (dừng nhận request mới, chờ request đang chạy xong rồi mới thoát):

```javascript
app.get("/slow", (req, res) => {
  setTimeout(() => res.send("done after 10s"), 10000);
});

const server = app.listen(PORT, () => console.log(`booking-service ${VERSION} listening on ${PORT}`));

process.on("SIGTERM", () => {
  console.log("SIGTERM received, stop accepting new requests, finish in-flight ones");
  server.close(() => {
    console.log("All connections closed, exiting");
    process.exit(0);
  });
});
```

`k8s/booking-deployment.yaml` - thêm `terminationGracePeriodSeconds` + `preStop` vào `spec.template.spec`:

```yaml
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: booking
          # ... (image, ports, env, envFrom như cũ)
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "sleep 5"]
          resources:
            # ... như cũ
```

**✅ Kết quả thật đã verify:**

- Request `/slow` bắt đầu lúc t=0 (cần 10s để xong). Pod bị `kubectl delete` lúc t≈0.8s. Kết quả: `done after 10s | elapsed=10.1s` - **request vẫn hoàn thành trọn vẹn, không rớt kết nối**, dù pod đã bị đánh dấu xoá gần như ngay từ đầu.
- Theo dõi `kubectl get pod -w` cho thấy pod ở trạng thái `Terminating` liên tục từ t≈0.8s tới khi biến mất hẳn ở t≈10-11s - khớp với lý thuyết: `preStop sleep 5` chạy trước (t=0.8s → t≈5.8s), sau đó mới gửi SIGTERM tới app; app nhận SIGTERM, gọi `server.close()` để ngừng nhận connection mới nhưng vẫn giữ request `/slow` đang chạy tới khi xong (t=10s) rồi mới thoát - tổng thời gian nằm gọn trong `terminationGracePeriodSeconds: 30`.
- Sau khi pod cũ biến mất, ReplicaSet tạo pod mới thay thế ngay (`kubectl get pods -l app=booking` luôn giữ đủ 3/3 Running trong suốt quá trình).

> **Bài học quan trọng**: Chỉ thêm `preStop: sleep 5` thôi KHÔNG đủ để graceful shutdown hoạt động - nếu app không tự bắt `SIGTERM`, Node sẽ dùng default action là thoát ngay lập tức khi nhận SIGTERM (sau khi preStop chạy xong), cắt ngang mọi request đang xử lý dở. Phải tự `process.on('SIGTERM', () => server.close(() => process.exit(0)))` để ĐÌNH NGỪNG nhận connection mới nhưng vẫn cho phép connection/request đang mở hoàn tất trước khi process thoát hẳn. Đây chính là điểm khác với PID 1 signal nuance ở Phase 9: SIGTERM lúc này do kubelet/container runtime gửi từ ngoài container (ancestor namespace), nên được xử lý bình thường - khác với `kubectl exec ... kill 1` gửi từ TRONG container (cùng namespace) vốn bị bỏ qua.

---

<a id="scenario-12"></a>
## Scenario 12 - Ingress + Ingress Controller (Phase 13)

`kind` không hỗ trợ patch `extraPortMappings` vào cluster đang chạy - phải xoá + tạo lại cluster với config có mở port 80/443, nên block này **replay toàn bộ** state cần thiết (ConfigMap/Secret/Deployments/Services/HPA) sau khi tạo lại cluster.

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1: tạo lại cluster với port 80/443 mở ra host ---
kind delete cluster --name grab-mini
kind create cluster --name grab-mini --config kind-config.yaml

# --- Bước 2: nạp lại image (image build cũ trong Docker Desktop vẫn còn, chỉ cache containerd của kind bị xoá) ---
kind load docker-image user-service:v1 --name grab-mini
kind load docker-image payment-service:v1 --name grab-mini
kind load docker-image booking-service:v1 --name grab-mini

# --- Bước 3: replay ConfigMap + Secret + Deployment + Service ---
kubectl apply -f k8s/booking-configmap.yaml
kubectl create secret generic booking-secret `
  --from-literal=DB_USERNAME=admin `
  --from-literal=DB_PASSWORD=<random>

kubectl apply -f k8s/user-deployment.yaml -f k8s/user-service.yaml
kubectl apply -f k8s/payment-deployment.yaml -f k8s/payment-service.yaml
kubectl apply -f k8s/booking-deployment.yaml -f k8s/booking-service.yaml
kubectl rollout status deployment/user --timeout=90s
kubectl rollout status deployment/payment --timeout=90s
kubectl rollout status deployment/booking --timeout=90s

# --- Bước 4: cài ingress-nginx (bundle chính thức cho provider kind) ---
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

# --- Bước 5: apply Ingress, test qua localhost:80 (KHÔNG cần port-forward nữa) ---
kubectl apply -f k8s/ingress.yaml
kubectl get ingress grab-mini-ingress

curl.exe -s http://localhost/users
curl.exe -s -X POST http://localhost/booking -H "Content-Type: application/json" -d '{"from":"A","to":"B"}'
curl.exe -s -X POST http://localhost/payment -H "Content-Type: application/json" -d '{"amount":100}'

# --- Bước 6 (tuỳ chọn): khôi phục lại HPA + metrics-server như trước khi xoá cluster ---
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s
kubectl autoscale deployment booking --cpu-percent=50 --min=1 --max=10
kubectl get hpa
```

**📄 Code liên quan:**

`kind-config.yaml` (mới, tại root `grab-mini/`) - mở port 80/443 từ container node ra host, bắt buộc để `ingress-nginx` nhận traffic từ `localhost`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
      - containerPort: 443
        hostPort: 443
```

`k8s/ingress.yaml` - route `/users`, `/booking`, `/payment` tới đúng Service. **Khác với bản nháp ban đầu trong Roadmap.md**: KHÔNG dùng annotation `nginx.ingress.kubernetes.io/rewrite-target: /`, vì route thật của 3 service này (`GET /users`, `POST /booking`, `POST /payment`) đã trùng khớp chính xác với path của Ingress - nếu rewrite về `/`, request sẽ bị forward sai path và cả 3 service đều trả lỗi/404:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grab-mini-ingress
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /users
            pathType: Prefix
            backend:
              service:
                name: user-service
                port:
                  number: 80
          - path: /booking
            pathType: Prefix
            backend:
              service:
                name: booking-service
                port:
                  number: 80
          - path: /payment
            pathType: Prefix
            backend:
              service:
                name: payment-service
                port:
                  number: 80
```

**✅ Kết quả thật đã verify:**

- `kubectl get ingress grab-mini-ingress` → `CLASS nginx`, `ADDRESS localhost`, `PORTS 80`.
- `curl http://localhost/users` → `{"service":"user-service","version":"v1","users":["alice","bob"]}`.
- `curl -X POST http://localhost/booking ...` → `{"service":"booking-service","version":"v1","payment":{"service":"payment-service",...}}` - tức là Ingress → booking → payment (DNS discovery nội bộ từ Phase 4) vẫn hoạt động xuyên suốt qua layer Ingress mới.
- `curl -X POST http://localhost/payment ...` → `{"service":"payment-service","version":"v1","body":{"amount":100},"pod":"payment-xxxxx"}`.
- Không còn cần `kubectl port-forward` để test từ máy host nữa - Ingress Controller lắng nghe thẳng trên `localhost:80` nhờ `extraPortMappings`.

> **Bài học quan trọng**: `extraPortMappings` là cấu hình **chỉ đặt được lúc tạo cluster** (`kind create cluster --config ...`), không có lệnh `kubectl`/`kind` nào patch thêm port mapping vào cluster đang chạy. Nếu quên khai báo từ đầu, cách duy nhất là xoá cluster và tạo lại - đây cũng là lý do Scenario 12 phải gộp replay toàn bộ ConfigMap/Secret/Deployment/Service/HPA thay vì chỉ 2-3 lệnh liên quan tới Ingress. Ngoài ra, annotation `rewrite-target` của `ingress-nginx` chỉ nên dùng khi path Ingress và path thật của backend **khác nhau** (ví dụ Ingress nhận `/api/v1/users` nhưng backend chỉ hiểu `/users`); dùng nhầm khi 2 path đã khớp sẵn sẽ làm hỏng request thay vì sửa nó.

---

<a id="scenario-13"></a>
## Scenario 13 - PostgreSQL + Persistent Storage (Phase 14)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

kubectl apply -f k8s/postgres.yaml
kubectl rollout status deployment/postgres --timeout=90s
kubectl get pvc
kubectl get pv

# --- Seed data ---
kubectl exec deploy/postgres -- psql -U postgres -d grabmini -c "CREATE TABLE ping(id serial primary key);"
kubectl exec deploy/postgres -- psql -U postgres -d grabmini -c "INSERT INTO ping DEFAULT VALUES;"
kubectl exec deploy/postgres -- psql -U postgres -d grabmini -c "\dt"

# --- Xoá Pod, xác nhận data còn nguyên trên Pod MỚI (tên khác, cùng PVC) ---
$oldPod = kubectl get pod -l app=postgres -o jsonpath="{.items[0].metadata.name}"
kubectl delete pod -l app=postgres
kubectl rollout status deployment/postgres --timeout=60s
$newPod = kubectl get pod -l app=postgres -o jsonpath="{.items[0].metadata.name}"
Write-Host "old=$oldPod new=$newPod"   # tên Pod phải khác nhau

kubectl exec deploy/postgres -- psql -U postgres -d grabmini -c "SELECT * FROM ping;"   # row id=1 phải còn
```

**📄 Code liên quan:**

`k8s/postgres.yaml` - `PersistentVolumeClaim` (dùng StorageClass `standard` có sẵn của `kind`, không cần tự tạo `PersistentVolume`) + Deployment + Service:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - name: POSTGRES_PASSWORD
              value: "<random>"
            - name: POSTGRES_DB
              value: "grabmini"
            # subdir avoids initdb "directory not empty" if the volume root has lost+found
            - name: PGDATA
              value: "/var/lib/postgresql/data/pgdata"
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
```

> `k8s/booking-configmap.yaml` đã có sẵn `DB_HOST: "postgres"` từ Phase 5 - trùng khớp với tên Service ở trên, không cần sửa gì thêm để `booking` có thể resolve DNS tới Postgres (dù `server.js` hiện tại chưa thật sự kết nối DB, chỉ dùng để minh hoạ wiring).

**✅ Kết quả thật đã verify:**

- `kubectl get pvc` → `postgres-pvc` ở trạng thái `Bound`, `STORAGECLASS standard`, `CAPACITY 1Gi`.
- Tạo bảng `ping` + insert 1 row, `kubectl delete pod -l app=postgres` → Pod cũ (`postgres-8bdc6d898-kjq2b`) biến mất, Pod MỚI xuất hiện (`postgres-8bdc6d898-lbskv`, tên khác - giống hành vi Deployment thường ở Phase 9, không phải Pod identity cố định của StatefulSet).
- `SELECT * FROM ping` trên Pod mới vẫn trả về đúng row `id=1` đã insert trước đó - **data sống sót qua Pod replacement** nhờ PVC được re-attach vào Pod mới, không phụ thuộc vòng đời của Pod.

> **Bài học quan trọng**: PVC tách rời vòng đời dữ liệu khỏi vòng đời Pod - khi Pod bị xoá/crash, ReplicaSet tạo Pod mới (tên khác, giống Phase 9), nhưng Pod mới mount lại ĐÚNG PVC cũ nên thấy lại đúng dữ liệu. Đây là khác biệt cốt lõi giữa Stateless (`booking`/`user`/`payment` - mất Pod không sao vì không giữ data) và Stateful (`postgres` - phải có PVC, nếu không mất Pod = mất data). Gotcha cần biết trước: mount PVC thẳng vào `/var/lib/postgresql/data` (root của volume) có thể gây lỗi `initdb: directory ... exists but is not empty` trên một số storage driver tạo sẵn thư mục `lost+found` - set `PGDATA` trỏ vào 1 thư mục con (`/var/lib/postgresql/data/pgdata`) là cách phòng ngừa tiêu chuẩn theo khuyến nghị chính thức của Postgres Docker image, dù `kind`'s `local-path-provisioner` không gặp vấn đề này trong lần test thật.

---

<a id="scenario-14"></a>
## Scenario 14 - Deployment → StatefulSet (Phase 15)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Xoá Deployment-based postgres (PVC + Deployment + Service) của Phase 14 ---
kubectl delete -f k8s/postgres.yaml

# --- Apply bản StatefulSet (headless Service + volumeClaimTemplates) ---
kubectl apply -f k8s/postgres-statefulset.yaml
kubectl rollout status statefulset/postgres --timeout=90s

kubectl get pods -l app=postgres -o wide   # tên Pod CỐ ĐỊNH: postgres-0 (không phải hash random)
kubectl get svc postgres                   # CLUSTER-IP = None (headless)
kubectl get pvc                            # PVC tự tạo tên data-postgres-0 (từ volumeClaimTemplates)

# --- Lab: xoá Pod, xác nhận Pod MỚI quay lại ĐÚNG TÊN CŨ (khác hẳn Deployment ở Scenario 13) ---
kubectl exec postgres-0 -- psql -U postgres -d grabmini -c "CREATE TABLE ping(id serial primary key);"
kubectl exec postgres-0 -- psql -U postgres -d grabmini -c "INSERT INTO ping DEFAULT VALUES;"
kubectl delete pod postgres-0
kubectl rollout status statefulset/postgres --timeout=60s
kubectl get pods -l app=postgres            # vẫn tên postgres-0, chỉ AGE reset
kubectl exec postgres-0 -- psql -U postgres -d grabmini -c "SELECT * FROM ping;"   # row id=1 vẫn còn
```

**📄 Code liên quan:**

`k8s/postgres-statefulset.yaml` - headless Service (`clusterIP: None`) + StatefulSet với `volumeClaimTemplates` (tự tạo 1 PVC riêng cho mỗi Pod, đặt tên theo pattern `<template-name>-<pod-name>`):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  clusterIP: None      # headless Service, cần cho StatefulSet
  selector:
    app: postgres
  ports:
    - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - name: POSTGRES_PASSWORD
              value: "<random>"
            - name: POSTGRES_DB
              value: "grabmini"
            - name: PGDATA
              value: "/var/lib/postgresql/data/pgdata"
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

**✅ Kết quả thật đã verify:**

- `kubectl get pods -l app=postgres` → tên Pod là `postgres-0` (đúng pattern `<statefulset-name>-<ordinal>`, không phải hash ngẫu nhiên như Deployment ở Scenario 13: `postgres-8bdc6d898-xxxxx`).
- `kubectl get svc postgres` → `CLUSTER-IP: None` (headless) - cho phép DNS trả về trực tiếp IP của từng Pod (`postgres-0.postgres.default.svc.cluster.local`) thay vì 1 ClusterIP load-balance chung.
- `kubectl get pvc` → PVC tự động tạo tên `data-postgres-0` (khớp `volumeClaimTemplates[0].metadata.name` + tên Pod), KHÔNG cần tự viết PVC thủ công như Phase 14.
- Tạo bảng `ping` + insert 1 row, `kubectl delete pod postgres-0` → Pod mới xuất hiện sau ít giây với **ĐÚNG TÊN `postgres-0`** (chỉ `AGE` reset về vài giây), khác hẳn hành vi Deployment (tên Pod đổi hoàn toàn mỗi lần xoá, xem Scenario 8 + Scenario 13). `SELECT * FROM ping` trên Pod mới vẫn trả về đúng row `id=1`.

> **Bài học quan trọng**: Đây là khác biệt cốt lõi giữa Deployment và StatefulSet. Deployment quản lý Pod như một **tập hợp các bản sao giống hệt nhau, không có identity** - xoá Pod nào cũng được, ReplicaSet tạo Pod mới với tên ngẫu nhiên mới, PVC (nếu có) được tạo thủ công và share chung giữa các lần thay thế Pod (nhưng không scale tốt với nhiều replica vì `ReadWriteOnce` chỉ 1 Pod mount được). StatefulSet quản lý Pod có **identity ổn định** (`postgres-0`, `postgres-1`, ...) - mỗi Pod có DNS name riêng qua headless Service, và mỗi Pod có PVC RIÊNG tự động tạo từ `volumeClaimTemplates` (quan trọng khi scale nhiều replica, ví dụ Postgres primary-replica hoặc Kafka broker, mỗi Pod cần ổ đĩa riêng không share). Khi xoá Pod, StatefulSet tái tạo lại ĐÚNG ordinal đó với cùng tên + cùng PVC - phù hợp cho workload cần "ordered, stable identity" thay vì chỉ "N bản sao giống nhau" như Deployment.

---

<a id="scenario-15"></a>
## Scenario 15 - Job + CronJob (Phase 16)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Apply CronJob (chạy 00:00 hằng ngày theo schedule, nhưng không cần đợi để test) ---
kubectl apply -f k8s/settlement-cronjob.yaml
kubectl get cronjob settlement-job

# --- Lab: trigger thủ công 1 Job từ CronJob, không cần đợi tới 00:00 ---
kubectl create job settlement-manual --from=cronjob/settlement-job
kubectl get jobs
kubectl get pods -l job-name=settlement-manual
kubectl logs job/settlement-manual
```

**📄 Code liên quan:**

`k8s/settlement-cronjob.yaml` - `CronJob` bọc 1 `Job` template, container chạy xong là thoát (khác hẳn Deployment luôn restart để giữ Pod sống mãi):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: settlement-job
spec:
  schedule: "0 0 * * *"      # chạy 00:00 hằng ngày
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: settlement
              image: booking-service:v1
              imagePullPolicy: IfNotPresent
              command: ["node", "-e", "console.log('running settlement...'); setTimeout(() => console.log('done'), 2000)"]
          restartPolicy: OnFailure
```

**✅ Kết quả thật đã verify:**

- `kubectl apply -f k8s/settlement-cronjob.yaml` → `kubectl get cronjob settlement-job` hiển thị `SCHEDULE: 0 0 * * *`, `SUSPEND: False`, `ACTIVE: 0` (chưa có lần chạy nào theo lịch, vì chưa tới 00:00).
- `kubectl create job settlement-manual --from=cronjob/settlement-job` → tạo Job thủ công dùng ĐÚNG template của CronJob, không cần sửa YAML, không cần đợi lịch.
- `kubectl get jobs` → `settlement-manual` chuyển `STATUS: Running` → `STATUS: Complete`, `COMPLETIONS: 1/1` sau ~6s.
- `kubectl get pods -l job-name=settlement-manual` → Pod ở `STATUS: Completed` (không bị xoá, không bị restart lại - vì `restartPolicy: OnFailure` + Job hoàn thành thành công thì không retry).
- `kubectl logs job/settlement-manual` → in đúng `running settlement...` rồi `done` - xác nhận container thật sự chạy xong rồi thoát, không phải treo mãi như Deployment.

> **Bài học quan trọng**: Job khác Deployment ở chỗ Job coi "container chạy xong rồi exit" là THÀNH CÔNG (không phải crash cần restart) - phù hợp cho batch job chạy 1 lần rồi dừng, thay vì long-running service. CronJob chỉ là lớp lịch (schedule) bọc ngoài Job - `kubectl create job --from=cronjob/<name>` cho phép test ngay logic của Job mà không cần chờ đúng giờ, rất hữu ích để debug trước khi tin tưởng lịch tự động chạy đúng lúc 00:00.

---

<a id="scenario-16"></a>
## Scenario 16 - Multi-node + Node Failure (Phase 17)

`kind` mặc định chỉ tạo 1 node - phải xoá + tạo lại cluster với 3 node (1 control-plane + 2 worker), nên block này **replay toàn bộ** state (giống Scenario 12).

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1: tạo lại cluster với 3 node ---
kind delete cluster --name grab-mini
kind create cluster --name grab-mini --config kind-multi-node.yaml
kubectl get nodes -o wide

# --- Bước 2: nạp lại image vào CẢ 3 node ---
kind load docker-image user-service:v1 --name grab-mini
kind load docker-image payment-service:v1 --name grab-mini
kind load docker-image booking-service:v1 --name grab-mini

# --- Bước 3: replay ConfigMap + Secret + Deployment + Service ---
kubectl apply -f k8s/booking-configmap.yaml
kubectl create secret generic booking-secret --from-literal=DB_USERNAME=admin --from-literal=DB_PASSWORD=<random>
kubectl apply -f k8s/user-deployment.yaml -f k8s/user-service.yaml
kubectl apply -f k8s/payment-deployment.yaml -f k8s/payment-service.yaml
kubectl apply -f k8s/booking-deployment.yaml -f k8s/booking-service.yaml

# --- Bước 4: ingress-nginx - CẦN THÊM nodeSelector ingress-ready (xem "Bài học quan trọng" bên dưới) ---
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=json -p '[{"op":"add","path":"/spec/template/spec/nodeSelector/ingress-ready","value":"true"}]'
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=90s

kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/postgres-statefulset.yaml
kubectl apply -f k8s/settlement-cronjob.yaml

# --- Bước 5: metrics-server + HPA (chạy patch TRỰC TIẾP trong terminal, không qua file .ps1 - xem gotcha bên dưới) ---
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s
kubectl autoscale deployment booking --cpu-percent=50 --min=1 --max=10

# --- Verify: pod trải đều trên worker/worker2, ingress hoạt động ---
kubectl get pods -o wide --sort-by=.spec.nodeName
curl.exe -s http://localhost/users

# --- Lab A: cordon + drain (giả lập bảo trì node, graceful) ---
kubectl cordon grab-mini-worker2
kubectl drain grab-mini-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=90s
kubectl get pods -o wide --sort-by=.spec.nodeName   # toàn bộ Pod trên worker2 chuyển sang worker
curl.exe -s http://localhost/users                   # vẫn hoạt động bình thường trong lúc drain
kubectl uncordon grab-mini-worker2

# --- Lab B: "mất điện thật" - dừng hẳn container node (mạnh tay hơn cordon/drain) ---
docker stop grab-mini-worker
kubectl get nodes -w          # sau ~40-90s: STATUS chuyển NotReady
kubectl get pods -o wide -w   # Pod vẫn "Running" (stale) cho tới khi qua tolerationSeconds mặc định (~5 phút),
                              # rồi chuyển "Terminating" + Pod THAY THẾ xuất hiện trên worker2

# --- Khôi phục ---
docker start grab-mini-worker
kubectl get nodes             # worker Ready trở lại sau ~20-30s
kubectl get pods -o wide --sort-by=.spec.nodeName   # Pod Terminating "kẹt" tự dọn sạch; postgres-0 reschedule lại ĐÚNG node worker
```

**📄 Code liên quan:**

`kind-multi-node.yaml` (mới, tại root `grab-mini/`) - 1 control-plane (giữ nguyên `extraPortMappings` 80/443 + nhãn `ingress-ready=true` từ Phase 13) + 2 worker:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
      - containerPort: 443
        hostPort: 443
  - role: worker
  - role: worker
```

`k8s/settlement-cronjob.yaml`, `k8s/postgres-statefulset.yaml`, `k8s/ingress.yaml` - giữ nguyên từ Phase 14-16, không cần sửa gì để chạy multi-node.

**✅ Kết quả thật đã verify:**

- `kubectl get pods -o wide` sau khi replay → Pod của `booking`/`payment`/`user`/`postgres` tự động trải đều trên **2 worker node** (scheduler mặc định không đặt lên `control-plane` vì node này có taint `NoSchedule` khi cluster có nhiều node - khác hẳn single-node trước đây, nơi `kind` tự gỡ taint để control-plane nhận luôn Pod).
- **Lab A (cordon + drain)**: `kubectl drain grab-mini-worker2` evict sạch toàn bộ Pod (bao gồm cả `metrics-server` tình cờ nằm trên đó) → Pod mới xuất hiện ngay trên `grab-mini-worker` còn lại, app vẫn trả lời `curl http://localhost/users` bình thường trong suốt quá trình - đúng chuẩn bảo trì node graceful, zero-downtime ở tầng ứng dụng.
- **Lab B (docker stop thật)**: `docker stop grab-mini-worker` lúc `02:16:59` → node chuyển `NotReady` trong vòng ~90s (khớp `node-monitor-grace-period` mặc định) → nhưng Pod vẫn báo `Running` (trạng thái cũ, API server không còn nhận heartbeat để cập nhật) cho tới đúng **~5 phút 44 giây sau** (`02:22:43`) mới đồng loạt chuyển `Terminating` và có Pod THAY THẾ chạy ngay trên `grab-mini-worker2` - khớp chính xác với `tolerationSeconds` mặc định (300s) của taint `node.kubernetes.io/not-ready` tự động gắn vào mọi Pod.
- **Phát hiện quan trọng về `postgres-0` (StatefulSet)**: khi `grab-mini-worker` down, `postgres-0` cũng bị đánh dấu `Terminating` giống các Pod khác, NHƯNG **không có Pod thay thế nào được tạo** trên `worker2` (khác hẳn `booking`/`payment`/`user`) - vì PVC `data-postgres-0` được `local-path-provisioner` của `kind` gắn `nodeAffinity` cố định vào ĐÚNG node đã tạo ra nó (`grab-mini-worker`), dữ liệu nằm trực tiếp trên đĩa local của node đó, không phải shared storage. Pod `postgres-0` kẹt `Terminating` vô thời hạn cho tới khi `docker start grab-mini-worker` đưa node cũ trở lại - lúc đó Pod `postgres-0` mới thực sự bị xoá rồi StatefulSet tạo lại ĐÚNG node đó (vì nodeAffinity bắt buộc), data không mất.
- Sau `docker start grab-mini-worker` (~20-30s để kubelet rejoin): node `Ready` trở lại, toàn bộ Pod `Terminating` "kẹt" tự dọn sạch, `postgres-0` tái tạo thành công, `curl http://localhost/users` và `/booking` hoạt động bình thường trở lại.

> **Bài học quan trọng #1 (gotcha mới phát hiện)**: Bundle `ingress-nginx` chính thức cho provider `kind` **không còn** `nodeSelector: ingress-ready: "true"` trong bản tải về thực tế lúc test (chỉ còn `nodeSelector: {kubernetes.io/os: linux}` + `tolerations` cho phép chạy trên control-plane, nhưng KHÔNG ép buộc). Với cluster nhiều node, scheduler có thể đặt `ingress-nginx-controller` lên BẤT KỲ node nào (kể cả worker) - nếu rơi vào worker, `curl http://localhost` sẽ bị `Empty reply from server` vì chỉ container `control-plane` có `extraPortMappings` 80/443 map ra host. Cách sửa: tự `kubectl patch` thêm `nodeSelector.ingress-ready: "true"` vào Deployment `ingress-nginx-controller` sau khi cài - ép Pod chỉ chạy trên node có nhãn đó (chỉ control-plane có nhãn này, đặt qua `kubeadmConfigPatches` trong `kind-multi-node.yaml`).
>
> **Bài học quan trọng #2 (gotcha PowerShell)**: lệnh `kubectl patch ... --type=json -p '[...]'` chạy BÊN TRONG 1 file `.ps1` gọi qua `powershell -File` có thể báo lỗi `"The request is invalid: the server rejected our request due to an error in our request"` (patch không áp dụng, im lặng bỏ qua) dù CÙNG lệnh đó chạy trực tiếp trong terminal thì thành công - nghi ngờ do cách `powershell -File` xử lý escaping dấu nháy đơn/kép khác với phiên terminal tương tác. Luôn `kubectl get deployment ... -o jsonpath='{.spec.template.spec.containers[0].args}'` để xác nhận patch thật sự áp dụng, và nếu nghi ngờ, chạy lại lệnh patch trực tiếp trong terminal thay vì qua script file.
>
> **Bài học quan trọng #3 (kiến trúc)**: Node failure test này là bằng chứng sống cho thấy **Stateless (Deployment) và Stateful (StatefulSet + local storage) phản ứng hoàn toàn khác nhau khi mất node**. Stateless tự phục hồi nhanh trên node khác vì không có ràng buộc nào ngoài image. Stateful với local storage (như `local-path-provisioner` của `kind`) bị khoá cứng vào 1 node vật lý - mất node đó nghĩa là service "đứng hình" (không tự chuyển node được) cho tới khi node hồi phục, dù data không mất. Đây chính là động lực thực tế để dùng replicated storage (Ceph, Longhorn, EBS multi-AZ, v.v.) hoặc Postgres replication (primary-replica) trong production thay vì local storage cho dữ liệu quan trọng.

---

<a id="scenario-17"></a>
## Scenario 17 - topologySpreadConstraints: spread Pod đều qua node (Phase 18)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Thêm topologySpreadConstraints vào booking/payment/user Deployment, apply + restart ---
kubectl apply -f k8s/booking-deployment.yaml -f k8s/payment-deployment.yaml -f k8s/user-deployment.yaml
kubectl rollout restart deployment/booking deployment/payment deployment/user
kubectl rollout status deployment/payment --timeout=60s
kubectl rollout status deployment/user --timeout=60s
kubectl rollout status deployment/booking --timeout=60s

# --- Verify: Pod trải đều (maxSkew 1) qua grab-mini-worker / grab-mini-worker2 ---
kubectl get pods -o wide --sort-by=.spec.nodeName

# --- Nếu có Pod kẹt Pending vĩnh viễn (xem "Bài học quan trọng" bên dưới), dọn ReplicaSet mồ côi đó ---
kubectl get rs -l 'app in (user,payment,booking)'   # tìm RS desired=1, READY=0, age lệch hẳn so với RS đang chạy 3/3/3
kubectl delete rs <ten-rs-ket-pending>
```

**📄 Code liên quan:** thêm vào `spec.template.spec` của `k8s/booking-deployment.yaml`, `k8s/payment-deployment.yaml`, `k8s/user-deployment.yaml`:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    nodeTaintsPolicy: Honor
    labelSelector:
      matchLabels:
        app: payment   # đổi theo từng Deployment: booking / payment / user
```

**✅ Kết quả thật đã verify:**

- **Trước khi sửa**: toàn bộ 7 Pod ứng dụng (`booking` x1 do HPA scale xuống, `payment` x3, `user` x3) đều nằm dồn hết trên MỘT node (`grab-mini-worker2`), `grab-mini-worker` chỉ có `postgres-0` + Job - dù cluster có 2 worker node, scheduler mặc định (ưu tiên cân bằng tài nguyên, không phải số lượng Pod cùng app) không tự trải đều.
- Sau khi thêm `topologySpreadConstraints` + apply + `rollout restart`: cả 3 Deployment trải đúng maxSkew=1 - `payment` 2 (`worker`) / 1 (`worker2`), `user` 1 (`worker`) / 2 (`worker2`), `booking` 2 (`worker`) / 1 (`worker2`) - xác nhận qua `kubectl get pods -o wide --sort-by=.spec.nodeName`.

> **Bài học quan trọng (gotcha mới phát hiện)**: thêm `topologySpreadConstraints` KHÔNG kèm `nodeTaintsPolicy: Honor` làm `rollout restart` bị TREO vĩnh viễn - Pod surge mới báo `FailedScheduling`: `"2 node(s) didn't match pod topology spread constraints"` dù cluster chỉ có đúng 2 node khả dụng (`grab-mini-control-plane` bị taint `NoSchedule`, Pod không tolerate). Nguyên nhân: mặc định, `topologySpreadConstraints` tính độ lệch (skew) qua **TẤT CẢ** node khớp `topologyKey`, kể cả node bị taint không thể nhận Pod - `control-plane` luôn có 0 Pod `app: payment`, trong khi 2 worker có 2 và 1 → skew = 2-0 = 2, VĨNH VIỄN vi phạm `maxSkew: 1` dù phân bổ giữa 2 worker thực tế đã hoàn hảo. Thêm `nodeTaintsPolicy: Honor` để loại trừ node có taint không được tolerate ra khỏi phép tính skew. Hệ quả phụ cần biết: vì `labelSelector` khớp theo label Pod (`app: payment`) xuyên suốt MỌI ReplicaSet (cũ lẫn mới), một `whenUnsatisfiable: DoNotSchedule` bị kẹt như trên để lại 1 ReplicaSet mồ côi `desired=1` không bao giờ schedule được - `kubectl scale rs ... --replicas=0` KHÔNG đủ (Deployment controller tự đặt lại =1 ngay), phải `kubectl delete rs <ten-rs>` hẳn để dọn sạch.

---

<a id="scenario-18"></a>
## Scenario 18 - High Availability: PodAntiAffinity + PDB + failover nhanh (Phase 19)

Phase 18 đã giải quyết "trải đều Pod" bằng `topologySpreadConstraints`. Phase 19 bổ sung 3 lớp HA còn thiếu: **(A)** hiểu `podAntiAffinity` (hard vs soft), **(B)** `PodDisruptionBudget` giữ app sống khi bảo trì node, **(C)** rút ngắn thời gian failover khi node chết thật (Phase 17 đo được ~5 phút 44 giây).

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Lab A: REQUIRED (hard) anti-affinity trên payment (3 replicas, chỉ có 2 worker) - DEMO, sẽ gỡ sau ---
# dùng --patch-file thay vì -p '...' để tránh lỗi escaping JSON của PowerShell (xem gotcha Scenario 16)
kubectl patch deployment payment --patch-file k8s/patches/payment-anti-affinity-required.yaml
kubectl rollout status deployment/payment --timeout=60s     # -> TIMEOUT: rollout kẹt vĩnh viễn (deadlock)
kubectl get pods -l app=payment -o wide                      # 3 Pod cũ Running + 1 Pod mới Pending
kubectl describe pod <pod-pending> | Select-String FailedScheduling
# -> "1 node(s) didn't match pod anti-affinity rules, 1 node(s) didn't match pod topology spread constraints, 1 node(s) had untolerated taint(s)"

# Xoá RS cũ để xem trường hợp "deploy mới tinh" với required anti-affinity
kubectl delete rs <payment-rs-cu>
kubectl get pods -l app=payment -o wide                      # 2 Running (1/node) + 1 Pending VĨNH VIỄN

# --- Gỡ required, chuyển sang cấu hình cuối (preferred anti-affinity + tolerations + PDB) ---
kubectl apply -f k8s/payment-deployment.yaml                 # CHÚ Ý: apply KHÔNG gỡ được required (xem gotcha #2)
kubectl get deploy payment -o jsonpath='{.spec.template.spec.affinity}'   # vẫn còn required!
kubectl patch deployment payment --type=json --patch-file k8s/patches/payment-anti-affinity-remove-required.json
kubectl get rs -l app=payment                                # nếu vẫn kẹt: xoá MỌI RS còn chứa required (xem gotcha #3)
kubectl delete rs <rs-con-required-1> <rs-con-required-2>
kubectl rollout status deployment/payment --timeout=90s

kubectl apply -f k8s/booking-deployment.yaml -f k8s/user-deployment.yaml -f k8s/pdb.yaml
kubectl patch hpa booking --patch-file k8s/patches/hpa-booking-min2.yaml   # HA cần tối thiểu 2 replica
kubectl get pdb,hpa

# --- Lab B1: PDB quá chặt (maxUnavailable 0) -> drain BỊ CHẶN ---
kubectl patch pdb user-pdb --type=merge --patch-file k8s/patches/pdb-user-strict.yaml
kubectl drain grab-mini-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=30s
# -> booking/payment evict OK, nhưng 2 Pod user: "global timeout reached: 30s" (PDB không cho evict)
kubectl apply -f k8s/pdb.yaml                                # trả về maxUnavailable: 1
kubectl uncordon grab-mini-worker2

# --- Lab B2: PDB hợp lý + drain trong lúc có traffic liên tục ---
# terminal 1: traffic loop (GET /users + POST /booking qua Ingress, mỗi 100ms)
1..300 | ForEach-Object {
  try { Invoke-WebRequest http://localhost/users -UseBasicParsing -TimeoutSec 10 | Out-Null } catch { Write-Host "$(Get-Date -f T) FAILED /users" }
  try { Invoke-WebRequest http://localhost/booking -Method POST -Body '{"from":"A"}' -ContentType "application/json" -UseBasicParsing -TimeoutSec 10 | Out-Null } catch { Write-Host "$(Get-Date -f T) FAILED /booking" }
  Start-Sleep -Milliseconds 100
}
# terminal 2:
kubectl drain grab-mini-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=90s
# -> "Cannot evict pod as it would violate the pod's disruption budget" (retry 5s) cho Pod thứ 2 của user/payment, rồi drained
kubectl uncordon grab-mini-worker2
kubectl rollout restart deployment/booking deployment/payment deployment/user   # uncordon KHÔNG tự trả Pod về node cũ

# --- Lab C: node chết thật với tolerationSeconds: 30 (thay vì 300 mặc định) ---
kubectl get pods -o wide --sort-by=.spec.nodeName            # chọn node KHÔNG chứa postgres-0 (ở đây: worker2)
# terminal 1: chạy lại traffic loop ở trên
# terminal 2: timeline
docker stop grab-mini-worker2
kubectl get nodes -w                                         # ~50s: NotReady
kubectl get pods -o wide -w                                  # ~30s SAU NotReady: Terminating + Pod mới trên worker
kubectl get endpointslices -l kubernetes.io/service-name=user-service -w

# --- Khôi phục + cân bằng lại ---
docker start grab-mini-worker2
kubectl wait --for=condition=Ready node/grab-mini-worker2 --timeout=120s
kubectl rollout restart deployment/booking deployment/payment deployment/user
kubectl get pods -o wide --sort-by=.spec.nodeName
```

**📄 Code liên quan:**

`k8s/patches/payment-anti-affinity-required.yaml` (mới - chỉ dùng cho Lab A):

```yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: payment
              topologyKey: kubernetes.io/hostname
```

`k8s/patches/payment-anti-affinity-remove-required.json` (mới):

```json
[{"op":"remove","path":"/spec/template/spec/affinity/podAntiAffinity/requiredDuringSchedulingIgnoredDuringExecution"}]
```

`k8s/patches/hpa-booking-min2.yaml` / `k8s/patches/pdb-user-strict.yaml` (mới):

```yaml
spec:
  minReplicas: 2        # hpa-booking-min2.yaml
---
spec:
  maxUnavailable: 0     # pdb-user-strict.yaml - CHỈ để demo drain bị chặn
```

`k8s/booking-deployment.yaml`, `k8s/payment-deployment.yaml`, `k8s/user-deployment.yaml` - thêm vào `spec.template.spec` (giữ nguyên `topologySpreadConstraints` của Phase 18):

```yaml
      # Phase 19: failover nhanh khi node chết (mặc định 300s)
      tolerations:
        - key: node.kubernetes.io/not-ready
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30
        - key: node.kubernetes.io/unreachable
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30
```

Riêng `k8s/payment-deployment.yaml` thêm soft anti-affinity (ví dụ học - `booking`/`user` không cần vì `topologySpreadConstraints` đã đủ):

```yaml
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: payment
                topologyKey: kubernetes.io/hostname
```

`k8s/pdb.yaml` (mới):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: booking-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: booking
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: payment-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: payment
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: user-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: user
```

**✅ Kết quả thật đã verify (10/11/2026):**

- **Lab A (required anti-affinity)**: `rollout status` timeout - Pod surge mới `Pending` với `didn't match pod anti-affinity rules`, vì 3 Pod CŨ (cùng label `app: payment`) đã chiếm cả 2 worker, và `maxUnavailable: 25%` của 3 replica làm tròn xuống = 0 nên Deployment không được phép xoá Pod cũ trước → **deadlock**. Sau khi xoá RS cũ: đúng **2 Running (1/worker) + 1 Pending vĩnh viễn** → với required anti-affinity theo `hostname`, **số replica tối đa = số node khả dụng**. Thêm chi tiết: Pod cũ đang `Terminating` (grace 30s) VẪN được tính vào anti-affinity - Pod mới chỉ schedule được sau khi Pod cũ biến mất hẳn.
- **Lab B1 (PDB `maxUnavailable: 0`)**: `kubectl drain` evict xong `booking`/`payment` nhưng 2 Pod `user` báo `global timeout reached: 30s` - PDB chặn eviction hoàn toàn, node kẹt ở trạng thái cordoned.
- **Lab B2 (PDB `maxUnavailable: 1` + traffic)**: drain thấy rõ PDB hoạt động - `Cannot evict pod as it would violate the pod's disruption budget` (retry sau 5s) cho Pod thứ 2 của `user` và `payment`, chỉ evict tiếp khi Pod thay thế đã Ready. Kết quả traffic: **188/188 request thành công, 0 FAILED**. Sau drain, mọi Pod dồn về `worker` (đúng: node cordoned có taint `unschedulable`, bị loại khỏi phép tính skew nhờ `nodeTaintsPolicy: Honor`); `uncordon` không tự kéo Pod về - phải `rollout restart`.
- **Lab C (`docker stop grab-mini-worker2`, `tolerationSeconds: 30`)** - timeline thật:

  | Thời điểm | Sự kiện |
  |---|---|
  | 07:00:34 | `docker stop grab-mini-worker2` (đang giữ 2/3 Pod của mỗi service) |
  | 07:01:25 (+51s) | node `NotReady`, endpoint Pod trên worker2 bị gỡ khỏi Service (user: 3 → 1 endpoint ready) |
  | 07:01:53 (+79s) | Pod cũ `Terminating`, Pod thay thế `ContainerCreating` trên `worker` (~28s sau NotReady ≈ `tolerationSeconds: 30`) |
  | 07:01:56 (+82s) | đủ 9/9 Pod Running, user: 3 endpoint ready |

  → Failover giảm từ **~5 phút 44 giây (Phase 17) xuống ~82 giây**. Traffic: **317 OK / 5 FAILED** - cả 5 lỗi đều nằm trong khoảng 51s TRƯỚC khi node NotReady (07:00:45 → 07:01:17): 3 lần `000` (timeout 10s - nginx vẫn gửi request tới IP Pod đã chết) và 2 lần `/booking` `500` (booking gọi `payment-service` trúng Pod payment đã chết, `fetch` lỗi → 500 vì chưa có retry/error handling). Sau NotReady: 0 lỗi.
- Sau `docker start grab-mini-worker2`: node Ready lại, Pod `Terminating` trên worker2 tự dọn, `postgres-0` (ở `worker`) không bị ảnh hưởng, `curl http://localhost/users` bình thường.

> **Bài học quan trọng #1 - required anti-affinity là "con dao 2 lưỡi"**: `requiredDuringScheduling` + `topologyKey: hostname` = cam kết cứng "mỗi node tối đa 1 Pod". Với số replica ≥ số node: (1) Pod thừa `Pending` vĩnh viễn, (2) rolling update **deadlock** vì Pod surge không có chỗ, (3) HPA scale-up cũng vô dụng. Production: chỉ dùng required khi replicas < số node chắc chắn (vd. 3 replica etcd/Kafka trên ≥ 3 node/zone); còn lại dùng `preferred` hoặc `topologySpreadConstraints` (`maxSkew`) như Phase 18.
>
> **Bài học quan trọng #2 - `kubectl apply` không gỡ field được thêm bằng `kubectl patch`**: apply dùng three-way merge dựa trên annotation `kubectl.kubernetes.io/last-applied-configuration`. Field `required...` được thêm bằng `patch` không có trong annotation đó → apply coi nó là "của người khác", giữ nguyên. Kết quả: object chứa CẢ preferred (từ file) LẪN required (từ patch). Luôn kiểm tra lại bằng `-o jsonpath` sau khi revert, và gỡ bằng JSON patch `op: remove` (hoặc `kubectl replace -f`).
>
> **Bài học quan trọng #3 - anti-affinity có tính ĐỐI XỨNG**: dù Pod mới chỉ có `preferred`, nó vẫn `Pending` với lý do `didn't satisfy existing pods anti-affinity rules` - các Pod CŨ đang chạy mang rule `required` "đẩy" mọi Pod có label `app: payment` ra khỏi node của chúng. Phải xoá hết RS còn mang rule required (chấp nhận gián đoạn ngắn) thì RS mới mới scale lên được.
>
> **Bài học quan trọng #4 - PDB chỉ bảo vệ "voluntary disruption"**: PDB chặn `drain`/eviction API (bảo trì, nâng cấp node, Cluster Autoscaler scale-down), KHÔNG chặn được node chết thật (Lab C). Kết hợp PDB với HPA phải cẩn thận: HPA `minReplicas: 1` + PDB `minAvailable: 1` → khi HPA scale về 1, drain bị chặn vĩnh viễn → đã nâng HPA booking lên `minReplicas: 2`.
>
> **Bài học quan trọng #5 - `tolerationSeconds` chỉ rút ngắn được nửa sau của failover**: khoảng ~50s đầu (từ lúc node chết tới `NotReady`, quyết định bởi `node-monitor-grace-period` của controller-manager) Service VẪN gửi traffic tới Pod đã chết, vì readiness probe do kubelet trên chính node đó chạy - node chết thì không ai báo Pod "not ready". 5 request lỗi duy nhất đều rơi vào khoảng này. Muốn 0 lỗi cả khi node chết thật cần thêm ở tầng ứng dụng/proxy: timeout ngắn + retry (vd. `booking` retry khi gọi `payment` thất bại, ingress-nginx `proxy-next-upstream`/`proxy-connect-timeout` ngắn), hoặc service mesh có outlier detection.

---

<a id="scenario-19"></a>
## Scenario 19 - NetworkPolicy: zero-trust trong namespace (Phase 20)

**Không cần tạo lại cluster**: Roadmap ban đầu ghi phải `disableDefaultCNI: true` + Calico vì `kindnet` không hỗ trợ NetworkPolicy - điều này **đã lỗi thời** từ `kind` v0.24. Cluster hiện tại (`kind` v0.33, `kindnetd:v20260820`) thực thi policy ngay → giữ nguyên cluster, data Postgres, PDB, HPA của các scenario trước.

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini
kind version
kubectl get ds kindnet -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# --- Bước 0: baseline TRƯỚC khi có policy (cả 3 phải CONNECTED) ---
# script test TCP bằng node (có sẵn trong image app); in ALLOWED / BLOCKED
# ('' = 1 dấu nháy đơn trong chuỗi PowerShell; KHÔNG dùng \" - PowerShell 7 truyền nguyên \" vào node -> lỗi cú pháp JS)
$T = 'const [h,p]=process.argv.slice(1);const s=require(''net'').connect(+p,h);s.setTimeout(3000);s.on(''connect'',()=>{console.log(''ALLOWED'');process.exit(0)});s.on(''timeout'',()=>{console.log(''BLOCKED'');process.exit(0)})'
foreach ($d in "user","booking","payment") { "$d -> postgres: " + (kubectl exec deploy/$d -- node -e $T postgres 5432) }

# --- Bước 1: chỉ booking + payment được vào postgres ---
kubectl apply -f k8s/netpol-postgres.yaml
foreach ($d in "user","booking","payment") { "$d -> postgres: " + (kubectl exec deploy/$d -- node -e $T postgres 5432) }
# -> user BLOCKED, booking/payment ALLOWED
kubectl run np-test --rm -i --restart=Never --image=postgres:16-alpine --command -- sh -c 'timeout 4 pg_isready -h postgres; echo exit=$?'
# -> "no response" - Pod không có label app=booking/payment cũng bị chặn

# --- Bước 2: default-deny toàn namespace -> mọi thứ chết (kể cả Ingress) ---
kubectl apply -f k8s/netpol-default-deny.yaml
curl.exe -s -o NUL -w "%{http_code} %{time_total}s`n" --max-time 15 http://localhost/users    # -> 000 15s (timeout)
kubectl get pods -l 'app in (booking,payment,user)'   # sau >1 phút vẫn 1/1 Ready, RESTARTS 0 -> probe kubelet KHÔNG bị chặn

# --- Bước 3: mở từng đường cần thiết ---
kubectl apply -f k8s/netpol-allow.yaml
kubectl get netpol
curl.exe -s http://localhost/users
curl.exe -s -X POST http://localhost/booking -H "Content-Type: application/json" -d '{"from":"A"}'   # booking -> payment vẫn OK

# --- Bước 4: ma trận kiểm tra pod -> pod ---
$cases = @("booking payment-service 80","user payment-service 80","user booking-service 80","payment booking-service 80",
           "booking postgres 5432","payment postgres 5432","user postgres 5432","booking user-service 80")
foreach ($c in $cases) { $a = $c.Split(" "); "$($a[0]) -> $($a[1]):$($a[2]) : " + (kubectl exec deploy/$($a[0]) -- node -e $T $a[1] $a[2]) }

# --- Bước 5: thứ khác không bị ảnh hưởng ---
kubectl top pods          # metrics-server scrape kubelet, không đi qua Pod -> vẫn chạy
kubectl get hpa booking
kubectl rollout restart deployment/payment; kubectl rollout status deployment/payment
# Pod mới vẫn bị policy áp dụng (policy chọn theo label, không theo tên Pod)
```

**📄 Code liên quan:**

`k8s/netpol-postgres.yaml` (mới):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-booking-payment-to-postgres
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: booking
        - podSelector:
            matchLabels:
              app: payment
      ports:
        - protocol: TCP
          port: 5432
```

`k8s/netpol-default-deny.yaml` (mới):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

`k8s/netpol-allow.yaml` (mới):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx-to-apps
spec:
  podSelector:
    matchExpressions:
      - key: app
        operator: In
        values: ["user", "booking", "payment"]
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
          podSelector:
            matchLabels:
              app.kubernetes.io/component: controller
      ports:
        - protocol: TCP
          port: 3001
        - protocol: TCP
          port: 3003
        - protocol: TCP
          port: 3004
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-booking-to-payment
spec:
  podSelector:
    matchLabels:
      app: payment
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: booking
      ports:
        - protocol: TCP
          port: 3004
```

**✅ Kết quả thật đã verify (10/11/2026):**

- Baseline: `user`/`booking`/`payment` → `postgres:5432` đều `CONNECTED`.
- Sau `netpol-postgres.yaml`: `user` → `TIMEOUT` (packet bị **DROP** im lặng, không phải `ECONNREFUSED`), `booking`/`payment` → `CONNECTED`; Pod tạm `np-test` (không có label) → `pg_isready: no response`.
- Sau `netpol-default-deny.yaml`: `GET /users` và `POST /booking` qua Ingress → `000` sau đúng 15s (timeout). Sau hơn 1 phút: tất cả Pod vẫn `1/1 Ready`, `RESTARTS 0`, không có event `Unhealthy` mới → readiness/liveness probe của kubelet KHÔNG bị chặn.
- Sau `netpol-allow.yaml`: 3 route Ingress trả 200, chain `booking → payment` qua Ingress OK. Ma trận pod → pod:

  | Từ → Tới | Kết quả |
  |---|---|
  | booking → payment-service:80 | ✅ ALLOWED |
  | booking → postgres:5432 | ✅ ALLOWED |
  | payment → postgres:5432 | ✅ ALLOWED |
  | user → payment-service:80 | ⛔ BLOCKED |
  | user → booking-service:80 | ⛔ BLOCKED |
  | payment → booking-service:80 | ⛔ BLOCKED |
  | user → postgres:5432 | ⛔ BLOCKED |
  | booking → user-service:80 | ⛔ BLOCKED |

- `kubectl top pods` + HPA (`cpu: 6%/50%`) vẫn hoạt động; `rollout restart deployment/payment` → Pod mới vẫn chặn `user` như cũ.

> **Bài học quan trọng #1 - NetworkPolicy "im lặng" khi CNI không hỗ trợ**: API server luôn nhận `kubectl apply` NetworkPolicy thành công bất kể CNI có thực thi hay không - policy chỉ là dữ liệu, CNI mới là thứ chặn packet. Vì vậy **luôn đo baseline trước** (Bước 0) rồi đo lại sau khi apply; nếu không có baseline, không phân biệt được "bị policy chặn" với "app lỗi/DNS sai". Đây cũng là lý do ghi chú "phải cài Calico" trong Roadmap cũ không gây lỗi rõ ràng nếu bỏ qua - chỉ làm policy vô tác dụng.
>
> **Bài học quan trọng #2 - `ports` trong policy là port của CONTAINER**: policy đánh giá packet SAU khi kube-proxy đã DNAT từ ClusterIP:80 sang PodIP:targetPort, nên phải khai báo `3001/3003/3004`, không phải `80` của Service - dù client gọi `http://payment-service` (port 80).
>
> **Bài học quan trọng #3 - AND vs OR trong `from`**: `namespaceSelector` + `podSelector` nằm **cùng 1 phần tử** (`- namespaceSelector: ... podSelector: ...`) = AND (đúng namespace VÀ đúng Pod). Nếu tách thành 2 phần tử (`- namespaceSelector: ...` và `- podSelector: ...`) = OR → `podSelector` khi đó chỉ khớp Pod trong namespace CỦA POLICY, ngữ nghĩa khác hẳn. (Lý thuyết - không demo được khác biệt trên cluster này vì namespace `default` không có Pod mang label `component: controller`.)
>
> **Bài học quan trọng #4 - traffic từ node không bị chặn**: probe của kubelet và metrics-server (scrape kubelet trên node) đều xuất phát từ host network của node, phần lớn CNI (bao gồm kindnet) cho phép mặc định → default-deny không làm Pod restart. Nhưng workload chạy **trong Pod** ở namespace khác (Prometheus ở Phase 21, Argo CD...) SẼ bị chặn - phải thêm policy allow từ namespace đó.
>
> **Khi tạo lại cluster**: xem [🔁 Dựng lại toàn bộ cluster](#rebuild).

---

<a id="scenario-20"></a>
## Scenario 20 - Observability: Prometheus + Grafana + app metrics (Phase 21)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1: cài kube-prometheus-stack (pin version để replay được) ---
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 93.1.1 `
  -n monitoring --create-namespace -f k8s/monitoring/values.yaml --wait --timeout 10m
kubectl get pods -n monitoring

# Xem target health KHÔNG cần port-forward: đi qua API server proxy
$P = "/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy"
kubectl get --raw "$P/api/v1/targets?state=active" | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)"' | Sort-Object | Group-Object | ForEach-Object { "$($_.Count) $($_.Name)" }

# --- Bước 2: app metrics (prom-client) - rebuild + load + rollout ---
foreach ($s in "booking","payment","user") {
  Push-Location "$s-service"; npm install prom-client; Pop-Location
  docker build -t "$s-service:v1" "./$s-service"
  kind load docker-image "$s-service:v1" --name grab-mini
}
kubectl apply -f k8s/booking-service.yaml -f k8s/payment-service.yaml -f k8s/user-service.yaml   # port "http" + label monitoring=enabled
kubectl rollout restart deployment/booking deployment/payment deployment/user

# --- Bước 3: ServiceMonitor -> target app "down" vì default-deny (Phase 20) ---
kubectl apply -f k8s/monitoring/servicemonitor-apps.yaml
kubectl get --raw "$P/api/v1/targets?state=active" | jq -r '.data.activeTargets[] | select(.labels.namespace=="default") | "\(.labels.service) \(.health) \(.lastError)"'
# -> "Get http://10.244.x.x:3003/metrics: context deadline exceeded"

# --- Bước 4: mở NetworkPolicy cho Prometheus -> tất cả up ---
kubectl apply -f k8s/netpol-allow-monitoring.yaml
kubectl get --raw "$P/api/v1/query?query=up%7Bjob%3D~%22.*-service%22%7D" | jq -r '.data.result[] | "\(.metric.job) \(.metric.pod) up=\(.value[1])"'

# --- Bước 5: dashboard dạng code ---
kubectl apply -f k8s/monitoring/grab-mini-dashboard-cm.yaml
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# terminal khác - mật khẩu admin:
kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
# mở http://localhost:3000/d/grab-mini/grab-mini-services  (user: admin)

# --- Bước 6: traffic + sự cố giả lập (payment = 0 trong 60s) ---
# terminal 1: 4 vòng lặp song song (users + booking + payment) qua Ingress, ~4 phút
1..4 | ForEach-Object -Parallel {
  $end = (Get-Date).AddMinutes(4)
  while ((Get-Date) -lt $end) {
    try { Invoke-WebRequest http://localhost/users -UseBasicParsing -TimeoutSec 5 | Out-Null } catch {}
    try { Invoke-WebRequest http://localhost/booking -Method POST -Body '{"from":"A"}' -ContentType "application/json" -UseBasicParsing -TimeoutSec 5 | Out-Null } catch {}
    try { Invoke-WebRequest http://localhost/payment -Method POST -Body '{"amount":1}' -ContentType "application/json" -UseBasicParsing -TimeoutSec 5 | Out-Null } catch {}
  }
} -ThrottleLimit 4
# terminal 2: sau ~90s
kubectl scale deploy payment --replicas=0
# ~60s sau
kubectl scale deploy payment --replicas=3
# -> dashboard: "Error rate (5xx)" đỏ, "p95 latency booking" nhảy lên ~2s, "Số Pod available" payment = 0
```

**📄 Code liên quan:**

`k8s/monitoring/values.yaml` (mới):

```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    scrapeInterval: 15s
    retention: 2d
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeEtcd:
  enabled: false
kubeProxy:
  enabled: false
```

`booking-service/metrics.js` (mới - copy y hệt sang `payment-service/` và `user-service/`):

```javascript
const client = require("prom-client");
client.collectDefaultMetrics();

const labelNames = ["method", "route", "status"];
const httpRequests = new client.Counter({ name: "http_requests_total", help: "Tổng số HTTP request đã xử lý", labelNames });
const httpDuration = new client.Histogram({
  name: "http_request_duration_seconds", help: "Thời gian xử lý HTTP request (giây)", labelNames,
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
});
const SKIP = new Set(["/metrics", "/health"]);

function middleware(req, res, next) {
  if (SKIP.has(req.path)) return next();
  const end = httpDuration.startTimer();
  let recorded = false;
  const record = (status) => {
    if (recorded) return;
    recorded = true;
    const labels = { method: req.method, route: req.route ? req.route.path : "unmatched", status };
    httpRequests.inc(labels);
    end(labels);
  };
  res.on("finish", () => record(String(res.statusCode)));
  res.on("close", () => { if (!res.writableFinished) record("499"); });   // client bỏ cuộc trước khi server trả lời
  next();
}

function mount(app) {
  app.get("/metrics", async (req, res) => {
    res.set("Content-Type", client.register.contentType);
    res.end(await client.register.metrics());
  });
}
module.exports = { middleware, mount };
```

`server.js` của cả 3 service - thêm ngay sau `const app = express(); app.use(express.json());`:

```javascript
const metrics = require("./metrics");
app.use(metrics.middleware);
metrics.mount(app);
```

`booking-service/server.js` - gọi `payment` có timeout + trả 503 rõ ràng (thay cho `fetch(...).then(r => r.json())` không xử lý lỗi):

```javascript
const PAYMENT_TIMEOUT_MS = Number(process.env.PAYMENT_TIMEOUT_MS || 2000);

app.post("/booking", async (req, res) => {
  if (BUGGY) { /* ... như cũ ... */ }
  try {
    const r = await fetch("http://payment-service/payment", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ amount: 100 }),
      signal: AbortSignal.timeout(PAYMENT_TIMEOUT_MS),
    });
    if (!r.ok) throw new Error(`payment-service HTTP ${r.status}`);
    const payment = await r.json();
    res.json({ service: "booking-service", version: VERSION, payment });
  } catch (err) {
    const detail = err.name === "TimeoutError" ? `timeout ${PAYMENT_TIMEOUT_MS}ms` : (err.cause && err.cause.code) || err.message;
    console.error("payment call failed:", detail);
    res.status(503).json({ service: "booking-service", version: VERSION, error: "payment unavailable", detail });
  }
});
```

`k8s/booking-service.yaml` (tương tự `payment-service.yaml`, `user-service.yaml`) - thêm label + đặt tên port:

```yaml
metadata:
  name: booking-service
  labels:
    monitoring: enabled
spec:
  selector:
    app: booking
  ports:
    - name: http
      port: 80
      targetPort: 3003
```

`k8s/monitoring/servicemonitor-apps.yaml` (mới):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: grab-mini-apps
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames: ["default"]
  selector:
    matchLabels:
      monitoring: enabled
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

`k8s/netpol-allow-monitoring.yaml` (mới):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
spec:
  podSelector:
    matchExpressions:
      - key: app
        operator: In
        values: ["user", "booking", "payment"]
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - protocol: TCP
          port: 3001
        - protocol: TCP
          port: 3003
        - protocol: TCP
          port: 3004
```

`k8s/monitoring/grab-mini-dashboard.json` + `k8s/monitoring/grab-mini-dashboard-cm.yaml` (mới) - dashboard `Grab Mini - Services` (uid `grab-mini`), 11 panel. ConfigMap sinh từ JSON bằng:

```powershell
kubectl create configmap grab-mini-dashboard -n monitoring --from-file=grab-mini-dashboard.json=k8s/monitoring/grab-mini-dashboard.json --dry-run=client -o yaml |
  kubectl label --local -f - grafana_dashboard=1 -o yaml > k8s/monitoring/grab-mini-dashboard-cm.yaml
```

Các query PromQL chính trong dashboard:

| Panel | PromQL |
|---|---|
| Request rate | `sum by (job) (rate(http_requests_total{job=~"booking-service\|payment-service\|user-service"}[1m]))` |
| Error rate | `sum by (job) (rate(http_requests_total{...,status=~"5.."}[1m])) / sum by (job) (rate(http_requests_total{...}[1m]))` |
| Latency p95 | `histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket{...}[1m])))` |
| CPU | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="default",container!="",pod=~"(booking\|payment\|user)-.*"}[1m]))` |
| Memory | `sum by (pod) (container_memory_working_set_bytes{namespace="default",container!="",pod=~"..."})` |
| Pod count | `kube_deployment_status_replicas_available` + `kube_horizontalpodautoscaler_status_desired_replicas` |
| Restart | `increase(kube_pod_container_status_restarts_total{namespace="default",...}[5m])` |

**✅ Kết quả thật đã verify (10/11/2026):**

- Cài mặc định (không có values): **6 target `down`** - `kube-controller-manager` (`:10257`), `kube-scheduler` (`:10259`), `kube-etcd` (`:2381`), `kube-proxy` x3 (`:10249`), đều `connection refused`. Sau `helm upgrade -f k8s/monitoring/values.yaml`: 0 target down.
- Sau khi apply `ServiceMonitor`: Prometheus tự phát hiện 8 Pod app nhưng tất cả `down` - `context deadline exceeded` (default-deny Phase 20 DROP packet). Sau `netpol-allow-monitoring.yaml`: **8/8 `up`**, và `user → payment` vẫn `BLOCKED` (policy chỉ mở cho Pod Prometheus).
- Grafana sidecar tự nạp dashboard (`/d/grab-mini/grab-mini-services`, 11 panel); chạy từng PromQL trong dashboard → mọi panel đều có series. Alert firing duy nhất: `Watchdog` (heartbeat luôn bật theo thiết kế). Stack monitoring dùng ~930Mi RAM, ~31m CPU lúc idle.
- **Sự cố lần 1 (code cũ)** - scale `payment` = 0 trong 70s dưới tải: `booking` **0 request 500**, 1225 request 200 - chỉ thấy RPS `booking` tụt 5.4 → 2 req/s. Debug trực tiếp: `curl /booking` (chờ 30s) → `500 sau 10.7s`; `fetch` trong Pod booking → `UND_ERR_CONNECT_TIMEOUT sau 10.6s`; `curl --max-time 5` → client bỏ cuộc (`000`) → response 500 không bao giờ ghi xong → `finish` không chạy → **không có trong metrics**.
- **Sự cố lần 2 (sau khi sửa)** - scale `payment` = 0 trong 60s (16:37:27 → 16:38:27 UTC): error rate `booking` **0% → 22% → 19% → 0%**, p95 latency **5ms → 2165ms** (= timeout 2s), **34 response `503`** (`payment unavailable`), tự về 0% sau khi `payment` scale lại 3.

> **Bài học quan trọng #1 - lỗi mà metrics không thấy**: metrics phía server chỉ ghi những gì server *trả lời được*. Khi dependency treo lâu hơn timeout của client, client bỏ đi, server trả lời vào khoảng không → từ góc nhìn dashboard "mọi thứ vẫn 200". Phải: (1) luôn đặt timeout ngắn hơn timeout của client cho mọi lời gọi ra ngoài, (2) đo cả request bị huỷ (`close` khi chưa `writableFinished`), (3) đo ở nhiều tầng - ingress-nginx cũng có metrics riêng (`nginx_ingress_controller_requests`) thấy được 5xx/timeout ở phía client.
>
> **Bài học quan trọng #2 - Service 0 endpoint = treo, không phải refuse** (trên cluster này): kết nối tới ClusterIP khi không còn Pod nào bị DROP thay vì `ECONNREFUSED` ngay → không có timeout là treo 10s (`undici` connect timeout mặc định). Không nên dựa vào "lỗi sẽ đến nhanh".
>
> **Bài học quan trọng #3 - NetworkPolicy áp dụng cho cả hạ tầng của chính mình**: default-deny (Phase 20) chặn luôn Prometheus. Target `down` + `context deadline exceeded` (không phải `connection refused`) là dấu hiệu điển hình của packet bị DROP bởi policy.
>
> **Bài học quan trọng #4 - kube-prometheus-stack trên kind**: chart mặc định giả định control-plane expose metrics ra ngoài - trên `kind` (và nhiều managed cluster như EKS/GKE, nơi control-plane bị ẩn hoàn toàn) phải tắt các ServiceMonitor đó, nếu không sẽ có alert `TargetDown` giả. Và `serviceMonitorSelectorNilUsesHelmValues: false` là bắt buộc nếu muốn Prometheus nhận ServiceMonitor tự viết không mang label `release: monitoring`.
>
> **Khi tạo lại cluster**: xem [🔁 Dựng lại toàn bộ cluster](#rebuild).

---

<a id="scenario-21"></a>
## Scenario 21 - Logs (Loki + Alloy) + Alert (PrometheusRule + Alertmanager) (Phase 21)

```text
Pod stdout ──► /var/log/pods trên node ──► Alloy (DaemonSet) ──► Loki ──► Grafana (Explore / panel log)
/metrics ──► Prometheus ──► PrometheusRule ──► Alertmanager ──► webhook (alert-webhook) ──► log ──► Loki
```

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update grafana

# --- Bước 1: Loki (SingleBinary, filesystem) + Alloy (DaemonSet thu log) ---
helm upgrade --install loki grafana/loki --version 7.5.0 -n monitoring -f k8s/monitoring/loki-values.yaml --wait --timeout 10m
helm upgrade --install alloy grafana/alloy --version 1.15.0 -n monitoring -f k8s/monitoring/alloy-values.yaml --wait
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy -o wide   # 3 Pod - 1 trên MỖI node, kể cả control-plane

# --- Bước 2: kiểm tra Loki nhận log (API server proxy, không cần port-forward) ---
$L = "/api/v1/namespaces/monitoring/services/loki:3100/proxy"
kubectl get --raw "$L/loki/api/v1/label/app/values"
$q = [uri]::EscapeDataString('sum by (app) (count_over_time({namespace="default"}[15m]))')
kubectl get --raw "$L/loki/api/v1/query?query=$q" | jq -r '.data.result[] | "\(.metric.app) \(.value[1])"'

# --- Bước 3: Loki datasource + alert routing (cả 2 nằm trong values của kube-prometheus-stack) ---
kubectl apply -f k8s/monitoring/alert-webhook.yaml        # receiver giả lập (thay Slack/Telegram)
kubectl apply -f k8s/monitoring/alerts-apps.yaml          # PrometheusRule grab-mini-alerts (5 rule)
helm upgrade monitoring prometheus-community/kube-prometheus-stack --version 93.1.1 -n monitoring -f k8s/monitoring/values.yaml --wait
kubectl apply -f k8s/monitoring/grab-mini-dashboard-cm.yaml   # dashboard có thêm 2 panel log (Loki)

$P = "/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy"
kubectl get --raw "$P/api/v1/rules" | jq -r '.data.groups[] | select(.name=="grab-mini.rules") | .rules[] | "\(.name) \(.state)"'
$A = "/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-alertmanager:9093/proxy"
kubectl get --raw "$A/api/v2/status" | jq -r '.config.original' | Select-String grab-mini-webhook   # config đã reload (có thể mất ~1 phút)

# --- Bước 4: sự cố - payment = 0 trong 150s dưới tải (dùng lại vòng lặp traffic của Scenario 20) ---
kubectl scale deploy payment --replicas=0
kubectl get --raw "$P/api/v1/alerts" | jq -r '.data.alerts[] | select(.labels.alertname|startswith("GrabMini")) | "\(.labels.alertname) \(.state)"'   # chạy lặp lại
# ~150s sau:
kubectl scale deploy payment --replicas=3
kubectl logs -n monitoring deploy/alert-webhook | Select-String ALERT       # FIRING ... rồi RESOLVED ...

# --- Bước 5: tìm log lỗi trong Loki ---
$q = [uri]::EscapeDataString('{app="booking"} |= "payment call failed"')
kubectl get --raw "$L/loki/api/v1/query_range?query=$q&limit=5&since=20m" | jq -r '.data.result[].values[][1]'
```

**📄 Code liên quan:**

`k8s/monitoring/loki-values.yaml` (mới):

```yaml
deploymentMode: SingleBinary
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  limits_config:
    retention_period: 48h
  compactor:
    retention_enabled: true
    delete_request_store: filesystem
singleBinary:
  replicas: 1
  persistence:
    size: 2Gi
backend: { replicas: 0 }
read: { replicas: 0 }
write: { replicas: 0 }
chunksCache: { enabled: false }
resultsCache: { enabled: false }
lokiCanary: { enabled: false }
test: { enabled: false }
gateway: { enabled: false }
```

`k8s/monitoring/alloy-values.yaml` (mới) - DaemonSet + toleration control-plane + pipeline `discovery.kubernetes` (chỉ Pod trên node của mình, qua `HOSTNAME` = `spec.nodeName` do chart tự set) → `discovery.relabel` (label `namespace`/`pod`/`container`/`app`/`node` + `__path__ = /var/log/pods/*<uid>/<container>/*.log`) → `local.file_match` → `loki.source.file` → `loki.process` (`stage.cri {}`) → `loki.write` (`http://loki.monitoring.svc:3100/loki/api/v1/push`). Xem file đầy đủ trong repo.

`k8s/monitoring/values.yaml` - thêm 2 khối:

```yaml
grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      uid: loki
      url: http://loki.monitoring.svc:3100
      access: proxy

alertmanager:
  config:                       # THAY THẾ toàn bộ config mặc định của chart
    global:
      resolve_timeout: 5m
    route:
      receiver: "null"
      group_by: ["alertname", "job", "deployment"]
      group_wait: 10s
      group_interval: 30s
      repeat_interval: 4h
      routes:
        - receiver: "null"
          matchers: ['alertname = "Watchdog"']
        - receiver: grab-mini-webhook
          matchers: ['alertname =~ "GrabMini.*"']
    receivers:
      - name: "null"
      - name: grab-mini-webhook
        webhook_configs:
          - url: http://alert-webhook.monitoring.svc/
            send_resolved: true
    inhibit_rules:
      - source_matchers: ['severity = "critical"']
        target_matchers: ['severity = "warning"']
        equal: ["job"]
```

`k8s/monitoring/alerts-apps.yaml` (mới) - `PrometheusRule` `grab-mini-alerts`:

| Alert | Điều kiện | for | severity |
|---|---|---|---|
| `GrabMiniHighErrorRate` | tỉ lệ 5xx theo `job` > 5% (rate 1m) | 1m | critical |
| `GrabMiniHighLatencyP95` | `histogram_quantile(0.95, ...)` > 1s | 1m | warning |
| `GrabMiniNoPodsAvailable` | `kube_deployment_status_replicas_available{deployment=~"booking\|payment\|user"} == 0` | 30s | critical |
| `GrabMiniPodRestarting` | `increase(kube_pod_container_status_restarts_total[10m]) > 2` | - | warning |
| `GrabMiniTargetDown` | `up{job=~"...-service"} == 0` | 1m | critical |

`k8s/monitoring/alert-webhook.yaml` (mới) - Deployment `node:20-alpine` chạy `node -e` 1 HTTP server nhỏ, in mỗi alert thành 1 dòng `ALERT <FIRING|RESOLVED> <alertname> severity=... | <summary>` + Service `alert-webhook:80`.

`k8s/monitoring/grab-mini-dashboard.json` - thêm panel 12 "Log lỗi theo app (dòng/phút)" (`sum by (app) (count_over_time({namespace="default", app=~"booking|payment|user"} |~ "(?i)(error|failed|exception)" [1m]))`) và panel 13 kiểu `logs` hiển thị các dòng đó.

**✅ Kết quả thật đã verify (10-11/11/2026):**

- Alloy chạy 3 Pod (`worker`, `worker2`, `control-plane`), không lỗi. Loki có label `app` = `booking, payment, user, postgres, kindnet, ...`, namespace = `default, ingress-nginx, kube-system, monitoring, ...`. `{app="payment"}` trả đúng dòng `handled by pod: payment-...`; `count_over_time` 15 phút: `payment 952`, `booking 4`.
- 5 rule được Prometheus nạp; Alertmanager reload config mới (route `GrabMini.*` → `grab-mini-webhook`).
- **Timeline sự cố** (`payment` = 0 lúc 23:56:49, scale lại lúc 23:59:20, giờ local):

  | Giờ | Sự kiện |
  |---|---|
  | 23:57:47 | `GrabMiniNoPodsAvailable` **pending** (~58s - gồm grace 30s của Pod payment + scrape kube-state-metrics + chu kỳ đánh giá rule) |
  | 23:58:16 | `GrabMiniNoPodsAvailable` **firing** → webhook: `ALERT FIRING GrabMiniNoPodsAvailable ... Deployment payment không còn Pod available nào` |
  | 23:58:18 | `GrabMiniHighErrorRate` + `GrabMiniHighLatencyP95` (booking) **pending** |
  | 23:59:16 | `GrabMiniHighErrorRate` **firing** → webhook: `booking-service: error rate 100% (> 5%)` |
  | 23:59:20 | `GrabMiniHighLatencyP95` **firing** trong Prometheus - nhưng **KHÔNG tới webhook** (bị `inhibit_rules` chặn vì đã có critical cùng `job=booking-service`) |
  | 00:00:16 | webhook: `ALERT RESOLVED GrabMiniNoPodsAvailable` |
  | 00:00:46 | webhook: `ALERT RESOLVED GrabMiniHighErrorRate ... error rate 31.82%` - hết alert |

- Loki: log `ALERT FIRING/RESOLVED` của webhook tìm được bằng `{namespace="monitoring", app="alert-webhook"} |= "ALERT"`; `{app="booking"} |= "payment call failed"` → **177 dòng** trong 20 phút (`timeout 2000ms` và `ECONNREFUSED`).

> **Bài học quan trọng #1 - độ trễ phát hiện ≠ 0**: từ lúc sự cố tới khi alert đầu tiên tới người trực mất **~87s**, alert error rate mất **~2.5 phút**: grace period của Pod + `scrapeInterval` (15-30s) + `rate(...[1m])` cần đủ mẫu + chu kỳ đánh giá rule (30s) + `for:` + `group_wait` (10s). Giảm `for:` thì nhanh hơn nhưng dễ báo động giả (flapping) - đây là trade-off phải chọn theo SLO.
>
> **Bài học quan trọng #2 - inhibition giảm "bão alert"**: 1 sự cố gốc (payment chết) sinh ra 3 alert. `inhibit_rules` (critical chặn warning cùng `job`) đã chặn alert latency - người trực nhận 2 tin thay vì 3. Production thường còn chặn alert "triệu chứng" khi alert "nguyên nhân" đang firing.
>
> **Bài học quan trọng #3 - thông báo RESOLVED mang giá trị CŨ**: `summary` của tin RESOLVED là `error rate 31.82%` - đó là giá trị lần cuối rule còn firing, không phải giá trị hiện tại (0%). Đừng đọc số trong tin RESOLVED như trạng thái hiện tại.
>
> **Bài học quan trọng #4 - `alertmanager.config` là thay thế, không phải merge**: khai báo khối này trong values xoá toàn bộ config mặc định của chart - phải tự thêm lại route `Watchdog → null` và `inhibit_rules`, nếu không `Watchdog` (luôn firing) sẽ bị gửi tới receiver mặc định.
>
> **Bài học quan trọng #5 - Promtail đã EOL**: collector log chính thức hiện tại là Grafana Alloy (cấu hình dạng pipeline `discovery → relabel → source → process → write`). Alloy DaemonSet mặc định KHÔNG chạy trên control-plane (taint) → mất log của ingress-nginx nếu quên `tolerations`.

---

<a id="scenario-22"></a>
## Scenario 22 - Helm: chart dùng chung + chuyển resource đang chạy sang Helm (Phase 22)

Thay vì `helm create booking-chart` cho từng service (3 bản copy gần giống nhau), dùng **1 chart dùng chung** cho mọi microservice + values theo 2 trục: *service* và *môi trường*:

```text
charts/
  grab-service/        Deployment + Service + PDB + HPA (booking / payment / user)
  grab-platform/       ConfigMap + Ingress + 5 NetworkPolicy + CronJob + PostgreSQL (1 bộ / namespace)
helm-values/
  booking.yaml  payment.yaml  user.yaml        <- riêng từng service (port, image, env, probe)
  env-dev.yaml  env-staging.yaml  env-prod.yaml <- riêng từng môi trường (replicas, HA, PDB)
  booking-prod.yaml                             <- booking × prod (resources + HPA + PDB minAvailable)
  platform-dev.yaml                             <- grab-platform ở dev (Ingress host riêng)

helm upgrade --install booking charts/grab-service -f helm-values/booking.yaml -f helm-values/env-prod.yaml -f helm-values/booking-prod.yaml
                                                     └── file sau ghi đè file trước ──────────────────────►
```

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1: lint + xem trước manifest ---
helm lint charts/grab-service -f helm-values/booking.yaml -f helm-values/env-prod.yaml -f helm-values/booking-prod.yaml
helm lint charts/grab-platform
helm template booking charts/grab-service -f helm-values/booking.yaml -f helm-values/env-prod.yaml -f helm-values/booking-prod.yaml

# --- Bước 2: SO SÁNH với object đang chạy TRƯỚC khi đụng vào (kubectl diff = server-side dry-run) ---
# Windows không có sẵn lệnh "diff" -> kubectl diff báo 'failed to run "diff"'. Dùng diff.exe của Git for Windows
# (KHÔNG đặt KUBECTL_EXTERNAL_DIFF="C:\Program Files\..." - kubectl tách chuỗi theo dấu cách, vỡ ở "Program Files")
$env:PATH = "C:\Program Files\Git\usr\bin;$env:PATH"
# exit code: 0 = không khác, 1 = có khác biệt, >1 = lỗi
# Lưu ý: kubectl diff mô phỏng KUBECTL apply (client-side, dựa trên annotation last-applied) chứ không phải cách
# Helm 4 apply (server-side) -> với booking nó luôn báo "replicas: 2 -> 1" dù helm upgrade thật KHÔNG đổi replicas.
# Muốn diff đúng theo Helm: plugin helm-diff (helm diff upgrade ...).
helm template booking charts/grab-service -f helm-values/booking.yaml -f helm-values/env-prod.yaml -f helm-values/booking-prod.yaml | kubectl diff -f -
helm template grab-platform charts/grab-platform | kubectl diff -f -
# -> chỉ được phép thấy: thêm labels app.kubernetes.io/* + helm.sh/chart (và "replicas" của booking - xem bài học #2)

# --- Bước 3: helm install thường -> BỊ TỪ CHỐI (resource đã tồn tại, không do Helm tạo) ---
helm install payment charts/grab-service -f helm-values/payment.yaml -f helm-values/env-prod.yaml
# -> "PodDisruptionBudget payment-pdb exists and cannot be imported into the current release: invalid ownership metadata"

# --- Bước 4: chiếm quyền quản lý (adopt) bằng --take-ownership, chạy traffic loop song song (Scenario 18) ---
helm upgrade --install payment charts/grab-service -f helm-values/payment.yaml -f helm-values/env-prod.yaml --take-ownership --wait
helm upgrade --install user    charts/grab-service -f helm-values/user.yaml    -f helm-values/env-prod.yaml --take-ownership --wait
helm upgrade --install booking charts/grab-service -f helm-values/booking.yaml -f helm-values/env-prod.yaml -f helm-values/booking-prod.yaml --take-ownership --wait
kubectl get deploy booking -o jsonpath='{.spec.replicas}'      # vẫn = số HPA đang giữ (2), KHÔNG bị reset về 1

# platform: lần đầu FAIL vì xung đột server-side apply ở volumeClaimTemplates (bài học #3)
helm upgrade --install grab-platform charts/grab-platform --take-ownership --wait
# kiểm tra an toàn bằng dry-run phía server rồi mới force:
helm template grab-platform charts/grab-platform -s templates/postgres.yaml | kubectl apply --server-side --field-manager=helm --force-conflicts --dry-run=server -f -
helm upgrade --install grab-platform charts/grab-platform --take-ownership --force-conflicts --wait
helm list
kubectl get deploy booking -o json --show-managed-fields | jq -r '.metadata.managedFields[] | "\(.manager) \(.operation)"'

# --- Bước 5: upgrade -> rollback -> upgrade lại (bật probe cho payment chỉ bằng values) ---
#   helm-values/payment.yaml: thêm  probes: { enabled: true }
helm template payment charts/grab-service -f helm-values/payment.yaml -f helm-values/env-prod.yaml | kubectl diff -f -   # chỉ thấy +readinessProbe +livenessProbe
helm upgrade payment charts/grab-service -f helm-values/payment.yaml -f helm-values/env-prod.yaml --wait   # REVISION 2
helm rollback payment 1 --wait                                                                            # REVISION 3 = "Rollback to 1"
helm upgrade payment charts/grab-service -f helm-values/payment.yaml -f helm-values/env-prod.yaml --wait   # REVISION 4
helm history payment
helm upgrade user charts/grab-service -f helm-values/user.yaml -f helm-values/env-prod.yaml --wait        # user cũng bật probe

# --- Bước 6: môi trường DEV = cùng chart, khác values, khác namespace ---
kubectl create namespace grab-dev
kubectl create secret generic booking-secret -n grab-dev --from-literal=DB_USERNAME=dev --from-literal=DB_PASSWORD=<random>
helm upgrade --install grab-platform charts/grab-platform -n grab-dev -f helm-values/platform-dev.yaml --wait
foreach ($s in "payment","user","booking") { helm upgrade --install $s charts/grab-service -n grab-dev -f "helm-values/$s.yaml" -f helm-values/env-dev.yaml --wait }
helm list -n grab-dev
curl.exe -s -H "Host: dev.grab.local" -X POST http://localhost/booking -H "Content-Type: application/json" -d '{}'   # dev
curl.exe -s -X POST http://localhost/booking -H "Content-Type: application/json" -d '{}'                             # prod

# --- Bước 7: dọn dev ---
foreach ($r in "booking","payment","user","grab-platform") { helm uninstall $r -n grab-dev --wait }
kubectl get pvc,secret -n grab-dev     # CÒN SÓT: PVC data-postgres-0 + Secret booking-secret (bài học #5)
kubectl delete namespace grab-dev
```

**📄 Code liên quan:**

`charts/grab-service/` (mới): `Chart.yaml` (version 0.1.0, appVersion v1), `values.yaml` (mặc định + chú thích từng field), `templates/_helpers.tpl`, `deployment.yaml`, `service.yaml`, `pdb.yaml`, `hpa.yaml`, `NOTES.txt`. Các điểm thiết kế chính:

```yaml
# _helpers.tpl - selector CHỈ dùng "app" (khớp Deployment cũ - selector bất biến), label chuẩn chỉ ở metadata
{{- define "grab-service.selectorLabels" -}}
app: {{ required "values.app là bắt buộc" .Values.app }}
{{- end -}}

# deployment.yaml - có HPA thì KHÔNG khai báo replicas (để HPA giữ quyền)
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}

# pdb.yaml - chặn cấu hình sai ngay lúc render
{{- if and $hasMin $hasMax }}
{{- fail "pdb: chỉ khai báo minAvailable HOẶC maxUnavailable, không cả hai (đặt cái còn lại = null)" }}
{{- end }}
```

Mọi tính năng của Phase 10-19 thành 1 dòng values: `probes.enabled`, `preStopSleepSeconds`, `terminationGracePeriodSeconds`, `resources`, `topologySpread.enabled`, `nodeFailureTolerationSeconds`, `preferredAntiAffinity`, `pdb.*`, `autoscaling.*`, `service.labels.monitoring`.

`charts/grab-platform/` (mới): `configmap.yaml` (`booking-config`), `ingress.yaml` (có `host` tuỳ chọn), `networkpolicies.yaml` (5 policy Phase 20-21), `cronjob.yaml` (`settlement-job`), `postgres.yaml` (headless Service + StatefulSet - pod template và `volumeClaimTemplates` cố tình KHÔNG thêm label Helm). `values.yaml` mặc định = đúng cấu hình prod đang chạy.

`helm-values/env-prod.yaml`:

```yaml
replicaCount: 3
topologySpread:
  enabled: true
nodeFailureTolerationSeconds: 30
pdb:
  enabled: true
  maxUnavailable: 1
```

`helm-values/env-dev.yaml`:

```yaml
replicaCount: 1
topologySpread:
  enabled: false
nodeFailureTolerationSeconds: null   # null = XOÁ key thừa hưởng (về mặc định 300s)
preferredAntiAffinity: false
pdb:
  enabled: false
autoscaling:
  enabled: false
resources: {}
```

`helm-values/booking-prod.yaml`:

```yaml
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits: { cpu: "500m", memory: "512Mi" }
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
pdb:
  minAvailable: 1
  maxUnavailable: null   # xoá maxUnavailable: 1 thừa hưởng từ env-prod.yaml
```

`helm-values/platform-dev.yaml`:

```yaml
ingress:
  name: grab-mini-ingress-dev
  host: dev.grab.local
settlement:
  enabled: false
postgres:
  password: <random>
```

**✅ Kết quả thật đã verify (11/11/2026):**

- `kubectl diff` trước khi adopt: `booking`/`payment`/`user` chỉ thêm label (+ `booking` báo `replicas: 2 → 1`), `grab-platform` chỉ thêm `labels` vào metadata của 10 object - **0 thay đổi spec**, kể cả pod template của `postgres`.
- `helm install` thường → `invalid ownership metadata` (thiếu label `app.kubernetes.io/managed-by: Helm` + annotation `meta.helm.sh/release-name/namespace`).
- Adopt 3 service bằng `--take-ownership` trong lúc traffic chạy: **636/636 request OK**; object giữ nguyên AGE 37 ngày (adopt, không tạo lại); `booking` vẫn **2** replica (không bị reset).
- `managedFields` của `booking` sau adopt: `helm Apply` (server-side apply, Helm 4 mặc định) **không** sở hữu `f:replicas`; `kube-controller-manager Update` sở hữu `f:replicas` (HPA).
- `grab-platform` lần 1: `Apply failed with 1 conflict: conflict with "kubectl-client-side-apply" ... .spec.volumeClaimTemplates` - release `failed` nhưng 9 object còn lại đã áp dụng, traffic 96/96 OK. Dry-run `--force-conflicts` phía server OK → chạy thật: REVISION 2 `deployed`, `postgres-0` **cùng UID** (không restart), `user → postgres` vẫn BLOCKED. Sau đó `helm` sở hữu `volumeClaimTemplates`.
- Upgrade/rollback `payment` (bật probe): diff chỉ `+readinessProbe +livenessProbe`; revision 2 có probe → `rollback 1` → probe biến mất (revision 3 "Rollback to 1") → upgrade lại (revision 4). Toàn bộ chuỗi upgrade/rollback/upgrade + upgrade `user`: **474/474 request OK**.
- DEV (`grab-dev`): 4 release, 1 replica mỗi service, không PDB/HPA, đủ 5 NetworkPolicy, Ingress host `dev.grab.local`; `curl -H "Host: dev.grab.local" /booking` → chain booking → payment của DEV (lần đầu 503 vài giây do ingress-nginx đồng bộ endpoint); prod không bị ảnh hưởng. `booking` dev → `payment-service.default.svc` (prod) **BLOCKED**, dev `user → postgres` BLOCKED, dev `booking` đọc `DB_USERNAME=dev`.
- `helm uninstall` 4 release dev → còn sót `persistentvolumeclaim/data-postgres-0` + `secret/booking-secret` → `kubectl delete namespace grab-dev` dọn sạch (PV tự xoá theo PVC, `reclaimPolicy: Delete`).
- Sau Phase 22: `helm list -A` = 7 release (`booking`, `payment`, `user`, `grab-platform`, `monitoring`, `loki`, `alloy`), Prometheus 30/30 target `up`, chỉ `Watchdog` firing, `/users` + `/booking` = 200.

> **Bài học quan trọng #1 - luôn `kubectl diff` trước khi để Helm "chiếm" resource đang chạy**: lần adopt đầu tiên là lúc nguy hiểm nhất - template sai 1 chữ ở selector, `volumeClaimTemplates` hay pod template của StatefulSet là tạo lại/restart workload thật. Diff phải sạch (chỉ label metadata) rồi mới chạy.
>
> **Bài học quan trọng #2 - HPA + `spec.replicas`**: chart có HPA phải BỎ `spec.replicas`, nếu không mỗi `helm upgrade` reset số Pod về `replicaCount` (đánh nhau với HPA). Nhưng việc bỏ field cũng nguy hiểm: `kubectl diff` (client-side apply, dựa trên annotation `last-applied` có `replicas: 3`) báo sẽ đặt lại `replicas` về mặc định **1**. Helm 4 dùng server-side apply → chỉ quản lý field nó khai báo, `replicas` thuộc `kube-controller-manager` → không bị đụng. Với Helm 3 (3-way merge client-side) hoặc `kubectl apply` thường, cần kiểm tra kỹ điểm này.
>
> **Bài học quan trọng #3 - xung đột server-side apply với field atomic**: `volumeClaimTemplates` là list atomic (cả list 1 chủ sở hữu), bản live có thêm field do server tự điền (`apiVersion`, `kind`, `volumeMode`, `status`) → SSA coi là giá trị khác → conflict với manager cũ `kubectl-client-side-apply`. `--force-conflicts` an toàn ở đây vì sau defaulting giá trị y hệt (đã chứng minh bằng `--dry-run=server`); nếu thật sự khác, API server sẽ từ chối vì field bất biến. Không bao giờ force mù quáng.
>
> **Bài học quan trọng #4 - `helm rollback` tạo revision MỚI**: history là append-only (1 → 2 → 3 "Rollback to 1" → 4). Rollback chỉ khôi phục những gì Helm quản lý - không khôi phục data, Secret tạo tay, hay image đã bị ghi đè cùng tag (vd. `:v1` đã build lại ở Phase 21 - rollback về revision cũ vẫn chạy image `:v1` MỚI). Đây là lý do production dùng tag bất biến (git SHA) thay vì build lại cùng tag.
>
> **Bài học quan trọng #5 - `helm uninstall` không xoá hết**: PVC sinh từ `volumeClaimTemplates` (do StatefulSet controller tạo, không nằm trong release) và Secret tạo bằng `kubectl` vẫn còn - đây là thiết kế có chủ đích để không mất data. Muốn xoá sạch môi trường: xoá namespace.
>
> **Bài học quan trọng #6 - drift**: sau khi Helm quản lý, `kubectl apply -f k8s/...yaml` / `kubectl scale` / `kubectl patch` trên các object này tạo drift - lần `helm upgrade` sau sẽ ghi đè (hoặc conflict với manager khác). Mọi thay đổi phải đi qua `helm-values/` - và đó chính là tiền đề cho CI/CD (Phase 23) và GitOps (Phase 24).

---

<a id="scenario-23"></a>
## Scenario 23 - CI/CD: pipeline local + local registry + tag theo git SHA (Phase 23)

```text
git commit ──► ci/pipeline.ps1 -Service <svc>
                 1 test    npm ci + node --test (dừng ở đây nếu test fail - không build gì)
                 2 build   docker build -t localhost:5001/<svc>-service:<git-sha>
                 3 push    docker push -> registry:2 (container kind-registry, cùng mạng Docker "kind")
                 4 deploy  ghi helm-values/<svc>-image.yaml + helm upgrade --rollback-on-failure --wait
                 5 smoke   gọi qua Ingress như người dùng thật; lỗi -> helm rollback
                 6 record  git commit "deploy(<svc>): <sha>"  (Git = nhật ký deploy, tiền đề GitOps Phase 24)
```

Đã chọn chạy **local** (không đẩy code lên GitHub): runner của GitHub không vào được cluster `kind` trên máy cá nhân. Bản GitHub Actions tương đương nằm ở `.github/workflows/ci.yaml` (chạy từ Phase 24, chỉ test + build). **Bổ sung [23b](#scenario-23b): CD qua self-hosted runner** - `git push` là tự chạy `pipeline.ps1`.

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1+2: local registry + containerd trên từng node (chạy lại nhiều lần vẫn an toàn) ---
# containerd của kind mặc định config_path = '' (bỏ qua hosts.toml) -> script bật config_path, tạo
# certs.d/localhost:5001/hosts.toml -> http://kind-registry:5000, restart containerd LẦN LƯỢT từng node
./ci/setup-local-registry.ps1
kubectl apply -f k8s/local-registry-hosting.yaml          # ConfigMap chuẩn KEP-1755 (tuỳ chọn)

# kiểm tra cluster pull được từ registry
docker tag user-service:v1 localhost:5001/registry-test:1; docker push localhost:5001/registry-test:1
kubectl run registry-test --image=localhost:5001/registry-test:1 --restart=Never --command -- node -e "console.log('ok')"
kubectl get events --field-selector involvedObject.name=registry-test | Select-String Pull   # Pulling -> Pulled
kubectl delete pod registry-test

# --- Bước 3: test + git ---
foreach ($s in "booking","payment","user") { Push-Location "$s-service"; npm test; Pop-Location }   # 10/10 pass
git init -b main; git add -A; git commit -m "snapshot"        # repo LOCAL, không có remote

# --- Bước 4: dọn field manager cũ (1 lần, xem bài học #1) ---
./ci/migrate-field-managers.ps1 -Release payment,user,booking,grab-platform -DryRun
./ci/migrate-field-managers.ps1 -Release payment,user,booking,grab-platform

# --- Bước 5: chạy pipeline (nên chạy kèm traffic loop của Scenario 18 ở terminal khác) ---
./ci/pipeline.ps1 -Service payment
./ci/pipeline.ps1 -Service user,booking
helm list; Get-Content helm-values/*-image.yaml; git log --oneline -5

# --- Demo A: tính năng mới ---
#   sửa booking-service/server.js (+ test) -> git commit
./ci/pipeline.ps1 -Service booking

# --- Demo B: bug bị test chặn -> pipeline dừng ở stage 1, không build/push/deploy ---
#   đổi res.status(503) -> res.status(500) -> git commit
./ci/pipeline.ps1 -Service booking      # "not ok 3 ... expected: 503, actual: 500"
git revert --no-edit HEAD

# --- Demo C: bug qua được test nhưng chết trên cluster -> Helm tự rollback ---
#   Dockerfile: CMD ["node", "server.jss"] -> git commit
./ci/pipeline.ps1 -Service booking -Timeout 60s   # "UPGRADE FAILED ... has been rolled back due to rollback-on-failure"
helm history booking                               # failed -> "Rollback to N"
git revert --no-edit HEAD
```

**📄 Code liên quan:**

- `ci/pipeline.ps1` (mới) - 6 stage như sơ đồ trên. Điểm chính: `$PSNativeCommandUseErrorActionPreference = $true` (lệnh ngoài trả exit code ≠ 0 → dừng ngay); guard "phải commit trước" (`git status --porcelain -- <svc>-service charts helm-values`); tag = `git log -1 --format=%h --abbrev=12 -- <svc>-service` (commit cuối **động vào thư mục service**, nên cùng source = cùng tag); smoke test thử lại 10 lần × 3s (ingress-nginx cần vài giây nhận endpoint mới); lỗi ở deploy/smoke → trả `helm-values/<svc>-image.yaml` về bản đã commit.
- `ci/setup-local-registry.ps1` (mới) - chạy `registry:2.8.3` (nếu chưa có) + `docker network connect kind`; với mỗi node: `docker cp` 2 file (`config-patch.toml`, `hosts.toml`) vào **`/etc/containerd/`** rồi `docker exec` gắn vào config + `systemctl restart containerd` + đợi node `Ready`.
- `ci/migrate-field-managers.ps1` (mới) - với mọi object của các release: merge patch `metadata.managedFields` = danh sách đã bỏ `kubectl-client-side-apply`, `kubectl-patch`, `kubectl-autoscale` + xoá annotation `last-applied-configuration`. Có `-DryRun` (`--dry-run=server`).
- `helm-values/<svc>-image.yaml` (mới, **do pipeline tạo** - không sửa tay):

  ```yaml
  # TẠO BỞI ci/pipeline.ps1 - KHÔNG sửa tay. Image đang chạy ở prod cho booking.
  image:
    repository: localhost:5001/booking-service
    tag: "5f5a024b8892"
  ```

- `<svc>-service/server.js` - `module.exports = app` + chỉ `app.listen()` khi `require.main === module` (để test `require` được mà không mở port thật). `booking` thêm `PAYMENT_URL` (đọc mỗi request - test trỏ sang payment giả) và `bookingId: randomUUID()` (Demo A).
- `<svc>-service/server.test.js` (mới) - `node:test` + `fetch`, không thêm dependency. `booking` (4 test): `/health`; `/booking` với payment **giả** (HTTP server trong test) → 200 + `bookingId`; payment không kết nối được → **503 trong < 2s**; `/metrics` có counter `route="/booking"` status 200 và 503, không có `/health`. `payment`, `user`: 3 test mỗi service.
- `<svc>-service/package.json`: `"test": "node --test"`. `Dockerfile`: `npm ci --omit=dev` (đúng lockfile). `.dockerignore` (mới): bỏ `node_modules` của máy host và `*.test.js` khỏi image.
- `kind-multi-node.yaml`: thêm `containerdConfigPatches` (`config_path = "/etc/containerd/certs.d"`) cho lần tạo cluster sau.
- `.github/workflows/ci.yaml` (mới, chưa chạy): `changes` (`dorny/paths-filter` - service nào đổi) → `build` (matrix: test → build → push GHCR chỉ khi push `main`; PR chỉ test + build) → `record` (1 job commit mọi `helm-values/<svc>-image.yaml`, `[skip ci]`). Không có job deploy - để Argo CD (Phase 24) làm.
- `.gitignore` (`node_modules/`), `.gitattributes` (`* text=auto eol=lf` - Windows `core.autocrlf=true` sẽ đổi YAML/JS sang CRLF).

**✅ Kết quả thật đã verify (11/11/2026):**

- Registry: cluster pull `localhost:5001/registry-test:1` → `Pulling` → `Pulled in 214ms`. Restart containerd lần lượt 3 node: node `Ready` lại ngay, không Pod nào restart.
- `setup-local-registry.ps1` bản đầu dùng `/tmp` → `cp: cannot stat '/tmp/hosts.toml'` trên cả 3 node (vẫn "chạy được" chỉ vì file cũ còn sót). Sửa sang `/etc/containerd/`, xoá hosts.toml cũ rồi chạy lại: tạo đủ 3 node, pull `--image-pull-policy=Always` → `Pulled in 137ms`, 0 Pod lỗi.
- Test: 10/10 pass trên máy host (Node 22) trước khi đưa vào pipeline.
- **Lần chạy đầu `payment` FAIL ở stage deploy**: `conflict with "kubectl-client-side-apply" ... .spec.template.spec.containers[name="payment"].image` → `--rollback-on-failure` tự rollback (revision 5 failed → 6 "Rollback to 4"). Sau `migrate-field-managers.ps1` (20 object): generation Deployment +1 nhưng **không có ReplicaSet mới, Pod giữ nguyên tuổi** → chạy lại pipeline OK.
- Pipeline 3 service: `payment` 29s, `user` 32s, `booking` 25s (test ~2s, build 3-6s, push 1-1.5s, deploy 13-21s, smoke 2s); mỗi lần 1 commit `deploy(<svc>): <sha>`. Traffic qua Ingress trong lúc lần fail + lần deploy `payment`: **570/570 OK**.
- **Demo A** (`bookingId`): tag mới `5f5a024b8892`, 23s, response có `"bookingId":"c27e78ed-..."`; traffic **220/220 OK**.
- **Demo B** (503 → 500): dừng ở `1/6 test` (`not ok 3 ... expected: 503 actual: 500`, `not ok 4` metrics) - Helm vẫn revision 3, registry **không có** tag `4038644672e0`, Pod vẫn chạy `5f5a024b8892`.
- **Demo C** (`CMD server.jss`): test/build/push đều OK (test chạy trên host, không đụng Dockerfile) → deploy: `resource Deployment/default/booking not ready ... Updated: 1/2 ... context deadline exceeded` → Helm tự rollback (revision 4 failed → 5 "Rollback to 3"), `booking-image.yaml` trả về tag cũ, git sạch. Traffic **318/318 OK** - Pod cũ không bị gỡ vì Pod mới không bao giờ Ready (`maxUnavailable` 25% của 2 replica = 0).
- Sau Phase 23: 4 release `deployed`, Prometheus 30/30 `up`, chỉ `Watchdog` firing.

> **Bài học quan trọng #1 - adopt vào Helm chưa xong cho tới lần ĐỔI giá trị đầu tiên**: `--take-ownership` (Phase 22) qua được vì Helm apply đúng giá trị cũ - manager cũ `kubectl-client-side-apply` vẫn đồng sở hữu mọi field. Lần đầu đổi `image` → server-side apply conflict. Phải dọn manager cũ 1 lần (hoặc `--force-conflicts` - nhưng dọn sạch thì về sau không phải force). Phụ: xoá annotation làm `generation` của Deployment tăng (Deployment tăng generation khi annotation đổi, StatefulSet thì không) nhưng không rollout.
>
> **Bài học quan trọng #2 - tag bất biến biến rollback thành thật**: `:v1` bị build đè ở Phase 21 nên "rollback về v1" vô nghĩa. Tag = git SHA → mỗi revision Helm trỏ tới đúng 1 image không đổi, `helm rollback` chạy lại đúng bản cũ. Tag tính theo commit cuối động vào thư mục service (không phải `HEAD`) → commit `deploy(...)` hay sửa service khác không đổi tag. Nhưng `git revert` tạo commit mới → cùng nội dung với bản trước vẫn ra **tag mới** (tag theo commit, không theo nội dung).
>
> **Bài học quan trọng #3 - test và cluster bắt các loại lỗi khác nhau**: Demo B (logic) bị test chặn trước khi tốn build/push; Demo C (đóng gói - Dockerfile) qua được test vì test chạy trên host. Lớp cuối là readiness probe + `--rollback-on-failure` + rolling update `maxUnavailable: 0` → bản lỗi không bao giờ nhận traffic. Muốn bắt sớm hơn: chạy test **bên trong** image vừa build (`docker run <image> npm test`) hoặc smoke test container trước khi push.
>
> **Bài học quan trọng #4 - từ giờ `helm upgrade` tay phải có `-f helm-values/<svc>-image.yaml`**: thiếu file này, chart lấy `image.repository` trong `helm-values/<svc>.yaml` (`booking-service`, tag mặc định `v1`) → **quay về image cũ** (bản `kind load`, không có `bookingId`). Deploy app nên luôn đi qua `ci/pipeline.ps1`.
>
> **Bài học quan trọng #5 - local registry trên kind**: `kind` không cấu hình sẵn containerd đọc `certs.d` (`config_path = ''`) → phải bật `config_path` + `hosts.toml` trên mọi node (registry nói HTTP, tên `kind-registry` phân giải được vì cùng mạng Docker `kind`). Image trong cluster tên `localhost:5001/...` nhưng containerd được chỉ sang `http://kind-registry:5000`.
>
> **Bài học quan trọng #6 - Windows/PowerShell**: bật `$PSNativeCommandUseErrorActionPreference` thì mọi lệnh ngoài lỗi đều ném exception - kể cả lệnh "dọn dẹp" trong `catch` (vd. `git checkout` file chưa track) → phải tự kiểm tra trước khi gọi. Truyền mảng `-Service a,b` chỉ chạy được khi gọi script trong phiên PowerShell (`./ci/pipeline.ps1`), không qua `pwsh -File`. Git Bash tự đổi `/etc/...` thành `C:/Program Files/Git/etc/...` khi `docker exec` → `MSYS_NO_PATHCONV=1`. `"$node:"` trong chuỗi PowerShell là lỗi cú pháp (`:` = scope) → `"${node}:"`.
>
> **Bài học quan trọng #7 - `/tmp` của node kind là tmpfs**: `docker cp file node:/tmp/x` báo thành công nhưng bên trong container KHÔNG thấy file (docker cp ghi vào lớp filesystem bên dưới mount tmpfs). Copy vào thư mục không phải mount (vd. `/etc/containerd/`). Bài học phụ: lỗi bị file cũ còn sót che mất - kiểm thử script "idempotent" thì phải xoá trạng thái cũ trước khi chạy lại.

<a id="scenario-23b"></a>
### 23b - CD qua self-hosted runner (bổ sung 13/11/2026)

Bản đầu của Phase 23 chạy `ci/pipeline.ps1` bằng tay. Bổ sung: **runner GitHub Actions cài ngay trên máy chạy kind** → `git push` code là tự deploy.

```text
git push (đổi *-service/**) ──► GitHub ──► job "deploy" (cd.yaml) ──► runner trên máy local (C:\actions-runner)
                                                                       ├ guard.ps1 (hook trước job): đúng repo/workflow/ref/event?
                                                                       └ ci/pipeline.ps1 -Service <svc đổi>
                                                                           test → build → push localhost:5001 → commit tag + git push
                                                                           → đợi Argo CD → smoke (lỗi: git revert)
ci.yaml (runner GitHub, ubuntu): test + build cho cả PR, KHÔNG deploy
```

**Vì sao self-hosted:** runner của GitHub chạy trên cloud, không vào được kind / `localhost:5001`. Runner tự cài nằm cạnh cluster → dùng chung docker, kubeconfig, registry với `pipeline.ps1`.

**Chặn PR từ fork (repo public = ai cũng mở PR được):**

| Lớp | Ở đâu | Chặn gì |
|---|---|---|
| 1 | `cd.yaml`: không có trigger `pull_request` | PR không kích hoạt workflow CD |
| 2 | `cd.yaml`: `if:` repository + ref `main` + event push/workflow_dispatch | chạy nhầm trigger/nhánh |
| 3 | **`C:\actions-runner\guard.ps1`** (bản gốc `ci/runner-guard.ps1`), hook `ACTIONS_RUNNER_HOOK_JOB_STARTED` | **mọi** job không phải `cd.yaml@refs/heads/main` + push/dispatch - kể cả workflow PR **tự thêm** với `runs-on: self-hosted` |
| 4 | Settings → Actions → General → *Require approval for all external contributors* | workflow của người ngoài phải được duyệt mới chạy |

Lớp 1-2 không đủ: workflow của PR là **bản trong nhánh PR**, kẻ tấn công chỉ cần thêm file `.github/workflows/x.yaml` mới. Lớp 3 nằm trên máy runner, PR không sửa được.

```powershell
# Cài runner (1 lần) - KHÔNG chạy như Windows service: service chạy dưới NETWORK SERVICE, không có Docker Desktop/kubeconfig
mkdir C:\actions-runner; cd C:\actions-runner
# tải actions-runner-win-x64-2.338.2.zip + kiểm SHA256 (Settings -> Actions -> Runners -> New self-hosted runner), giải nén
.\config.cmd --url https://github.com/huybosch/k8s-grab --token <TOKEN 1 giờ> --name grab-mini-local --labels grab-mini --work _work --unattended

# Hook chặn job: lưu UTF-8 CÓ BOM (runner gọi bằng Windows PowerShell 5.1 - không BOM thì tiếng Việt lỗi font)
$t = Get-Content -Raw -Encoding utf8 D:\OBsidian\NUO3HC\Kubernetes\grab-mini\ci\runner-guard.ps1
[IO.File]::WriteAllText("C:\actions-runner\guard.ps1", $t, [Text.UTF8Encoding]::new($true))
"ACTIONS_RUNNER_HOOK_JOB_STARTED=C:\actions-runner\guard.ps1" | Set-Content C:\actions-runner\.env

# Chạy runner (dưới tài khoản Windows của bạn)
Start-Process C:\actions-runner\run.cmd -WorkingDirectory C:\actions-runner -WindowStyle Minimized

# tự chạy khi đăng nhập Windows (đã đăng ký 14/11/2026)
$a = New-ScheduledTaskAction -Execute C:\actions-runner\run.cmd -WorkingDirectory C:\actions-runner
Register-ScheduledTask -TaskName "GitHub Actions Runner (grab-mini)" -Action $a -Trigger (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME")
```

Code liên quan - `.github/workflows/cd.yaml` (rút gọn):

```yaml
on:
  push: { branches: [main], paths: ["*-service/**"] }
  workflow_dispatch: { inputs: { services: { required: true, default: booking } } }
permissions: { contents: write }                              # pipeline commit tag + git push / git revert
concurrency: { group: cd-main, cancel-in-progress: false }    # không huỷ deploy giữa chừng
jobs:
  deploy:
    if: github.repository == 'huybosch/k8s-grab' && github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'workflow_dispatch')
    runs-on: [self-hosted, grab-mini]
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }     # pipeline cần lịch sử: tag = SHA commit cuối của <svc>-service
      - id: pick                     # tự git diff before..HEAD - KHÔNG dùng action bên thứ 3 trên máy có quyền vào cluster
        run: ...                     # -> services=driver
      - run: ./ci/pipeline.ps1 -Service ($env:SERVICES -split ",")
```

`ci/runner-guard.ps1` (lõi):

```powershell
$workflow = "huybosch/k8s-grab/.github/workflows/cd.yaml@refs/heads/main"
if ($env:GITHUB_REPOSITORY -ne "huybosch/k8s-grab")                   { $why += "repo" }
if (@("push","workflow_dispatch") -notcontains $env:GITHUB_EVENT_NAME) { $why += "event" }
if ($env:GITHUB_REF -ne "refs/heads/main")                             { $why += "ref" }
if ($env:GITHUB_WORKFLOW_REF -ne $workflow)                            { $why += "workflow" }
if ($why.Count -gt 0) { exit 1 }   # runner huỷ job, không chạy bước nào
```

**Kết quả thực tế:**
- Thử hook bằng env giả lập: push / dispatch `cd.yaml@main` → exit 0; workflow lạ từ `refs/pull/9/merge`, workflow lạ trên `main`, `cd.yaml` từ nhánh `feature` → exit 1.
- Đăng ký runner `grab-mini-local` (label `grab-mini`), log `Listening for Jobs`.
- **Deploy thật:** push `1778048` (sửa comment `driver-service/server.js`) → `cd` success, `ci` success. Runner tự commit `105a6f5 deploy(driver): 17780489fb4a`; cluster chạy `localhost:5001/driver-service:17780489fb4a`. Log Worker: `Pre Job Hook` chạy `guard.ps1` → exit 0 (ngữ cảnh GitHub thật khớp).
- **Không lặp:** commit deploy `105a6f5` push bằng `GITHUB_TOKEN` → GitHub **không** tạo run mới.
- **Chặn workflow lạ** (mô phỏng PR tự thêm workflow): nhánh `test-evil` có `evil.yaml` (`runs-on: [self-hosted, grab-mini]`, chạy `kubectl get nodes`) → job `failure` ở bước *Set up runner* (hook), bước `kubectl` **skipped**. Đã xoá nhánh.

> **Bài học quan trọng #8 - self-hosted runner + repo public**: runner có quyền gì thì job chạy trên nó có quyền đó (ở đây: docker, kubeconfig, push Git). Điều kiện trong YAML không bảo vệ được vì PR mang **workflow của chính nó** → phải chặn ở **phía runner** (hook trước job; với organization: runner group chỉ cho workflow chỉ định) + bắt duyệt workflow người ngoài. GitHub khuyến cáo không dùng self-hosted runner cho repo public; lab này chấp nhận vì có hook + chỉ chạy trên `main`.
>
> **Bài học quan trọng #9 - commit bằng `GITHUB_TOKEN` không kích hoạt workflow**: pipeline commit tag rồi push lại `main` mà không lặp vô hạn - GitHub cố ý không tạo run mới cho push bằng `GITHUB_TOKEN`. Đổi sang PAT/deploy key thì phải tự chống lặp (vd. `paths-ignore: helm-values/*-image.yaml`).
>
> **Runner phải đang chạy**: tắt máy / tắt `run.cmd` → job `cd` nằm chờ (queued) tới khi runner quay lại (GitHub huỷ nếu chờ quá 24 giờ). Deploy tay `./ci/pipeline.ps1` vẫn dùng được như cũ.

---

<a id="scenario-24"></a>
## Scenario 24 - GitOps: Argo CD + app-of-apps, deploy = git push (Phase 24)

```text
máy local: ci/pipeline.ps1 -Service <svc>                       GitHub: huybosch/k8s-grab (public)
  1 test     npm ci + node --test                                  │  Actions ci.yaml: test -> build -> chạy thử container
  2 build    docker build + CHẠY THỬ container (GET /health)       │  (KHÔNG push image, KHÔNG deploy)
  3 push     localhost:5001/<svc>-service:<git-sha>                │
  4 release  commit helm-values/<svc>-image.yaml + git push ──────►│ main
  5 sync     đợi Argo CD: Synced@<commit> + Healthy + rollout       │
  6 smoke    gọi qua Ingress                                        ▼ poll 60s (+ pipeline chủ động refresh)
  lỗi 5/6 -> git revert <commit deploy> + git push            Argo CD (namespace argocd, trong cluster)
                                                                 root ──► argocd/apps/ ──► AppProject grab-mini
                                                                                       ├─► ApplicationSet ──► booking, payment, user
                                                                                       └─► grab-platform
```

Pipeline **không còn ghi vào cluster** (không `helm upgrade`, không `kubectl apply`) - chỉ ghi vào Git. Argo CD kéo Git về, render chart bằng `helm template`, apply bằng server-side apply. Không có webhook (GitHub không vào được cluster trên máy cá nhân) → Argo CD poll Git mỗi 60s, pipeline annotate `argocd.argoproj.io/refresh` để khỏi đợi.

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1: cài Argo CD (Helm, chart pin version) ---
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd --version 10.16.0 -n argocd --create-namespace -f k8s/argocd/values.yaml --wait --timeout 5m
# UI: kubectl port-forward svc/argocd-server -n argocd 8081:80  -> http://localhost:8081, user admin, password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | %{ [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }

# --- Bước 2: kiểm tra TRƯỚC khi Argo CD tiếp quản: render kiểu Argo CD (helm template) == manifest Helm đang chạy ---
#   (khác 1 dòng = Argo CD apply khác = có thể rollout lại Pod)
$s = "booking"; $a = helm template $s charts/grab-service -n default -f helm-values/$s.yaml -f helm-values/env-prod.yaml -f helm-values/booking-prod.yaml -f helm-values/$s-image.yaml
(($a -join "`n").Trim() -eq ((helm get manifest $s) -join "`n").Trim())   # True (4/4 release)

# --- Bước 3: đẩy repo lên GitHub (repo trống, public -> Argo CD đọc không cần token) ---
git remote add origin https://github.com/huybosch/k8s-grab.git
git push -u origin main

# --- Bước 4: bootstrap - lệnh kubectl apply DUY NHẤT (chạy kèm traffic loop, ghi lại tên Pod trước/sau) ---
kubectl apply -f argocd/root.yaml
kubectl get applications -n argocd        # 5 app Synced Healthy

# --- Bước 5: Helm "buông" release: xoá bản ghi release (Secret sh.helm.release.*) - KHÔNG xoá object nào ---
#   còn để lại: `helm uninstall booking` sẽ xoá Deployment mà Argo CD đang quản lý; `helm rollback` đánh nhau với selfHeal
kubectl delete secret -n default -l owner=helm
helm list -n default                      # rỗng

# --- Bước 6: dọn manager `helm` khỏi managedFields (lặp lại bài học #1 Scenario 23, xem bài học #3 dưới) ---
./ci/migrate-field-managers.ps1 -ArgoApp booking,payment,user,grab-platform -LegacyManagers helm -DryRun
./ci/migrate-field-managers.ps1 -ArgoApp booking,payment,user,grab-platform -LegacyManagers helm

# --- Demo A: tính năng mới qua GitOps ---
#   payment-service/server.js: thêm transactionId: randomUUID() (+ test) -> git commit
./ci/pipeline.ps1 -Service payment

# --- Demo B: selfHeal - sửa tay cluster ---
kubectl delete svc user-service                                          # Argo CD tạo lại
Set-Content $env:TEMP\p.json '{"data":{"DB_HOST":"hacked-host"}}'; kubectl patch cm booking-config --type merge --patch-file $env:TEMP\p.json   # đưa về "postgres"
Set-Content $env:TEMP\p.json '{"data":{"HACKED":"by-hand"}}';      kubectl patch cm booking-config --type merge --patch-file $env:TEMP\p.json   # KHÔNG bị xoá (bài học #2)

# --- Demo C: bản lỗi qua được test -> Argo CD sync -> timeout -> git revert ---
#   user-service/Dockerfile: CMD ["node", "server.jss"] -> git commit
./ci/pipeline.ps1 -Service user           # 5/6 timeout 180s -> git revert <deploy commit> + push -> Argo CD về tag cũ
git revert --no-edit <commit sửa Dockerfile>; git push   # pipeline chỉ revert commit DEPLOY, commit code lỗi phải tự revert

# --- xem trạng thái ---
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision
git log --oneline -8
```

**📄 Code liên quan:**

- `k8s/argocd/values.yaml` (mới) - `server.insecure: true` (UI qua port-forward HTTP), `timeout.reconciliation: 60s` (poll Git, mặc định 180s), `controller.diff.server.side: "true"` (so sánh Git/cluster bằng server-side dry-run - API server tự điền default, không OutOfSync giả ở `volumeClaimTemplates`), tắt Dex + notifications, request nhỏ cho kind.
- `argocd/root.yaml` (mới) - Application `root` (project `default`) trỏ `path: argocd/apps`, `automated: {prune, selfHeal}`. Thêm/sửa/xoá app từ giờ = sửa file trong `argocd/apps/` rồi push.
- `argocd/apps/project.yaml` (mới) - AppProject `grab-mini`: chỉ repo này, chỉ namespace `default`, `clusterResourceWhitelist: []` (app không được tạo ClusterRole/Namespace...). `sync-wave: "-1"` → tạo trước các Application dùng nó.
- `argocd/apps/services.yaml` (mới) - ApplicationSet `grab-services`, generator `list` (booking/payment/user) → 3 Application dùng chung chart `charts/grab-service`:

  ```yaml
  helm:
    releaseName: "{{.svc}}"          # PHẢI trùng tên release Helm cũ (label instance trong pod template)
    valueFiles:
      - "../../helm-values/{{.svc}}.yaml"
      - ../../helm-values/env-prod.yaml
      - "../../helm-values/{{.svc}}-prod.yaml"   # chỉ booking có
      - "../../helm-values/{{.svc}}-image.yaml"  # pipeline ghi tag vào đây
    ignoreMissingValueFiles: true
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [ServerSideApply=true]
  ```

- `argocd/apps/grab-platform.yaml` (mới) - như trên nhưng `prune: false`: chart có Postgres + PVC, lỡ xoá/đổi tên trong Git không được kéo theo xoá dữ liệu.
- `ci/pipeline.ps1` (viết lại) - stage 4 `release`: ghi `helm-values/<svc>-image.yaml` (luôn LF) → commit `deploy(<svc>): <sha>` → `git push origin HEAD:main`. Stage 5 `Wait-ArgoSync`: annotate refresh, đợi `sync.revision == HEAD` + `Synced` + `Healthy` + không có operation `Running`, chốt bằng `kubectl rollout status` (chỉ đọc). Lỗi ở 5/6 → `git revert` commit deploy + push + đợi sync + smoke. Guard thêm: `argocd/` phải sạch, local không được tụt sau `origin/main`. Hàm mới `Test-Container`: `docker run` image vừa build, `docker exec ... wget /health` (port lấy từ `EXPOSE`), container thoát → in 5 dòng log cuối.
- `ci/migrate-field-managers.ps1` - thêm `-ArgoApp`: lấy object từ `status.resources` của Application (Helm release đã bị xoá nên không còn `helm get manifest`).
- `.github/workflows/ci.yaml` (viết lại) - chỉ **CI**: `changes` → `check` (matrix: `npm test` → build `load: true` → `container smoke (/health)`). Bỏ push GHCR + job `record` của Phase 23.

**✅ Kết quả thật đã verify (11/11/2026):**

- Argo CD 3.6.1 (chart 10.16.0) cài xong trong 77s, 6 Pod trên `grab-mini-worker`.
- `helm template` (cách Argo CD render) **giống hệt từng byte** `helm get manifest` của cả 4 release → bootstrap `root`: 5 app `Synced Healthy` ở commit `a4fca91`; tên 12 Pod trước/sau **không đổi** (không rollout), traffic `/booking` **64/64 OK**. Deployment có annotation `argocd.argoproj.io/tracking-id: booking:apps/Deployment:default/booking`; managedFields: `helm` + `argocd-controller` cùng sở hữu.
- Xoá 18 Secret `sh.helm.release.*` → `helm list` rỗng, Argo CD vẫn 5/5 `Synced Healthy`. `migrate-field-managers -LegacyManagers helm`: 20 object, `generation` Deployment trước/sau `21 30 16` / `21 30 16` (không rollout).
- GitHub Actions: 6/6 run `success` (`changes` 6s, `check` 17-22s/service; bản thêm `container smoke (/health)` cũng pass cả 3).
- **Demo A** (`transactionId`): 38s tổng (test 2.5s, build 3.4s, push 1.3s, release 3s, **sync 25s**, smoke 2s). Argo CD: `Synced@a4fca91 Healthy` → `Synced@ffdcc54 Progressing` → `Healthy`. Response có `"transactionId":"07be30ef-..."`. Traffic `/booking` (gọi qua payment) **345/345 OK**.
- **Demo B** (selfHeal): xoá `Service user-service` → tạo lại sau **1s**; `DB_HOST=hacked-host` → về `postgres` sau **1s**; key lạ `HACKED` **vẫn còn sau 120s**, app vẫn `Synced` (managedFields: `kubectl-patch Update f:HACKED` - field không thuộc Argo CD). Phải tự xoá.
- **Demo C** (`CMD server.jss`): test/build/push OK → commit `463a1ef` → `Synced@463a1ef Progressing` suốt **180s** (không bao giờ `Degraded`, xem bài học #4) → pipeline `git revert` → `f462f61` → `Synced Healthy` sau ~10s → smoke OK. Tổng 200s; 3 Pod `user` vẫn chạy `f7958a35c003` suốt quá trình; traffic `/users` **1132/1132 OK**. CI GitHub của commit lỗi cũng **success** (chỉ build, không chạy image) → thêm `Test-Container`: image lỗi bị bắt sau **0.5s** (`MODULE_NOT_FOUND`), 3 image tốt pass.
- Chạy lại `booking` (code không đổi): ra tag mới `82affcb71c1a` (commit revert Demo C của Scenario 23 - cùng nội dung `5f5a024b8892`), 31s, sync 16s.

> **Bài học quan trọng #1 - đổi công cụ quản lý (Helm → Argo CD) mà không restart Pod**: điều kiện là Argo CD render **giống hệt** manifest đang chạy - kiểm tra bằng `helm template` vs `helm get manifest` trước khi bootstrap. Bẫy cụ thể: `releaseName` phải trùng tên release cũ vì pod template có label `app.kubernetes.io/instance: {{ .Release.Name }}` (Argo CD mặc định dùng tên Application). Sau đó **Helm phải buông**: xoá Secret `sh.helm.release.*` (chỉ là bản ghi, không xoá object), nếu không `helm uninstall`/`helm rollback` vẫn tác động vào object của Argo CD.
>
> **Bài học quan trọng #2 - selfHeal chỉ sửa field Argo CD sở hữu**: với server-side apply/diff, Argo CD so sánh đúng các field nó đã apply. Xoá object hay đổi giá trị field có trong Git → về lại sau ~1s. Nhưng **thêm** field/key mới bằng tay (manager khác) → Argo CD không coi là drift, vẫn `Synced`. GitOps không thay được RBAC: muốn chặn sửa tay thì bỏ quyền ghi của người dùng vào namespace.
>
> **Bài học quan trọng #3 - field manager cũ chặn việc XOÁ field**: sau khi tiếp quản, `helm` vẫn đồng sở hữu mọi field. Đổi giá trị thì không sao (Argo CD dùng force), nhưng xoá 1 field khỏi Git thì server-side apply **không xoá trên cluster** vì manager `helm` vẫn giữ. Lần 2 gặp cùng 1 vấn đề (Scenario 23 là `kubectl` → Helm) → mỗi lần đổi công cụ quản lý: dọn manager cũ.
>
> **Bài học quan trọng #4 - rollback trong GitOps là `git revert`, và Argo CD không tự rollback**: Argo CD chỉ làm cho cluster giống Git - bản lỗi vẫn ở `Progressing` cho tới `progressDeadlineSeconds` (mặc định 600s) mới thành `Degraded`. Ai quyết định "lỗi" là pipeline (timeout 180s) → `git revert` commit deploy → Git lại đúng → Argo CD sync bản cũ. `helm rollback`/`kubectl rollout undo` sẽ bị selfHeal đè lại ngay. Lịch sử deploy + rollback nằm hết trong `git log`. Commit code lỗi vẫn phải revert riêng.
>
> **Bài học quan trọng #5 - bắt lỗi đóng gói trước khi deploy**: Demo C lọt qua `npm test` (chạy trên host) **và** CI GitHub (chỉ build). Chạy thử container + `/health` sau build tốn ~1s và chặn được lỗi trước khi tốn 3 phút chờ cluster.
>
> **Bài học quan trọng #6 - CI ở đâu, CD ở đâu**: runner GitHub không vào được cluster kind và cluster không kéo được image GHCR private. Nếu để CI commit tag `ghcr.io/...` như bản Phase 23 → Argo CD sync xong Pod `ImagePullBackOff`. Tách: GitHub Actions = kiểm tra (test + build + chạy thử), pipeline local = build/push registry local + commit tag. Trên cluster thật (EKS): CI push ECR/GHCR + commit tag, Argo CD trong cluster kéo về - không ai cần `kubeconfig` ngoài cluster.

---

<a id="scenario-25"></a>
## Scenario 25 - Final Project: ráp đủ Grab Mini Platform (5 service + Redis + PostgreSQL)

```text
                    ingress-nginx (localhost:80)
        /users        /booking         /drivers        /payment(s)
          │              │                │                │
          ▼              ▼                ▼                ▼
       user x3       booking x2-10     driver x3       payment x3 ──► PostgreSQL (user DB "payment": SELECT+INSERT)
          │           │       │           │                ▲
          ▼           │       └──────┐    │                │ db-init Job (Argo CD PostSync): role + bảng payments
        Redis         └──► payment   ▼    ▼
     (cache, views)        (retry +  notification x2   (chỉ nội bộ, không có route Ingress)
                            idempotency key)

   phụ thuộc QUAN TRỌNG (lỗi = lỗi):        booking → payment → PostgreSQL
   phụ thuộc KHÔNG quan trọng (lỗi = null): user → Redis, booking/driver → notification
```

Mọi thay đổi đi qua Git → Argo CD (Scenario 24): platform (Redis, Job, NetworkPolicy, Ingress) = sửa chart + `git push`; service = `./ci/pipeline.ps1`. Thứ tự deploy theo phụ thuộc: platform → `notification` → `driver` → `payment` → `user` → `booking`.

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- Bước 1: Secret DB riêng cho payment (ngoài Git, password ngẫu nhiên, không in ra) ---
$pw = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) -replace '[+/=]', ''
kubectl create secret generic payment-db --from-literal=DB_USERNAME=payment --from-literal=DB_PASSWORD=$pw; Remove-Variable pw

# --- Bước 2: platform + code + values -> git push (ApplicationSet CHƯA thêm driver/notification) ---
git commit -am "feat(final): platform + code 5 service"; git push
kubectl logs job/db-init                       # CREATE ROLE / ALTER ROLE / CREATE TABLE / GRANT / db-init done
kubectl get application grab-platform -n argocd -o json | ConvertFrom-Json | % { $_.status.resources | ? requiresPruning }
kubectl delete netpol allow-booking-payment-to-postgres   # policy cũ: đã xoá khỏi Git nhưng prune: false -> phải tự xoá

# kiểm tra quyền mạng (nc từ trong Pod)
kubectl exec deploy/booking -- nc -z -w 2 postgres 5432; $LASTEXITCODE   # 1 = BLOCKED
kubectl exec deploy/payment -- nc -z -w 2 postgres 5432; $LASTEXITCODE   # 0 = OPEN
kubectl exec deploy/user    -- nc -z -w 2 redis 6379;    $LASTEXITCODE   # 0

# --- Bước 3: service mới - mỗi lần thêm 1 element vào argocd/apps/services.yaml, commit, rồi pipeline ---
git commit -am "feat(argocd): thêm Application notification"; ./ci/pipeline.ps1 -Service notification
git commit -am "feat(argocd): thêm Application driver";       ./ci/pipeline.ps1 -Service driver
./ci/pipeline.ps1 -Service payment,user,booking

# --- Bước 4: verify end-to-end ---
curl.exe -s -X POST http://localhost/booking -H "Content-Type: application/json" -d '{}'
curl.exe -s http://localhost/payments/stats
kubectl exec postgres-0 -- psql -U postgres -d grabmini -tAc "SELECT count(*) FROM payments"
curl.exe -s -X POST http://localhost/drivers/driver-1/accept -H "Content-Type: application/json" -d '{"bookingId":"b-42"}'
kubectl logs -l app=notification --tail 5

# --- Bước 5: đo zero-downtime khi 5 service rollout CÙNG LÚC (traffic loop 5 endpoint ở terminal khác) ---
kubectl rollout restart deploy booking payment user driver notification   # restartedAt không thuộc Argo CD -> không bị selfHeal đè
```

**📄 Code liên quan:**

- `payment-service/server.js` - `pg` 8.23.1, `Pool` (`max 5`, `connectionTimeoutMillis`/`query_timeout` 1500ms, `pool.on("error")` để client rảnh bị ngắt không làm crash process). `POST /payment`: validate `amount`, nhận `paymentId` (idempotency key, phải là UUID) → `INSERT ... ON CONFLICT (id) DO NOTHING`; DB lỗi → **503 `database unavailable`**. `GET /payments/stats`. `/health` **không** kiểm tra DB (DB chết mà liveness fail = kubelet restart toàn bộ Pod payment vô ích). DB inject được qua `app.set("db", ...)` để test không cần PostgreSQL.
- `booking-service/server.js` - `callPayment(paymentId)`: tối đa 2 lần × 1s, retry khi lỗi kết nối / timeout / 5xx (không retry 4xx), `paymentId = bookingId`. `notify()`: timeout 1s, lỗi → `notification: null`, booking vẫn 200. Bỏ `envFrom` DB (booking không dùng DB).
- `user-service/server.js` - `redis` 6.3.0 (`disableOfflineQueue: true`: mất kết nối → lệnh lỗi ngay thay vì xếp hàng; `reconnectStrategy` tối đa 2s). `GET /users` → `INCR users:views` với timeout 300ms; Redis lỗi/treo → `views: null`.
- `driver-service/server.js` (viết lại) - `GET /drivers`, `POST /drivers/:id/accept` → báo notification (best-effort như booking), 404 nếu tài xế không tồn tại. `notification-service/server.js` (viết lại) - `POST /notify` ghi 1 dòng log JSON (Loki thu được), trả `notificationId`. Cả hai: `metrics.js`, `server.test.js`, export `app`, `.dockerignore`, `npm ci`.
- Test: 25 test (`booking` 6, `payment` 7, `user` 5, `driver` 4, `notification` 3) - mỗi phụ thuộc đều có server/client **giả** và test trường hợp phụ thuộc chết/treo.
- `charts/grab-platform/templates/redis.yaml` (mới) - Deployment `redis:7.4-alpine` 1 replica, `--save "" --appendonly no --maxmemory 64mb --maxmemory-policy allkeys-lru` (cache, không lưu đĩa), `strategy: Recreate`, probe `redis-cli ping`.
- `charts/grab-platform/templates/db-init.yaml` (mới) - Job hook `argocd.argoproj.io/hook: PostSync` (+ `helm.sh/hook: post-install,post-upgrade`), `hook-delete-policy: BeforeHookCreation`, label `app: db-init`. `psql`: tạo role `payment` nếu chưa có (`\gexec`), `ALTER ROLE ... PASSWORD :'app_password'` (từ Secret `payment-db`), `CREATE TABLE IF NOT EXISTS payments`, `GRANT SELECT, INSERT`.
- `charts/grab-platform/templates/networkpolicies.yaml` (viết lại) - khai báo theo values: `appPorts` (app → containerPort), `public` (có route Ingress), `allow` (mỗi dòng `{to, from[], port}` → 1 policy `allow-<from>-to-<to>`):

  ```yaml
  allow:
    - { to: payment, from: [booking], port: 3004 }
    - { to: notification, from: [booking, driver], port: 3005 }
    - { to: postgres, from: [payment, db-init], port: 5432 }   # booking KHÔNG còn vào DB
    - { to: redis, from: [user], port: 6379 }
  ```

- `charts/grab-platform/values.yaml` - route Ingress `/drivers`, `/payments`; `dbInit`, `redis`.
- `charts/grab-service/templates/deployment.yaml` - `topologySpreadConstraints.matchLabelKeys: ["pod-template-hash"]`.
- `helm-values/driver.yaml`, `notification.yaml`, `notification-prod.yaml` (`replicaCount: 2`) (mới); `payment.yaml` (`envFrom` `booking-config` + `payment-db`), `user.yaml` (`REDIS_URL`), mọi service có `resources` (requests 50m/64Mi, limit memory 256Mi); `env-prod.yaml`: `preStopSleepSeconds: 10` cho mọi service.
- `argocd/apps/services.yaml` - thêm element `notification`, `driver`. `ci/pipeline.ps1` - `ValidateSet` 5 service; `Wait-ArgoSync` chờ được Application **chưa tồn tại** (refresh `root`); smoke `driver` qua Ingress, `notification` qua `kubectl exec deploy/booking -- wget` (không có route Ingress). `ci.yaml`: `paths: ["*-service/**"]` + filter 5 service. `alerts-apps.yaml` + dashboard: `job=~"(booking|payment|user|driver|notification)-service"`.

**✅ Kết quả thật đã verify (11/11/2026):**

- Push platform: Redis chạy, `db-init` in `CREATE ROLE / ALTER ROLE / CREATE TABLE / GRANT / db-init done`; 3 service cũ rollout vì đổi values; traffic `/booking` `/users` `/payment` **2046/2046 OK**.
- `grab-platform` kẹt `OutOfSync`: `NetworkPolicy/allow-booking-payment-to-postgres requiresPruning=True`. Trước khi xoá: `booking → postgres:5432` **OPEN** (Git đã cấm nhưng cluster vẫn cho). `kubectl delete netpol` → booking **BLOCKED**, payment OPEN, app về `Synced`. Ma trận cuối: booking→postgres BLOCKED, user→postgres BLOCKED, user→redis OPEN, booking→redis BLOCKED.
- `notification` 29s, `driver` 28s - pipeline in `chưa có Application -> refresh root` rồi `Synced Healthy` sau ~13s. `payment` 38s, `user` 43s, `booking` 29s; traffic **1737/1737 OK**.
- End-to-end: booking `0cf6676c-...` → dòng `aa84d643-...|100.00` trong bảng `payments`; role `payment` chỉ có `INSERT,SELECT`; log notification có `bookingId` + `transactionId`; `views` 251 → 252 → 253. `driver-1/accept` → `"notification":{"type":"driver-accepted",...}`. User Redis thật (container tạm trên máy): views 1 → 2; dừng Redis → `views: null` sau 3ms.
- **Lỗi 1**: `/payments/stats` → **404 của nginx** - Prefix `/payment` không khớp `/payments` → thêm route `/payments`.
- **Lỗi 2**: 2 Pod `booking` cùng nằm trên `grab-mini-worker` dù có topologySpread `maxSkew: 1, DoNotSchedule` → thêm `matchLabelKeys: ["pod-template-hash"]` → sau rollout: booking 1/1, service 3 replica 1/2.
- **Lỗi 3 - rớt request khi 5 service rollout cùng lúc** (đổi chart/`env-prod.yaml` dùng chung):

  | Cấu hình | Traffic (5 endpoint) | Lỗi |
  |---|---|---|
  | chỉ booking có `preStop 5s` | 1769 / 1 | `/users` lỗi kết nối |
  | mọi service `preStop 5s` | 4790 / 5 | 3× booking 503 (log: `ECONNREFUSED`, 2× `timeout 2000ms`), 2× treo 5s (`/payment`, `/drivers/.../accept`) |
  | `preStop 10s` + booking retry có idempotency key | **5265 / 0** | không lần retry nào xảy ra |

  Thử giả thuyết "NetworkPolicy cho Pod mới áp chậm": Pod mới (`app=notification`) → booking connect được **ngay lần thử đầu**, cả trong `default` (có policy) lẫn namespace không có policy → **bác bỏ**. Metric kube-proxy (`kubeproxy_network_programming_duration_seconds`, iptables, `minSyncPeriod: 1s`): trung bình 2.3s, 98% < 3s, **đuôi tới 25-37s** → Pod cũ vẫn nhận kết nối sau khi đã tắt.
- Sau cùng: 7 Application `Synced Healthy`; Prometheus **35/35** target `up` (5 service), chỉ `Watchdog` firing; 4940 payment trong DB; GitHub Actions `success` mọi commit. Phân bố: `worker`: booking, driver, notification, payment, user ×1 + postgres; `worker2`: booking ×1, driver/payment/user ×2, notification ×1 + redis.

> **Bài học quan trọng #1 - phân loại phụ thuộc trước khi viết code gọi nó**: payment/DB là phụ thuộc **quan trọng** (không trừ được tiền thì booking phải lỗi - trả 503 rõ ràng, nhanh). Redis, notification là **không quan trọng** → timeout ngắn (300ms-1s) + trả `null`, request chính vẫn 200. Không phân loại thì 1 cache chết kéo sập cả `/users`. `/health` không được kiểm tra phụ thuộc (DB chết ≠ Pod payment hỏng; liveness fail sẽ restart vô ích).
>
> **Bài học quan trọng #2 - retry POST chỉ an toàn khi có idempotency key**: lỗi kết nối/timeout không cho biết request đã tới DB hay chưa. Retry mù = có thể trừ tiền 2 lần. `paymentId = bookingId` + `INSERT ... ON CONFLICT DO NOTHING` → gọi bao nhiêu lần cũng 1 dòng. Không retry 4xx (gọi lại vẫn sai).
>
> **Bài học quan trọng #3 - `preStop` là cược với độ trễ cập nhật mạng**: endpoint của Pod đang tắt được gỡ ngay, nhưng kube-proxy (iptables) và ingress-nginx cần thời gian áp vào - đo được trung bình 2.3s, đuôi > 25s, và tệ hơn khi nhiều Deployment rollout cùng lúc. 5s đủ cho 1 service rollout tuần tự (0 lỗi ở mọi lần pipeline), không đủ cho 5 service cùng lúc. Phòng thủ nhiều lớp: preStop dài hơn + client retry (an toàn nhờ #2) + tránh rollout đồng loạt (sửa file dùng chung như `env-prod.yaml` = rollout mọi service).
>
> **Bài học quan trọng #4 - topologySpread đếm cả Pod của revision cũ**: lúc rolling update, Pod cũ cùng label vẫn được tính → Pod mới dồn về node ít Pod cũ → xoá Pod cũ xong thì lệch. `matchLabelKeys: [pod-template-hash]` = chỉ đếm Pod cùng ReplicaSet.
>
> **Bài học quan trọng #5 - `prune: false` để lại quyền cũ**: đổi tên/xoá NetworkPolicy trong Git thì policy cũ vẫn chạy - ở đây là **lỗ hổng** (booking vẫn vào được DB). Argo CD có báo (`OutOfSync` + `requiresPruning`) nhưng không tự sửa → phải kiểm tra `requiresPruning` sau mỗi lần đổi platform và xoá có chủ đích. Least privilege kiểm chứng bằng **phép thử thật** (`nc` từ trong Pod), không phải đọc YAML.
>
> **Bài học quan trọng #6 - Ingress `pathType: Prefix` khớp theo đoạn path**: `/payment` khớp `/payment` và `/payment/x`, KHÔNG khớp `/payments` (404 trả từ nginx, request không tới app).
>
> **Bài học quan trọng #7 - least privilege cho DB ở 3 lớp**: (1) mạng - chỉ `payment` + `db-init` vào được `postgres:5432`; (2) credential - booking không còn `envFrom` Secret DB, payment có user riêng; (3) quyền SQL - role `payment` chỉ `SELECT, INSERT` (không `UPDATE/DELETE/DROP`), superuser chỉ Job `db-init` dùng. Đây là nền cho Incident 7.

---

<a id="scenario-26"></a>
## Scenario 26 - Production Simulation: Incident 1-7 (gây sự cố thật, đo, xử lý, vá)

Mỗi incident: gây sự cố trên cluster thật **trong lúc có traffic** → đo ảnh hưởng tới người dùng → xử lý → tìm nguyên nhân gốc → vá (qua Git/Argo CD) → đo lại. Công cụ mới trong `ci/`:

| File | Dùng để |
|---|---|
| `ci/traffic.ps1` | traffic tuần tự qua Ingress (5 endpoint), in ok/fail/slow theo endpoint + **thời điểm từng lỗi** |
| `ci/load.js` | tải song song: `node ci/load.js <url> <luồng> <giây> [method] [pauseMs]`, in ok/fail/p95 mỗi giây; `LOAD_TIMEOUT_MS` cho request dài |
| `ci/slow-burst.js` | bắn N request chậm cùng lúc, in **Pod nào** trả lời (Incident 5) |
| `ci/rollback.ps1` | rollback GitOps 1 lệnh: `git revert` commit gần nhất đổi `helm-values/<svc>*` + push + refresh Argo CD + đợi |
| `ci/attack-surface.ps1` | "kẻ tấn công có shell trong Pod": thử mọi đường mạng + credential, in OPEN/BLOCKED |

### Tổng hợp

| # | Incident | Ảnh hưởng đo được | Giải pháp đã áp dụng (verify lại) |
|---|---|---|---|
| 1 | 1 Pod booking chết (`kill -9`) | 0/754, **7**/~6000, 0/13 313 lỗi - chỉ request **đang xử lý dở** trên Pod chết; container restart tại chỗ sau 17-20s; mất 50% công suất (2 Pod) | booking HPA `min 3` + PDB `minAvailable 2`; alert restart/NoPods phủ đủ 5 service + redis/postgres |
| 2 | Release v2 lỗi (config) | **686/1320** booking lỗi; alert sau 132s; tổng 5 phút (rollback chờ Argo CD poll 67s) | `ci/rollback.ps1`: Synced sau **12s** |
| 3 | Traffic 10x (16 → 160 req/s) | **0/31 055** lỗi, p95 12 → 17-33ms; HPA 3 → 10 trong 73s nhưng **chạm trần** (CPU 70-83% > 50%); payment ~113% CPU request | booking `maxReplicas 20`; payment HPA 3-10 (chuyển quyền `replicas` trước - không mất Pod nào) |
| 4 | Node chạy payment chết | trước vá: 8 lỗi tuần tự + 14/12 030 (timeout 5s), Redis mất > 5 phút | nginx `proxy-connect-timeout 1s` + `next-upstream` → **3** lỗi + 8/12 336; Redis `tolerationSeconds 30` → lên lại sau **86s** |
| 5 | Deploy lúc request dài 15s | **30/30 OK**, 16 request được Pod **đã bị xoá** trả lời trọn vẹn; request 35s (> grace) → Pod bị kill, nginx gửi lại GET (67s, chạy 2 lần) | đã đúng sẵn: `grace 30 ≥ preStop 10 + 15 + dư` - ghi quy tắc |
| 6 | Memory leak | 18 → 226 MiB trong 77s, **cả 3 Pod OOMKilled cùng lúc** → `/users` sập ~8s (~670 lỗi); alert sau OOM 50s | rollback 25s; alert mới `MemoryNearLimit` + `MemoryLeakSuspected` (`predict_linear` - backtest: báo **trước** OOM 28s) |
| 7 | user-service bị chiếm, tìm đường vào DB | DB/service khác **đã chặn** từ trước; nhưng **Internet, Kubernetes API (có token), Argo CD, Grafana: OPEN** | NetworkPolicy **egress** cho 5 app (sinh từ cùng `allow` list) + `automountServiceAccountToken: false` → chỉ còn Redis + DNS |

Phát hiện thêm trong lúc chạy: **race keep-alive** nginx ↔ Node (1 lần 502 / 3h) → `keepAliveTimeout 65s`; pipeline **revert oan** khi HPA `Degraded` thoáng qua → chỉ fail khi Degraded > 30s; HPA **scale lên 19 Pod** khi nâng `maxReplicas` ngay sau spike.

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini
./ci/traffic.ps1 -Seconds 15          # baseline: 510/510 OK

# ---------- Incident 1: Pod chết (crash thật: kill -9 process từ node, như Scenario 8) ----------
$job = Start-Job { node D:\OBsidian\NUO3HC\Kubernetes\grab-mini\ci\load.js http://127.0.0.1/booking 20 30 POST }
$pod = kubectl get pods -l app=booking -o jsonpath='{.items[0].metadata.name}'; $node = kubectl get pod $pod -o jsonpath='{.spec.nodeName}'
$cid = (docker exec $node crictl ps --label "io.kubernetes.pod.name=$pod" --name booking -q).Trim()
docker exec $node kill -9 (docker exec $node crictl inspect --output go-template --template '{{.info.pid}}' $cid).Trim()
kubectl get pod $pod -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'   # exitCode 137
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --since=1m | Select-String "Connection refused"   # nginx thử Pod khác

# ---------- Incident 2: release lỗi -> phát hiện -> rollback ----------
#   helm-values/booking.yaml: VERSION: v2 + BUGGY: "true" -> git commit + push (không qua pipeline)
kubectl logs -n monitoring deploy/alert-webhook | Select-String HighErrorRate   # FIRING sau ~2 phút
./ci/rollback.ps1 -Service booking                                              # git revert + push + refresh + đợi

# ---------- Incident 3: 1x (1 luồng, nghỉ 40ms ~16 req/s) -> 10x (10 luồng) ----------
node ci/load.js http://127.0.0.1/booking 1 300 POST 40      # terminal 1 (nền)
node ci/load.js http://127.0.0.1/booking 9 180 POST 40      # terminal 2, sau 60s
kubectl get hpa -w; kubectl top pods -l 'app in (booking,payment,postgres)'
# bật HPA cho Deployment ĐANG chạy: chuyển quyền spec.replicas sang manager khác TRƯỚC khi push chart bỏ replicas
'{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"name":"payment","namespace":"default"},"spec":{"replicas":3}}' | kubectl apply --server-side --field-manager=handover-to-hpa -f -
git push    # helm-values/payment-prod.yaml (autoscaling) -> spec.replicas không bao giờ < 3

# ---------- Incident 4: node chết ----------
docker stop grab-mini-worker2      # traffic.ps1 + load.js /payment chạy nền
kubectl get node grab-mini-worker2 -w
docker start grab-mini-worker2
kubectl rollout restart deploy booking payment user driver notification   # rải lại Pod (node về KHÔNG tự cân bằng)

# ---------- Incident 5: deploy khi có request 15s ----------
node ci/slow-burst.js 15000 30     # rồi NGAY: kubectl rollout restart deploy/booking
node ci/slow-burst.js 35000 30     # đối chứng: request dài hơn grace period

# ---------- Incident 6: memory leak ----------
#   helm-values/user.yaml: LEAK_KB_PER_REQUEST: "64" -> push; tải /users
kubectl top pods -l app=user; kubectl describe pod <user-pod> | Select-String "Last State|Reason|Exit Code"
#   PromQL chẩn đoán: nodejs_heap_size_used_bytes vs nodejs_external_memory_bytes vs process_resident_memory_bytes
./ci/rollback.ps1 -Service user

# ---------- Incident 7: Pod bị chiếm ----------
./ci/attack-surface.ps1 -App user
./ci/attack-surface.ps1 -App payment
```

**📄 Code liên quan:**

- `helm-values/booking-prod.yaml` - `minReplicas: 3`, `maxReplicas: 20`, PDB `minAvailable: 2`. `helm-values/payment-prod.yaml` (mới) - HPA 3-10, 50% CPU.
- `k8s/monitoring/alerts-apps.yaml` - regex 5 service (+ redis, postgres cho restart); mới: `GrabMiniOOMKilled` (báo ngay lần đầu: `last_terminated_reason=OOMKilled` **and** restarts tăng trong 10 phút - không báo mãi chuyện cũ), `GrabMiniMemoryNearLimit` (working set / limit > 85%, `for: 1m`), `GrabMiniMemoryLeakSuspected`:

  ```yaml
  expr: |
    predict_linear((max by (pod, container) (container_memory_working_set_bytes{namespace="default",container!=""}))[5m:15s], 600)
    / on (pod, container)
    max by (pod, container) (kube_pod_container_resource_limits{namespace="default",resource="memory"}) > 1
  for: 1m     # lọc nhiễu lúc Pod mới khởi động (0 -> mức nền, vượt ngưỡng 10-20s)
  ```

- `charts/grab-platform/values.yaml` + `templates/ingress.yaml` - `ingress.annotations`: `proxy-connect-timeout: "1"`, `proxy-next-upstream: "error timeout"`, `proxy-next-upstream-tries: "3"`. `templates/redis.yaml` - toleration `not-ready`/`unreachable` 30s.
- `charts/grab-platform/templates/networkpolicies.yaml` - `networkPolicies.egress.enabled`: mỗi app trong `appPorts` 1 policy `egress-<app>` = DNS (kube-dns 53 UDP/TCP) + mọi `allow` có app đó trong `from` (port **container**, vì policy so sau DNAT của Service). Kết quả: booking → payment:3004, notification:3005; driver → notification:3005; payment → postgres:5432; user → redis:6379; notification → (không gì).
- `charts/grab-service` - `automountServiceAccountToken: false` (mặc định). `<svc>-service/server.js` (5 service) - `server.keepAliveTimeout = 65000; server.headersTimeout = 66000`.
- `booking-service/server.js` - `/booking/slow?ms=` (qua được Ingress + NetworkPolicy). `user-service/server.js` - fault injection `LEAK_KB_PER_REQUEST` (mặc định 0, giống `BUGGY` của booking).
- `ci/pipeline.ps1` - `Wait-ArgoSync`: Degraded chỉ là lỗi khi liên tục > 30s.

**✅ Kết quả thật đã verify (12/11/2026):**

- **Incident 1**: `kill -9` → `exitCode 137`, `BackOff` 10s, Ready lại sau 17-20s (cùng tên Pod). 3 lần đo: 0/754 (tuần tự), **7 lỗi** đúng giây bị kill (20 luồng), 0/13 313 (20 luồng). nginx: `connect() failed (111: Connection refused) while connecting to upstream` → thử upstream khác (request chưa gửi → retry được cả POST). Throughput 1 giây sau kill giảm ~384 → ~220 req/s (1 Pod gánh hết). Phụ: 2 lần load test 20 luồng đẩy HPA booking 2 → 4 → 8 → 10 Pod trong 30s; cluster đã bị restart qua đêm (Docker Desktop) - mọi Pod `restartCount=1`, metrics-server chưa sẵn sàng → HPA báo `unable to fetch metrics`.
- **Incident 2** (timeline từ lúc push): 87s request 500 đầu tiên (Argo CD poll) → 100s rollout xong, **20/20 = 500** (readiness vẫn pass vì `/health` ok) → **232s** webhook `FIRING GrabMiniHighErrorRate ... error rate 100%` → 235s `git revert` + push → 302s request 200 đầu tiên (lại đợi poll) → 314s Synced → 416s `RESOLVED`. Traffic: `/booking` **686 lỗi / 1320**, `/users` 0. Lần 2 với `rollback.ps1`: release lỗi lên trong 9s (có refresh), rollback **Synced sau 12s**, 26/30 = 200 ngay sau đó (4 request còn vào Pod v2 đang `preStop` 10s).
- **Incident 3**: lần đầu định nghĩa sai "1x" = 2 luồng không nghỉ = ~225 req/s → HPA 3 → 10 ngay, 74 166/74 166 OK. Đo lại đúng: 1x ~16 req/s (4847 req/300s), 10x thêm ~145 req/s (26 208 req/180s): **0 lỗi**, p95 1x 12ms, 10x 17-33ms. HPA: tải tăng lúc 60s → `New size: 6` sau ~40s → `10` sau ~73s → `ScalingLimited: desired more than maximum` (CPU 70-83%); payment 3 Pod ~170m (request 3×50m); postgres ~60m. Scale-down: hết tải → đợi đúng 5 phút → 10 → 4 → 3. Bật HPA payment: chuyển quyền `replicas` (`handover-to-hpa`) → push → `min spec.replicas seen = 3`, traffic 1512/1512 OK. Bất ngờ: push `maxReplicas 20` → HPA booking `New size: 19; reason: All metrics below target` (dùng khuyến nghị cao nhất trong 5 phút - lúc spike cần ~19 nhưng bị trần 10).
- **Incident 4** (worker2: payment ×2-3, redis, alertmanager, alert-webhook, kube-state-metrics, loki, argocd-server): `Ready=Unknown` sau 47-51s, evict sau 75-79s (+30s toleration), payment 3 Pod Ready ở node còn lại sau 88s. Trước vá: 8 lỗi (7 timeout 5s, tất cả trong ~50s trước `Unknown`) + 14/12 030 trên luồng `/payment`; `/booking` **0** (retry + idempotency key của Scenario 25); Redis không lên lại trong 180s. Sau vá (cùng kịch bản): `/users`, `/drivers`, `/payment`, `accept` **0 lỗi** (chỉ chậm > 1s), `/booking` 3×503 (cả 2 lần booking gọi payment đều trúng Pod chết), luồng `/payment` 8/12 336 (`504` ×7 = cả 3 lần thử đều trúng Pod chết), Redis Ready sau **86s**, views tiếp tục đếm. Node về: Ready sau 3s nhưng **mọi Pod app dồn sang worker** (không tự cân bằng) → `rollout restart` rải lại; `kube-state-metrics` CrashLoop 4 lần (`dial tcp 10.96.0.1:443: connection refused` - kube-proxy của node vừa bật chưa có rule) rồi tự hồi.
- **Incident 5**: 30 luồng × request 15s, `rollout restart` giữa chừng: **210/210 OK**. Burst 30 request 15s cùng lúc + rollout sau 2s: **30/30 OK**, xong sau 15.06s, **16 request do Pod đã bị xoá trả lời trọn vẹn**. Đối chứng 35s: 30/30 "OK" nhưng **67s** - nginx log: `10.244.1.61:3003, 10.244.2.67:3003 ... 32.042, 35.002  502, 200` (Pod cũ bị SIGKILL lúc grace hết → 502 → nginx gửi lại GET sang Pod mới, chạy lại 35s). 6 lần `upstream prematurely closed connection`.
- **Incident 6**: memory 18 → 43 → 90 → 149 → 197/226 MiB (0-77s), 92s: **3/3 Pod `OOMKilled/137`** cùng lúc; tải `/users`: 7 giây liền `ok=0 fail=124-132` (~670 lỗi). Webhook `FIRING GrabMiniOOMKilled` sau 138s. Prometheus 5 phút: `nodejs_heap_size_used_bytes` **19 MiB**, `nodejs_external_memory_bytes` **205 MiB**, `process_resident_memory_bytes` 287 MiB → leak nằm ở Buffer (ngoài heap JS). `describe`: `Last State: Terminated, Reason: OOMKilled, Exit Code: 137, Limits memory: 256Mi`. Rollback 25s → 30 MiB ổn định dưới tải. Backtest `predict_linear` trên dữ liệu thật: vượt ngưỡng liên tục từ 21:43:30, OOMKilled 21:44:58 → với `for: 1m` báo lúc 21:44:30 (**trước 28s**); nhiễu lúc Pod khởi động chỉ 10-20s. Tỉ lệ working set/limit đỉnh 10 phút = 90% (mẫu 15s).
- **Incident 7** (từ trong Pod user, trước vá): BLOCKED `postgres:5432`, `payment-service`, `notification-service`, `booking-service`; OPEN `redis:6379`, **`10.96.0.1:443`**, **`1.1.1.1:443`**, **`argocd-server.argocd:80`**, **`monitoring-grafana.monitoring:80`**; env không có credential; **token có mount**, gọi `GET /api/v1/namespaces/default/secrets` → `403 Forbidden` (RBAC chặn). Push egress (traffic 90s: 3184/3185 - lỗi duy nhất là race keep-alive, không liên quan) → 5 policy `egress-*`; deploy 5 service (keepalive + automount): nginx 5 phút `200=7231`, **0 lỗi 5xx**. Sau vá: user chỉ OPEN `redis:6379` + DNS, token **không** mount; payment chỉ OPEN `postgres:5432` + DNS (có `DB_USERNAME/DB_PASSWORD` - cần cho việc của nó). Cuối: 36/36 target `up`, chỉ `Watchdog`, 7 app `Synced Healthy`, traffic 710/710.
- Race keep-alive: nginx `"POST /booking" ... 10.244.1.19:3003 0 0.000 502` + `upstream prematurely closed connection while reading response header`; 1 lần trong 3 giờ log. Node `keepAliveTimeout=5000`, nginx upstream `keepalive_timeout 60s`.

> **Bài học quan trọng #1 - replica không cứu được lỗi chung**: Pod chết lẻ (Incident 1) → các Pod khác gánh, gần như không ai thấy. Nhưng lỗi nằm trong **code/config** (Incident 2, 6) có mặt ở **mọi** replica: leak làm 3/3 Pod OOMKilled **cùng giây**, bug v2 làm 100% request lỗi. Chống lỗi chung = rollback nhanh + giới hạn phạm vi (canary), không phải thêm replica.
>
> **Bài học quan trọng #2 - `/health` và readiness không bắt được lỗi logic**: v2 trả 500 cho mọi booking nhưng Argo CD báo `Healthy`, rollout "thành công". Phải có tín hiệu nghiệp vụ: smoke test sau sync (pipeline có, nhưng đổi config đi thẳng Git thì không qua pipeline) và alert theo error rate - alert tới sau ~2 phút (`rate[1m]` + `for: 1m` + `group_wait`).
>
> **Bài học quan trọng #3 - MTTR = phát hiện + quyết định + thực thi; GitOps thêm độ trễ poll**: rollback bằng `git revert` mà không refresh Argo CD = đợi thêm tới 60s. `ci/rollback.ps1` đưa phần thực thi về 12s. `preStop` làm Pod lỗi phục vụ thêm 10s cả khi rollback.
>
> **Bài học quan trọng #4 - HPA có trần, có độ trễ, và có trí nhớ**: phản ứng sau ~40s (metrics-server 15s + chu kỳ HPA 15s + scale ×2 mỗi 15s), scale-down đợi 5 phút. Chạm `maxReplicas` = hết đường mà không có lỗi nào báo (chỉ `ScalingLimited`). Nâng trần ngay sau spike → HPA áp dụng khuyến nghị cũ (19 Pod). Thứ không có HPA (payment) và stateful (Postgres 1 Pod) là nút cổ chai tiếp theo. Định nghĩa "1x" sai (2 luồng không nghỉ = 225 req/s) cho kết luận sai.
>
> **Bài học quan trọng #5 - bật HPA cho Deployment đang chạy dưới server-side apply**: bỏ `spec.replicas` khỏi manifest mà không ai khác sở hữu field đó → API server xoá field → replicas về **1**. Chuyển quyền trước (`kubectl apply --server-side --field-manager=handover-to-hpa` chỉ field replicas) rồi mới push.
>
> **Bài học quan trọng #6 - node chết: ~50s "vùng mù" trước khi Kubernetes biết**: endpoint vẫn trỏ Pod chết tới khi node `Unknown` (~47-51s). Phía gọi phải tự bảo vệ: connect-timeout ngắn + thử đích khác (nginx: an toàn cả POST vì request chưa gửi), client retry có idempotency key. Pod hạ tầng (Redis) không có `tolerationSeconds` = đợi 300s mặc định. Node quay về không tự cân bằng Pod. Một node chứa cả Alertmanager + webhook = mất node là **mất luôn kênh báo động**.
>
> **Bài học quan trọng #7 - grace period là hợp đồng với request dài nhất**: `terminationGracePeriodSeconds ≥ preStop + request dài nhất + dư` (10 + 15 + 5 = 30). Vượt → SIGKILL giữa chừng; nginx gửi lại GET (người dùng chờ gấp đôi, server làm 2 lần) nhưng **không** gửi lại POST (502). Việc dài hơn vài chục giây nên đưa ra hàng đợi/job, không giữ trong request HTTP.
>
> **Bài học quan trọng #8 - memory: limit cứu node, metric đúng mới cứu service**: limit 256Mi khiến leak chỉ giết container (node không sao). Heap JS 19 MiB nhưng RSS 287 MiB - nhìn heap sẽ kết luận sai. Alert OOMKilled tới **sau** sự cố; báo trước cần ngưỡng so với limit + xu hướng (`predict_linear`), và backtest trên dữ liệu thật để chọn `for:` lọc nhiễu khởi động.
>
> **Bài học quan trọng #9 - "chặn được DB" chưa phải là an toàn**: NetworkPolicy chiều ingress bảo vệ đích, nhưng Pod bị chiếm vẫn ra được Internet (tải tool, gửi dữ liệu), Kubernetes API (với token được mount sẵn), và namespace không có policy (Argo CD - điều khiển cả cluster). Egress default-deny + không mount token + RBAC tối thiểu + credential DB tối thiểu = nhiều lớp; mỗi lớp kiểm chứng bằng phép thử thật từ trong Pod.
>
> **Bài học quan trọng #10 - keep-alive: server phải giữ kết nối lâu hơn proxy**: Node đóng kết nối rảnh sau 5s, nginx tái dùng tới 60s → hiếm nhưng chắc chắn có 502 (POST không retry). `keepAliveTimeout` của server > của proxy (65s > 60s), `headersTimeout` > `keepAliveTimeout`.

---

<a id="cleanup"></a>
## Cleanup - xoá image Docker cũ không dùng

```powershell
docker image prune -f
docker images --filter "reference=*-service" --format "{{.Repository}}:{{.Tag}}"
# xoá tag cụ thể không còn dùng, ví dụ:
docker rmi booking-service:v1   # CHỈ chạy nếu chắc chắn không còn Deployment nào tham chiếu tag này
```

---

<a id="rebuild"></a>
## 🔁 Dựng lại toàn bộ cluster từ đầu

Dùng khi cluster hỏng hẳn - điển hình: **Docker Desktop restart làm `grab-mini-control-plane` mất port mapping** (`docker port` rỗng dù container "Up", `kubectl` báo `connection refused`). Lưu ý: nếu container vừa mới khởi động, đợi ~10-30s và kiểm tra lại `docker port grab-mini-control-plane` trước - lần gặp ngày 10/11 cluster tự hồi phục, không cần dựng lại.

> Mất data: PVC của Postgres (local-path) nằm trong container node → **xoá cluster = mất data Postgres**.
>
> **Đã chạy trọn vẹn 1 lần liên tục ngày 13/11/2026** (xoá cluster thật, dựng lại từ đầu): **~11 phút, không bước nào lỗi, không sửa tay**.
>
> | Bước | Thời gian | Kết quả |
> |---|---|---|
> | 0 backup Postgres | vài giây | `pg_dumpall` 166.827 dòng (166.627 payment - data load test) |
> | 1 cluster 3 node | 33s | 3 node v1.37.0 |
> | 2 local registry | 10s | `hosts.toml` trên 3 node; catalog còn đủ 5 image (registry nằm ngoài cluster) |
> | 3 ingress-nginx + metrics-server | 81s | controller v1.15.1, metrics-server v0.9.1 (nay đã pin trong runbook) |
> | 4 monitoring + Loki + Alloy | 328s | kube-prometheus-stack 155s, Loki 62s, Alloy ~60s |
> | 5 Secret + Argo CD + bootstrap | 106s + **72s** | 7 app Synced Healthy 72s sau `kubectl apply -f argocd/root.yaml`; booking/payment `Degraded` ~30s (HPA chưa có metric Pod mới - bình thường) |
> | 6 verify | - | 4 release Helm, `db-init done`, 4 endpoint trả đúng (booking có `transactionId` + `notificationId`), **36/36 target up**, 12 NetworkPolicy, HPA 3-20 / 3-10, Pod trải 2 worker; `ci/attack-surface.ps1`: user chỉ tới được Redis + DNS (như sau Incident 7) |
>
> Lưu ý: ngay sau khi dựng, `CPUThrottlingHigh` (info) của `alert-webhook` pending + `InfoInhibitor` firing - CPU limit nhỏ lúc khởi động, tự hết. Không restore backup cũ: `pg_dumpall` chứa **cả role `payment` với password cũ** → restore sẽ đè password, lệch Secret `payment-db` mới (muốn giữ data: chỉ restore bảng, `pg_dump -t payments --data-only`).

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini

# --- 0. backup Postgres (xoá cluster = mất PVC). Image postgres không có role "root" -> phải -U postgres ---
New-Item -ItemType Directory -Force "$env:USERPROFILEackups\grab-mini" | Out-Null   # KHÔNG để trong %TEMP% (Windows tự dọn)
kubectl exec postgres-0 -- pg_dumpall -U postgres > "$env:USERPROFILEackups\grab-mini\pg-backup-$(Get-Date -Format yyyyMMdd).sql"

# --- 1. cluster 3 node (control-plane có port 80/443 + nhãn ingress-ready) ---
kind delete cluster --name grab-mini
kind create cluster --name grab-mini --config kind-multi-node.yaml

# --- 2. local registry: container kind-registry KHÔNG bị xoá theo cluster (image trong đó vẫn còn),
#        nhưng containerd của các node MỚI phải cấu hình lại ---
./ci/setup-local-registry.ps1

# --- 3. ingress-nginx + metrics-server (patch bằng file - tránh lỗi escape JSON của PowerShell; CHỈ chạy 1 lần) ---
#   PIN version (13/11/2026): trước đây dùng URL main/latest -> mỗi lần dựng có thể ra bản khác. 2 URL dưới = đúng bản đã chạy thật
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml
kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=json --patch-file k8s/patches/ingress-nginx-nodeselector.json
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json --patch-file k8s/patches/metrics-server-insecure-tls.json
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s

# --- 4. monitoring (cài TRƯỚC app để có CRD ServiceMonitor/PrometheusRule) ---
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 93.1.1 -n monitoring --create-namespace -f k8s/monitoring/values.yaml --wait --timeout 10m
helm upgrade --install loki grafana/loki --version 7.5.0 -n monitoring -f k8s/monitoring/loki-values.yaml --wait --timeout 10m
helm upgrade --install alloy grafana/alloy --version 1.15.0 -n monitoring -f k8s/monitoring/alloy-values.yaml --wait
kubectl apply -f k8s/monitoring/servicemonitor-apps.yaml -f k8s/monitoring/alerts-apps.yaml -f k8s/monitoring/alert-webhook.yaml -f k8s/monitoring/grab-mini-dashboard-cm.yaml

# --- 5. app: Secret (ngoài Git) -> Argo CD -> bootstrap 1 lệnh; Argo CD tự dựng platform + 5 service từ Git ---
#   2 Secret PHẢI có trước: postgres-superuser (StatefulSet postgres initdb + Job db-init), payment-db (db-init tạo role payment, payment-service dùng)
$pw = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) -replace '[+/=]', ''
kubectl create secret generic postgres-superuser --from-literal=POSTGRES_PASSWORD=$pw
$pw = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)) -replace '[+/=]', ''
kubectl create secret generic payment-db --from-literal=DB_USERNAME=payment --from-literal=DB_PASSWORD=$pw; Remove-Variable pw
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd --version 10.16.0 -n argocd --create-namespace -f k8s/argocd/values.yaml --wait --timeout 5m
kubectl apply -f argocd/root.yaml
# image tag lấy từ helm-values/<svc>-image.yaml trong Git -> image PHẢI còn trong registry kind-registry
#   (mất registry: ./ci/pipeline.ps1 -Service notification,driver,payment,user,booking - build + push lại; tag không đổi -> không có commit mới)
# cluster mới: Argo CD tự tạo object -> KHÔNG cần migrate-field-managers, không có release Helm nào để xoá

# --- 6. verify ---
helm list -A                                            # 4 release: monitoring, loki, alloy, argocd
kubectl get applications -n argocd                      # 7 app Synced Healthy
kubectl logs job/db-init                                # db-init done
kubectl get pods -o wide --sort-by=.spec.nodeName       # Pod trải đều worker / worker2
curl.exe -s http://localhost/users
curl.exe -s -X POST http://localhost/booking -H "Content-Type: application/json" -d '{}'   # có payment.transactionId + notification
curl.exe -s http://localhost/payments/stats; curl.exe -s http://localhost/drivers
$P = "/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy"
kubectl get --raw "$P/api/v1/targets?state=active" | jq -r '[.data.activeTargets[].health] | group_by(.) | map("\(.[0])=\(length)") | join(" ")'   # chỉ có "up"
kubectl get netpol                                      # 12
./ci/attack-surface.ps1                                 # từ Pod user: chỉ OPEN redis + DNS

# --- 7. self-hosted runner (23b): KHÔNG cần làm gì - kind create ghi lại context kind-grab-mini (đã thử 13/11: push driver -> cd success 55s trên cluster mới) ---
```

---

<a id="bai-hoc"></a>
## 🧠 Tổng hợp bài học

Mỗi dòng là 1 điều đã **tự gặp khi chạy thật** (chi tiết + bằng chứng ở scenario tương ứng).

**Deploy, rollout, rollback**

| Bài học | Scenario |
|---|---|
| `port-forward` gắn vào đúng 1 Pod - không dùng để test load-balancing hay rollout (Pod bị thay là kết nối chết). Test qua Service DNS từ trong cluster hoặc qua Ingress | [3](#scenario-3), [6](#scenario-6) |
| `kubectl rollout undo` chỉ lùi **1** revision - `set image` + `set env` là 2 revision riêng; dùng `rollout history` + `--to-revision` | [7](#scenario-7) |
| `helm rollback` tạo revision **mới** (history chỉ thêm, không lùi), và không khôi phục image bị build đè cùng tag | [22](#scenario-22) |
| Tag image phải bất biến: `:v1` đã bị build lại ở Phase 21 → rollback về "v1 cũ" là không thể | [20](#scenario-20), [22](#scenario-22) |

**Vòng đời Pod & tài nguyên**

| Bài học | Scenario |
|---|---|
| Process PID 1 bỏ qua tín hiệu không có handler: `kubectl exec ... kill -9 1` không giết được container; phải `crictl stop` từ node | [8](#scenario-8) |
| Vượt memory limit = **bị kill** (`OOMKilled`, exit 137); vượt CPU limit = **bị throttle** (xem `cpu.stat`), không bị kill | [9](#scenario-9) |
| HPA scale-down chờ ~5 phút (`stabilizationWindowSeconds`) - không phải lỗi | [10](#scenario-10) |
| Graceful shutdown cần đủ 3 thứ: `preStop sleep` (chờ endpoint gỡ Pod) + handler `SIGTERM` gọi `server.close()` + `terminationGracePeriodSeconds` đủ dài | [11](#scenario-11) |
| `preStop` phải đủ dài so với độ trễ kube-proxy/ingress (đo được trung bình 2.3s, đuôi > 25s): 5s rớt 5/4795 khi 5 service rollout cùng lúc, 10s → 0/5265 | [25](#scenario-25) |

**Networking & Ingress**

| Bài học | Scenario |
|---|---|
| `extraPortMappings` của `kind` chỉ đặt được lúc tạo cluster | [12](#scenario-12) |
| `rewrite-target: /` làm hỏng request khi path Ingress đã khớp path backend | [12](#scenario-12) |
| Cluster nhiều node: phải ép `ingress-nginx` về control-plane (`nodeSelector ingress-ready`), nếu không `localhost:80` trả `Empty reply` | [16](#scenario-16) |
| NetworkPolicy **im lặng** nếu CNI không hỗ trợ → luôn đo baseline trước. `kind` ≥ v0.24 (kindnet) đã hỗ trợ, không cần Calico | [19](#scenario-19) |
| `ports` trong NetworkPolicy là port **container** (3003), không phải port Service (80); packet bị chặn = timeout (DROP), không phải refused | [19](#scenario-19) |
| Default-deny chặn cả hạ tầng của mình (Prometheus `context deadline exceeded`), nhưng không chặn probe của kubelet | [19](#scenario-19), [20](#scenario-20) |
| Gọi Service có 0 endpoint bị **treo** (~10s), không lỗi ngay → mọi lời gọi ra ngoài phải có timeout | [20](#scenario-20) |
| Ingress `pathType: Prefix` khớp theo đoạn path: `/payment` không khớp `/payments` (404 từ nginx) | [25](#scenario-25) |
| `prune: false` giữ lại NetworkPolicy đã xoá khỏi Git → booking vẫn vào được DB; kiểm tra `requiresPruning` + thử thật bằng `nc` từ trong Pod | [25](#scenario-25) |

**Storage & stateful**

| Bài học | Scenario |
|---|---|
| Đặt `PGDATA` vào thư mục con để tránh `initdb: directory not empty` | [13](#scenario-13) |
| StatefulSet giữ tên Pod + PVC cố định (`postgres-0`, `data-postgres-0`) | [14](#scenario-14) |
| PVC `local-path` bị khoá vào 1 node → mất node = Postgres đứng (kẹt `Terminating`) tới khi node quay lại; stateless thì tự chuyển node | [16](#scenario-16) |
| `helm uninstall` không xoá PVC tạo từ `volumeClaimTemplates` và Secret tạo tay | [22](#scenario-22) |

**Scheduling & HA**

| Bài học | Scenario |
|---|---|
| Scheduler mặc định cân bằng theo tài nguyên, không theo số Pod cùng app → cần `topologySpreadConstraints` | [17](#scenario-17) |
| `topologySpreadConstraints` thiếu `nodeTaintsPolicy: Honor` → control-plane (0 Pod) bị tính vào skew → `FailedScheduling` vĩnh viễn | [17](#scenario-17) |
| topologySpread đếm cả Pod revision cũ lúc rolling update → 2 Pod booking cùng 1 node; `matchLabelKeys: [pod-template-hash]` | [25](#scenario-25) |
| Required anti-affinity: số replica tối đa = số node, rolling update deadlock; anti-affinity có tính **đối xứng** → dùng `preferred` | [18](#scenario-18) |
| `kubectl apply` không gỡ được field đã thêm bằng `kubectl patch` (three-way merge theo `last-applied`) | [18](#scenario-18) |
| Node chết: Pod chỉ bị thay sau `tolerationSeconds` (mặc định 300s, đo được 5m44s); đặt 30s → failover ~82s | [16](#scenario-16), [18](#scenario-18) |
| ~50s đầu khi node chết (trước `NotReady`) traffic vẫn tới Pod đã chết - Kubernetes không tự cứu được, cần retry ở app/proxy | [18](#scenario-18) |
| PDB chỉ chặn drain/eviction, không chặn node chết; HPA `min 1` + PDB `minAvailable 1` = drain kẹt vĩnh viễn | [18](#scenario-18) |

**Thiết kế service & phụ thuộc**

| Bài học | Scenario |
|---|---|
| Phân loại phụ thuộc: quan trọng (DB của payment → lỗi nhanh 503) vs không quan trọng (Redis, notification → timeout ngắn + `null`, request vẫn 200) | [25](#scenario-25) |
| Retry POST chỉ an toàn khi có idempotency key (`paymentId = bookingId` + `ON CONFLICT DO NOTHING`); không retry 4xx | [25](#scenario-25) |
| `/health` không kiểm tra DB - DB chết mà liveness fail = restart toàn bộ Pod vô ích | [25](#scenario-25) |
| Least privilege DB 3 lớp: NetworkPolicy, Secret riêng từng service, quyền SQL tối thiểu (`SELECT, INSERT`); superuser chỉ cho Job `db-init` | [25](#scenario-25) |

**Xử lý sự cố (Production Simulation)**

| Bài học | Scenario |
|---|---|
| Pod chết lẻ: chỉ mất request đang xử lý dở (0-7 / 13k); lỗi code/config có ở MỌI replica (leak: 3/3 OOMKilled cùng giây) → chống bằng rollback nhanh/canary, không phải thêm replica | [26](#scenario-26) |
| `/health` + readiness không bắt lỗi logic (v2 trả 500, Argo CD vẫn Healthy) → smoke test sau sync + alert error rate (~2 phút) | [26](#scenario-26) |
| Rollback GitOps không refresh = đợi poll 60s; `ci/rollback.ps1` (revert + push + refresh) → 12s | [26](#scenario-26) |
| HPA: phản ứng ~40s, chạm `maxReplicas` không báo lỗi; nâng trần ngay sau spike → scale lên theo khuyến nghị cũ (19 Pod) | [26](#scenario-26) |
| Bật HPA cho Deployment đang chạy (SSA): chuyển quyền `spec.replicas` sang field manager khác trước, nếu không replicas về 1 | [26](#scenario-26) |
| Node chết: ~50s endpoint vẫn trỏ Pod chết → nginx `proxy-connect-timeout 1s` + `next-upstream` (an toàn cả POST), client retry + idempotency key; node về không tự cân bằng | [26](#scenario-26) |
| `terminationGracePeriodSeconds ≥ preStop + request dài nhất + dư`; vượt → SIGKILL, nginx gửi lại GET (chạy 2 lần), POST thành 502 | [26](#scenario-26) |
| Memory leak: heap 19 MiB nhưng RSS 287 MiB (Buffer); alert OOMKilled tới sau sự cố → `predict_linear` + `for: 1m` (backtest: báo trước 28s) | [26](#scenario-26) |
| Pod bị chiếm: ingress policy chặn DB nhưng vẫn ra Internet / K8s API (token mount) / namespace khác → egress policy + `automountServiceAccountToken: false` | [26](#scenario-26) |
| Keep-alive: server phải giữ lâu hơn proxy (Node 5s < nginx 60s → 502 hiếm); `keepAliveTimeout 65s` | [26](#scenario-26) |
| HPA `Degraded` thoáng qua sau rollout (chưa có metric Pod mới) → pipeline chỉ fail khi Degraded > 30s | [26](#scenario-26) |
| Password superuser Postgres nằm trong `values.yaml` của repo **public** (13/11 mới phát hiện) → chuyển sang Secret `postgres-superuser` + `ALTER USER` đổi password (giá trị cũ còn trong lịch sử Git mãi mãi - chỉ xoá khỏi file là **không đủ**); `POSTGRES_PASSWORD` chỉ có tác dụng lúc initdb | [rebuild](#rebuild) |
| Thiếu `NODE_ENV=production` → Express trả **nguyên stack trace** (đường dẫn, thư viện) cho request lỗi ra Internet; đặt 1 lần ở `env-prod.yaml` (Helm gộp map `env`), rollout 5 service 0/5300 lỗi | - |

**Observability**

| Bài học | Scenario |
|---|---|
| `kube-prometheus-stack` trên `kind`: tắt controller-manager/scheduler/etcd/kube-proxy (bind `127.0.0.1`) để không có target `down` giả | [20](#scenario-20) |
| Metrics phía server không thấy request mà client đã bỏ đi → bắt cả sự kiện `close` (ghi 499) | [20](#scenario-20) |
| Alert tới người trực chậm ~1.5-2.5 phút (scrape + `rate[1m]` + chu kỳ rule + `for:` + `group_wait`) | [21](#scenario-21) |
| `inhibit_rules` giảm số alert gửi đi trong 1 sự cố; tin RESOLVED mang giá trị cũ; `alertmanager.config` trong values **thay thế** config mặc định | [21](#scenario-21) |
| Promtail đã EOL → dùng Grafana Alloy; DaemonSet cần toleration để thu log control-plane | [21](#scenario-21) |

**Helm**

| Bài học | Scenario |
|---|---|
| Resource tạo bằng `kubectl` → `helm install` bị từ chối (`invalid ownership metadata`); dùng `kubectl diff` rồi `--take-ownership` | [22](#scenario-22) |
| Có HPA thì chart không khai báo `spec.replicas`; Helm 4 (server-side apply) không đụng field nó không sở hữu - `kubectl diff` vẫn báo sai `replicas 2 → 1` | [22](#scenario-22) |
| Xung đột SSA ở field atomic (`volumeClaimTemplates`) → `--force-conflicts` chỉ sau khi `--dry-run=server` thành công | [22](#scenario-22) |
| Adopt bằng `--take-ownership` để lại manager cũ `kubectl-client-side-apply` → lần đầu ĐỔI giá trị (image) bị conflict → dọn `managedFields` 1 lần | [23](#scenario-23) |

**CI/CD**

| Bài học | Scenario |
|---|---|
| Tag = git SHA (commit cuối động vào thư mục service) → image bất biến, `helm rollback` chạy lại đúng bản cũ; `git revert` vẫn ra tag mới | [23](#scenario-23) |
| Test chặn lỗi logic trước khi build; lỗi đóng gói (Dockerfile) qua được test → readiness + `--rollback-on-failure` + `maxUnavailable: 0` giữ 0 request lỗi | [23](#scenario-23) |
| `helm upgrade` tay thiếu `-f helm-values/<svc>-image.yaml` = quay về image cũ → deploy chỉ qua `ci/pipeline.ps1` | [23](#scenario-23) |
| Local registry trên kind: containerd mặc định `config_path = ''` → phải bật + `hosts.toml` trên mọi node | [23](#scenario-23) |
| `/tmp` của node kind là tmpfs - `docker cp` vào đó không thấy được; test script idempotent phải xoá trạng thái cũ trước | [23](#scenario-23) |
| `$PSNativeCommandUseErrorActionPreference`: lệnh dọn dẹp trong `catch` cũng ném lỗi; `helm history` của release chưa có cũng lỗi → kiểm tra trước | [23](#scenario-23) |
| Lỗi đóng gói lọt qua cả `npm test` lẫn CI chỉ-build → chạy thử container + `/health` sau build (~1s) | [24](#scenario-24) |
| CI GitHub không được commit tag image mà cluster không kéo được (GHCR private → `ImagePullBackOff`) → tách CI (GitHub) / CD (registry local + Git) | [24](#scenario-24) |

**GitOps (Argo CD)**

| Bài học | Scenario |
|---|---|
| Tiếp quản không restart Pod: `helm template` phải giống hệt `helm get manifest`; `releaseName` = tên release cũ (label `instance` trong pod template) | [24](#scenario-24) |
| Sau khi Argo CD tiếp quản: xoá Secret `sh.helm.release.*` (Helm buông) + dọn manager `helm` (nếu không, xoá field khỏi Git không xoá được trên cluster) | [24](#scenario-24) |
| selfHeal chỉ sửa field Argo CD sở hữu: xoá object / đổi giá trị → về lại ~1s; **thêm** key bằng tay → vẫn `Synced`, không bị xoá | [24](#scenario-24) |
| Rollback = `git revert` commit deploy; `helm rollback` bị selfHeal đè. Argo CD không tự rollback - bản lỗi `Progressing` tới `progressDeadlineSeconds` (600s) | [24](#scenario-24) |
| Không có webhook → Argo CD poll Git (mặc định 180s, đặt 60s); pipeline annotate `argocd.argoproj.io/refresh` để sync ngay | [24](#scenario-24) |
| `prune: true` cho app stateless, `prune: false` cho app có PVC/database | [24](#scenario-24) |

**PowerShell / Windows**

| Bài học | Scenario |
|---|---|
| `-p '[...]'` JSON trong file `.ps1` có thể bị escape sai → dùng `--patch-file` | [16](#scenario-16), [18](#scenario-18) |
| Chuỗi JS/JSON truyền cho lệnh ngoài: dùng `''` trong chuỗi nháy đơn, không dùng `\"` (PowerShell 7) | [19](#scenario-19) |
| `kubectl diff` cần `diff.exe`: thêm `C:\Program Files\Git\usr\bin` vào `PATH` (không dùng `KUBECTL_EXTERNAL_DIFF` có dấu cách) | [22](#scenario-22) |

---

<a id="con-thieu"></a>
## Việc còn thiếu

**App**
- Driver/notification là bản tối giản: danh sách tài xế cố định, notification chỉ ghi log (chưa gửi SMS/push), chưa có queue (booking gọi notification đồng bộ - nên đổi sang message queue / outbox).
- Chưa có migration tool (Flyway / node-pg-migrate) - schema nằm trong Job `db-init`; chưa có bảng `bookings` (booking không lưu gì).
- Image `<svc>-service:v1/v2/v3` (bản `kind load` cũ của Phase 2-21) vẫn còn trên node + Docker Desktop nhưng không còn dùng - prod chạy `localhost:5001/<svc>-service:<sha>`.

**CI/CD + GitOps**
- CD chạy qua **self-hosted runner** trên máy local ([23b](#scenario-23b)) - máy tắt = không deploy được (runner tự chạy khi đăng nhập Windows - Task Scheduler). Chưa có registry chung mà cả runner GitHub lẫn cluster cùng dùng được.
- Chưa scan lỗ hổng image (Trivy...); chưa có môi trường staging (deploy thẳng prod), chưa có approval / branch protection cho `main`.
- Argo CD: chưa có webhook (poll 60s), chưa có notifications (Slack) khi sync lỗi, chưa đổi password admin / tắt user admin, chưa scrape metrics Argo CD vào Prometheus. Monitoring, ingress-nginx, metrics-server và chính Argo CD **chưa** được quản lý bằng Argo CD (vẫn Helm/kubectl tay).
- `postgres-superuser`, `payment-db` tạo tay (ngoài Git) → Argo CD không dựng lại được nếu thiếu; cần Sealed Secrets / External Secrets.
- Chưa giảm `progressDeadlineSeconds` → Argo CD chỉ báo `Degraded` sau 10 phút.
- Sửa file dùng chung (`env-prod.yaml`, chart `grab-service`) = rollout **mọi** service cùng lúc - chưa có cách tách đợt (sync-wave / từng app).
- Registry dùng volume có tên `kind-registry-data` (14/11 - trước đó là volume không tên, `docker volume prune` sẽ xoá sạch image); vẫn chỉ 1 bản trên 1 máy, chưa backup. Registry còn image rác (`registry-test`, `booking-service:989561244027` của Demo C) - `registry:2` mặc định tắt API xoá.

**Vận hành**
- `ingress-nginx` (v1.15.1) và `metrics-server` (v0.9.1) đã pin trong runbook, nhưng vẫn cài bằng `kubectl apply` tay - chưa quản lý bằng Argo CD.
- Postgres dùng `local-path` (1 node) - chưa có replication/backup. Redis 1 replica, không lưu đĩa (cache - chấp nhận mất).
- **Khuyến nghị từ Production Simulation (chưa làm)**:
  - Incident 2: progressive delivery (Argo Rollouts canary + AnalysisTemplate theo error rate → tự abort), hoặc PostSync smoke Job cho thay đổi config đi thẳng Git.
  - Incident 4: Alertmanager + `alert-webhook` 2 replica trải 2 node (hiện cùng node với kube-state-metrics → mất node = mất kênh báo động); outlier detection (service mesh) để đóng ~50s vùng mù; descheduler cân bằng lại Pod khi node quay về.
  - Incident 5: việc dài (> ~20s) đưa vào hàng đợi/job thay vì giữ request HTTP.
  - Incident 6: cache có giới hạn (LRU/TTL); công cụ heap profiling trên prod.
  - Incident 7: NetworkPolicy ingress cho namespace `argocd`, `monitoring`; Redis AUTH; runtime detection (Falco); audit log Postgres.
- Egress NetworkPolicy mới có cho 5 app trong `default` (Incident 7); Postgres/Redis và namespace khác chưa có.

**Observability**
- Chưa có tracing (OpenTelemetry), chưa scrape metrics của `ingress-nginx`, alert chưa gửi tới receiver thật (Slack/Telegram).

**Helm**
- `env-staging.yaml` chưa deploy thử; chưa đóng gói/publish chart (`helm package`, OCI registry); chưa dùng plugin `helm-diff`.

**Roadmap**
- Demo cuối khoá + review toàn bộ; giai đoạn 2: đưa lên AWS EKS (Future Plan trong Roadmap).
