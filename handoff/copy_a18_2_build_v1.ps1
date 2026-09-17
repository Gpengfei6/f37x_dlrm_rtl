# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Prompt must look like: PS D:\FpgaWork\f37x_dlrm_rtl>
# If you see [chaosuan@localhost ...]$ you are still on Linux. Stop.
#
# This only uploads and extracts the A18.2 XO source tree.
# It does not run check, xo, v++, or program a card.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$Base = "/home/chaosuan/gpf/gpf_f37x_dlrm"
$Build = "$Base/f37x_dlrm_rtl_stage2n_a18_2_buildonly"
$ZipName = "stage2n_a18_2_build_v1.zip"
$Zip = Join-Path $Root "handoff\$ZipName"
$Expect = "54b2418c857dba4664b22fbea01a11837dadc2293f8bd843aa5ce6cd3b4b3f0e"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }
if (-not (Test-Path $Zip)) { throw "missing build zip: $Zip" }

$Actual = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower()
if ($Actual -ne $Expect) { throw "local zip hash mismatch: $Actual" }

Write-Host "1) upload zip"
scp -i $Id -o IdentitiesOnly=yes $Zip "${Remote}:${Base}/${ZipName}"
if ($LASTEXITCODE -ne 0) { throw "upload failed" }

Write-Host "2) extract into a new empty directory (refuses A17.6 overlay)"
$RemoteCmd = @"
set -euo pipefail
test -f '$Base/$ZipName'
echo $Expect  '$Base/$ZipName' | sha256sum -c -
test ! -e '$Build'
mkdir '$Build'
unzip -o '$Base/$ZipName' -d '$Build'
test -f '$Build/scripts/run_stage2n_a18_2_build_v1.py'
test ! -f '$Build/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv'
echo A18_2_EXTRACT=PASS
echo BUILD=$Build
"@
ssh -i $Id -o IdentitiesOnly=yes $Remote $RemoteCmd
if ($LASTEXITCODE -ne 0) { throw "remote extract failed" }

Write-Host "DONE"
Write-Host "Extract is on the server at $Build"
Write-Host "Now go to the Linux window and run check, then xo."
