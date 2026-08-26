param(
    [string]$VivadoBin =
        'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
$expectedBranch = 'work/stage2n-a15-hbm-pipeline-integration'
$authorizationCommit = '2020e4ccd2f802d69714d957e7b8baf8172a39fa'
$top = 'tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1'
$snapshot = 'tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1_sim'
$runtimeTcl = Join-Path $scriptDir `
    'run_stage2n_a15_integration_xsim_v1.tcl'
$runtimeTclForXsim = $runtimeTcl.Replace('\', '/')

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot `
        'results\stage2n_a15_1\integration_xsim_v1'
}
$ResultDir = [System.IO.Path]::GetFullPath($ResultDir)
$workDir = Join-Path $ResultDir 'work'
$statusPath = Join-Path $ResultDir 'status.txt'
$resultRootCreated = $false
$branch = 'NOT_RECORDED'
$head = 'NOT_RECORDED'

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
    (Join-Path $repoRoot 'rtl\control\mlp_sequence_controller_segmented.sv')
    (Join-Path $repoRoot `
        'rtl\interaction\dlrm_feature_interaction_engine.sv')
    (Join-Path $repoRoot `
        'rtl\pipeline\dlrm_internal_pipeline_controller.sv')
    (Join-Path $repoRoot `
        'rtl\pipeline\dlrm_internal_pipeline_controller_stage2n_a13_v1.sv')
    (Join-Path $repoRoot `
        'rtl\hbm\dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv')
    (Join-Path $repoRoot `
        'rtl\pipeline\dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv')
    (Join-Path $repoRoot `
        'tb\tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv')
)

$passMarkers = @(
    'A15_1_HBM_SLOT0_INJECTION=PASS'
    'A15_1_LANE_ORDER=PASS'
    'A15_1_HOST_SLOT123_PRESERVED=PASS'
    'A15_1_LOADED_MASK=PASS'
    'A15_1_DELAYED_READY=PASS'
    'A15_1_LOOKUP_ERROR_GUARD=PASS'
    'A15_1_BUSY_GUARD=PASS'
    'A15_1_HOST_SLOT0_GUARD=PASS'
    'A15_1_A13_ABI_PRESERVED=PASS'
    'STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1_PASS'
)

function Fail([string]$Message) {
    throw "Stage 2N-A15.1 XSim failed: $Message"
}

