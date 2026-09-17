# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Uploads the A18.2 protected board runner onto the A18.2 tree.
# Does not program and does not run execute.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$Build = "/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a18_2_buildonly"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }

$pairs = @(
    @("scripts\run_stage2n_a18_2_protected_board_v1.sh", "scripts/run_stage2n_a18_2_protected_board_v1.sh"),
    @("scripts\check\check_stage2n_a18_2_host_elf_identity_v1.py", "scripts/check/check_stage2n_a18_2_host_elf_identity_v1.py"),
    @("scripts\check\check_stage2n_a18_2_board_prepare_v1.py", "scripts/check/check_stage2n_a18_2_board_prepare_v1.py")
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
test -f '$Build/scripts/run_stage2n_a18_2_protected_board_v1.sh'
chmod +x '$Build/scripts/run_stage2n_a18_2_protected_board_v1.sh'
sed -i 's/\r$//' \
  '$Build/scripts/run_stage2n_a18_2_protected_board_v1.sh' \
  '$Build/scripts/check/check_stage2n_a18_2_host_elf_identity_v1.py' \
  '$Build/scripts/check/check_stage2n_a18_2_board_prepare_v1.py'
echo A18_2_PROTECTED_RUNNER=UPLOADED
"@
ssh -i $Id -o IdentitiesOnly=yes $Remote $RemoteCmd
if ($LASTEXITCODE -ne 0) { throw "remote chmod failed" }

Write-Host "DONE"
Write-Host "On Linux run: bash scripts/run_stage2n_a18_2_protected_board_v1.sh prepare"
Write-Host "Do not run execute unless you authorize replacing the A16 xclbin."
