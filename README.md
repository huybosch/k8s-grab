# Grab Mini

Một nền tảng đặt xe nhỏ chạy trên Kubernetes, dùng để học vận hành production: 5 microservice Node.js, PostgreSQL, Redis, trên cluster `kind` 3 node. Mọi thứ trong cluster được dựng từ repo này bằng GitOps (Argo CD).

Đọc theo thứ tự: **README này** (hệ thống là gì, làm việc hằng ngày thế nào) → [DEMO.md](DEMO.md) (xem hệ thống chịu lỗi ra sao, 8 cảnh) → [COMMANDS.md](COMMANDS.md) (nhật ký lab: từng bước đã làm, số đo, bài học - tra cứu khi cần).

---

## 1. Kiến trúc

```text
                         Internet / trình duyệt (http://localhost)
                                        │
                      ingress-nginx  (retry sang Pod khác nếu Pod chết)
          /users           /booking            /payment(s)          /drivers
            │                  │                     │                   │
        user (x3)        booking (x3-20)  ────►  payment (x3-10)     driver (x3)
            │             canary + HPA              │                   │
          Redis                 └──► notification (x2) ◄────────────────┘
       (cache, có thể mất)          (best-effort: lỗi cũng không làm hỏng cuốc xe)
                                                    │
                                              PostgreSQL (chỉ payment ghi được)
```

**Một cuốc xe đi qua hệ thống:**

1. `POST /booking` → booking tạo `bookingId`, gọi payment.
2. payment ghi 1 dòng vào bảng `payments` với `id = bookingId`. Gọi lại cùng id **không trừ tiền 2 lần** (idempotency key) → booking được phép thử lại khi payment chậm/chết.
3. booking gọi notification (timeout 1s; lỗi thì bỏ qua) rồi trả kết quả.

| Service | Port | Phụ thuộc | Ghi chú |
|---|---|---|---|
| user | 3001 | Redis (đếm lượt xem) | Redis chết → vẫn trả danh sách user, `views: null` |
| driver | 3002 | notification | `/drivers/:id/accept` |
| booking | 3003 | payment, notification | retry payment 2 lần; Argo Rollouts canary |
| payment | 3004 | PostgreSQL | user DB `payment` chỉ có quyền SELECT + INSERT |
| notification | 3005 | - | chỉ nội bộ (không có route Ingress), ghi log JSON |

Mỗi service có `/health` (probe) và `/metrics` (Prometheus).

---

## 2. Cách hệ thống được quản lý

**Quy tắc duy nhất cần nhớ: Git (`main` của `github.com/huybosch/k8s-grab`) là nguồn sự thật.** Argo CD trong cluster đọc Git mỗi 60s và làm cho cluster giống hệt Git. Sửa tay trên cluster (`kubectl edit/scale/apply`) sẽ bị **đè lại trong ~1 giây** (selfHeal).

```text
 sửa code service ──git push──► GitHub ──► runner trên máy local (cd.yaml)
                                               test → build image (tag = git SHA) → chạy thử container
                                               → push localhost:5001 → commit helm-values/<svc>-image.yaml → git push
 sửa cấu hình (charts/, helm-values/, argocd/) ──git push──────────────────────────────────┐
                                                                                            ▼
                                     Argo CD: thấy commit mới → render Helm chart → apply → đợi Healthy
                                     (booking: canary 1/3 → 2/3 → 100%, lỗi thì tự huỷ)
```

