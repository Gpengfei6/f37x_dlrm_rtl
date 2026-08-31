param(
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
$expectedBranch = 'work/stage2n-a15-hbm-pipeline-integration'
$baseline = '585ec44547dd9eaeee44c6b857bd49dfd279e275'
$expectedRtlSha =
    'a6eec09c4ebfe358751f7dfc31c2e77d509cd55d4fc8953f465a2227c3e7f7a5'

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot 'results\stage2n_a16_2\local_preparation_v1'
}
$ResultDir = [System.IO.Path]::GetFullPath($ResultDir)
if (Test-Path -LiteralPath $ResultDir) {
    throw "Refusing to overwrite result directory: $ResultDir"
}
New-Item -ItemType Directory -Path $ResultDir | Out-Null

$sourceLog = Join-Path $ResultDir 'source_validation.log'
$xoLog = Join-Path $ResultDir 'xo_validator_self_test.log'
$xclbinLog = Join-Path $ResultDir 'xclbin_validator_self_test.log'
$boardLog = Join-Path $ResultDir 'board_log_validator_self_test.log'
$statusPath = Join-Path $ResultDir 'a16_2_local_preparation_v1_status.txt'

function Invoke-PythonCheck {
    param([string[]]$Arguments, [string]$LogPath)
    & python @Arguments 2>&1 | Tee-Object -FilePath $LogPath
    if ($LASTEXITCODE -ne 0) {
        throw "Python validation failed: $($Arguments -join ' ')"
    }
}

Push-Location $repoRoot
try {
    $branch = (git branch --show-current).Trim()
    $head = (git rev-parse HEAD).Trim()
    if ($branch -ne $expectedBranch) {
        throw "Expected branch $expectedBranch, got $branch"
    }
    git merge-base --is-ancestor $baseline HEAD
    if ($LASTEXITCODE -ne 0) {
        throw 'A16.1 baseline is not an ancestor of HEAD'
    }
    $rtl = 'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv'
    $rtlSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $rtl).Hash.ToLower()
    if ($rtlSha -ne $expectedRtlSha) {
        throw 'Frozen A16.1 RTL SHA256 mismatch'
    }

    $env:PYTHONDONTWRITEBYTECODE = '1'
    Invoke-PythonCheck @(
        'scripts/validate_stage2n_a16_2_sources_v1.py', '--repo', $repoRoot
    ) $sourceLog
    Invoke-PythonCheck @(
        'scripts/validate_stage2n_a16_2_xo_v1.py', '--self-test'
    ) $xoLog
    Invoke-PythonCheck @(
        'scripts/validate_stage2n_a16_2_xclbin_v1.py', '--self-test'
    ) $xclbinLog
    Invoke-PythonCheck @(
        'scripts/validate_stage2n_a16_2_board_log_v1.py', '--self-test'
    ) $boardLog

    $targetScripts = @(
        'scripts/build_stage2n_a16_2_target_xo_v1.sh'
        'scripts/link_stage2n_a16_2_target_xclbin_v1.sh'
        'scripts/build_stage2n_a16_2_host_v1.sh'
        'scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh'
    )
    $forbiddenGit = 'git -C|git branch --show-current|git symbolic-ref --short'
    foreach ($targetScript in $targetScripts) {
        if (Select-String -LiteralPath $targetScript -Pattern $forbiddenGit) {
            throw "Old-Git-incompatible command in $targetScript"
        }
    }
    $bashSyntax = 'NOT_RUN_WINDOWS_BASH_UNAVAILABLE'
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($null -ne $bash) {
        foreach ($targetScript in $targetScripts) {
            & $bash.Source -n $targetScript
            if ($LASTEXITCODE -ne 0) {
                throw "Bash syntax failed: $targetScript"
            }
        }
        $bashSyntax = 'PASS'
    }

    $hostSha = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        'host/stage2n_a16_2_physical_latency_v1.cpp').Hash.ToLower()
    $runnerSha = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        'scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh').Hash.ToLower()
    @(
        'A16_2_LOCAL_PREPARATION=PASS'
        'A16_2_ABI_VALIDATION=PASS'
        'A16_2_PROTECTION_GATE=PASS'
        "BRANCH=$branch"
        "PREPARATION_HEAD=$head"
        "A16_RTL_SHA256=$rtlSha"
        "HOST_SHA256=$hostSha"
        "RUNNER_SHA256=$runnerSha"
        'KERNEL=dlrm_f37x_rtl_kernel_stage2n_a16_v1'
        'COMPUTE_UNIT=dlrm_a16_1'
        'CONTROL_INTERFACE=s_axi_control'
        'M_AXI_GMEM_MASTER_COUNT=1'
        'M_AXI_GMEM_ADDR_WIDTH=64'
        'M_AXI_GMEM_DATA_WIDTH=128'
        'TABLE_BASE_ARGUMENT_OFFSET=0x304'
        'A13_COUNTER_ABI=0x218,0x21C,0x220,0x224'
        'A15_ABI=0x300,0x304,0x308'
        'A16_COUNTER_ABI=0x30C,0x310'
        'HBM_MAPPING=dlrm_a16_1.m_axi_gmem:HBM[0]'
        'TARGET_PART=xcvu37p-fsvh2892-2L-e'
        'PLATFORM=inspur_f37x_xdma_201920_3'
        'REQUESTED_CLOCK_MHZ=100'
        'XO_VALIDATOR_SELF_TEST=PASS'
        'XCLBIN_VALIDATOR_SELF_TEST=PASS'
        'BOARD_LOG_VALIDATOR_SELF_TEST=PASS'
        "BASH_SYNTAX=$bashSyntax"
        'TARGET_XO_BUILD=NOT_RUN_TARGET_REQUIRED'
        'TARGET_XCLBIN_LINK=NOT_RUN_TARGET_REQUIRED'
        'TARGET_TIMING=NOT_RUN_TARGET_REQUIRED'
        'A16_2_PHYSICAL_HBM_LATENCY=NOT_VALIDATED'
        'A16_2_PERFORMANCE=NOT_CLAIMED'
        'FROZEN_A15_RTL_MODIFIED=NO'
        'A16_1_RTL_MODIFIED=NO'
        'A15_XCLBIN_REBUILT=NO'
        'SERVER_ACCESS=NONE'
        'NETWORK_ACCESS=NONE'
        'FPGA_DEVICE_ACCESS=NONE'
        'READY_TO_TRANSFER_A16_2_TO_TARGET=YES'
    ) | Set-Content -LiteralPath $statusPath -Encoding utf8
    Get-Content -LiteralPath $statusPath
} finally {
    Pop-Location
}
