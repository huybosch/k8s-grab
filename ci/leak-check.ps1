<#
Kiểm tra rò rỉ bộ nhớ (15/11/2026): bắn tải liên tục vào các endpoint, đo heap Node.js + working set container
TRƯỚC / CUỐI tải / SAU khi nghỉ. Leak = bộ nhớ tăng theo số request và KHÔNG quay về khi hết tải.

  ./ci/leak-check.ps1                    # 240s tải + 90s nghỉ
  ./ci/leak-check.ps1 -LoadSec 600       # tải lâu hơn: leak chậm mới lộ

Đọc kết quả: heap "sau nghỉ" ~ "trước" (chênh vài MiB) = không leak. Heap tăng đều theo thời gian tải = nghi leak
(so sánh Incident 6: LEAK_KB_PER_REQUEST=200 -> working set 18 -> 226 MiB trong 77s).
#>
param([int]$LoadSec = 240, [int]$RestSec = 90)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$P = "/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy"

function Q([string]$promql, [double]$Div = 1MB) {   # mặc định đổi byte -> MiB; số đếm thì -Div 1
  $r = kubectl get --raw "$P/api/v1/query?query=$([uri]::EscapeDataString($promql))" | ConvertFrom-Json
  $h = @{}; foreach ($x in $r.data.result) { $h[$x.metric.job ?? $x.metric.container] = [math]::Round([double]$x.value[1] / $Div, 1) }; $h
}
function Snap([string]$label) {
  $heap = Q 'max by (job) (nodejs_heap_size_used_bytes{job=~"(booking|payment|user|driver|notification)-service"})'
  $ws = Q 'max by (container) (container_memory_working_set_bytes{namespace="default",container=~"booking|payment|user|driver|notification"})'
  $req = Q 'sum by (job) (http_requests_total{job=~"(booking|payment|user|driver|notification)-service"})' -Div 1
  [pscustomobject]@{ label = $label; heap = $heap; ws = $ws; req = $req }
}

$s0 = Snap "trước"
Write-Host "tải ${LoadSec}s: POST /booking, GET /users, GET /drivers, POST /drivers/driver-2/accept (mỗi endpoint 4 luồng, nghỉ 20ms)"
$targets = @(@("http://127.0.0.1/booking", "POST"), @("http://127.0.0.1/users", "GET"), @("http://127.0.0.1/drivers", "GET"), @("http://127.0.0.1/drivers/driver-2/accept", "POST"))
$jobs = foreach ($t in $targets) { Start-Job -ArgumentList "$root\ci\load.js", $t[0], $t[1], $LoadSec { param($js, $u, $m, $s) node $js $u 4 $s $m 20 | Select-Object -Last 1 } }
$mid = $null
Start-Sleep ([int]($LoadSec / 2)); $mid = Snap "giữa tải"
$jobs | Wait-Job | Out-Null; $s1 = Snap "cuối tải"
$jobs | ForEach-Object { "  " + (Receive-Job $_) }; $jobs | Remove-Job
Write-Host "nghỉ ${RestSec}s cho GC..."; Start-Sleep $RestSec; $s2 = Snap "sau nghỉ"

"{0,-13} {1,9} {2,9} {3,9} {4,9} | {5,8} {6,8} {7,8} | {8,10}" -f "service", "heap0", "heapGiữa", "heapCuối", "heapNghỉ", "ws0", "wsCuối", "wsNghỉ", "request"
foreach ($svc in "booking", "payment", "user", "driver", "notification") {
  $j = "$svc-service"
  # tính $n RIÊNG: viết "... -f a, b, (x) * 2" thì PowerShell nhân CẢ CHUỖI kết quả (lặp chuỗi) - từng in ra 64MB
  $n = $s2.req[$j] - $s0.req[$j]
  "{0,-13} {1,8}M {2,8}M {3,8}M {4,8}M | {5,7}M {6,7}M {7,7}M | {8,10:N0}" -f $svc, $s0.heap[$j], $mid.heap[$j], $s1.heap[$j], $s2.heap[$j], $s0.ws[$svc], $s1.ws[$svc], $s2.ws[$svc], $n
}
