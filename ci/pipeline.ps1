<#
Phase 23 - CI/CD pipeline chạy LOCAL cho Grab Mini

  test -> build (tag = git SHA) -> push (local registry) -> deploy (helm, tự rollback) -> smoke test -> ghi lại (git commit)

Cách dùng (trong 1 cửa sổ PowerShell 7, thư mục grab-mini):
  ./ci/pipeline.ps1 -Service booking
  ./ci/pipeline.ps1 -Service payment,user,booking
  (KHÔNG dùng "pwsh -File ci/pipeline.ps1 -Service a,b" - với -File, "a,b" là 1 chuỗi, không phải mảng)

Yêu cầu: registry localhost:5001 (container kind-registry), cluster grab-mini, Ingress ở http://localhost.
Pipeline tương đương trên GitHub Actions: .github/workflows/ci.yaml
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet("booking", "payment", "user")]
  [string[]]$Service,
  [string]$Registry = "localhost:5001",
  [string]$Timeout = "3m"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true   # lệnh ngoài (git, npm, docker, helm) trả exit code != 0 -> dừng pipeline
Set-Location (Split-Path $PSScriptRoot -Parent)

# Trả file helm-values/<svc>-image.yaml về bản đã commit (hoặc xoá nếu chưa từng commit)
function Restore-ImageValues([string]$Path) {
  if (git ls-files -- $Path) { git checkout -- $Path } else { Remove-Item $Path -ErrorAction SilentlyContinue }
}

function Invoke-Stage([string]$Name, [scriptblock]$Body) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Write-Host "==> [$Name]" -ForegroundColor Cyan
  & $Body
  Write-Host ("    OK ({0:N1}s)" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
}

# Smoke test: gọi qua Ingress như người dùng thật. Thử lại vài lần vì ingress-nginx cần vài giây
# để nhận endpoint mới sau rollout (đã gặp 503 tạm thời ở Phase 19/22).
function Test-Smoke([string]$Svc) {
  $req = switch ($Svc) {
    "user"    { @{ Uri = "http://localhost/users";   Method = "GET";  Expect = "user-service" } }
    "payment" { @{ Uri = "http://localhost/payment"; Method = "POST"; Expect = "payment-service" } }
    "booking" { @{ Uri = "http://localhost/booking"; Method = "POST"; Expect = '"payment":{"service":"payment-service"' } }
  }
  for ($i = 1; $i -le 10; $i++) {
    try {
      $r = Invoke-WebRequest -Uri $req.Uri -Method $req.Method -Body '{}' -ContentType "application/json" -UseBasicParsing -TimeoutSec 5
      if ($r.StatusCode -eq 200 -and $r.Content.Contains($req.Expect)) { Write-Host "    $($req.Method) $($req.Uri) -> 200"; return }
      Write-Host "    lần $i : HTTP $($r.StatusCode), nội dung không khớp"
    } catch { Write-Host "    lần $i : $($_.Exception.Message)" }
    Start-Sleep -Seconds 3
  }
  throw "smoke test thất bại: $($req.Method) $($req.Uri)"
}

foreach ($svc in $Service) {
  $total = [Diagnostics.Stopwatch]::StartNew()
  Write-Host "`n################ $svc-service ################" -ForegroundColor Yellow

  # --- 0. guard: image phải build từ code ĐÃ commit, nếu không tag SHA sẽ nói dối ---
  $dirty = git status --porcelain -- "$svc-service" charts helm-values
  if ($dirty) { throw "Có thay đổi chưa commit trong $svc-service/, charts/ hoặc helm-values/:`n$dirty`nCommit trước rồi chạy lại." }

  # tag = commit cuối cùng ĐỘNG VÀO thư mục service (build context) -> cùng source = cùng tag
  $sha = git log -1 --format=%h --abbrev=12 -- "$svc-service"
  $image = "$Registry/$svc-service:$sha"
  $valuesImage = "helm-values/$svc-image.yaml"
  $valuesArgs = @("-f", "helm-values/$svc.yaml", "-f", "helm-values/env-prod.yaml")
  if (Test-Path "helm-values/$svc-prod.yaml") { $valuesArgs += @("-f", "helm-values/$svc-prod.yaml") }
  $valuesArgs += @("-f", $valuesImage)
  Write-Host "image: $image"

  Invoke-Stage "1/6 test" {
    Push-Location "$svc-service"
    try { npm ci --no-audit --no-fund --loglevel=error; npm test } finally { Pop-Location }
  }

  Invoke-Stage "2/6 build" {
    docker build -q -t $image --label "org.opencontainers.image.revision=$sha" "./$svc-service"
  }

  Invoke-Stage "3/6 push" {
    docker push -q $image
  }

  $previous = (helm history $svc -o json | ConvertFrom-Json | Where-Object status -eq "deployed").revision
  Invoke-Stage "4/6 deploy" {
    @"
# TẠO BỞI ci/pipeline.ps1 - KHÔNG sửa tay. Image đang chạy ở prod cho $svc.
image:
  repository: $Registry/$svc-service
  tag: "$sha"
"@ | Set-Content -Encoding utf8NoBOM $valuesImage
    try {
      # --rollback-on-failure: Pod mới không Ready trong $Timeout -> Helm tự rollback về revision trước
      helm upgrade --install $svc charts/grab-service @valuesArgs --rollback-on-failure --wait --timeout $Timeout
    } catch {
      Restore-ImageValues $valuesImage
      throw "deploy thất bại -> Helm đã tự rollback về revision $previous. $_"
    }
    $running = kubectl get pods -l "app=$svc" -o jsonpath="{range .items[*]}{.spec.containers[0].image}{'\n'}{end}" | Sort-Object -Unique
    Write-Host "    Pod đang chạy image: $($running -join ', ')"
  }

  Invoke-Stage "5/6 smoke test" {
    try { Test-Smoke $svc }
    catch {
      Write-Host "    smoke test lỗi -> helm rollback $svc $previous" -ForegroundColor Red
      helm rollback $svc $previous --wait --timeout $Timeout
      Restore-ImageValues $valuesImage
      throw
    }
  }

  Invoke-Stage "6/6 record" {
    # Git là nhật ký deploy: commit file chứa tag đang chạy (tiền đề cho GitOps ở Phase 24)
    git add $valuesImage
    if (git diff --cached --name-only) { git commit -q -m "deploy($svc): $sha"; Write-Host "    commit: $(git log -1 --format='%h %s')" }
    else { Write-Host "    $valuesImage không đổi (đã deploy đúng tag này từ trước)" }
  }

  $rev = (helm history $svc -o json | ConvertFrom-Json | Where-Object status -eq "deployed").revision
  Write-Host ("DONE {0}: {1} (helm revision {2}, {3:N0}s)" -f $svc, $image, $rev, $total.Elapsed.TotalSeconds) -ForegroundColor Green
}
