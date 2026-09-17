# Run this in a NEW Windows PowerShell. Do NOT paste it into the SSH session.
# Prompt must look like: PS D:\FpgaWork\f37x_dlrm_rtl>
# If you see [chaosuan@localhost ...]$ you are still on Linux. Stop.
#
# Uploads A18.3 Host sources onto the existing A18.2 buildonly tree.
# Does not compile, program, or run the Host. Does not replace A18.2 Host.

$ErrorActionPreference = "Stop"
$Id = Join-Path $env:USERPROFILE ".ssh\id_fpga"
$Root = "D:\FpgaWork\f37x_dlrm_rtl"
$Remote = "chaosuan@172.17.8.254"
$Base = "/home/chaosuan/gpf/gpf_f37x_dlrm"
$Build = "$Base/f37x_dlrm_rtl_stage2n_a18_2_buildonly"
$ZipName = "stage2n_a18_3_host_overlay_v1.zip"
$Zip = Join-Path $Root "handoff\$ZipName"
$Expect = "7b80a91d1dfd96003107032f91a83ec3099dbf48ad8be2aa5348364f83a7fe73"
$A18_2_HostSha = "0a00e8ab7eab7be90b53905b3e4114921e365e681ecc0aef4a73e9f4565c521f"

if (-not (Test-Path $Id)) { throw "missing SSH key: $Id" }
if (-not (Test-Path $Zip)) { throw "missing overlay zip: $Zip" }
$Actual = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower()
if ($Actual -ne $Expect) { throw "local overlay zip hash mismatch: $Actual" }

Write-Host "1) upload A18.3 Host overlay zip"
scp -i $Id -o IdentitiesOnly=yes $Zip "${Remote}:${Base}/${ZipName}"
if ($LASTEXITCODE -ne 0) { throw "upload failed" }

Write-Host "2) extract new files only; keep A18.2 Host"
$RemoteCmd = @"
set -euo pipefail
test -d '$Build'
test -s '$Build/host/stage2n_a18_2_four_bo_host_v1.cpp'
test -s '$Build/scripts/build_stage2n_a18_2_host_v1.sh'
echo $Expect  '$Base/$ZipName' | sha256sum -c -
unzip -l '$Base/$ZipName' | grep -F 'stage2n_a18_2_four_bo_host_v1.cpp' && {
  echo 'overlay must not contain the A18.2 Host'; exit 3
} || true
unzip -o '$Base/$ZipName' -d '$Build'
test -s '$Build/host/stage2n_a18_3_index_tuple_host_v1.cpp'
test -s '$Build/scripts/build_stage2n_a18_3_host_v1.sh'
sed -i 's/\r$//' '$Build/scripts/build_stage2n_a18_3_host_v1.sh'
chmod +x '$Build/scripts/build_stage2n_a18_3_host_v1.sh'
echo $A18_2_HostSha  '$Build/host/stage2n_a18_2_four_bo_host_v1.cpp' | sha256sum -c -
echo A18_3_HOST_OVERLAY=PASS
echo BUILD=$Build
echo NEXT='bash scripts/build_stage2n_a18_3_host_v1.sh'
"@
ssh -i $Id -o IdentitiesOnly=yes $Remote $RemoteCmd
if ($LASTEXITCODE -ne 0) { throw "remote overlay extract failed" }

Write-Host "DONE"
Write-Host "Now go to the Linux window and compile the A18.3 Host only."
Write-Host "Do not program. Do not run the Host. PERFORMANCE=NOT_CLAIMED"
