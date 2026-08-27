param(
    [string]$VivadoBin =
        'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
$expectedBranch = 'work/stage2n-a15-hbm-pipeline-integration'
$baselineCommit = '7d0c3519c29b2dd07e0615dc98ba7060d728bc4f'
$top = 'tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1'
$snapshot = 'tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1_sim'
$runtimeTcl = Join-Path $scriptDir `
    'run_stage2n_a15_4_kernel_xsim_v1.tcl'
$runtimeTclForXsim = $runtimeTcl.Replace('\', '/')

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot 'results\stage2n_a15_4'
}
$ResultDir = [System.IO.Path]::GetFullPath($ResultDir)
$workDir = Join-Path $ResultDir 'work'
$statusPath = Join-Path $ResultDir 'status.txt'
$resultRootCreated = $false
$branch = 'NOT_RECORDED'
$head = 'NOT_RECORDED'
$xvlogExit = -1
$xelabExit = -1
$xsimExit = -1

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
    (Join-Path $repoRoot `
        'rtl\interaction\dlrm_feature_interaction_engine.sv')
    (Join-Path $repoRoot `
        'rtl\f37x\dlrm_f37x_rtl_kernel_stage2n_a2.sv')
    (Join-Path $repoRoot 'rtl\control\mlp_sequence_controller_segmented.sv')
    (Join-Path $repoRoot `
        'rtl\pipeline\dlrm_internal_pipeline_controller.sv')
    (Join-Path $repoRoot `
        'rtl\pipeline\dlrm_internal_pipeline_controller_stage2n_a13_v1.sv')
    (Join-Path $repoRoot `
        'rtl\hbm\dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv')
    (Join-Path $repoRoot `
        'rtl\pipeline\dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv')
    (Join-Path $repoRoot `
        'rtl\f37x\dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv')
    (Join-Path $repoRoot `
        'tb\tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv')
)

$protectedFiles = @(
    'AGENTS.md'
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv'
    'rtl/pipeline/dlrm_internal_pipeline_controller.sv'
    'rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv'
    'rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv'
    'rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv'
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv'
    'rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv'
    'rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv'
    'tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv'
    'tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv'
    'tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v3.sv'
    'scripts/run_stage2n_a15_integration_xsim_v1.ps1'
    'scripts/run_stage2n_a15_integration_xsim_v1.tcl'
    'scripts/run_stage2n_a15_2_pipeline_xsim_v1.ps1'
    'scripts/run_stage2n_a15_2_pipeline_xsim_v1.tcl'
    'scripts/run_stage2n_a15_3_integration_xsim_v1.ps1'
    'scripts/run_stage2n_a15_3_integration_xsim_v1.tcl'
    'docs/STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1.md'
    'docs/STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1.md'
    'docs/STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1.md'
)

$passMarkers = @(
    'A15_4_RESET_CLEAN=PASS'
    'A15_4_SLOT0_ERROR_PROTECTION=PASS'
    'A15_4_MID_SEQUENCE_ERROR_PROTECTION=PASS'
    'A15_4_HOST_EMBEDDING_REJECT=PASS'
    'A15_4_TABLE_BASE_CAPTURE=PASS'
    'A15_4_FOUR_LOOKUPS=PASS'
    'A15_4_FOUR_SLOT_INJECTION=PASS'
    'A15_4_LOADED_MASK=PASS'
    'A15_4_PIPELINE_START_GUARD=PASS'
    'A15_4_DELAYED_ARREADY=PASS'
    'A15_4_DELAYED_RVALID=PASS'
    'A15_4_RESPONSE_RETENTION_REUSED=PASS'
    'A15_4_REPEATED_START_REJECT=PASS'
    'A15_4_END_TO_END_PIPELINE=PASS'
    'A15_4_RESULT_MATCH=PASS'
    'A15_4_A13_COUNTER_ABI=PASS'
    'A15_4_A13_PUBLIC_ABI=PASS'
    'STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1_PASS'
)

function Fail([string]$Message) {
    throw "Stage 2N-A15.4 kernel XSim failed: $Message"
}

function Read-UniqueMarker([string]$Path, [string]$Key) {
    $matches = @(Select-String -LiteralPath $Path `
        -Pattern ('^' + [regex]::Escape($Key) + '=(.+)$'))
    if ($matches.Count -ne 1) {
        Fail "expected exactly one $Key marker"
    }
    return $matches[0].Matches[0].Groups[1].Value.Trim()
}

