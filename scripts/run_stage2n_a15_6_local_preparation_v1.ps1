[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $RepoRoot

$ExpectedBranch = 'work/stage2n-a15-hbm-pipeline-integration'
$ExpectedHead = '14cb37721b918e644c8cae689791628247a00eec'
$ExpectedRtlSha = 'c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1'
$ResultDir = Join-Path $RepoRoot 'results/stage2n_a15_6/local_preparation_v1'
$GeneratedDir = Join-Path $ResultDir 'generated'
$EvidenceDir = Join-Path $RepoRoot 'docs/evidence/stage2n_a15_6/local_preparation_v1'
$Manifest = Join-Path $RepoRoot 'models/stage2n_a15_6/stage2n_a15_6_cases_v1.json'
$Status = Join-Path $ResultDir 'a15_6_local_preparation_v1_status.txt'
New-Item -ItemType Directory -Force -Path $ResultDir, $GeneratedDir, $EvidenceDir | Out-Null

function Invoke-Checked {
    param([string]$Name, [scriptblock]$Action)
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit $LASTEXITCODE" }
}

$branch = (git branch --show-current).Trim()
$head = (git rev-parse HEAD).Trim()
if ($branch -ne $ExpectedBranch) { throw "wrong branch: $branch" }
if ($head -ne $ExpectedHead) { throw "wrong HEAD: $head" }

$rtlSha = (Get-FileHash -Algorithm SHA256 -LiteralPath 'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv').Hash.ToLowerInvariant()
if ($rtlSha -ne $ExpectedRtlSha) { throw 'accepted A15.4 RTL SHA256 changed' }

$pythonFiles = @(
    'python/build_stage2n_a15_6_board_assets_v1.py',
    'scripts/validate_stage2n_a15_6_sources_v1.py',
    'scripts/assemble_stage2n_a15_6_evidence_v1.py',
    'scripts/validate_stage2n_a15_6_evidence_v1.py'
)
foreach ($file in $pythonFiles) {
    Invoke-Checked "Python syntax $file" {
        python -c "import ast,pathlib; ast.parse(pathlib.Path(r'$file').read_text(encoding='utf-8')); print('PYTHON_SYNTAX_PASS=$file')"
    }
}

$generationLog = Join-Path $ResultDir 'golden_generation.log'
& python 'python/build_stage2n_a15_6_board_assets_v1.py' `
    --source-package 'models/stage2m/stage2m_trained_hybrid_dlrm.f37xhd' `
    --output-dir $GeneratedDir `
    --status (Join-Path $ResultDir 'golden_generation_status.txt') `
    2>&1 | Tee-Object -FilePath $generationLog
if ($LASTEXITCODE -ne 0) { throw 'golden generation failed' }

$trackedAssetDir = Join-Path $RepoRoot 'models/stage2n_a15_6'
$assetNames = @(
    'stage2n_a15_6_model_v1.bin',
    'stage2n_a15_6_cases_v1.json',
    'stage2n_a15_6_case0_baseline_table_v1.bin',
    'stage2n_a15_6_case1_slot0_sensitivity_table_v1.bin',
    'stage2n_a15_6_case2_slot1_sensitivity_table_v1.bin',
    'stage2n_a15_6_case3_slot2_sensitivity_table_v1.bin',
    'stage2n_a15_6_case4_slot3_sensitivity_table_v1.bin'
)
foreach ($name in $assetNames) {
    $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $trackedAssetDir $name)).Hash
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $GeneratedDir $name)).Hash
    if ($actual -ne $expected) { throw "deterministic asset mismatch: $name" }
}

$sourceLog = Join-Path $ResultDir 'source_validation.log'
& python 'scripts/validate_stage2n_a15_6_sources_v1.py' --repo $RepoRoot 2>&1 |
    Tee-Object -FilePath $sourceLog
if ($LASTEXITCODE -ne 0) { throw 'source validation failed' }

$validatorLog = Join-Path $ResultDir 'validator_self_test.log'
& python 'scripts/validate_stage2n_a15_6_evidence_v1.py' --manifest $Manifest --self-test 2>&1 |
    Tee-Object -FilePath $validatorLog
if ($LASTEXITCODE -ne 0) { throw 'evidence validator self-test failed' }

