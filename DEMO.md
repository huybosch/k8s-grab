# Grab Mini - Demo cuối khoá

Kịch bản ~15 phút: một nền tảng đặt xe nhỏ (5 microservice + Postgres + Redis) chạy trên Kubernetes 3 node, deploy hoàn toàn bằng GitOps, chịu được Pod chết, release lỗi và tải tăng 10 lần.

Hệ thống là gì, chạy thế nào: [README.md](README.md). Mỗi cảnh chạy bằng **1 lệnh** `./ci/demo.ps1 <số>` (PowerShell 7, thư mục `grab-mini`). Số liệu "Kết quả tập" bên dưới lấy từ lần chạy tập ngày 13/11/2026 trên cluster vừa dựng lại từ đầu.

## Kiến trúc

```text
                    Ingress (nginx, retry khi Pod chết)
       /users        /booking         /payment(s)        /drivers
         │               │                 │                 │
     user (x3) ──┐   booking (canary, HPA 3-20) ─► payment (HPA 3-10) ─► Postgres (StatefulSet)
         │       │       │                                       ▲ chỉ payment vào được
       Redis ◄───┘       └──► notification (x2) ◄── driver (x3)
                         (best-effort, timeout 1s)

 Git (github.com/huybosch/k8s-grab) ──► Argo CD (app-of-apps, 9 Application) ──► cluster
 git push code ──► self-hosted runner ──► test → build → push registry → commit tag ──► Argo CD
 Prometheus + Grafana + Loki + Alertmanager; 12 NetworkPolicy (default-deny, cả ingress + egress)
 Secret: SealedSecret trong Git; backup Postgres mỗi đêm (CronJob) + restore thử; booking: Argo Rollouts canary
```

## Chuẩn bị (5 phút trước demo)

```powershell
cd D:\OBsidian\NUO3HC\Kubernetes\grab-mini
git pull --rebase origin main                           # cảnh 3, 6 tạo commit - local phải mới nhất
kubectl get applications -n argocd                      # 9 app Synced Healthy
Get-Process Runner.Listener                             # runner đang chạy? không có -> Start-Process C:\actions-runner\run.cmd
kubectl get hpa                                         # booking về 3 replica (sau cảnh 7 lần tập: đợi ~5 phút)
# terminal phụ: Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# -> http://localhost:3000/d/grab-mini/grab-mini-services (mật khẩu admin: xem COMMANDS.md Scenario 20)
# tab trình duyệt: https://github.com/huybosch/k8s-grab/actions
```

