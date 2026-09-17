# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Prompt must look like: PS D:\FpgaWork\f37x_dlrm_rtl>
# If you see [chaosuan@localhost ...]$ you are still on Linux. Stop.
#
# Copies A18.2 link review files only. Does not copy the xclbin. Does not program.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$RemoteRun = "/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a18_2_buildonly/runs/a18_2_link_001"
$LocalDir = Join-Path $Root "docs\evidence\stage2n_a18_2\link_001"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }
if (Test-Path $LocalDir) { throw "refusing to overwrite $LocalDir" }
New-Item -ItemType Directory -Force (Join-Path $LocalDir "post_route") | Out-Null

$pairs = @(
    @("status.json", "status.json"),
    @("vivado_version.log", "vivado_version.log"),
    @("vpp_version.log", "vpp_version.log"),
    @("xclbinutil_version.log", "xclbinutil_version.log"),
    @("xclbin.info", "xclbin.info"),
    @("connectivity.json", "connectivity.json"),
    @("mem_topology.json", "mem_topology.json"),
    @("ip_layout.json", "ip_layout.json"),
    @("post_route.log", "post_route.log"),
    @("post_route/post_route_metrics.txt", "post_route\post_route_metrics.txt"),
    @("post_route/post_route_timing_summary.rpt", "post_route\post_route_timing_summary.rpt"),
    @("post_route/post_route_check_timing.rpt", "post_route\post_route_check_timing.rpt"),
    @("post_route/post_route_methodology.rpt", "post_route\post_route_methodology.rpt")
)
foreach ($pair in $pairs) {
    $dest = Join-Path $LocalDir $pair[1]
    Write-Host "copy $($pair[0])"
    scp -i $Id -o IdentitiesOnly=yes "${Remote}:${RemoteRun}/$($pair[0])" $dest
    if ($LASTEXITCODE -ne 0) { throw "copy failed: $($pair[0])" }
    if (-not (Test-Path $dest) -or ((Get-Item $dest).Length -eq 0)) {
        throw "empty or missing after copy: $dest"
    }
}

$Py = "D:\miniforge3\python.exe"
if (-not (Test-Path $Py)) { $Py = "python" }
Write-Host "review"
& $Py (Join-Path $Root "scripts\review_stage2n_a18_2_link_evidence_v1.py") $LocalDir
if ($LASTEXITCODE -ne 0) { throw "local link evidence review failed" }

Write-Host "DONE"
Write-Host "LOCAL=$LocalDir"
Write-Host "Keep the xclbin on the server. Do not program. Do not run the A17 Host."
