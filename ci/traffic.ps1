<#
Production Simulation - traffic giả lập người dùng qua Ingress, đo lỗi theo endpoint + thời điểm
  ./ci/traffic.ps1 -Seconds 120                         # in tổng kết khi xong
  Start-Job { & D:\...\ci\traffic.ps1 -Seconds 120 }    # chạy nền trong lúc gây sự cố
Mỗi vòng gọi lần lượt các endpoint; lỗi = exception (timeout/kết nối) hoặc HTTP >= 500.
#>
param(
  [int]$Seconds = 60,
  [int]$TimeoutSec = 5,
  [int]$PauseMs = 100,
  [string[]]$Endpoint = @("POST /booking", "GET /users", "GET /drivers", "POST /payment", "POST /drivers/driver-2/accept")
)
$base = "http://127.0.0.1"
$stats = [ordered]@{}; foreach ($e in $Endpoint) { $stats[$e] = @{ ok = 0; fail = 0; slow = 0 } }
$errors = [Collections.Generic.List[string]]::new()
$t0 = Get-Date; $end = $t0.AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
  foreach ($e in $Endpoint) {
    $method, $path = $e -split ' ', 2
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
      $null = Invoke-WebRequest "$base$path" -Method $method -Body '{}' -ContentType "application/json" -UseBasicParsing -TimeoutSec $TimeoutSec
      $stats[$e].ok++
      if ($sw.ElapsedMilliseconds -gt 1000) { $stats[$e].slow++ }
    } catch {
      $stats[$e].fail++
      $code = $_.Exception.Response.StatusCode.value__
      $msg = if ($code) { "HTTP $code" } else { ($_.Exception.Message -split '\.')[0] }
      $errors.Add(("+{0,5:N1}s {1,-30} {2} ({3}ms)" -f ((Get-Date) - $t0).TotalSeconds, $e, $msg, $sw.ElapsedMilliseconds))
    }
  }
  Start-Sleep -Milliseconds $PauseMs
}
$total = 0; $fail = 0
foreach ($e in $Endpoint) { $total += $stats[$e].ok + $stats[$e].fail; $fail += $stats[$e].fail }
"TRAFFIC {0}s: ok={1} fail={2}" -f $Seconds, ($total - $fail), $fail
foreach ($e in $Endpoint) { "  {0,-30} ok={1,-5} fail={2,-4} slow(>1s)={3}" -f $e, $stats[$e].ok, $stats[$e].fail, $stats[$e].slow }
if ($errors.Count) { "  lỗi (thời điểm tính từ lúc bắt đầu):"; $errors | Select-Object -First 25 | ForEach-Object { "    $_" }; if ($errors.Count -gt 25) { "    ... +$($errors.Count - 25) lỗi nữa" } }
