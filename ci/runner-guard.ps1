<#
Phase 23 (bổ sung) - hook chạy TRƯỚC mỗi job trên self-hosted runner (ACTIONS_RUNNER_HOOK_JOB_STARTED).
Exit != 0 -> runner huỷ job, không chạy bước nào.

Vì sao cần (repo public):
  PR từ fork có thể TỰ THÊM workflow mới với `runs-on: self-hosted` -> chạy code lạ trên máy có docker + kubeconfig.
  Bỏ trigger pull_request trong cd.yaml là KHÔNG đủ (workflow của PR là bản trong nhánh PR, không phải bản trên main).
  Hook này nằm trên máy runner (C:\actions-runner\guard.ps1), PR không sửa được.

Chỉ cho chạy: repo này + workflow cd.yaml + ref main + event push/workflow_dispatch.
  - push lên main: chỉ người có quyền ghi repo làm được
  - workflow_dispatch: cũng chỉ người có quyền ghi
  - pull_request / pull_request_target / bất kỳ workflow nào khác: từ chối

Cài: copy file này vào C:\actions-runner\guard.ps1, thêm vào C:\actions-runner\.env:
  ACTIONS_RUNNER_HOOK_JOB_STARTED=C:\actions-runner\guard.ps1
(Viết tương thích Windows PowerShell 5.1 - runner có thể gọi powershell.exe thay vì pwsh)
#>
$repo     = "huybosch/k8s-grab"
$workflow = "$repo/.github/workflows/cd.yaml@refs/heads/main"
$events   = @("push", "workflow_dispatch")

$e = $env:GITHUB_EVENT_NAME; $r = $env:GITHUB_REPOSITORY; $ref = $env:GITHUB_REF; $wf = $env:GITHUB_WORKFLOW_REF
Write-Host "runner-guard: repo=$r event=$e ref=$ref workflow=$wf actor=$env:GITHUB_ACTOR"

$why = @()
if ($r -ne $repo)          { $why += "repo '$r' != '$repo'" }
if ($events -notcontains $e) { $why += "event '$e' không được phép (chỉ $($events -join ', '))" }
if ($ref -ne "refs/heads/main") { $why += "ref '$ref' != refs/heads/main" }
if ($wf -ne $workflow)     { $why += "workflow '$wf' != '$workflow'" }

if ($why.Count -gt 0) {
  Write-Host "runner-guard: TỪ CHỐI job:"
  $why | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host "runner-guard: OK"
exit 0
