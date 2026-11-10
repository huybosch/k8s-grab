<#
Phase 23 - dọn "field manager" cũ sau khi adopt resource vào Helm (chạy 1 LẦN cho mỗi release)

Vấn đề: object tạo bằng `kubectl apply` (client-side) rồi được Helm 4 adopt bằng --take-ownership vẫn còn
manager cũ `kubectl-client-side-apply` đồng sở hữu mọi field. Lần đầu Helm ĐỔI giá trị 1 field (vd. image tag)
-> server-side apply báo conflict -> upgrade thất bại.
Cách sửa: xoá các manager cũ khỏi metadata.managedFields + xoá annotation last-applied-configuration.
Field vẫn giữ nguyên giá trị, chỉ đổi "ai sở hữu".

  ./ci/migrate-field-managers.ps1 -Release payment,user,booking,grab-platform -DryRun
  ./ci/migrate-field-managers.ps1 -Release payment,user,booking,grab-platform
#>
param(
  [Parameter(Mandatory)][string[]]$Release,
  [string[]]$LegacyManagers = @("kubectl-client-side-apply", "kubectl-patch", "kubectl-autoscale"),
  [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$legacyJson = ConvertTo-Json -Compress @($LegacyManagers)
$tmp = New-TemporaryFile

foreach ($r in $Release) {
  $objects = helm get manifest $r | kubectl get -f - -o json --show-managed-fields | jq -c '(.items // [.])[]'
  foreach ($o in $objects) {
    $ref = $o | jq -r '"\(.kind)/\(.metadata.name) -n \(.metadata.namespace)"'
    $before = $o | jq -r '[.metadata.managedFields[].manager] | unique | join(",")'
    # merge patch: managedFields = danh sách đã lọc (thay toàn bộ list), annotation last-applied = null (xoá)
    $o | jq -c --argjson legacy $legacyJson '{metadata: {
          managedFields: [.metadata.managedFields[] | select(.manager as $m | $legacy | index($m) | not)],
          annotations: {"kubectl.kubernetes.io/last-applied-configuration": null}}}' | Set-Content -Encoding utf8NoBOM $tmp
    $kind, $name = ($o | jq -r '.kind, .metadata.name')
    $ns = $o | jq -r '.metadata.namespace'
    $extra = @(); if ($DryRun) { $extra = @("--dry-run=server") }
    kubectl patch $kind $name -n $ns --type=merge --patch-file $tmp @extra -o json --show-managed-fields |
      jq -r --arg ref $ref --arg before $before '"\($ref): \($before)  ->  " + ([.metadata.managedFields[].manager] | unique | join(","))'
  }
}
Remove-Item $tmp