$fixtureHostLog = Join-Path $ResultDir 'assembler_fixture_host.log'
$fixtureBuilder = @'
import json, pathlib, sys
m=json.load(open(sys.argv[1], 'r', encoding='utf-8'))
lines=[
'STAGE2N_A15_6_ALL_HBM_BOARD_VALIDATION_V1=PASS',
'A15_6_BO_CLEANUP=PASS','A15_6_ALL_FIVE_CASES=PASS',
'BO_PADDR_HEX=0x0000000000000000','BO_SIZE_BYTES=1024',
'HBM_BANK=HBM[0]','HBM_MEMORY_INDEX=0']
for i,c in enumerate(m['cases']):
 p=f'CASE{i}_'
 lines += [p+'NAME='+c['name'],p+'EXPECTED_RESULT='+str(c['expected_final_result']),
 p+'ACTUAL_RESULT='+str(c['expected_final_result']),p+'TABLE_BASE_LO_HEX=0x00000000',
 p+'TABLE_BASE_HI_HEX=0x00000000',p+'EMBEDDING_LOADED_MASK=0xF',
 p+'BOTTOM_CYCLES=322',p+'INTERACTION_CYCLES=100',p+'TOP_CYCLES=744',
 p+'TOTAL_CYCLES=1174',p+'COMPLETE_DLRM_RESULT=PASS']
pathlib.Path(sys.argv[2]).write_text('\n'.join(lines)+'\n',encoding='utf-8')
'@
$fixtureBuilder | python - $Manifest $fixtureHostLog
if ($LASTEXITCODE -ne 0) { throw 'assembler fixture construction failed' }

$fixtureEvidence = Join-Path $ResultDir 'assembler_fixture_evidence.json'
$assemblerLog = Join-Path $ResultDir 'assembler_positive.log'
& python 'scripts/assemble_stage2n_a15_6_evidence_v1.py' `
    --host-log $fixtureHostLog --manifest $Manifest --output $fixtureEvidence `
    --timestamp-utc '2026-08-28T00:00:00Z' --hostname 'local-fixture' `
    --branch $branch --head $head --device-index 2 --bdf '0000:9b:00.1' `
    --xclbin-path '/fixture/a15.xclbin' `
    --xclbin-sha256 '23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356' `
    --uuid '1b555645-a9e2-4f5e-95af-6ce4adacbc3c' `
    --programming-status PASS --device-close-status PASS 2>&1 |
    Tee-Object -FilePath $assemblerLog
if ($LASTEXITCODE -ne 0) { throw 'evidence assembler positive test failed' }
& python 'scripts/validate_stage2n_a15_6_evidence_v1.py' --manifest $Manifest --evidence $fixtureEvidence |
    Add-Content -LiteralPath $assemblerLog
if ($LASTEXITCODE -ne 0) { throw 'assembled fixture validation failed' }

$diffCheck = git diff --check 2>&1
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed: $diffCheck" }

$bashState = 'NOT_RUN_WINDOWS_LOCAL_POLICY'
$hostCompileState = 'NOT_RUN_TARGET_ENV_REQUIRED'
$statusLines = @(
    'A15_6_LOCAL_PREPARATION=PASS',
    "GIT_BRANCH=$branch",
    "GIT_HEAD=$head",
    "FROZEN_RTL_SHA256=$rtlSha",
    'FROZEN_RTL_MODIFIED=NO',
    'XCLBIN_REBUILT=NO',
    'GOLDEN_ASSET_GENERATION=PASS',
    'GOLDEN_CASES=5',
    'EXPECTED_BASELINE_RESULT=-393',
    'EXPECTED_SLOT0_RESULT=-392',
    'EXPECTED_SLOT1_RESULT=-93',
    'EXPECTED_SLOT2_RESULT=-689',
    'EXPECTED_SLOT3_RESULT=-519',
    'SOURCE_VALIDATION=PASS',
    'EVIDENCE_ASSEMBLER_POSITIVE=PASS',
    'EVIDENCE_VALIDATOR_POSITIVE=PASS',
    'EVIDENCE_VALIDATOR_NEGATIVE_CASES=8',
    "BASH_SYNTAX=$bashState",
    "HOST_XRT_COMPILE=$hostCompileState",
    'FPGA_PROGRAMMING=NOT_RUN',
    'HOST_EXECUTION=NOT_RUN',
    'PHYSICAL_HBM=NOT_RUN',
    'BOARD_FUNCTIONAL=NOT_RUN',
    'PERFORMANCE=NOT_CLAIMED',
    'FPGA_DEVICE_ACCESS=NONE',
    'SERVER_ACCESS=NONE',
    'NETWORK_ACCESS=NONE',
    'READY_FOR_PROTECTED_BOARD_EXECUTION=YES'
)
Set-Content -LiteralPath $Status -Value $statusLines -Encoding UTF8
Copy-Item -LiteralPath $Status,$generationLog,$sourceLog,$validatorLog,$assemblerLog -Destination $EvidenceDir -Force

$manifestLines = Get-ChildItem -LiteralPath $EvidenceDir -File | Sort-Object Name | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    "$hash  $($_.Name)"
}
Set-Content -LiteralPath (Join-Path $EvidenceDir 'LOCAL_EVIDENCE_SHA256.txt') -Value $manifestLines -Encoding Ascii
$statusLines | ForEach-Object { Write-Output $_ }
