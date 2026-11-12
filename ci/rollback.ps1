<#
Production Simulation (Incident 2) - rollback GitOps 1 lệnh: git revert commit gần nhất đụng tới service + push + refresh Argo CD + đợi.

  ./ci/rollback.ps1 -Service booking              # revert commit gần nhất đổi helm-values/booking*.yaml (code/config/tag)
  ./ci/rollback.ps1 -Service booking -Commit abc123

Không dùng helm rollback / kubectl rollout undo: Argo CD selfHeal đè lại ngay (Scenario 24).
Commit gần nhất đụng env-prod.yaml / chart chung KHÔNG tự chọn (ảnh hưởng mọi service) -> truyền -Commit.
#>
param(
  [Parameter(Mandatory)][ValidateSet("booking", "payment", "user", "driver", "notification")][string]$Service,
  [string]$Commit,
  [int]$TimeoutSec = 180
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-Location (Split-Path $PSScriptRoot -Parent)
$sw = [Diagnostics.Stopwatch]::StartNew()

git fetch -q origin main
if ([int](git rev-list --count HEAD..origin/main) -gt 0) { git pull -q --rebase origin main }
if (-not $Commit) { $Commit = git log -1 --format=%H -- "helm-values/$Service.yaml" "helm-values/$Service-*.yaml" }
"revert: $(git log -1 --format='%h %s (%cr)' $Commit)"
git revert --no-edit $Commit | Out-Null
git push -q origin HEAD:main
$rev = git rev-parse HEAD
kubectl -n argocd annotate application $Service argocd.argoproj.io/refresh=normal --overwrite | Out-Null

$deadline = (Get-Date).AddSeconds($TimeoutSec)
do {
  Start-Sleep -Seconds 2
  $s = (kubectl -n argocd get application $Service -o json | ConvertFrom-Json).status
} until (($s.sync.revision -eq $rev -and $s.sync.status -eq "Synced" -and $s.health.status -eq "Healthy") -or (Get-Date) -gt $deadline)
if ((Get-Date) -gt $deadline) { throw "Argo CD chưa sync $Service về $($rev.Substring(0,7)) sau ${TimeoutSec}s" }
kubectl rollout status "deployment/$Service" --timeout "${TimeoutSec}s" | Out-Null
"rolled back: $(git log -1 --format='%h %s') - {0:N0}s" -f $sw.Elapsed.TotalSeconds