| Thành phần | Nằm ở đâu trong repo | Ai đưa vào cluster |
|---|---|---|
| 5 service | `<svc>-service/` (code), `charts/grab-service` (chart dùng chung), `helm-values/<svc>*.yaml` | Argo CD (ApplicationSet `grab-services`) |
| Postgres, Redis, Ingress, NetworkPolicy, CronJob, Secret | `charts/grab-platform` | Argo CD (`grab-platform`, **không** tự xoá - vì có data) |
| Sealed Secrets, Argo Rollouts | `argocd/apps/*.yaml` | Argo CD |
| Danh sách app của Argo CD | `argocd/apps/` (app-of-apps, gốc là `argocd/root.yaml`) | `kubectl apply -f argocd/root.yaml` (1 lần khi dựng) |
| Argo CD | `k8s/argocd/values.yaml` | `helm` tay |
| Monitoring (Prometheus, Grafana, Loki, Alloy) + alert | `k8s/monitoring/` | `helm` + `kubectl apply` tay |
| ingress-nginx, metrics-server | URL upstream (pin version) + `k8s/patches/` | `kubectl apply` tay |
| Registry image | container Docker `kind-registry` (`localhost:5001`) | `ci/setup-local-registry.ps1` |
| CI (chỉ kiểm tra) / CD | `.github/workflows/ci.yaml` / `cd.yaml` | GitHub Actions |

Cấu trúc values của 1 service (file sau ghi đè file trước): `<svc>.yaml` (riêng service) → `env-prod.yaml` (chung cho prod) → `<svc>-prod.yaml` (riêng service ở prod) → `<svc>-image.yaml` (tag image, **do pipeline ghi, không sửa tay**).

> Thư mục `k8s/*.yaml` (trừ `k8s/argocd`, `k8s/monitoring`, `k8s/patches`) là manifest cũ của Phase 0-21, **không còn dùng** - giữ để đọc lại lịch sử. `kind-config.yaml` (1 node) cũng vậy; cluster hiện tại dùng `kind-multi-node.yaml`.

---

## 3. Dựng từ đầu

**Cần có:** Windows + Docker Desktop, `kind`, `kubectl`, `helm`, Node.js, PowerShell 7, `jq`. Và **2 file ngoài Git** (không bao giờ commit):

| File | Dùng để | Mất thì sao |
|---|---|---|
| `%USERPROFILE%\backups\grab-mini\sealed-secrets-key.yaml` | giải mã password DB trong Git | tạo lại password + `kubeseal` lại 2 file `sealedsecret-*.yaml` |
| `%USERPROFILE%\backups\grab-mini\grabmini-*.dump` | data bảng `payments` | mất data (DB mới trống) |

