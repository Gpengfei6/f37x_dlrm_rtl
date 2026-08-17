param(
    [string]$VivadoBin =
        'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
$expectedBranch = 'work/stage2n-a13-cycle-counter'
$expectedHead = '592720922a7e770f678e6370d07d65c13afdb1b2'
$top = 'tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1'
$snapshot = 'tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1_sim'

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot `
        'results\stage2n_a13_cycle_counter_xsim_v1'
}
$ResultDir = [System.IO.Path]::GetFullPath($ResultDir)
$workDir = Join-Path $ResultDir 'work'

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'

$sources = @(
    (Join-Path $repoRoot 'rtl\common\rv_fifo.sv')
    (Join-Path $repoRoot 'rtl\common\runtime_relu_quant.sv')
    (Join-Path $repoRoot 'rtl\compute\mac_lane.sv')
    (Join-Path $repoRoot 'rtl\memory\banked_activation_buffer.sv')
    (Join-Path $repoRoot 'rtl\memory\local_weight_provider.sv')
    (Join-Path $repoRoot 'rtl\compute\vector_dot_product_core.sv')
    (Join-Path $repoRoot 'rtl\compute\dense_layer_engine.sv')
    (Join-Path $repoRoot 'rtl\control\mlp_sequence_controller.sv')
    (Join-Path $repoRoot 'rtl\top\dlrm_f37x_rtl_kernel.sv')
    (Join-Path $repoRoot 'rtl\interaction\dlrm_feature_interaction_engine.sv')
    (Join-Path $repoRoot 'rtl\f37x\dlrm_f37x_rtl_kernel_stage2n_a2.sv')
    (Join-Path $repoRoot 'rtl\control\mlp_sequence_controller_segmented.sv')
    (Join-Path $repoRoot 'rtl\pipeline\dlrm_internal_pipeline_controller.sv')
    (Join-Path $repoRoot `
        'rtl\pipeline\dlrm_internal_pipeline_controller_stage2n_a13_v1.sv')
    (Join-Path $repoRoot `
        'rtl\f37x\dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv')
    (Join-Path $repoRoot `
        'rtl\f37x\dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv')
    (Join-Path $repoRoot `
        'tb\tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1.sv')
)

function Fail([string]$Message) {
    throw "Stage 2N-A13 XSim failed: $Message"
}

function Read-MarkerValue(
    [string]$Path,
    [string]$Key
) {
    $match = Select-String -LiteralPath $Path `
        -Pattern ("^" + [regex]::Escape($Key) + "=([0-9]+)$")
    if (@($match).Count -ne 1) {
        Fail "expected exactly one $Key marker"
    }
    return [uint32]$match.Matches[0].Groups[1].Value
}

