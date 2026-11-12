<#
Phase 24 - pipeline GitOps cho Grab Mini (bản Phase 23 deploy bằng helm: xem git history của file này)

  test -> build (tag = git SHA) -> push (local registry) -> release (commit tag + git push) -> sync (đợi Argo CD) -> smoke test
                                                                                              lỗi ──► git revert + git push

Pipeline KHÔNG còn quyền ghi vào cluster: nó chỉ ghi vào Git. Argo CD (trong cluster) kéo Git về và apply.
  -> rollback = git revert, không phải helm rollback (helm rollback sẽ bị Argo CD selfHeal đè lại ngay)

Cách dùng (PowerShell 7, thư mục grab-mini):
  ./ci/pipeline.ps1 -Service booking
  ./ci/pipeline.ps1 -Service payment,user,booking
  (KHÔNG dùng "pwsh -File ci/pipeline.ps1 -Service a,b" - với -File, "a,b" là 1 chuỗi, không phải mảng)

Yêu cầu: registry localhost:5001, Argo CD đã bootstrap (kubectl apply -f argocd/root.yaml), remote origin, Ingress http://localhost.
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet("booking", "payment", "user", "driver", "notification")]
  [string[]]$Service,
  [string]$Registry = "localhost:5001",
  [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true   # lệnh ngoài (git, npm, docker, kubectl) trả exit code != 0 -> dừng pipeline
Set-Location (Split-Path $PSScriptRoot -Parent)

function Invoke-Stage([string]$Name, [scriptblock]$Body) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Write-Host "==> [$Name]" -ForegroundColor Cyan
  & $Body
  Write-Host ("    OK ({0:N1}s)" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
}

# Đợi Argo CD: app đã sync ĐÚNG commit $Revision, Synced + Healthy, và Deployment rollout xong.
# Không có webhook GitHub -> cluster nên "refresh" chủ động thay vì đợi chu kỳ poll (60s).
function Wait-ArgoSync([string]$App, [string]$Revision) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec); $last = ""; $refreshed = $false; $degradedSince = $null
  while ((Get-Date) -lt $deadline) {
    # service MỚI: Application chưa có cho tới khi root sync ApplicationSet (commit này thêm element) -> refresh root, đợi
    $json = kubectl -n argocd get application $App --ignore-not-found -o json
    if (-not $json) {
      if ($last -ne "missing") { Write-Host "    argocd $App : chưa có Application -> refresh root"; $last = "missing" }
      kubectl -n argocd annotate application root argocd.argoproj.io/refresh=normal --overwrite | Out-Null
      Start-Sleep -Seconds 3; continue
    }
    if (-not $refreshed) { kubectl -n argocd annotate application $App argocd.argoproj.io/refresh=normal --overwrite | Out-Null; $refreshed = $true }
    $s = ($json | ConvertFrom-Json).status
    $now = "sync={0}@{1} health={2} op={3}" -f $s.sync.status, "$($s.sync.revision)".Substring(0, [Math]::Min(7, "$($s.sync.revision)".Length)), $s.health.status, $s.operationState.phase
    if ($now -ne $last) { Write-Host "    argocd $App : $now"; $last = $now }
    # Degraded THOÁNG QUA là bình thường với app có HPA: ngay sau rollout HPA chưa có metric của Pod mới
    # (ScalingActive=False/FailedGetResourceMetric) -> Argo CD coi HPA Degraded ~30s (gặp ở Incident 4).
    # Chỉ coi là lỗi khi Degraded LIÊN TỤC > 30s, nếu không pipeline sẽ git revert oan.
    if ($s.health.status -eq "Degraded") {
      if (-not $degradedSince) { $degradedSince = Get-Date }
      elseif (((Get-Date) - $degradedSince).TotalSeconds -gt 30) { throw "Argo CD báo $App Degraded liên tục > 30s" }
    } else { $degradedSince = $null }
    # sync.revision = commit Argo CD đang so sánh; Synced ở revision đó = cluster khớp Git của commit đó.
    # (không đòi operationState.revision: commit không đổi manifest của app này thì Argo CD không chạy sync nào)
    if ($s.sync.revision -eq $Revision -and $s.sync.status -eq "Synced" -and $s.health.status -eq "Healthy" -and
        $s.operationState.phase -ne "Running") {
      # Argo CD có thể báo Healthy 1 nhịp trước khi controller thấy generation mới -> chốt lại bằng rollout status (chỉ đọc)
      $left = [int]($deadline - (Get-Date)).TotalSeconds
      kubectl rollout status "deployment/$App" -n default --timeout "$([Math]::Max($left, 1))s" | Out-Null
      return
    }
    Start-Sleep -Seconds 3
  }
  throw "Argo CD chưa sync $App về $($Revision.Substring(0,7)) Synced/Healthy sau ${TimeoutSec}s"
}