Các bước (chi tiết + lệnh đầy đủ: [runbook trong COMMANDS.md](COMMANDS.md#rebuild), đã chạy thật 2 lần, ~11 phút):

0. Backup data cũ ra máy: `./ci/pg-backup-pull.ps1 -Now`
1. Tạo cluster: `kind create cluster --name grab-mini --config kind-multi-node.yaml`
2. Nối registry: `./ci/setup-local-registry.ps1`
3. ingress-nginx + metrics-server (2 URL đã pin version)
4. Monitoring: 3 lệnh `helm` + `kubectl apply -f k8s/monitoring/...`
5. **Khôi phục khoá** → cài Argo CD → `kubectl apply -f argocd/root.yaml`. Từ đây Argo CD tự dựng mọi thứ còn lại (~90s)
6. Khôi phục data: `pg_restore --data-only -t payments`
7. Kiểm tra: 9 app `Synced Healthy`, 36/36 target Prometheus `up`

> Đừng cắt output lệnh dài bằng `| Select-Object -First N`: PowerShell 7 sẽ **kill** tiến trình (`helm` kẹt `pending-install`).

---

## 4. Việc hằng ngày

| Muốn | Làm | Ghi chú |
|---|---|---|
| Deploy code mới | sửa `<svc>-service/` → `git commit` → `git push` | runner tự chạy pipeline. Chạy tay: `./ci/pipeline.ps1 -Service booking` |
| Đổi cấu hình (env, replicas, resources...) | sửa `helm-values/` hoặc `charts/` → `git push` | sửa `env-prod.yaml` hay chart = **rollout cả 5 service** |
| Rollback | `./ci/rollback.ps1 -Service booking` | = `git revert` commit gần nhất của service + push + đợi. **Không** dùng `kubectl rollout undo` / `helm rollback` (bị Argo CD đè) |
| Xem trạng thái | `kubectl get applications -n argocd`, `kubectl get pods -o wide`, `kubectl get rollouts.argoproj.io` | Argo CD UI: `kubectl port-forward svc/argocd-server -n argocd 8081:80` |
| Xem dashboard / log | `kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80` → `/d/grab-mini/grab-mini-services`; log: Grafana → Explore → Loki `{app="booking"}` | |
| Backup DB ra máy + thử restore | `./ci/pg-backup-pull.ps1 -Now` | backup tự động chạy 02:00 mỗi đêm nhưng nằm **trong** cluster |
| Đổi password DB | tạo Secret mới `--dry-run=client -o json \| kubeseal --format yaml` → thay file `charts/grab-platform/templates/sealedsecret-*.yaml` → push | password superuser: phải thêm `ALTER USER postgres` (biến môi trường chỉ có tác dụng lúc DB tạo lần đầu) |
| Thêm service mới | `<svc>-service/` + `helm-values/<svc>.yaml` + 1 dòng trong `argocd/apps/services.yaml` + port trong `networkPolicies.appPorts` (`charts/grab-platform/values.yaml`) | NetworkPolicy chặn mặc định - phải khai báo ai được gọi service đó (`allow`) |
| Thử tải / kiểm tra | `./ci/traffic.ps1 -Seconds 60` (lỗi theo endpoint), `node ci/load.js <url> <luồng> <giây>`, `./ci/leak-check.ps1` (rò rỉ bộ nhớ), `./ci/attack-surface.ps1` (Pod bị chiếm làm được gì) | |
| Demo | `./ci/demo.ps1 <1-8>` | xem [DEMO.md](DEMO.md) |

**Endpoint gây lỗi cho lab** (mặc định tắt): booking `/toggle-health`, `/booking/slow` chỉ chạy khi env `ENABLE_FAULT_ENDPOINTS: "true"`; booking `BUGGY: "true"` (trả 500); user `LEAK_KB_PER_REQUEST` (giả lập leak). Bật bằng cách thêm vào `helm-values/<svc>.yaml` rồi push - **nhớ revert sau khi tập**.

---

## 5. Khi có sự cố

Alert (Prometheus → Alertmanager → `alert-webhook`, xem log: `kubectl logs -n monitoring deploy/alert-webhook`):

| Alert | Nghĩa là | Làm gì trước tiên |
|---|---|---|
| `GrabMiniHighErrorRate` | > 5% request 5xx trong 1 phút | vừa deploy? → `./ci/rollback.ps1 -Service <svc>`. Không → xem log Loki của service |
| `GrabMiniHighLatencyP95` | p95 > ngưỡng | phụ thuộc chậm (DB, payment)? `kubectl top pods`, HPA đã chạm `maxReplicas`? |
| `GrabMiniNoPodsAvailable` | service không còn Pod Ready | `kubectl describe pod`, events |
| `GrabMiniPodRestarting` / `GrabMiniOOMKilled` | container restart / vượt memory limit | `kubectl logs --previous`; OOM lặp lại = nghi leak |
| `GrabMiniMemoryNearLimit` / `GrabMiniMemoryLeakSuspected` | memory > 85% limit / xu hướng sẽ chạm limit trong 10 phút | `./ci/leak-check.ps1`; so heap (`nodejs_heap_size_used_bytes`) với RSS |
| `GrabMiniPodStuck` | Pod kẹt `ImagePullBackOff` / `CrashLoopBackOff` / thiếu Secret > 3 phút | image có trong `localhost:5001`? Secret có không (`kubectl get sealedsecret`)? |
| `GrabMiniJobFailed` / `GrabMiniBackupStale` | Job lỗi / 26 giờ không có backup thành công | `kubectl logs job/<tên>` |
| `GrabMiniTargetDown` | Prometheus không scrape được Pod | NetworkPolicy? Pod còn sống? |

Triệu chứng thường gặp:

| Triệu chứng | Nguyên nhân hay gặp | Xử lý |
|---|---|---|
| `kubectl` báo `connection refused` sau khi bật máy | Docker Desktop chưa chạy / mất port mapping | bật Docker Desktop, đợi 30s, `docker port grab-mini-control-plane`; vẫn rỗng mới dựng lại |
| Argo CD app `Degraded` ~30s ngay sau deploy | HPA chưa có metric của Pod mới | bình thường, tự hết |
| Rollout booking `Degraded`, message `RolloutAborted` | canary bị analysis huỷ (error rate cao) - cluster đã tự về bản cũ | `./ci/rollback.ps1 -Service booking` để Git khớp lại |
| Argo CD app kẹt `Progressing` mãi | 1 resource không bao giờ Healthy (vd. PVC chờ Pod) | `kubectl -n argocd get application <app> -o json \| jq .status.operationState.message` |
| Sửa tay trên cluster rồi mất | selfHeal của Argo CD | sửa trong Git |
| Deploy notification luôn bị revert | (đã sửa 15/11) smoke test exec vào `deploy/booking` - booking giờ là Rollout | - |

---

## 6. Vì sao thiết kế như vậy (mỗi cơ chế 1 dòng)

| Cơ chế | Chống lại | Số đo thật |
|---|---|---|
| readiness/liveness probe | gửi traffic vào Pod chưa sẵn sàng / Pod treo | - |
| `preStop` 10s + `keepAliveTimeout` 65s | lỗi lúc Pod tắt (proxy còn gửi tới) / 502 do Node đóng kết nối trước nginx | rollout 5 service cùng lúc: 0/5265 lỗi |
| ≥ 3 replica + PDB + topologySpread 2 worker | Pod chết, node chết, bảo trì node | Pod chết dưới tải: 0/1400 lỗi |
| nginx `proxy-connect-timeout 1s` + thử Pod khác | ~50s đầu khi node chết (endpoint còn trỏ Pod chết) | node chết: 4/5 endpoint 0 lỗi |
| retry payment + idempotency key | mất response giữa chừng mà không trừ tiền 2 lần | - |
| HPA (booking 3-20, payment 3-10) | tải tăng đột biến | 10x tải: 3 → 13 Pod, 0/9293 lỗi |
| Argo Rollouts canary + analysis | release lỗi logic (`/health` vẫn OK nên probe không bắt được) | lỗi tới 1/3 traffic, **tự huỷ sau 43s** (trước: 100% lỗi, cần người rollback) |
| NetworkPolicy default-deny cả 2 chiều | 1 Pod bị chiếm đi tiếp sang DB / service khác / Internet | Pod user chỉ tới được Redis + DNS |
| không mount ServiceAccount token, `NODE_ENV=production` | Pod bị chiếm gọi Kubernetes API / lộ stack trace ra ngoài | - |
| Sealed Secrets | password trong repo public | Git dựng lại được Secret, chỉ cần 1 file khoá |
| backup mỗi đêm + restore thử | xoá nhầm / hỏng data | backup = DB thật (25740 dòng) |
| alert theo xu hướng memory (`predict_linear`) | leak làm mọi replica OOM cùng lúc | báo trước OOM 28s |

Replica chỉ chống được lỗi **lẻ** (1 Pod, 1 node). Lỗi trong code/config có ở **mọi** replica cùng lúc → chống bằng canary + rollback nhanh, không phải thêm Pod.

---

## 7. Điểm yếu đã biết

Danh sách đầy đủ + hướng xử lý: [COMMANDS.md → Việc còn thiếu](COMMANDS.md#con-thieu). Quan trọng nhất:

- Mọi thứ chạy trên **1 máy cá nhân**: tắt máy = không có cluster, không deploy được; khoá Sealed Secrets và backup chỉ có 1 bản.
- Postgres 1 replica (mất node chạy Postgres = payment trả 503 tới khi Pod lên lại).
- Alert chưa gửi tới kênh thật (Slack/Telegram); Alertmanager 1 bản.
- Canary chỉ có ở booking; không có service mesh nên bước nhỏ nhất là 1/3 traffic.

Hướng tiếp theo: đưa lên AWS EKS (registry ECR, RDS, Secrets Manager) - xem Roadmap.
