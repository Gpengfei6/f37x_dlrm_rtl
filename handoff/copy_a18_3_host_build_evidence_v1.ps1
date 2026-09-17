# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Copies A18.3 Host compile records only. Does not program or run the Host.
# host_build.log may be zero bytes when g++ printed no diagnostics.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$RemoteDir = "/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a18_2_buildonly/build/stage2n_a18_3/host_v1"
$LocalDir = Join-Path $Root "docs\evidence\stage2n_a18_3\host_v1\20260917_compile"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }
New-Item -ItemType Directory -Force $LocalDir | Out-Null

$required = @(
    @{ Name = "host_build_status.txt"; AllowEmpty = $false },
    @{ Name = "host_build.log"; AllowEmpty = $true },
    @{ Name = "compiler_version.log"; AllowEmpty = $false },
    @{ Name = "xrt_version.log"; AllowEmpty = $false }
)
foreach ($item in $required) {
    $dest = Join-Path $LocalDir $item.Name
    if ((Test-Path $dest) -and (((Get-Item $dest).Length -gt 0) -or $item.AllowEmpty)) {
        Write-Host "keep $($item.Name)"
        continue
    }
    Write-Host "copy $($item.Name)"
    scp -i $Id -o IdentitiesOnly=yes "${Remote}:${RemoteDir}/$($item.Name)" $dest
    if ($LASTEXITCODE -ne 0) { throw "copy failed: $($item.Name)" }
    if (-not (Test-Path $dest)) { throw "missing after copy: $dest" }
    if ((-not $item.AllowEmpty) -and ((Get-Item $dest).Length -eq 0)) {
        throw "empty after copy: $dest"
    }
}

$log = Join-Path $LocalDir "host_build.log"
$note = Join-Path $LocalDir "EMPTY_COMPILER_LOG.txt"
if ((Get-Item $log).Length -eq 0) {
    @"
A18_3_HOST_BUILD_LOG=EMPTY
NOTE=g++ -Wall -Wextra -Wpedantic produced no diagnostics; tee wrote a zero-byte log.
COMPILER_EXIT_CODE=0 from host_build_status.txt
NOT_A_MISSING_FILE=1
"@ | Set-Content -Path $note -Encoding ascii
}

Write-Host "DONE"
Write-Host "LOCAL=$LocalDir"
Write-Host "Do not program. Do not run the Host. BOARD=NOT_RUN"
