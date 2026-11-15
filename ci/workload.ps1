<#
Hàm dùng chung (dot-source: . "$PSScriptRoot/workload.ps1") - service có thể là Deployment HOẶC Argo Rollout (booking từ 15/11).
  Get-WorkloadKind booking      -> "rollout" | "deployment"
  Get-WorkloadImage booking     -> image trong spec (bản Git muốn chạy)
  Wait-Workload booking 300     -> đợi rollout xong; Rollout bị ABORT (analysis thất bại) -> throw
#>
function Get-WorkloadKind([string]$Name) {
  if (kubectl get rollouts.argoproj.io $Name -n default --ignore-not-found -o name 2>$null) { "rollout" } else { "deployment" }
}

function Get-WorkloadImage([string]$Name) {
  $k = Get-WorkloadKind $Name
  $kind = if ($k -eq "rollout") { "rollouts.argoproj.io" } else { "deployment" }
  kubectl get $kind $Name -n default -o jsonpath='{.spec.template.spec.containers[0].image}'
}

# Rollout: xong = phase Healthy + stableRS = hash Pod hiện tại (canary đã promote 100%).
# phase Degraded / status.abort = analysis thất bại -> controller đã đưa về stable -> báo lỗi cho người gọi.
function Wait-Workload([string]$Name, [int]$TimeoutSec = 300) {
  if ((Get-WorkloadKind $Name) -eq "deployment") {
    kubectl rollout status "deployment/$Name" -n default --timeout "${TimeoutSec}s" | Out-Null
    return
  }
  $deadline = (Get-Date).AddSeconds($TimeoutSec); $last = ""
  while ((Get-Date) -lt $deadline) {
    $s = (kubectl get rollouts.argoproj.io $Name -n default -o json | ConvertFrom-Json).status
    $now = "phase={0} step={1} pod mới={2}/{3}" -f $s.phase, $s.currentStepIndex, $s.updatedReplicas, $s.replicas   # canary không mesh: tỉ lệ traffic = tỉ lệ Pod
    if ($now -ne $last) { Write-Host "    rollout $Name : $now $($s.message)"; $last = $now }
    if ($s.abort -or $s.phase -eq "Degraded") { throw "Rollout $Name bị ABORT: $($s.message)" }
    if ($s.phase -eq "Healthy" -and $s.stableRS -eq $s.currentPodHash) { return }
    Start-Sleep -Seconds 2
  }
  throw "Rollout $Name chưa xong sau ${TimeoutSec}s"
}
