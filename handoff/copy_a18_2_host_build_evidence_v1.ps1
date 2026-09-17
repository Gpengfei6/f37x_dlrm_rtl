# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Copies A18.2 Host compile records only. Does not program.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$RemoteDir = "/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a18_2_buildonly/build/stage2n_a18_2/host_v1"
$LocalDir = Join-Path $Root "docs\evidence\stage2n_a18_2\host_v1"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }
if (Test-Path $LocalDir) { throw "refusing to overwrite $LocalDir" }
New-Item -ItemType Directory -Force $LocalDir | Out-Null

$names = @(
    "host_build_status.txt",
    "host_build.log",
    "compiler_version.log",
    "xrt_version.log"
)
foreach ($name in $names) {
    $dest = Join-Path $LocalDir $name
    Write-Host "copy $name"
    scp -i $Id -o IdentitiesOnly=yes "${Remote}:${RemoteDir}/${name}" $dest
    if ($LASTEXITCODE -ne 0) { throw "copy failed: $name" }
}

Write-Host "DONE"
Write-Host "LOCAL=$LocalDir"
Write-Host "Do not program. Do not run the Host."
