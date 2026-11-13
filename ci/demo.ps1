<#
Demo cuối khoá - mỗi cảnh 1 lệnh, in ra đúng số liệu cần nói. Kịch bản + lời dẫn: DEMO.md

  ./ci/demo.ps1 1   # tổng quan: node, Pod trải 2 worker, 7 app Argo CD
  ./ci/demo.ps1 2   # gọi API như người dùng: booking -> payment (DB) -> notification
  ./ci/demo.ps1 3   # deploy = git push: sửa code booking -> runner tự chạy pipeline -> Argo CD -> 0 lỗi
  ./ci/demo.ps1 4   # self-heal: ai đó scale tay -> Argo CD đưa về Git
  ./ci/demo.ps1 5   # Pod chết dưới traffic -> 0 lỗi
  ./ci/demo.ps1 6   # release lỗi -> thấy lỗi -> rollback 1 lệnh (git revert)
  ./ci/demo.ps1 7   # tải tăng -> HPA scale
  ./ci/demo.ps1 8   # bảo mật: Pod bị chiếm làm được gì?

Cảnh 3 và 6 tạo commit thật trên main (đó là điểm của GitOps: lịch sử deploy = lịch sử Git).
#>
param([Parameter(Mandatory)][ValidateRange(1, 8)][int]$Scene)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Title([string]$t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Say([string]$t) { Write-Host "  $t" -ForegroundColor Yellow }
function Elapsed($sw) { "{0:N1}s" -f $sw.Elapsed.TotalSeconds }

function Start-Traffic([int]$Seconds) {
  $script:traffic = Start-Job -ArgumentList "$root\ci\traffic.ps1", $Seconds { param($p, $s) & $p -Seconds $s }
  Say "traffic nền ${Seconds}s: 5 endpoint qua Ingress, gọi liên tục"
}
function Stop-Traffic {
  Say "đợi traffic chạy xong..."
  $out = Receive-Job $script:traffic -Wait -AutoRemoveJob
  $out | ForEach-Object { Write-Host "  $_" }
}
function Sync-Main {
  git fetch -q origin main
  if ([int](git rev-list --count HEAD..origin/main) -gt 0) { git pull -q --rebase origin main }
}
function Get-Image([string]$d) { kubectl get deploy $d -o jsonpath='{.spec.template.spec.containers[0].image}' }

switch ($Scene) {
  1 {
    Title "1. Tổng quan: 3 node, 5 service + Postgres + Redis, mọi thứ từ Git"
    kubectl get nodes
    Say "Pod của mỗi service trải trên 2 worker (topologySpread) - mất 1 node vẫn còn Pod:"
    kubectl get pods -o wide --no-headers | Where-Object { $_ -notmatch '^db-init' } | ForEach-Object {
      $c = $_ -split '\s+'; [pscustomobject]@{ app = ($c[0] -replace '-[a-z0-9]+-[a-z0-9]+$', '' -replace '-\d+$', ''); node = $c[6] -replace 'grab-mini-', '' }
    } | Group-Object app | ForEach-Object { "  {0,-13} {1}" -f $_.Name, (($_.Group.node | Sort-Object) -join ', ') }
    Say "Argo CD: 7 Application, tất cả Synced + Healthy = cluster khớp Git"
    kubectl get applications -n argocd
    Say "HPA:"; kubectl get hpa
  }
  2 {
    Title "2. Một cuốc xe: booking -> payment (ghi Postgres) -> notification"
    $r = Invoke-RestMethod -Method Post http://127.0.0.1/booking -ContentType application/json -Body '{}'
    "  bookingId      : $($r.bookingId)"
    "  payment        : transactionId $($r.payment.transactionId) (pod $($r.payment.pod))"
    "  notification   : $($r.notification.type) $($r.notification.notificationId)"
    Say "gọi lại payment cùng bookingId -> KHÔNG trừ tiền 2 lần (idempotency key):"
    $stats1 = Invoke-RestMethod http://127.0.0.1/payments/stats
    $null = Invoke-RestMethod -Method Post http://127.0.0.1/payment -ContentType application/json -Body (@{ amount = 100; paymentId = $r.bookingId } | ConvertTo-Json)
    $stats2 = Invoke-RestMethod http://127.0.0.1/payments/stats
    "  payments trong DB: $($stats1.count) -> $($stats2.count)"
    $u = Invoke-RestMethod http://127.0.0.1/users; "  /users views (Redis): $($u.views)"
    $d = Invoke-RestMethod http://127.0.0.1/drivers; "  /drivers: $($d.drivers -join ', ')"
  }
  3 {
    Title "3. Deploy = git push (self-hosted runner -> pipeline -> Argo CD)"
    Sync-Main
    $before = Get-Image booking; Say "đang chạy: $before"
    Start-Traffic 150
    $f = "booking-service/server.js"
    $lines = Get-Content $f
    $stamp = "// demo deploy $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if ($lines[0] -like "// demo deploy *") { $lines[0] = $stamp } else { $lines = @($stamp) + $lines }
    [IO.File]::WriteAllText("$root\$f", (($lines -join "`n") + "`n"))
    git add $f; git commit -q -m "demo: đổi code booking"; git push -q origin HEAD:main
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Say "đã push $(git rev-parse --short HEAD) - từ đây không gõ lệnh nào nữa. Xem: https://github.com/huybosch/k8s-grab/actions"
    do { Start-Sleep 3; $now = Get-Image booking } until ($now -ne $before -or $sw.Elapsed.TotalSeconds -gt 300)
    if ($now -eq $before) { throw "sau 300s image chưa đổi - runner có đang chạy không? (C:\actions-runner\run.cmd)" }
    Say "Argo CD nhận tag mới sau $(Elapsed $sw): $now"
    kubectl rollout status deploy/booking --timeout=180s | Out-Null
    Say "rollout xong sau $(Elapsed $sw) (pipeline còn smoke test vài giây)"
    Stop-Traffic
    Sync-Main; Say "commit do runner tạo: $(git log -1 --format='%h %s' -- helm-values/booking-image.yaml)"
  }
  4 {
    Title "4. Self-heal: sửa tay trên cluster -> Argo CD đưa về đúng Git"
    kubectl get deploy user
    Say "giả sử ai đó: kubectl scale deploy/user --replicas=1"
    kubectl scale deploy/user --replicas=1 | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    do { Start-Sleep -Milliseconds 100; $r = kubectl get deploy user -o jsonpath='{.spec.replicas}' } until ($r -eq "3" -or $sw.Elapsed.TotalSeconds -gt 60)
    Say "spec.replicas về 3 sau $(Elapsed $sw) - Git mới là nguồn sự thật"
    kubectl rollout status deploy/user --timeout=60s | Out-Null; kubectl get deploy user
  }
  5 {
    Title "5. Pod chết giữa giờ cao điểm"
    Start-Traffic 40
    Start-Sleep 10
    $pod = kubectl get pods -l app=booking -o jsonpath='{.items[0].metadata.name}'
    Say "xoá $pod (Kubernetes rút Pod khỏi Service trước, đợi preStop 10s, rồi mới tắt)"
    kubectl delete pod $pod --wait=false | Out-Null
    Start-Sleep 5; kubectl get pods -l app=booking
    Stop-Traffic
  }
  6 {
    Title "6. Release lỗi -> phát hiện -> rollback 1 lệnh"
    Sync-Main
    Start-Traffic 120
    Start-Sleep 5
    $v = "helm-values/booking.yaml"
    (Get-Content -Raw $v) -replace "  VERSION: v1`n", "  VERSION: v1`n  BUGGY: `"true`"   # demo: release lỗi`n" | Set-Content -NoNewline $v
    git add $v; git commit -q -m "release(booking): config mới (demo - có lỗi)"; git push -q origin HEAD:main
    kubectl -n argocd annotate application booking argocd.argoproj.io/refresh=normal --overwrite | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Say "đã push release lỗi - readiness /health vẫn OK nên Kubernetes KHÔNG chặn được"
    do { Start-Sleep 1; $code = try { (Invoke-WebRequest -Method Post http://127.0.0.1/booking -Body '{}' -ContentType application/json -UseBasicParsing).StatusCode } catch { $_.Exception.Response.StatusCode.value__ } } until ($code -eq 500 -or $sw.Elapsed.TotalSeconds -gt 120)
    Say "booking bắt đầu trả 500 sau $(Elapsed $sw); Argo CD vẫn báo: $(kubectl -n argocd get application booking -o jsonpath='{.status.health.status}')"
    Start-Sleep 15
    Say "rollback:"
    ./ci/rollback.ps1 -Service booking
    Stop-Traffic
  }
  7 {
    Title "7. Tải tăng ~10 lần -> HPA tự thêm Pod"
    kubectl get hpa booking
    Say "60s tải: 10 luồng x (request + nghỉ 50ms) ~ 160 req/s = 10x traffic thường (Incident 3)"
    $load = Start-Job -ArgumentList "$root\ci\load.js" { param($p) node $p http://127.0.0.1/booking 10 60 POST 50 }
    $sw = [Diagnostics.Stopwatch]::StartNew(); $last = ""
    while ($load.State -eq "Running") {
      $h = kubectl get hpa booking -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}% replicas={.status.currentReplicas}->{.status.desiredReplicas}'
      if ($h -ne $last) { "  +{0,3}s cpu={1}" -f [int]$sw.Elapsed.TotalSeconds, $h; $last = $h }
      Start-Sleep 3
    }
    Receive-Job $load -AutoRemoveJob -Wait | Select-Object -Last 4 | ForEach-Object { "  $_" }
    kubectl get hpa booking
    Say "Pod mới sẽ tự giảm sau ~5 phút (stabilization window) - không cần làm gì"
  }
  8 {
    Title "8. Pod user bị chiếm: kẻ tấn công làm được gì?"
    ./ci/attack-surface.ps1
  }
}