Nếu cluster hỏng: [runbook dựng lại](COMMANDS.md#rebuild) - đã chạy thật, ~11 phút.

## Kịch bản

| # | Cảnh | Thông điệp | Thời lượng |
|---|---|---|---|
| 1 | Tổng quan | cluster = Git; Pod trải 2 worker | 1' |
| 2 | Một cuốc xe | luồng nghiệp vụ thật, idempotency | 1' |
| 3 | Deploy = `git push` | không ai gõ lệnh deploy; 0 lỗi | 2' |
| 4 | Self-heal | sửa tay bị Argo CD đè lại | 0.5' |
| 5 | Pod chết | người dùng không thấy gì | 1' |
| 6 | Release lỗi | Kubernetes không bắt được lỗi logic → canary + analysis **tự huỷ** | 2.5' |
| 7 | Tải 10x | HPA tự thêm Pod | 1.5' |
| 8 | Bảo mật | Pod bị chiếm vẫn bị nhốt | 1' |
| - | Grafana + Hỏi đáp | | 4' |

### 1. Tổng quan - `./ci/demo.ps1 1`

> "3 node: 1 control-plane, 2 worker. Mỗi service có Pod trên **cả 2 worker** - mất 1 máy vẫn chạy. 9 Application trong Argo CD đều Synced: cluster đang khớp đúng từng dòng trong Git."

Kết quả tập: booking/payment/user `worker, worker2, worker2`, notification `worker, worker2`; 7 app `Synced Healthy`; HPA booking 3-20, payment 3-10.

### 2. Một cuốc xe - `./ci/demo.ps1 2`

> "Booking gọi payment (ghi Postgres) rồi gọi notification. Mạng chập chờn thì booking gọi lại payment - nên `bookingId` được dùng làm khoá idempotency: gọi lại cùng id **không trừ tiền 2 lần**."

Kết quả tập: `payments trong DB: 2 -> 2` sau khi gửi lại cùng `paymentId`.

### 3. Deploy = git push - `./ci/demo.ps1 3`

> "Tôi sửa code booking và `git push`. Từ đây không gõ thêm lệnh nào: runner trên máy này chạy test → build image (tag = git SHA) → chạy thử container → push registry → commit tag vào Git. Argo CD thấy commit; booking là **canary**: 1 Pod mới nhận ~1/3 traffic trong 45s, rồi 2/3 trong 30s, rồi 100% - suốt quá trình Argo Rollouts đo error rate trên Prometheus. Traffic vẫn chạy."

Kết quả tập (15/11, sau khi chuyển canary): Argo CD nhận tag mới sau **39s**, canary 1/3 → 2/3 → 100% xong sau **131s**; traffic **3200/3200 OK, 0 lỗi**; runner tự tạo commit `deploy(booking): 3d6405e27f9e`; job `cd` success. Mở tab GitHub Actions để chỉ job `cd` chạy trên runner `grab-mini-local`.

### 4. Self-heal - `./ci/demo.ps1 4`

> "Nếu ai đó vào cluster sửa tay - ví dụ scale user xuống 1 - Argo CD đưa về đúng Git ngay."

Kết quả tập: `spec.replicas` về 3 sau **0.2s**.

### 5. Pod chết - `./ci/demo.ps1 5`

> "Xoá 1 Pod booking giữa giờ cao điểm. Kubernetes rút Pod khỏi Service, Pod đợi 10s (preStop) cho các request đang chạy xong rồi mới tắt; Pod mới được tạo bù."

Kết quả tập: **1400/1400 OK, 0 lỗi**.

### 6. Release lỗi - `./ci/demo.ps1 6`

> "Giờ tôi đẩy một config lỗi: booking trả 500. `/health` vẫn OK nên **Kubernetes không biết** - readiness probe chỉ kiểm tra process sống, không kiểm tra logic. Nhưng bản mới chỉ được 1 Pod (~1/3 traffic); Argo Rollouts đo error rate mỗi 15s - vượt 5% hai lần là **tự huỷ**, không cần ai bấm."

Kết quả tập (15/11): Argo CD áp bản lỗi sau **2s**, 500 đầu tiên **+9s** (chỉ từ Pod canary), **TỰ ABORT +43s** (`Metric "error-rate" assessed Failed due to failed (2) > failureLimit (1)`). Booking **102 request lỗi** (khoảng 1/3 request booking trong ~42s), 4 endpoint khác 0 lỗi. Sau abort, `rollback.ps1` chỉ dọn Git (revert commit lỗi): **6s**, không tạo Pod mới.

> So sánh để nói: trước canary (13/11) cùng release lỗi → **100%** request booking lỗi, **218** request, phải có người chạy `rollback.ps1`. Lần đầu ở Incident 2 (chưa có gì) → ~5 phút mới ra khỏi sự cố.

### 7. Tải 10x - `./ci/demo.ps1 7`

> "160 request/giây - gấp 10 lần bình thường. HPA đo CPU, thêm Pod."

Kết quả tập: CPU 15% → 207%, replicas **3 → 5 → 10 → 13** trong 56s; **9293/9293 OK, 0 lỗi**, p95 16-20ms. Pod tự giảm sau ~5 phút.

### 8. Bảo mật - `./ci/demo.ps1 8`

> "Giả sử kẻ tấn công chiếm được Pod user. Từ bên trong Pod, họ chỉ tới được đúng Redis và DNS: không vào DB, không gọi service khác, không ra Internet, không có token Kubernetes."

Kết quả tập: `BLOCKED` postgres, payment, notification, booking, Kubernetes API, Internet, argocd, grafana; `OPEN` chỉ redis + DNS; không có env nhạy cảm, không mount token.

### Grafana

Dashboard `grab-mini-services`: request rate, error rate (thấy rõ vạch lỗi của cảnh 6), p95, số Pod (thấy HPA ở cảnh 7). Loki: `{app="notification"} |= "booking-confirmed"` - log của từng cuốc xe.

## Hỏi đáp dự kiến

| Câu hỏi | Trả lời ngắn |
|---|---|
| Vì sao không dùng `kubectl apply`/`helm upgrade` để deploy? | Git là nguồn sự thật: ai deploy, lúc nào, bản nào đều nằm trong `git log`; rollback = `git revert`; sửa tay bị selfHeal đè lại. |
| Node chết thì sao? | Đã thử (Incident 4): ~50s đầu endpoint vẫn trỏ Pod chết, nginx `connect-timeout 1s` + thử Pod khác → 4/5 endpoint 0 lỗi; Pod được tạo lại sau ~80s. |
| Postgres chết? | 1 replica, `local-path` - **điểm yếu**: chưa có replica/backup tự động. Payment trả 503 rõ ràng thay vì treo. |
| Sao repo public mà dùng self-hosted runner được? | Hook `guard.ps1` trên runner từ chối mọi job không phải `cd.yaml` trên `main` - kể cả workflow PR tự thêm (đã thử: job bị chặn, `kubectl` skipped). |
| Memory leak? | Incident 6: 3/3 Pod OOMKilled cùng lúc. Thêm alert `predict_linear` - backtest báo trước OOM 28s. Replica không chống được lỗi code. |

## Review toàn bộ

Đã làm (chi tiết từng phần: [COMMANDS.md](COMMANDS.md)):

- **Nền tảng**: kind 3 node, 5 service Node.js, Postgres StatefulSet, Redis, Ingress, ConfigMap/Secret, probes, requests/limits, HPA, PDB, topologySpread, graceful shutdown (preStop 10s, keepAlive 65s).
- **Đóng gói + deploy**: 1 Helm chart dùng chung cho 5 service + chart platform; Argo CD app-of-apps + ApplicationSet; pipeline test → build → container smoke → push → commit tag → đợi sync → smoke → tự revert; GitHub Actions CI; CD qua self-hosted runner.
- **Vận hành**: Prometheus/Grafana/Loki/Alertmanager, 8 alert app; 7 incident chạy thật có số đo trước/sau; runbook dựng lại cluster đã chạy thật (~11 phút).
- **Bảo mật**: NetworkPolicy default-deny cả 2 chiều, least privilege DB (role payment chỉ SELECT/INSERT), không mount ServiceAccount token, runner guard, Sealed Secrets, quét dependency (vá `body-parser` DoS) + Node 24 LTS, endpoint gây lỗi mặc định tắt.

## Phần còn yếu

| Điểm yếu | Hậu quả | Hướng xử lý |
|---|---|---|
| Canary chỉ cho booking, không mesh | bước nhỏ nhất = 1/3 traffic; analysis đo cả service → lỗi nhẹ ở canary bị pha loãng, có thể lọt ngưỡng 5% | trafficRouting nginx (canary 5-10%) + metric theo revision; canary cho 4 service còn lại |
| Postgres 1 replica; backup mỗi đêm nằm trong cluster | mất node = DB dừng; mất cluster = mất cả backup nếu chưa chạy `ci/pg-backup-pull.ps1` | CloudNativePG / RDS; đẩy backup ra object storage (S3) tự động |
| Khoá Sealed Secrets chỉ có 1 bản trên máy cá nhân | mất máy = mất khoá = không giải mã được Secret trong Git | lưu khoá ở nơi thứ 2 (password manager); trên cloud: External Secrets + AWS Secrets Manager |
| Alertmanager + alert-webhook 1 replica, alert chưa gửi kênh thật | mất node = mất kênh báo động; không ai nhận alert | 2 replica trải 2 node, receiver Slack/Telegram |
| CD phụ thuộc máy cá nhân | tắt máy = không deploy được | EKS + registry chung (ECR), runner GitHub push image |
| Hạ tầng ngoài Argo CD | ingress-nginx, metrics-server, monitoring, Argo CD vẫn cài tay (đã pin version) | đưa vào app-of-apps |
| Alert dự báo leak nhạy lúc Pod khởi động | lần tập: `pending` 30s khi Pod user mới chạy (không `firing` nhờ `for: 1m`) | bỏ qua Pod tuổi < 5 phút hoặc tăng cửa sổ `predict_linear` |
| Chưa có tracing, chưa staging | khó lần theo request qua nhiều service; mọi thay đổi đi thẳng prod | OpenTelemetry + Tempo; môi trường staging + promote |

Tiếp theo: giai đoạn 2 - đưa lên AWS EKS (Future Plan trong Roadmap).