# Chạy thử IMAGE vừa build (không phải code): bắt lỗi Dockerfile/entrypoint mà npm test không thấy
# (Phase 24 demo C: CMD server.jss qua được test + build, chỉ lộ ra khi Pod CrashLoop sau 3 phút chờ Argo CD)
function Test-Container([string]$Image) {
  $port = (docker inspect $Image --format '{{range $p, $_ := .Config.ExposedPorts}}{{$p}}{{end}}') -replace '/tcp', ''
  $cid = docker run -d $Image
  try {
    for ($i = 1; $i -le 10; $i++) {
      Start-Sleep -Milliseconds 500
      if ((docker inspect $cid --format '{{.State.Running}}') -ne "true") {
        throw "container thoát ngay (exit $(docker inspect $cid --format '{{.State.ExitCode}}')):`n$((docker logs $cid 2>&1 | Select-Object -Last 5) -join "`n")"
      }
      $PSNativeCommandUseErrorActionPreference = $false
      $body = docker exec $cid wget -qO- "http://127.0.0.1:$port/health" 2>$null
      $PSNativeCommandUseErrorActionPreference = $true
      if ($body -eq "ok") { Write-Host "    container: GET :$port/health -> ok"; return }
    }
    throw "container không trả /health sau 5s"
  } finally { docker rm -f $cid | Out-Null }
}

# Smoke test: gọi qua Ingress như người dùng thật (retry vì ingress-nginx cần vài giây nhận endpoint mới)
function Test-Smoke([string]$Svc) {
  $req = switch ($Svc) {
    "user"    { @{ Uri = "http://localhost/users";   Method = "GET";  Expect = "user-service" } }
    "payment" { @{ Uri = "http://localhost/payment"; Method = "POST"; Expect = '"transactionId"'; Body = '{"amount":1}' } }
    "booking" { @{ Uri = "http://localhost/booking"; Method = "POST"; Expect = '"payment":{"service":"payment-service"' } }
    "driver"  { @{ Uri = "http://localhost/drivers"; Method = "GET";  Expect = "driver-service" } }
    # notification KHÔNG có route Ingress (chỉ nội bộ) -> gọi từ trong 1 Pod booking (NetworkPolicy chỉ cho booking/driver vào)
    "notification" { @{ Exec = "deploy/booking"; Uri = "http://notification-service/notify"; Method = "POST"; Expect = "notification-service"; Body = '{"type":"smoke-test"}' } }
  }
  $body = if ($req.Body) { $req.Body } else { '{}' }
  for ($i = 1; $i -le 10; $i++) {
    try {
      if ($req.Exec) {
        $PSNativeCommandUseErrorActionPreference = $false
        $content = kubectl exec $req.Exec -- wget -qO- -T 5 --header "Content-Type: application/json" --post-data $body $req.Uri 2>&1
        $PSNativeCommandUseErrorActionPreference = $true
        if ($LASTEXITCODE -eq 0 -and "$content".Contains($req.Expect)) { Write-Host "    (từ $($req.Exec)) $($req.Method) $($req.Uri) -> ok"; return }
        Write-Host "    lần $i : $content"
      } else {
        $r = Invoke-WebRequest -Uri $req.Uri -Method $req.Method -Body $body -ContentType "application/json" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200 -and $r.Content.Contains($req.Expect)) { Write-Host "    $($req.Method) $($req.Uri) -> 200"; return }
        Write-Host "    lần $i : HTTP $($r.StatusCode), nội dung không khớp"
      }
    } catch { Write-Host "    lần $i : $($_.Exception.Message)" }
    Start-Sleep -Seconds 3
  }
  throw "smoke test thất bại: $($req.Method) $($req.Uri)"
}

foreach ($svc in $Service) {
  $total = [Diagnostics.Stopwatch]::StartNew()
  Write-Host "`n################ $svc-service ################" -ForegroundColor Yellow

  # --- 0. guard ---
  # (a) image phải build từ code ĐÃ commit, nếu không tag SHA sẽ nói dối
  $dirty = git status --porcelain -- "$svc-service" charts helm-values argocd
  if ($dirty) { throw "Có thay đổi chưa commit trong $svc-service/, charts/, helm-values/ hoặc argocd/:`n$dirty`nCommit trước rồi chạy lại." }
  # (b) Git là nguồn sự thật -> code local phải đã có trên origin, và local không được tụt sau origin
  git fetch -q origin main
  $behind = [int](git rev-list --count HEAD..origin/main)
  if ($behind -gt 0) { throw "local main tụt sau origin/main $behind commit -> git pull --rebase trước" }

  $sha = git log -1 --format=%h --abbrev=12 -- "$svc-service"
  $image = "$Registry/$svc-service:$sha"
  $valuesImage = "helm-values/$svc-image.yaml"
  Write-Host "image: $image"

  Invoke-Stage "1/6 test" {
    Push-Location "$svc-service"
    try { npm ci --no-audit --no-fund --loglevel=error; npm test } finally { Pop-Location }
  }

  Invoke-Stage "2/6 build" {
    docker build -q -t $image --label "org.opencontainers.image.revision=$sha" "./$svc-service"
    Test-Container $image
  }

  Invoke-Stage "3/6 push image" {
    docker push -q $image
  }

  $deployCommit = $null
  Invoke-Stage "4/6 release (git)" {
    @"
# TẠO BỞI ci/pipeline.ps1 - KHÔNG sửa tay. Image đang chạy ở prod cho $svc (Argo CD đọc file này).
image:
  repository: $Registry/$svc-service
  tag: "$sha"
"@ -replace "`r`n", "`n" | Set-Content -NoNewline -Encoding utf8NoBOM $valuesImage   # file .ps1 là CRLF -> here-string cũng CRLF; file YAML trong Git là LF
    Add-Content -NoNewline -Value "`n" $valuesImage
    git add $valuesImage
    if (git diff --cached --name-only) {
      git commit -q -m "deploy($svc): $sha"
      $script:deployCommit = git rev-parse HEAD
      Write-Host "    commit: $(git log -1 --format='%h %s')"
    } else { Write-Host "    $valuesImage không đổi (tag này đã ở trong Git)" }
    git push -q origin HEAD:main   # đẩy cả code (nếu chưa push) lẫn commit deploy
  }

  try {
    Invoke-Stage "5/6 sync (Argo CD)" { Wait-ArgoSync $svc (git rev-parse HEAD) }
    Invoke-Stage "6/6 smoke test" { Test-Smoke $svc }
  } catch {
    $err = $_
    if ($deployCommit) {
      # Rollback kiểu GitOps: commit ngược lại commit deploy -> Argo CD sync về tag cũ
      Write-Host "    LỖI: $err`n    -> git revert $($deployCommit.Substring(0,7)) + push, đợi Argo CD đưa về tag cũ" -ForegroundColor Red
      git revert --no-edit $deployCommit | Out-Null
      git push -q origin HEAD:main
      Wait-ArgoSync $svc (git rev-parse HEAD)
      Test-Smoke $svc
      Write-Host "    đã rollback: $(git log -1 --format='%h %s')" -ForegroundColor Yellow
    }
    throw "deploy $svc thất bại: $err"
  }

  Write-Host ("DONE {0}: {1} (git {2}, {3:N0}s)" -f $svc, $image, (git rev-parse --short HEAD), $total.Elapsed.TotalSeconds) -ForegroundColor Green
}
