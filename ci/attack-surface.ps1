<#
Incident 7 - "kẻ tấn công có shell trong Pod <app>": từ bên trong Pod thử mọi đường đi + credential.
  ./ci/attack-surface.ps1 -App user
Chỉ ĐỌC/KẾT NỐI thử (nc -z, wget đầu tiên), không ghi gì. In ma trận OPEN/BLOCKED.
#>
param([string]$App = "user")
$PSNativeCommandUseErrorActionPreference = $false
$pod = kubectl get pods -l "app=$App" -o jsonpath='{.items[0].metadata.name}'
"Pod: $pod"
function Try-Tcp($label, $hostname, $port) {
  kubectl exec $pod -- nc -z -w 3 $hostname $port 2>&1 | Out-Null
  "  {0,-8} {1}" -f $(if ($LASTEXITCODE -eq 0) { "OPEN" } else { "BLOCKED" }), $label
}
"--- mạng (TCP connect từ trong Pod):"
Try-Tcp "postgres:5432           (DB - mục tiêu chính)" postgres 5432
Try-Tcp "payment-service:80      (gọi thẳng payment)" payment-service 80
Try-Tcp "notification-service:80" notification-service 80
Try-Tcp "booking-service:80" booking-service 80
Try-Tcp "redis:6379              (đường hợp lệ của user)" redis 6379
Try-Tcp "kubernetes API 10.96.0.1:443" 10.96.0.1 443
Try-Tcp "Internet 1.1.1.1:443    (tải tool / gửi dữ liệu ra ngoài)" 1.1.1.1 443
Try-Tcp "argocd-server.argocd:80 (namespace khác)" argocd-server.argocd 80
Try-Tcp "grafana.monitoring:80   (namespace khác)" monitoring-grafana.monitoring 80
"--- DNS:"
$dns = kubectl exec $pod -- nslookup postgres 2>&1 | Select-String "Address" | Select-Object -Last 1
"  {0,-8} nslookup postgres -> {1}" -f $(if ($dns) { "OPEN" } else { "BLOCKED" }), "$dns".Trim()
"--- credential trong Pod:"
$envNames = (kubectl exec $pod -- env 2>&1) | ? { $_ -match '^(DB_|PG|POSTGRES|.*PASSWORD|.*SECRET|.*TOKEN)' } | % { ($_ -split '=')[0] }
"  env nhạy cảm: " + $(if ($envNames) { $envNames -join ', ' } else { "(không có)" })
kubectl exec $pod -- ls /var/run/secrets/kubernetes.io/serviceaccount/token 2>&1 | Out-Null
$hasToken = $LASTEXITCODE -eq 0
"  ServiceAccount token mount: " + $(if ($hasToken) { "CÓ" } else { "không" })
if ($hasToken) {
  $code = kubectl exec $pod -- sh -c 'wget -q -S -O /dev/null --no-check-certificate --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://10.96.0.1/api/v1/namespaces/default/secrets 2>&1 | grep "HTTP/" | tail -1' 2>&1
  "  dùng token đọc Secret qua API: " + ("$code".Trim() -replace '^$', '(không kết nối được API)')
}
$sa = kubectl get pod $pod -o jsonpath='{.spec.serviceAccountName}'
"  RBAC của SA '$sa': list secrets = $(kubectl auth can-i list secrets --as=system:serviceaccount:default:$sa), get pods = $(kubectl auth can-i get pods --as=system:serviceaccount:default:$sa)"
$global:LASTEXITCODE = 0   # `kubectl auth can-i` trả exit 1 khi câu trả lời là "no" - đó là kết quả mong muốn, không phải lỗi