Push-Location $repoRoot
try {
    $branch = (git branch --show-current).Trim()
    $head = (git rev-parse HEAD).Trim()
    if ($branch -ne $expectedBranch) {
        Fail "wrong branch $branch"
    }
    if ($head -ne $expectedHead) {
        Fail "wrong HEAD $head"
    }
    foreach ($tool in @($xvlog, $xelab, $xsim)) {
        if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
            Fail "missing Vivado simulator tool $tool"
        }
    }
    foreach ($source in $sources) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            Fail "missing source $source"
        }
    }
    if (Test-Path -LiteralPath $ResultDir) {
        Fail "result directory already exists: $ResultDir"
    }

    New-Item -ItemType Directory -Path $workDir | Out-Null
    $commandLog = Join-Path $ResultDir 'command_transcript.txt'
    Start-Transcript -LiteralPath $commandLog | Out-Null
    try {
        Push-Location $workDir
        try {
            Write-Output "A13_XSIM_TOP=$top"
            Write-Output "A13_XSIM_SOURCE_COUNT=$($sources.Count)"

            & $xvlog --sv @sources 2>&1 |
                Tee-Object -LiteralPath `
                    (Join-Path $ResultDir 'a13_xvlog.log')
            $xvlogExit = $LASTEXITCODE
            Write-Output "A13_XVLOG_EXIT=$xvlogExit"
            if ($xvlogExit -ne 0) {
                Fail "xvlog returned $xvlogExit"
            }

            & $xelab $top -s $snapshot --timescale 1ns/1ps 2>&1 |
                Tee-Object -LiteralPath `
                    (Join-Path $ResultDir 'a13_xelab.log')
            $xelabExit = $LASTEXITCODE
            Write-Output "A13_XELAB_EXIT=$xelabExit"
            if ($xelabExit -ne 0) {
                Fail "xelab returned $xelabExit"
            }

            & $xsim $snapshot -runall 2>&1 |
                Tee-Object -LiteralPath `
                    (Join-Path $ResultDir 'a13_xsim.log')
            $xsimExit = $LASTEXITCODE
            Write-Output "A13_XSIM_EXIT=$xsimExit"
            if ($xsimExit -ne 0) {
                Fail "xsim returned $xsimExit"
            }
        } finally {
            Pop-Location
        }
    } finally {
        Stop-Transcript | Out-Null
    }

    $xsimLog = Join-Path $ResultDir 'a13_xsim.log'
    $primaryLogs = @(
        (Join-Path $ResultDir 'a13_xvlog.log'),
        (Join-Path $ResultDir 'a13_xelab.log'),
        $xsimLog
    )
    $passText =
        'tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1: ' +
        'PASS runs=2 final=36 descriptors=5 weights=1360 biases=73'
    $passCount = @(
        Select-String -LiteralPath $xsimLog -SimpleMatch $passText
    ).Count
    $errors = @(
        Select-String -LiteralPath $primaryLogs `
            -Pattern '^(ERROR:|FATAL:)' -ErrorAction SilentlyContinue
    )
    $warnings = @(
        Select-String -LiteralPath $primaryLogs `
            -Pattern '^(WARNING:|CRITICAL WARNING:)' `
            -ErrorAction SilentlyContinue
    )
    if ($passCount -ne 1) {
        Fail 'canonical PASS marker missing or duplicated'
    }
    if ($errors.Count -ne 0) {
        Fail "anchored error/fatal count is $($errors.Count)"
    }

    $bottomCycles = Read-MarkerValue $xsimLog 'BOTTOM_CYCLES'
    $interactionCycles =
        Read-MarkerValue $xsimLog 'INTERACTION_CYCLES'
    $topCycles = Read-MarkerValue $xsimLog 'TOP_CYCLES'
    $totalCycles = Read-MarkerValue $xsimLog 'TOTAL_CYCLES'
    $overheadCycles =
        Read-MarkerValue $xsimLog 'CONTROLLER_OVERHEAD_CYCLES'

    $status = @(
        'STAGE2N_A13_CYCLE_COUNTER_XSIM_V1_PASS'
        "BRANCH=$branch"
        "HEAD=$head"
        "TOP=$top"
        'RUNS=2'
        'ARITHMETIC_RESULT=36'
        "BOTTOM_CYCLES=$bottomCycles"
        "INTERACTION_CYCLES=$interactionCycles"
        "TOP_CYCLES=$topCycles"
        "TOTAL_CYCLES=$totalCycles"
        "CONTROLLER_OVERHEAD_CYCLES=$overheadCycles"
        'BACKPRESSURE_ITERATIONS=12'
        'RESTART_MATCH=1'
        'RESULT_INDEX=0'
        'RESULT_TAG=4'
        "WARNING_COUNT=$($warnings.Count)"
        "ERROR_FATAL_COUNT=$($errors.Count)"
        'NO_FPGA_ACCESS=1'
        'NO_FPGA_PROGRAMMING_OR_RESET=1'
    )
    $status | Set-Content -LiteralPath `
        (Join-Path $ResultDir 'status.txt') -Encoding UTF8
    Write-Output ($status -join [Environment]::NewLine)
} finally {
    Pop-Location
}
