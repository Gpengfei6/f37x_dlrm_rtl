param(
    [string]$VivadoBin =
        'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))
$expectedBranch = 'work/stage2n-a15-hbm-pipeline-integration'
$baselineCommit = 'b3031d4f9d3c445a3f1eaa227ae2d28d35d78ae9'
$top = 'tb_dlrm_hbm_pipeline_integration_stage2n_a15_v3'
$snapshot = 'tb_dlrm_hbm_pipeline_integration_stage2n_a15_v3_sim'
$runtimeTcl = Join-Path $scriptDir `
    'run_stage2n_a15_3_integration_xsim_v1.tcl'
$runtimeTclForXsim = $runtimeTcl.Replace('\', '/')

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot 'results\stage2n_a15_3'
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
        'rtl\pipeline\dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv')
    (Join-Path $repoRoot `
        'tb\tb_dlrm_hbm_pipeline_integration_stage2n_a15_v3.sv')
)

$protectedFiles = @(
    'rtl/pipeline/dlrm_internal_pipeline_controller.sv'
    'rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv'
    'rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv'
    'rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv'
    'rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv'
    'tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv'
    'tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv'
    'scripts/run_stage2n_a15_integration_xsim_v1.ps1'
    'scripts/run_stage2n_a15_2_pipeline_xsim_v1.ps1'
    'docs/STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1.md'
    'docs/STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1.md'
)

$passMarkers = @(
    'A15_3_SLOT0_HBM_LOOKUP=PASS'
    'A15_3_SLOT1_HBM_LOOKUP=PASS'
    'A15_3_SLOT2_HBM_LOOKUP=PASS'
    'A15_3_SLOT3_HBM_LOOKUP=PASS'
    'A15_3_SLOT0_LANE_ORDER=PASS'
    'A15_3_SLOT1_LANE_ORDER=PASS'
    'A15_3_SLOT2_LANE_ORDER=PASS'
    'A15_3_SLOT3_LANE_ORDER=PASS'
    'A15_3_ALL_FOUR_HBM_EMBEDDINGS=PASS'
    'A15_3_EMBEDDING_LOADED_MASK=PASS'
    'A15_3_DELAYED_REQUEST_READY=PASS'
    'A15_3_DELAYED_RESPONSE=PASS'
    'A15_3_DELAYED_EMBEDDING_READY=PASS'
    'A15_3_LOOKUP_ERROR_PROTECTION=PASS'
    'A15_3_ERROR_FAILING_SLOT_NOT_LOADED=PASS'
    'A15_3_BUSY_REQUEST_PROTECTION=PASS'
    'A15_3_RESPONSE_HOLD=PASS'
    'A15_3_HOST_EMBEDDING_WRITE_REJECT=PASS'
    'A15_3_PIPELINE_START_GUARD=PASS'
    'A15_3_A13_PIPELINE_ABI_UNCHANGED=PASS'
    'A15_3_A13_CYCLE_COUNTER_ABI_UNCHANGED=PASS'
    'A15_3_END_TO_END_PIPELINE=PASS'
    'A15_3_END_TO_END_RESULT_MATCH=PASS'
    'STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1_PASS'
)

