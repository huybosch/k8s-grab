<#
Backup Postgres ra NGOÀI cluster + restore thử (15/11/2026).
CronJob pg-backup ghi vào PVC trong cluster -> xoá cluster là mất. Script này:
  1. (tuỳ chọn -Now) chạy backup ngay: kubectl create job --from=cronjob/pg-backup
  2. mở Pod tạm gắn PVC pg-backup, copy bản .dump mới nhất về $Dest
  3. restore thử vào DB tạm "restore_check" trong postgres-0, so số dòng payments với DB thật, xoá DB tạm
     (backup chưa từng restore thử = chưa chắc có backup)

  ./ci/pg-backup-pull.ps1            # lấy bản mới nhất + restore thử
  ./ci/pg-backup-pull.ps1 -Now       # backup ngay rồi lấy
#>
param(
  [switch]$Now,
  [string]$Dest = "$env:USERPROFILE\backups\grab-mini"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
New-Item -ItemType Directory -Force $Dest | Out-Null

if ($Now) {
  $job = "pg-backup-manual-$(Get-Date -Format 'yyyyMMddHHmmss')"
  kubectl create job $job --from=cronjob/pg-backup | Out-Null
  kubectl wait --for=condition=complete "job/$job" --timeout=300s | Out-Null
  kubectl logs "job/$job" | Select-Object -First 1 | ForEach-Object { "  $_" }
}

# Pod tạm đọc PVC (local-path: PVC gắn với 1 node -> scheduler tự đặt Pod lên đúng node)
$pod = "pg-backup-reader"
$spec = @{ spec = @{ automountServiceAccountToken = $false; containers = @(@{ name = "r"; image = "postgres:16-alpine"; command = @("sleep", "300")
        volumeMounts = @(@{ name = "b"; mountPath = "/backup" }) }); volumes = @(@{ name = "b"; persistentVolumeClaim = @{ claimName = "pg-backup" } }) } } | ConvertTo-Json -Depth 8 -Compress
kubectl run $pod --restart=Never --image postgres:16-alpine --overrides $spec | Out-Null
try {
  kubectl wait --for=condition=ready "pod/$pod" --timeout=120s | Out-Null
  $latest = kubectl exec $pod -- sh -c 'ls -1t /backup/*.dump | head -1'
  if (-not $latest) { throw "PVC pg-backup chưa có bản .dump nào (chạy với -Now)" }
  $name = Split-Path $latest -Leaf
  # kubectl cp hiểu "C:\..." là "<pod C>:<path>" -> cd vào thư mục đích, copy bằng tên tương đối
  Push-Location $Dest; try { kubectl cp "default/${pod}:$latest" $name | Out-Null } finally { Pop-Location }
  $local = Join-Path $Dest $name
  "copy: $local ($([math]::Round((Get-Item $local).Length / 1KB)) KB)"
} finally { kubectl delete pod $pod --wait=false | Out-Null }

# restore thử
Push-Location $Dest; try { kubectl cp $name "default/postgres-0:/tmp/restore_check.dump" | Out-Null } finally { Pop-Location }
$sql = 'DROP DATABASE IF EXISTS restore_check; CREATE DATABASE restore_check;'
$sql | kubectl exec -i postgres-0 -- psql -U postgres -q -v ON_ERROR_STOP=1 | Out-Null
kubectl exec postgres-0 -- pg_restore -U postgres -d restore_check --no-owner /tmp/restore_check.dump
$restored = kubectl exec postgres-0 -- psql -U postgres -d restore_check -tAc "select count(*) from payments"
$live = kubectl exec postgres-0 -- sh -c 'psql -U postgres -d "$POSTGRES_DB" -tAc "select count(*) from payments"'
'DROP DATABASE restore_check;' | kubectl exec -i postgres-0 -- psql -U postgres -q | Out-Null
kubectl exec postgres-0 -- rm -f /tmp/restore_check.dump
"restore thử: payments trong bản backup = $restored, DB đang chạy = $live (chênh = số payment mới từ lúc backup)"
if ([int]$restored -le 0) { throw "restore thử ra 0 dòng - backup có vấn đề" }
