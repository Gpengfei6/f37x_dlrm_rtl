# Run this in a NEW Windows PowerShell after the Linux execute stamp is known.
# Copies A18.3 five-tuple originals. Does not program or reset.
#
# Usage:
#   $env:A18_3_EVIDENCE_STAMP = "YYYYMMDD_HHMMSS"
#   powershell -NoProfile -File handoff\copy_a18_3_function_evidence_v1.ps1

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$Build = "/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a18_2_buildonly"
$Stamp = $env:A18_3_EVIDENCE_STAMP
if ([string]::IsNullOrWhiteSpace($Stamp)) {
    $Stamp = "20260917_202130"
}
$RemoteRun = "$Build/results/stage2n_a18_3/protected_v1/$Stamp"
$LocalDir = Join-Path $Root "docs\evidence\stage2n_a18_3\function_pass_v1\$Stamp"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }
if (Test-Path $LocalDir) { throw "refusing to overwrite $LocalDir" }
New-Item -ItemType Directory -Force $LocalDir | Out-Null

$files = @(
    "host.log",
    "runner.log",
    "pre_device_query.txt",
    "post_host_query.txt",
    "a18_2_mem_map.txt",
    "connectivity.json",
    "mem_topology.json",
    "ip_layout.json",
    "dlrm_f37x_rtl_kernel_stage2n_a18_v1.xclbin.info"
)
foreach ($name in $files) {
    $dest = Join-Path $LocalDir $name
    Write-Host "copy $name"
    scp -i $Id -o IdentitiesOnly=yes "${Remote}:${RemoteRun}/${name}" $dest
    if ($LASTEXITCODE -ne 0) { throw "copy failed: $name" }
    if (-not (Test-Path $dest) -or ((Get-Item $dest).Length -eq 0)) {
        throw "empty or missing after copy: $dest"
    }
}

Write-Host "DONE"
Write-Host "LOCAL=$LocalDir"
Write-Host "Do not extra-run. Do not reset. PERFORMANCE=NOT_CLAIMED"
