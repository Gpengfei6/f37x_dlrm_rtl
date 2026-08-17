param(
    [string]$VivadoBat =
        'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat',
    [string]$Part = 'xc7a200tfbg484-2',
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
$worker = Join-Path $scriptDir `
    'run_stage2n_a13_cycle_counter_ooc_v1.tcl'
$expectedBranch = 'work/stage2n-a13-cycle-counter'
$expectedHead = '592720922a7e770f678e6370d07d65c13afdb1b2'

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot `
        'results\stage2n_a13_cycle_counter_ooc_artix7_v1'
}
$ResultDir = [System.IO.Path]::GetFullPath($ResultDir)

function Fail([string]$Message) {
    throw "Stage 2N-A13 OOC failed: $Message"
}

function Read-Status([string]$Path) {
    $result = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([^=]+)=(.*)$') {
            $result[$matches[1]] = $matches[2]
        }
    }
    return $result
}

function As-Double([string]$Value) {
    return [double]::Parse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture)
}

function As-Int([string]$Value) {
    return [int64]::Parse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture)
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
    if (-not (Test-Path -LiteralPath $VivadoBat -PathType Leaf)) {
        Fail "Vivado not found: $VivadoBat"
    }
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
        Fail "worker Tcl not found: $worker"
    }
    if (Test-Path -LiteralPath $ResultDir) {
        Fail "result directory already exists: $ResultDir"
    }

    New-Item -ItemType Directory -Path $ResultDir | Out-Null
    Start-Transcript -LiteralPath `
        (Join-Path $ResultDir 'command_transcript.txt') | Out-Null
    try {
        $cases = @(
            @{
                Label = 'pre_a13_baseline'
                Top = 'dlrm_f37x_rtl_kernel_stage2n_a10_v2'
            },
            @{
                Label = 'a13_cycle_counter'
                Top = 'dlrm_f37x_rtl_kernel_stage2n_a13_v1'
            }
        )

        foreach ($case in $cases) {
            $label = $case.Label
            $top = $case.Top
            $caseResult = Join-Path $ResultDir $label
            $log = Join-Path $ResultDir ($label + '_vivado.log')
            $env:STAGE2N_A13_SYNTH_TOP = $top
            $env:STAGE2N_A13_SYNTH_LABEL = $label
            $env:STAGE2N_A13_SYNTH_RESULT_DIR = $caseResult
            $env:STAGE2N_A13_SYNTH_PART = $Part

            Write-Output "OOC_LABEL=$label"
            Write-Output "OOC_TOP=$top"
            & $VivadoBat -mode batch -nolog -nojournal `
                -source $worker 2>&1 | Tee-Object -LiteralPath $log
            $vivadoExit = $LASTEXITCODE
            Write-Output "OOC_VIVADO_EXIT_$($label.ToUpperInvariant())=$vivadoExit"
            if ($vivadoExit -ne 0) {
                Fail "$label Vivado returned $vivadoExit"
            }

            $statusPath = Join-Path $caseResult 'status.txt'
            if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
                Fail "$label status file is missing"
            }
            $firstLine = Get-Content -LiteralPath $statusPath -TotalCount 1
            if ($firstLine -notin @(
                    'STAGE2N_A13_OOC_SYNTH_V1_PASS',
                    'STAGE2N_A13_OOC_SYNTH_V1_FAIL')) {
                Fail "$label OOC status marker is missing"
            }
            $anchoredErrors = @(
                Select-String -LiteralPath $log `
                    -Pattern '^(ERROR:|FATAL:)' `
                    -ErrorAction SilentlyContinue
            )
            if ($anchoredErrors.Count -ne 0) {
                Fail "$label anchored error/fatal count is $($anchoredErrors.Count)"
            }
        }
    } finally {
        Stop-Transcript | Out-Null
    }

    $baseline = Read-Status `
        (Join-Path $ResultDir 'pre_a13_baseline\status.txt')
    $a13 = Read-Status `
        (Join-Path $ResultDir 'a13_cycle_counter\status.txt')

    $baselineLog = Join-Path $ResultDir 'pre_a13_baseline_vivado.log'
    $a13Log = Join-Path $ResultDir 'a13_cycle_counter_vivado.log'
    $baselineWarnings = @(
        Select-String -LiteralPath $baselineLog `
            -Pattern '^(WARNING:|CRITICAL WARNING:)' `
            -ErrorAction SilentlyContinue
    ).Count
    $a13Warnings = @(
        Select-String -LiteralPath $a13Log `
            -Pattern '^(WARNING:|CRITICAL WARNING:)' `
            -ErrorAction SilentlyContinue
    ).Count

    $comparisonPass =
        ($baseline.SYNTHESIS_COMPLETED -eq '1') -and
        ($a13.SYNTHESIS_COMPLETED -eq '1') -and
        ($a13.TIMING_MET -eq '1') -and
        ($a13.LATCH_COUNT -eq '0') -and
        ($a13.DRC_ERROR_COUNT -eq '0')
    $comparisonMarker = if ($comparisonPass) {
        'STAGE2N_A13_CYCLE_COUNTER_OOC_V1_PASS'
    } else {
        'STAGE2N_A13_CYCLE_COUNTER_OOC_V1_FAIL'
    }

    $comparison = @(
        $comparisonMarker
        "BRANCH=$branch"
        "HEAD=$head"
        "PART=$Part"
        'CLOCK_PERIOD_NS=10.000'
        "BASELINE_WNS_NS=$($baseline.WNS_NS)"
        "A13_WNS_NS=$($a13.WNS_NS)"
        "BASELINE_TIMING_MET=$($baseline.TIMING_MET)"
        "A13_TIMING_MET=$($a13.TIMING_MET)"
        ('WNS_DELTA_NS=' +
            ((As-Double $a13.WNS_NS) -
             (As-Double $baseline.WNS_NS)).ToString(
                '0.000',
                [System.Globalization.CultureInfo]::InvariantCulture))
        "BASELINE_TNS_NS=$($baseline.TNS_NS)"
        "A13_TNS_NS=$($a13.TNS_NS)"
        "BASELINE_FAILING_ENDPOINTS=$($baseline.FAILING_ENDPOINTS)"
        "A13_FAILING_ENDPOINTS=$($a13.FAILING_ENDPOINTS)"
        "BASELINE_LUT=$($baseline.LUT_COUNT)"
        "A13_LUT=$($a13.LUT_COUNT)"
        ('LUT_DELTA=' +
            ((As-Int $a13.LUT_COUNT) -
             (As-Int $baseline.LUT_COUNT)))
        "BASELINE_FF=$($baseline.FF_COUNT)"
        "A13_FF=$($a13.FF_COUNT)"
        ('FF_DELTA=' +
            ((As-Int $a13.FF_COUNT) -
             (As-Int $baseline.FF_COUNT)))
        "BASELINE_RAMB36=$($baseline.RAMB36_COUNT)"
        "A13_RAMB36=$($a13.RAMB36_COUNT)"
        "BASELINE_RAMB18=$($baseline.RAMB18_COUNT)"
        "A13_RAMB18=$($a13.RAMB18_COUNT)"
        "BASELINE_DSP=$($baseline.DSP_COUNT)"
        "A13_DSP=$($a13.DSP_COUNT)"
        "BASELINE_LATCH=$($baseline.LATCH_COUNT)"
        "A13_LATCH=$($a13.LATCH_COUNT)"
        "BASELINE_DRC_ERROR=$($baseline.DRC_ERROR_COUNT)"
        "A13_DRC_ERROR=$($a13.DRC_ERROR_COUNT)"
        "BASELINE_METHODOLOGY_CRITICAL=$($baseline.METHODOLOGY_CRITICAL_WARNING_COUNT)"
        "A13_METHODOLOGY_CRITICAL=$($a13.METHODOLOGY_CRITICAL_WARNING_COUNT)"
        "BASELINE_LOG_WARNING_COUNT=$baselineWarnings"
        "A13_LOG_WARNING_COUNT=$a13Warnings"
        'NO_DCP_WRITTEN=1'
        'NO_XO_OR_XCLBIN_BUILD=1'
        'NO_FPGA_ACCESS=1'
        'NO_FPGA_PROGRAMMING_OR_RESET=1'
    )
    $comparison | Set-Content -LiteralPath `
        (Join-Path $ResultDir 'comparison_status.txt') `
        -Encoding UTF8
    Write-Output ($comparison -join [Environment]::NewLine)
} finally {
    Remove-Item Env:STAGE2N_A13_SYNTH_TOP -ErrorAction SilentlyContinue
    Remove-Item Env:STAGE2N_A13_SYNTH_LABEL -ErrorAction SilentlyContinue
    Remove-Item Env:STAGE2N_A13_SYNTH_RESULT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:STAGE2N_A13_SYNTH_PART -ErrorAction SilentlyContinue
    Pop-Location
}