Push-Location $repoRoot
try {
    $branch = (git branch --show-current).Trim()
    $head = (git rev-parse HEAD).Trim()
    if ($branch -ne $expectedBranch) {
        Fail "wrong branch $branch"
    }
    git merge-base --is-ancestor $authorizationCommit HEAD
    if ($LASTEXITCODE -ne 0) {
        Fail "authorization commit is not an ancestor of HEAD"
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
    if (-not (Test-Path -LiteralPath $runtimeTcl -PathType Leaf)) {
        Fail "missing XSim Tcl runner $runtimeTcl"
    }
    if (Test-Path -LiteralPath $ResultDir) {
        Fail "result directory already exists: $ResultDir"
    }

    $a13Adapter = Join-Path $repoRoot `
        'rtl\f37x\dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv'
    $a13Text = Get-Content -Raw -LiteralPath $a13Adapter
    $abiPatterns = @(
        'ADDR_PIPE_BOTTOM_CYCLES\s*=\s*12''h218'
        'ADDR_PIPE_INTERACTION_CYCLES\s*=\s*12''h21C'
        'ADDR_PIPE_TOP_CYCLES\s*=\s*12''h220'
        'ADDR_PIPE_TOTAL_CYCLES\s*=\s*12''h224'
    )
    foreach ($pattern in $abiPatterns) {
        if ($a13Text -notmatch $pattern) {
            Fail "A13 cycle-counter ABI source guard failed: $pattern"
        }
    }

    New-Item -ItemType Directory -Path $workDir | Out-Null
    $resultRootCreated = $true
    @(
        'STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_XSIM=RUNNING'
        "BRANCH=$branch"
        "HEAD=$head"
        "AUTHORIZATION_COMMIT=$authorizationCommit"
        "TOP=$top"
        'NO_NETWORK_ACCESS=1'
        'NO_SERVER_ACCESS=1'
        'NO_FPGA_ACCESS=1'
        'NO_PHYSICAL_HBM_VALIDATION=1'
        'NO_PERFORMANCE_CLAIM=1'
    ) | Set-Content -LiteralPath $statusPath -Encoding UTF8

    $commandLog = Join-Path $ResultDir 'command_transcript.txt'
    Start-Transcript -LiteralPath $commandLog | Out-Null
    try {
        Push-Location $workDir
        try {
            Write-Output "A15_1_XSIM_TOP=$top"
            Write-Output "A15_1_XSIM_SOURCE_COUNT=$($sources.Count)"

            & $xvlog --sv @sources 2>&1 |
                Tee-Object -LiteralPath `
                    (Join-Path $ResultDir 'a15_1_xvlog.log') |
                Out-Host
            $xvlogExit = $LASTEXITCODE
            Write-Output "A15_1_XVLOG_EXIT=$xvlogExit"
            if ($xvlogExit -ne 0) {
                Fail "xvlog returned $xvlogExit"
            }

            & $xelab $top -s $snapshot --timescale 1ns/1ps 2>&1 |
                Tee-Object -LiteralPath `
                    (Join-Path $ResultDir 'a15_1_xelab.log') |
                Out-Host
            $xelabExit = $LASTEXITCODE
            Write-Output "A15_1_XELAB_EXIT=$xelabExit"
            if ($xelabExit -ne 0) {
                Fail "xelab returned $xelabExit"
            }

            & $xsim $snapshot -tclbatch $runtimeTclForXsim 2>&1 |
                Tee-Object -LiteralPath `
                    (Join-Path $ResultDir 'a15_1_xsim.log') |
                Out-Host
            $xsimExit = $LASTEXITCODE
            Write-Output "A15_1_XSIM_EXIT=$xsimExit"
            if ($xsimExit -ne 0) {
                Fail "xsim returned $xsimExit"
            }
        } finally {
            Pop-Location
        }
    } finally {
        Stop-Transcript | Out-Null
    }

    $primaryLogs = @(
        (Join-Path $ResultDir 'a15_1_xvlog.log'),
        (Join-Path $ResultDir 'a15_1_xelab.log'),
        (Join-Path $ResultDir 'a15_1_xsim.log')
    )
    $xsimLog = Join-Path $ResultDir 'a15_1_xsim.log'
    foreach ($marker in $passMarkers) {
        $count = @(
            Select-String -LiteralPath $xsimLog -SimpleMatch $marker
        ).Count
        if ($count -ne 1) {
            Fail "PASS marker missing or duplicated: $marker"
        }
    }
    $errors = @(
        Select-String -LiteralPath $primaryLogs `
            -Pattern '^(ERROR:|FATAL:)' -ErrorAction SilentlyContinue
    )
    $warnings = @(
        Select-String -LiteralPath $primaryLogs `
            -Pattern '^(WARNING:|CRITICAL WARNING:)' `
            -ErrorAction SilentlyContinue
    )
    if ($errors.Count -ne 0) {
        Fail "anchored error/fatal count is $($errors.Count)"
    }

    $status = @(
        'STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_XSIM=PASS'
        "BRANCH=$branch"
        "HEAD=$head"
        "AUTHORIZATION_COMMIT=$authorizationCommit"
        "TOP=$top"
        'HBM_SLOT0_INJECTION=PASS'
        'LANE_ORDER=PASS'
        'HOST_SLOT123_PRESERVED=PASS'
        'LOADED_MASK=PASS'
        'DELAYED_READY=PASS'
        'LOOKUP_ERROR_GUARD=PASS'
        'BUSY_GUARD=PASS'
        'HOST_SLOT0_GUARD=PASS'
        'A13_ABI_PRESERVED=PASS'
        "WARNING_COUNT=$($warnings.Count)"
        "ERROR_FATAL_COUNT=$($errors.Count)"
        'NO_NETWORK_ACCESS=1'
        'NO_SERVER_ACCESS=1'
        'NO_FPGA_ACCESS=1'
        'NO_PHYSICAL_HBM_VALIDATION=1'
        'NO_PERFORMANCE_CLAIM=1'
    )
    $status | Set-Content -LiteralPath $statusPath -Encoding UTF8
    Write-Output ($status -join [Environment]::NewLine)
} catch {
    if ($resultRootCreated -and
        (Test-Path -LiteralPath $ResultDir -PathType Container)) {
        $failureReason = $_.Exception.Message -replace '[\r\n]+', ' '
        @(
            'STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_XSIM=FAIL'
            "BRANCH=$branch"
            "HEAD=$head"
            "FAIL_REASON=$failureReason"
            'NO_NETWORK_ACCESS=1'
            'NO_SERVER_ACCESS=1'
            'NO_FPGA_ACCESS=1'
            'NO_PHYSICAL_HBM_VALIDATION=1'
            'NO_PERFORMANCE_CLAIM=1'
        ) | Set-Content -LiteralPath $statusPath -Encoding UTF8
    }
    throw
} finally {
    Pop-Location
}
