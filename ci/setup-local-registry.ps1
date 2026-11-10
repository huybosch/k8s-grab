<#
Phase 23 - local registry cho cluster kind "grab-mini" (chạy lại nhiều lần vẫn an toàn)

  1. container registry:2 ở localhost:5001, nối vào mạng Docker "kind"
  2. trên MỖI node: bật containerd config_path + hosts.toml trỏ localhost:5001 -> http://kind-registry:5000
     (file được docker cp vào /etc/containerd của node - KHÔNG dùng /tmp vì /tmp của node kind là tmpfs, docker cp ghi vào đó sẽ không thấy được; không phải escape dấu nháy qua PowerShell -> docker exec -> sh)
  3. restart containerd LẦN LƯỢT từng node, đợi node Ready (container đang chạy không bị dừng)

  ./ci/setup-local-registry.ps1
#>
param([string]$Cluster = "grab-mini", [string]$Name = "kind-registry", [int]$Port = 5001)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# --- 1. registry ---
if (-not (docker ps -a --filter "name=^$Name$" --format "{{.Names}}")) {
  docker run -d --restart=always -p "127.0.0.1:${Port}:5000" --name $Name registry:2.8.3 | Out-Null
  Write-Host "registry $Name started"
}
$networks = docker inspect $Name --format "{{json .NetworkSettings.Networks}}" | ConvertFrom-Json
if (-not $networks.PSObject.Properties["kind"]) { docker network connect kind $Name; Write-Host "$Name connected to network kind" }

# --- 2 + 3. containerd trên từng node ---
$tmp = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) "kind-registry-$PID")
@"

# Phase 23 - local registry: containerd đọc cấu hình registry trong certs.d
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
"@ | Set-Content -NoNewline -Encoding utf8NoBOM "$tmp/config-patch.toml"
"[host.`"http://${Name}:5000`"]`n" | Set-Content -NoNewline -Encoding utf8NoBOM "$tmp/hosts.toml"

foreach ($node in (kind get nodes --name $Cluster)) {
  docker cp "$tmp/config-patch.toml" "${node}:/etc/containerd/config-patch.toml"
  docker cp "$tmp/hosts.toml" "${node}:/etc/containerd/hosts.toml.new"
  docker exec $node sh -c "grep -q certs.d /etc/containerd/config.toml || cat /etc/containerd/config-patch.toml >> /etc/containerd/config.toml; mkdir -p /etc/containerd/certs.d/localhost:$Port; mv /etc/containerd/hosts.toml.new /etc/containerd/certs.d/localhost:$Port/hosts.toml; rm -f /etc/containerd/config-patch.toml; systemctl restart containerd"
  kubectl wait --for=condition=Ready "node/$node" --timeout=120s | Out-Null
  Write-Host "${node}: containerd $(docker exec $node systemctl is-active containerd), hosts.toml = $(docker exec $node cat /etc/containerd/certs.d/localhost:$Port/hosts.toml)"
}
Remove-Item -Recurse $tmp
Write-Host "registry catalog: $(curl.exe -s http://localhost:${Port}/v2/_catalog)"
