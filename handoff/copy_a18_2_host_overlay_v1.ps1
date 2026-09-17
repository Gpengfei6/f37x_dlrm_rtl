# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Prompt must look like: PS D:\FpgaWork\f37x_dlrm_rtl>
# If you see [chaosuan@localhost ...]$ you are still on Linux. Stop.
#
# Uploads and extracts the A18.2 Host overlay onto the A18.2 buildonly tree.
# Does not compile the Host, does not program, does not run the Host.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$Base = "/home/chaosuan/gpf/gpf_f37x_dlrm"
$Build = "$Base/f37x_dlrm_rtl_stage2n_a18_2_buildonly"
$ZipName = "stage2n_a18_2_host_overlay_v1.zip"
$Zip = Join-Path $Root "handoff\$ZipName"
$Expect = "d76248a1d8b020d7d81580f1a06a8aa73f3230e071c6215503d77efd2a8c6118"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }
if (-not (Test-Path $Zip)) { throw "missing overlay zip: $Zip" }
$Actual = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower()
if ($Actual -ne $Expect) { throw "local overlay zip hash mismatch: $Actual" }

Write-Host "1) upload overlay zip"
scp -i $Id -o IdentitiesOnly=yes $Zip "${Remote}:${Base}/${ZipName}"
if ($LASTEXITCODE -ne 0) { throw "upload failed" }

Write-Host "2) extract onto the A18.2 tree only"
$RemoteCmd = @"
set -euo pipefail
test -d '$Build'
test -f '$Build/scripts/run_stage2n_a18_2_build_v1.py'
test ! -f '$Build/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv'
echo $Expect  '$Base/$ZipName' | sha256sum -c -
unzip -o '$Base/$ZipName' -d '$Build'
test -s '$Build/scripts/build_stage2n_a18_2_host_v1.sh'
test -s '$Build/host/stage2n_a18_2_four_bo_host_v1.cpp'
chmod +x '$Build/scripts/build_stage2n_a18_2_host_v1.sh'
echo A18_2_HOST_OVERLAY=PASS
echo BUILD=$Build
"@
ssh -i $Id -o IdentitiesOnly=yes $Remote $RemoteCmd
if ($LASTEXITCODE -ne 0) { throw "remote overlay extract failed" }

Write-Host "DONE"
Write-Host "Now go to the Linux window and compile the Host only. Do not program."
