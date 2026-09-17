# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Uploads the A18.3 extra-run runner. Does not program, reset, or execute.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$Build = "/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a18_2_buildonly"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }

$pairs = @(
    @("scripts\run_stage2n_a18_3_extra_run_v1.sh", "scripts/run_stage2n_a18_3_extra_run_v1.sh"),
    @("scripts\check\check_stage2n_a18_3_extra_run_v1.py", "scripts/check/check_stage2n_a18_3_extra_run_v1.py")
)
foreach ($pair in $pairs) {
    $src = Join-Path $Root $pair[0]
    if (-not (Test-Path $src)) { throw "missing $src" }
    Write-Host "upload $($pair[1])"
    scp -i $Id -o IdentitiesOnly=yes $src "${Remote}:${Build}/$($pair[1])"
    if ($LASTEXITCODE -ne 0) { throw "upload failed: $($pair[1])" }
}

$RemoteCmd = @"
set -euo pipefail
test -f '$Build/scripts/run_stage2n_a18_3_extra_run_v1.sh'
chmod +x '$Build/scripts/run_stage2n_a18_3_extra_run_v1.sh'
sed -i 's/\r$//' \
  '$Build/scripts/run_stage2n_a18_3_extra_run_v1.sh' \
  '$Build/scripts/check/check_stage2n_a18_3_extra_run_v1.py'
echo A18_3_EXTRA_RUN_RUNNER=UPLOADED
"@
ssh -i $Id -o IdentitiesOnly=yes $Remote $RemoteCmd
if ($LASTEXITCODE -ne 0) { throw "remote chmod failed" }

Write-Host "DONE"
Write-Host "On Linux: bash scripts/run_stage2n_a18_3_extra_run_v1.sh prepare"
Write-Host "Then extra-run only with A18_3_EXTRA_RUN_AUTHORIZED=yes A18_3_CONFIRM=yes"
Write-Host "Do not program. Do not reset."