function Fail([string]$Message) {
    throw "Stage 2N-A15.3 XSim failed: $Message"
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
        Fail 'an accepted A13/A14/A15.1/A15.2 file has a working-tree change'
    }
    git -C $repoRoot diff --cached --quiet $baselineCommit -- @protectedFiles
    if ($LASTEXITCODE -ne 0) {
        Fail 'an accepted A13/A14/A15.1/A15.2 file has a staged change'
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
        'A15_3_FLOW=STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1'
        'A15_3_XSIM=RUNNING'
        "GIT_BRANCH=$branch"
        "GIT_HEAD=$head"
        "BASELINE_COMMIT=$baselineCommit"
        "TOP=$top"
        'NETWORK_ACCESS=NONE'
        'SERVER_ACCESS=NONE'
        'FPGA_DEVICE_ACCESS=NONE'
        'PHYSICAL_HBM=NOT_RUN'
        'TARGET_BUILD=NOT_RUN'
        'PERFORMANCE=NOT_CLAIMED'
    ) | Set-Content -LiteralPath $statusPath -Encoding UTF8

    $commandLog = Join-Path $ResultDir 'command_transcript.txt'
    Start-Transcript -LiteralPath $commandLog | Out-Null
    try {
        Push-Location $workDir
        try {
            Write-Output "A15_3_XSIM_TOP=$top"
            Write-Output "A15_3_XSIM_SOURCE_COUNT=$($sources.Count)"

            & $xvlog --sv @sources 2>&1 |
                Tee-Object -LiteralPath (Join-Path $ResultDir 'xvlog.log') |
                Out-Host
            $xvlogExit = $LASTEXITCODE
            Write-Output "A15_3_XVLOG_RC=$xvlogExit"
            if ($xvlogExit -ne 0) {
                Fail "xvlog returned $xvlogExit"
            }

            & $xelab $top -s $snapshot --timescale 1ns/1ps 2>&1 |
                Tee-Object -LiteralPath (Join-Path $ResultDir 'xelab.log') |
                Out-Host
            $xelabExit = $LASTEXITCODE
            Write-Output "A15_3_XELAB_RC=$xelabExit"
            if ($xelabExit -ne 0) {
                Fail "xelab returned $xelabExit"
            }

            & $xsim $snapshot -tclbatch $runtimeTclForXsim 2>&1 |
                Tee-Object -LiteralPath (Join-Path $ResultDir 'xsim.log') |
                Out-Host
            $xsimExit = $LASTEXITCODE
            Write-Output "A15_3_XSIM_RC=$xsimExit"
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
    if (($errors.Count -ne 0) -or ($fatals.Count -ne 0)) {
        Fail "error/fatal count is $($errors.Count)/$($fatals.Count)"
    }

    $goldenResult = Read-UniqueMarker $xsimLog 'A15_3_GOLDEN_FINAL_RESULT'
    $finalResult = Read-UniqueMarker $xsimLog 'A15_3_ACTUAL_FINAL_RESULT'
    $bottomCycles = Read-UniqueMarker $xsimLog 'BOTTOM_CYCLES'
    $interactionCycles = Read-UniqueMarker $xsimLog 'INTERACTION_CYCLES'
    $topCycles = Read-UniqueMarker $xsimLog 'TOP_CYCLES'
    $totalCycles = Read-UniqueMarker $xsimLog 'TOTAL_CYCLES'
    $logicalLookups = Read-UniqueMarker $xsimLog 'LOGICAL_LOOKUP_REQUESTS'
    $arHandshakes = Read-UniqueMarker $xsimLog 'AXI_AR_HANDSHAKES'
    $rHandshakes = Read-UniqueMarker $xsimLog 'AXI_R_HANDSHAKES'
    $injections = Read-UniqueMarker $xsimLog 'SUCCESSFUL_SLOT_INJECTIONS'

    if ($goldenResult -ne '36' -or $finalResult -ne '36') {
        Fail "golden/result mismatch expected=$goldenResult actual=$finalResult"
    }
    if ($logicalLookups -ne '4' -or $arHandshakes -ne '4' -or
        $rHandshakes -ne '4' -or $injections -ne '4') {
        Fail 'successful four-lookup accounting mismatch'
    }
    if ($bottomCycles -ne '322' -or $interactionCycles -ne '100' -or
        $topCycles -ne '744' -or $totalCycles -ne '1174') {
        Fail 'accepted A13 cycle marker mismatch'
    }

    @(
        'A15_3_FLOW=STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1'
        'A15_3_SOURCE_AUDIT=PASS'
        'A15_3_SEQUENTIAL_LOOKUPS=PASS'
        'A15_3_SLOT0_FROM_HBM=PASS'
        'A15_3_SLOT1_FROM_HBM=PASS'
        'A15_3_SLOT2_FROM_HBM=PASS'
        'A15_3_SLOT3_FROM_HBM=PASS'
        'A15_3_LANE_ORDER=PASS'
        'A15_3_READY_HOLD=PASS'
        'A15_3_ERROR_PRESERVATION=PASS'
        'A15_3_BUSY_REJECTION=PASS'
        'A15_3_HOST_EMBEDDING_REJECT=PASS'
        'A15_3_EMBEDDING_MASK_F=PASS'
        'A15_3_PIPELINE_START_GUARD=PASS'
        'A15_3_END_TO_END_PIPELINE=PASS'
        'A15_3_GOLDEN_MATCH=PASS'
        'A15_3_A13_ABI_PRESERVED=PASS'
        'A15_3_CYCLE_COUNTER_ABI_PRESERVED=PASS'
        'A15_3_XSIM=PASS'
        "GIT_BRANCH=$branch"
        "GIT_HEAD=$head"
        "BASELINE_COMMIT=$baselineCommit"
        'LOOKUP_SLOT0_INDEX=37'
        'LOOKUP_SLOT1_INDEX=38'
        'LOOKUP_SLOT2_INDEX=39'
        'LOOKUP_SLOT3_INDEX=40'
        "FINAL_RESULT=$finalResult"
        "GOLDEN_RESULT=$goldenResult"
        "BOTTOM_CYCLES=$bottomCycles"
        "INTERACTION_CYCLES=$interactionCycles"
        "TOP_CYCLES=$topCycles"
        "TOTAL_CYCLES=$totalCycles"
        "LOGICAL_LOOKUP_REQUESTS=$logicalLookups"
        "AXI_AR_HANDSHAKES=$arHandshakes"
        "AXI_R_HANDSHAKES=$rHandshakes"
        "SUCCESSFUL_SLOT_INJECTIONS=$injections"
        "XVLOG_RC=$xvlogExit"
        "XELAB_RC=$xelabExit"
        "XSIM_RC=$xsimExit"
        "WARNING_COUNT=$($warnings.Count)"
        "ERROR_COUNT=$($errors.Count)"
        "FATAL_COUNT=$($fatals.Count)"
        'NETWORK_ACCESS=NONE'
        'SERVER_ACCESS=NONE'
        'FPGA_DEVICE_ACCESS=NONE'
        'PHYSICAL_HBM=NOT_RUN'
        'TARGET_BUILD=NOT_RUN'
        'PERFORMANCE=NOT_CLAIMED'
        'FAIL_REASON=NONE'
    ) | Set-Content -LiteralPath $statusPath -Encoding UTF8

    Get-Content -LiteralPath $statusPath
} catch {
    if ($resultRootCreated) {
        @(
            'A15_3_FLOW=STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1'
            'A15_3_XSIM=FAIL'
            "GIT_BRANCH=$branch"
            "GIT_HEAD=$head"
            "BASELINE_COMMIT=$baselineCommit"
            "XVLOG_RC=$xvlogExit"
            "XELAB_RC=$xelabExit"
            "XSIM_RC=$xsimExit"
            "FAIL_REASON=$($_.Exception.Message)"
            'NETWORK_ACCESS=NONE'
            'SERVER_ACCESS=NONE'
            'FPGA_DEVICE_ACCESS=NONE'
            'PHYSICAL_HBM=NOT_RUN'
            'TARGET_BUILD=NOT_RUN'
            'PERFORMANCE=NOT_CLAIMED'
        ) | Set-Content -LiteralPath $statusPath -Encoding UTF8
    }
    throw
}