try {
    Push-Location $repoRoot
    try {
        $branch = (git branch --show-current).Trim()
        $head = (git rev-parse HEAD).Trim()
    } finally {
        Pop-Location
    }
    if ($branch -ne $expectedBranch) {
        Fail "expected branch $expectedBranch, got $branch"
    }
    git -C $repoRoot merge-base --is-ancestor $baselineCommit HEAD
    if ($LASTEXITCODE -ne 0) {
        Fail 'authorization baseline is not an ancestor of HEAD'
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

    git -C $repoRoot diff --quiet $baselineCommit -- @protectedFiles
    if ($LASTEXITCODE -ne 0) {
        Fail 'an accepted A13/A14/A15.1/A15.2/A15.3 file has a working-tree change'
    }
    git -C $repoRoot diff --cached --quiet $baselineCommit -- @protectedFiles
    if ($LASTEXITCODE -ne 0) {
        Fail 'an accepted A13/A14/A15.1/A15.2/A15.3 file has a staged change'
    }

    $a13Adapter = Join-Path $repoRoot `
        'rtl\f37x\dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv'
    $a13Text = Get-Content -Raw -LiteralPath $a13Adapter
    foreach ($pattern in @(
        'ADDR_PIPE_BOTTOM_CYCLES\s*=\s*12''h218',
        'ADDR_PIPE_INTERACTION_CYCLES\s*=\s*12''h21C',
        'ADDR_PIPE_TOP_CYCLES\s*=\s*12''h220',
        'ADDR_PIPE_TOTAL_CYCLES\s*=\s*12''h224'
    )) {
        if ($a13Text -notmatch $pattern) {
            Fail "A13 cycle-counter ABI source guard failed: $pattern"
        }
    }

    $modelPath = Join-Path $repoRoot `
        'models\stage2n_a14_embedding_table.json'
    $model = Get-Content -Raw -LiteralPath $modelPath | ConvertFrom-Json
    if ($model.schema -ne 'stage2n_a14_embedding_table_v1' -or
        $model.embedding_rows -ne 64 -or
        $model.embedding_dimension -ne 8 -or
        $model.row_stride_bytes -ne 16 -or
        $model.lane_packing -ne 'lane_0_in_bits_15_0') {
        Fail 'canonical A14 table metadata mismatch'
    }
    foreach ($rowId in 37..40) {
        $row = @($model.table | Where-Object { $_.row_id -eq $rowId })
        if ($row.Count -ne 1) {
            Fail "canonical row $rowId is missing or duplicated"
        }
        for ($lane = 0; $lane -lt 8; $lane++) {
            $expected = $rowId * 8 + $lane - 256
            if ($row[0].values[$lane] -ne $expected) {
                Fail "canonical row $rowId lane $lane mismatch"
            }
        }
    }

    New-Item -ItemType Directory -Path $workDir | Out-Null
    $resultRootCreated = $true
    @(
        'A15_4_FLOW=STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1'
        'A15_4_XSIM=RUNNING'
        "GIT_BRANCH=$branch"
        "GIT_HEAD=$head"
        "BASELINE_COMMIT=$baselineCommit"
        "TOP=$top"
        'A15_4_NETWORK_ACCESS=NONE'
        'A15_4_SERVER_ACCESS=NONE'
        'A15_4_FPGA_DEVICE_ACCESS=NONE'
        'A15_4_PHYSICAL_HBM=NOT_RUN'
        'A15_4_TARGET_BUILD=NOT_RUN'
        'A15_4_XO=NOT_RUN'
        'A15_4_XCLBIN=NOT_RUN'
        'A15_4_BOARD=NOT_RUN'
        'A15_4_PERFORMANCE=NOT_CLAIMED'
    ) | Set-Content -LiteralPath $statusPath -Encoding UTF8

    $commandLog = Join-Path $ResultDir 'command_transcript.txt'
    Start-Transcript -LiteralPath $commandLog | Out-Null
    try {
        Push-Location $workDir
        try {
            Write-Output "A15_4_XSIM_TOP=$top"
            Write-Output "A15_4_XSIM_SOURCE_COUNT=$($sources.Count)"

            & $xvlog --sv @sources 2>&1 |
                Tee-Object -LiteralPath (Join-Path $ResultDir 'xvlog.log') |
                Out-Host
            $xvlogExit = $LASTEXITCODE
            Write-Output "A15_4_XVLOG_RC=$xvlogExit"
            if ($xvlogExit -ne 0) {
                Fail "xvlog returned $xvlogExit"
            }

            & $xelab $top -s $snapshot --timescale 1ns/1ps 2>&1 |
                Tee-Object -LiteralPath (Join-Path $ResultDir 'xelab.log') |
                Out-Host
            $xelabExit = $LASTEXITCODE
            Write-Output "A15_4_XELAB_RC=$xelabExit"
            if ($xelabExit -ne 0) {
                Fail "xelab returned $xelabExit"
            }

            & $xsim $snapshot -tclbatch $runtimeTclForXsim 2>&1 |
                Tee-Object -LiteralPath (Join-Path $ResultDir 'xsim.log') |
                Out-Host
            $xsimExit = $LASTEXITCODE
            Write-Output "A15_4_XSIM_RC=$xsimExit"
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
        (Join-Path $ResultDir 'xvlog.log'),
        (Join-Path $ResultDir 'xelab.log'),
        (Join-Path $ResultDir 'xsim.log')
    )
    $xsimLog = Join-Path $ResultDir 'xsim.log'
    foreach ($marker in $passMarkers) {
        $count = @(Select-String -LiteralPath $xsimLog `
            -SimpleMatch $marker).Count
        if ($count -ne 1) {
            Fail "PASS marker missing or duplicated: $marker"
        }
    }

    $warnings = @($primaryLogs | ForEach-Object {
        Select-String -LiteralPath $_ -Pattern '^\s*WARNING(?:\s*:|\b)'
    })
    $errors = @($primaryLogs | ForEach-Object {
        Select-String -LiteralPath $_ -Pattern '^\s*ERROR\s*:'
    })
    $fatals = @($primaryLogs | ForEach-Object {
        Select-String -LiteralPath $_ -Pattern '^\s*(?:FATAL|Fatal)\s*:'
    })
    $assertionFailures = @($primaryLogs | ForEach-Object {
        Select-String -LiteralPath $_ `
            -Pattern '(?i)assertion\s+(?:failed|failure)'
    })
    if (($errors.Count -ne 0) -or ($fatals.Count -ne 0) -or
        ($assertionFailures.Count -ne 0)) {
        Fail "error/fatal/assertion count is $($errors.Count)/$($fatals.Count)/$($assertionFailures.Count)"
    }

    $goldenResult = Read-UniqueMarker $xsimLog 'A15_4_GOLDEN_FINAL_RESULT'
    $finalResult = Read-UniqueMarker $xsimLog 'A15_4_ACTUAL_FINAL_RESULT'
    $bottomCycles = Read-UniqueMarker $xsimLog 'A15_4_BOTTOM_CYCLES'
    $interactionCycles = Read-UniqueMarker $xsimLog 'A15_4_INTERACTION_CYCLES'
    $topCycles = Read-UniqueMarker $xsimLog 'A15_4_TOP_CYCLES'
    $totalCycles = Read-UniqueMarker $xsimLog 'A15_4_TOTAL_CYCLES'
    $logicalLookups = Read-UniqueMarker $xsimLog 'A15_4_LOOKUP_REQUESTS'
    $arHandshakes = Read-UniqueMarker $xsimLog 'A15_4_AR_HANDSHAKES'
    $rHandshakes = Read-UniqueMarker $xsimLog 'A15_4_R_HANDSHAKES'
    $injections = Read-UniqueMarker $xsimLog 'A15_4_SLOT_INJECTIONS'
    $loadedMask = Read-UniqueMarker $xsimLog 'A15_4_FINAL_LOADED_MASK'

    if ($goldenResult -ne '36' -or $finalResult -ne '36') {
        Fail "golden/result mismatch expected=$goldenResult actual=$finalResult"
    }
    if ($logicalLookups -ne '4' -or $arHandshakes -ne '4' -or
        $rHandshakes -ne '4' -or $injections -ne '4') {
        Fail 'successful four-lookup accounting mismatch'
    }
    if ($loadedMask.ToLowerInvariant() -ne '0xf') {
        Fail "expected loaded mask 0xf, got $loadedMask"
    }
    if ($bottomCycles -ne '322' -or $interactionCycles -ne '100' -or
        $topCycles -ne '744' -or $totalCycles -ne '1174') {
        Fail 'accepted A13 cycle marker mismatch'
    }

    @(
        'A15_4_FLOW=STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1'
        'A15_4_SOURCE_AUDIT=PASS'
        'A15_4_XVLOG=PASS'
        'A15_4_XELAB=PASS'
        'A15_4_XSIM=PASS'
        'A15_4_TABLE_BASE=0x0000000123456000'
        'A15_4_ROW0_ADDRESS=0x0000000123456250'
        'A15_4_ROW1_ADDRESS=0x0000000123456260'
        'A15_4_ROW2_ADDRESS=0x0000000123456270'
        'A15_4_ROW3_ADDRESS=0x0000000123456280'
        "A15_4_LOOKUP_REQUESTS=$logicalLookups"
        "A15_4_AR_HANDSHAKES=$arHandshakes"
        "A15_4_R_HANDSHAKES=$rHandshakes"
        "A15_4_SLOT_INJECTIONS=$injections"
        'A15_4_LOADED_MASK=0xF'
        "A15_4_PIPELINE_RESULT=$finalResult"
        "A15_4_GOLDEN_RESULT=$goldenResult"
        'A15_4_RESULT_MATCH=PASS'
        "A15_4_BOTTOM_CYCLES=$bottomCycles"
        "A15_4_INTERACTION_CYCLES=$interactionCycles"
        "A15_4_TOP_CYCLES=$topCycles"
        "A15_4_TOTAL_CYCLES=$totalCycles"
        'A15_4_A13_COUNTER_ABI=PASS'
        'A15_4_A13_PUBLIC_ABI=PASS'
        'A15_4_POSITIVE_TESTS=PASS'
        'A15_4_NEGATIVE_TESTS=PASS'
        'A15_4_HOST_EMBEDDING_REJECT=PASS'
        'A15_4_PIPELINE_START_GUARD=PASS'
        'A15_4_END_TO_END_PIPELINE=PASS'
        "GIT_BRANCH=$branch"
        "GIT_HEAD=$head"
        "BASELINE_COMMIT=$baselineCommit"
        'LOOKUP_SLOT0_INDEX=37'
        'LOOKUP_SLOT1_INDEX=38'
        'LOOKUP_SLOT2_INDEX=39'
        'LOOKUP_SLOT3_INDEX=40'
        "XVLOG_RC=$xvlogExit"
        "XELAB_RC=$xelabExit"
        "XSIM_RC=$xsimExit"
        "WARNING_COUNT=$($warnings.Count)"
        "ERROR_COUNT=$($errors.Count)"
        "FATAL_COUNT=$($fatals.Count)"
        "ASSERTION_FAILURE_COUNT=$($assertionFailures.Count)"
        'A15_4_NETWORK_ACCESS=NONE'
        'A15_4_SERVER_ACCESS=NONE'
        'A15_4_FPGA_DEVICE_ACCESS=NONE'
        'A15_4_PHYSICAL_HBM=NOT_RUN'
        'A15_4_TARGET_BUILD=NOT_RUN'
        'A15_4_XO=NOT_RUN'
        'A15_4_XCLBIN=NOT_RUN'
        'A15_4_BOARD=NOT_RUN'
        'A15_4_PERFORMANCE=NOT_CLAIMED'
        'FAIL_REASON=NONE'
    ) | Set-Content -LiteralPath $statusPath -Encoding UTF8

    Get-Content -LiteralPath $statusPath
} catch {
    if ($resultRootCreated) {
        @(
            'A15_4_FLOW=STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1'
            'A15_4_XSIM=FAIL'
            "GIT_BRANCH=$branch"
            "GIT_HEAD=$head"
            "BASELINE_COMMIT=$baselineCommit"
            "XVLOG_RC=$xvlogExit"
            "XELAB_RC=$xelabExit"
            "XSIM_RC=$xsimExit"
            "FAIL_REASON=$($_.Exception.Message)"
            'A15_4_NETWORK_ACCESS=NONE'
            'A15_4_SERVER_ACCESS=NONE'
            'A15_4_FPGA_DEVICE_ACCESS=NONE'
            'A15_4_PHYSICAL_HBM=NOT_RUN'
            'A15_4_TARGET_BUILD=NOT_RUN'
            'A15_4_XO=NOT_RUN'
            'A15_4_XCLBIN=NOT_RUN'
            'A15_4_BOARD=NOT_RUN'
            'A15_4_PERFORMANCE=NOT_CLAIMED'
        ) | Set-Content -LiteralPath $statusPath -Encoding UTF8
    }
    throw
}
