param(
    [string]$VivadoBin = 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$baseline = 'e4ce2ab59b594910003c20fc00174b3a465e9bca'

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $ResultDir = Join-Path $repoRoot "results\stage2n_a17_2\$stamp"
}
$ResultDir = [IO.Path]::GetFullPath($ResultDir)
if (Test-Path -LiteralPath $ResultDir) {
    throw "Result directory already exists: $ResultDir"
}

$sourcesRelative = @(
    'rtl/common/rv_fifo.sv'
    'rtl/common/runtime_relu_quant.sv'
    'rtl/compute/mac_lane.sv'
    'rtl/memory/banked_activation_buffer.sv'
    'rtl/memory/local_weight_provider.sv'
    'rtl/compute/vector_dot_product_core.sv'
    'rtl/compute/dense_layer_engine.sv'
    'rtl/control/mlp_sequence_controller.sv'
    'rtl/top/dlrm_f37x_rtl_kernel.sv'
    'rtl/interaction/dlrm_feature_interaction_engine.sv'
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv'
    'rtl/control/mlp_sequence_controller_segmented.sv'
    'rtl/pipeline/dlrm_internal_pipeline_controller.sv'
    'rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv'
    'rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv'
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv'
    'rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv'
    'rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv'
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv'
    'tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv'
)
$sources = @($sourcesRelative | ForEach-Object {
    Join-Path $repoRoot $_
})

$runtime = Join-Path $PSScriptRoot 'run_stage2n_a17_2_public_kernel_xsim_v1.tcl'
$canonicalTable = Join-Path $repoRoot 'models/stage2n_a14_embedding_table.json'
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'

foreach ($path in (@($xvlog, $xelab, $xsim, $runtime, $canonicalTable) + $sources)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing file: $path"
    }
}

# Every path already present in the accepted A17.1 commit is immutable here.
# Check bounded chunks so the full 511-path baseline does not exceed the
# Windows process command-line limit. Baseline-absent A17.2 files are never in
# these chunks and therefore remain legal before and after their later commit.
$protected = @(git -C $repoRoot ls-tree -r --name-only $baseline)
if ($LASTEXITCODE -ne 0 -or $protected.Count -eq 0) {
    throw "Cannot enumerate frozen baseline $baseline"
}
function Assert-FrozenBaseline {
    for ($offset = 0; $offset -lt $protected.Count; $offset += 40) {
        $last = [Math]::Min($offset + 39, $protected.Count - 1)
        $chunk = @($protected[$offset..$last])
        & git -C $repoRoot diff --quiet $baseline -- @chunk
        if ($LASTEXITCODE -ne 0) {
            throw "A file frozen at baseline $baseline has changed"
        }
    }
}
Assert-FrozenBaseline

# Audit all 64 rows rather than trusting only the four rows used by this bench.
$table = Get-Content -Raw -LiteralPath $canonicalTable | ConvertFrom-Json
if ($table.schema -ne 'stage2n_a14_embedding_table_v1' -or
    $table.embedding_rows -ne 64 -or
    $table.embedding_dimension -ne 8 -or
    $table.row_stride_bytes -ne 16 -or
    $table.lane_packing -ne 'lane_0_in_bits_15_0') {
    throw 'Canonical embedding table contract mismatch'
}
foreach ($rowId in 0..63) {
    $row = @($table.table | Where-Object { $_.row_id -eq $rowId })
    if ($row.Count -ne 1) {
        throw "Missing or duplicate canonical row $rowId"
    }
    foreach ($lane in 0..7) {
        $expected = $rowId * 8 + $lane - 256
        if ($row[0].values[$lane] -ne $expected) {
            throw "Canonical row $rowId lane $lane mismatch"
        }
    }
}

New-Item -ItemType Directory -Path $ResultDir | Out-Null
$status = Join-Path $ResultDir 'status.txt'
@(
    'A17_2_PUBLIC_KERNEL_XSIM=RUNNING'
    "BASELINE_COMMIT=$baseline"
    "GIT_HEAD=$(git -C $repoRoot rev-parse HEAD)"
    "GIT_BRANCH=$(git -C $repoRoot branch --show-current)"
    'A17_2_TARGET_BUILD=NOT_RUN'
    'A17_2_PHYSICAL_HBM=NOT_VALIDATED'
    'A17_2_PERFORMANCE=NOT_CLAIMED'
    'NETWORK_ACCESS=NONE'
    'SERVER_ACCESS=NONE'
    'FPGA_DEVICE_ACCESS=NONE'
) | Set-Content -LiteralPath $status -Encoding UTF8

$manifestPaths = @($sourcesRelative + @(
    'scripts/run_stage2n_a17_2_public_kernel_xsim_v1.ps1'
    'scripts/run_stage2n_a17_2_public_kernel_xsim_v1.tcl'
    'models/stage2n_a14_embedding_table.json'
))
$beforeHashes = @{}
$manifest = @($manifestPaths | ForEach-Object {
    $digest = (Get-FileHash -LiteralPath (Join-Path $repoRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
    $beforeHashes[$_] = $digest
    "$digest  $_"
})
$manifest | Set-Content -LiteralPath (Join-Path $ResultDir 'source_sha256.txt') -Encoding UTF8

$top = 'tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1'
$passMarker = 'STAGE2N_A17_2_PUBLIC_KERNEL_XSIM_V1_PASS'
$workDir = Join-Path $ResultDir $top
New-Item -ItemType Directory -Path $workDir | Out-Null

try {
    Push-Location $workDir
    try {
        & $xvlog --sv @sources 2>&1 |
            Tee-Object -FilePath 'xvlog.console.log' | Out-Host
        $rc = $LASTEXITCODE
        "XVLOG_RC=$rc" | Add-Content -LiteralPath $status
        if ($rc -ne 0) { throw 'xvlog failed' }

        & $xelab $top -s a17_2_public_kernel_test --timescale 1ns/1ps 2>&1 |
            Tee-Object -FilePath 'xelab.console.log' | Out-Host
        $rc = $LASTEXITCODE
        "XELAB_RC=$rc" | Add-Content -LiteralPath $status
        if ($rc -ne 0) { throw 'xelab failed' }

        & $xsim a17_2_public_kernel_test -tclbatch $runtime.Replace('\','/') 2>&1 |
            Tee-Object -FilePath 'xsim.console.log' | Out-Host
        $rc = $LASTEXITCODE
        "XSIM_RC=$rc" | Add-Content -LiteralPath $status
        if ($rc -ne 0) { throw 'xsim failed' }

        $passMatches = @(Select-String -LiteralPath 'xsim.console.log' `
            -Pattern ('^' + [regex]::Escape($passMarker) + '$'))
        if ($passMatches.Count -ne 1) {
            throw "Missing or duplicated final PASS marker: $passMarker"
        }

        $requiredMarkers = @(
            'A17_2_SPLIT_AXI_LITE=PASS'
            'A17_2_FOUR_BASE_CAPTURE=PASS'
            'A17_2_FOUR_AXI=PASS'
            'A17_2_FOUR_AR_BEFORE_ANY_R=PASS'
            'A17_2_REORDER=PASS'
            'A17_2_STALL=PASS'
            'A17_2_ERROR=PASS'
            'A17_2_ERROR_DRAIN_RECOVERY=PASS'
            'A17_2_COUNTER_RESTART_DETERMINISM=PASS'
            'A17_2_RESTART=PASS'
            'A17_2_LATENCY_ACCOUNTING=PASS'
        )
        foreach ($marker in $requiredMarkers) {
            $matches = @(Select-String -LiteralPath 'xsim.console.log' `
                -Pattern ('^' + [regex]::Escape($marker) + '$'))
            if ($matches.Count -ne 1) {
                throw "Missing or duplicated required marker: $marker"
            }
        }

        # XSim can return zero even after a testbench $fatal, so scan every log.
        $failurePattern = '(?i)^\s*(fatal|error)\s*:|\bassertion\s+(failed|failure)\b|\$fatal'
        $failures = @(Select-String `
            -Path 'xvlog.console.log','xelab.console.log','xsim.console.log' `
            -Pattern $failurePattern)
        if ($failures.Count -ne 0) {
            throw 'Tool error, fatal, or assertion failure found in logs'
        }
        $warnings = @(Select-String `
            -Path 'xvlog.console.log','xelab.console.log','xsim.console.log' `
            -Pattern '(?i)^\s*warning\b')
        "WARNING_COUNT=$($warnings.Count)" | Add-Content -LiteralPath $status
    } finally {
        Pop-Location
    }

    foreach ($path in $manifestPaths) {
        $after = (Get-FileHash -LiteralPath (Join-Path $repoRoot $path) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($after -ne $beforeHashes[$path]) {
            throw "Source changed during test: $path"
        }
    }
    Assert-FrozenBaseline

    @(
        'CANONICAL_TABLE_AUDIT=PASS'
        'FROZEN_BASELINE_E4CE2AB_UNCHANGED=PASS'
        'A17_2_PUBLIC_KERNEL_XSIM=PASS'
    ) | Add-Content -LiteralPath $status

    $evidenceDir = Join-Path $repoRoot 'docs\evidence\stage2n_a17_2'
    New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
    $xvlogLog = Join-Path $workDir 'xvlog.console.log'
    $xelabLog = Join-Path $workDir 'xelab.console.log'
    $xsimLog = Join-Path $workDir 'xsim.console.log'
    Copy-Item -LiteralPath $xsimLog -Destination (Join-Path $evidenceDir 'xsim.log') -Force
    @(
        Get-Content -LiteralPath $xvlogLog
        ''
        '===== xelab ====='
        Get-Content -LiteralPath $xelabLog
    ) | Set-Content -LiteralPath (Join-Path $evidenceDir 'compile.log') -Encoding UTF8
    $head = git -C $repoRoot rev-parse HEAD
    $branch = git -C $repoRoot branch --show-current
    $now = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
    @(
        'STAGE=STAGE2N_A17_3_PUBLIC_KERNEL_XSIM_REGRESSION'
        "DATE=$now"
        "GIT_HEAD=$head"
        "GIT_BRANCH=$branch"
        "RESULT_DIRECTORY=$ResultDir"
        'A17_3_RTL=PASS'
        'A17_3_TB=PASS'
        'A17_2_PUBLIC_KERNEL_XSIM=PASS'
        'COMPILE=PASS'
        'SIMULATION=PASS'
        'FOUR_AXI=PASS'
        'REORDER=PASS'
        'STALL=PASS'
        'ERROR=PASS'
        'RESTART=PASS'
        'A17_2_TARGET_BUILD=NOT_RUN'
        'A17_2_PHYSICAL_HBM=NOT_VALIDATED'
        'A17_2_PERFORMANCE=NOT_CLAIMED'
        Get-Content -LiteralPath $status
    ) | Set-Content -LiteralPath (Join-Path $evidenceDir 'run_summary.txt') -Encoding UTF8
    $evidenceFiles = @(
        'docs/evidence/stage2n_a17_2/xsim.log'
        'docs/evidence/stage2n_a17_2/compile.log'
        'docs/evidence/stage2n_a17_2/run_summary.txt'
    )
    $manifest = @(Get-Content -LiteralPath (Join-Path $ResultDir 'source_sha256.txt'))
    $manifest += @($evidenceFiles | ForEach-Object {
        $digest = (Get-FileHash -LiteralPath (Join-Path $repoRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
        "$digest  $_"
    })
    $manifest | Set-Content -LiteralPath (Join-Path $evidenceDir 'manifest.txt') -Encoding UTF8

    Write-Output 'A17_2_PUBLIC_KERNEL_XSIM=PASS'
    Write-Output "RESULT_DIR=$ResultDir"
    Write-Output "EVIDENCE_DIR=$evidenceDir"
} catch {
    'A17_2_PUBLIC_KERNEL_XSIM=FAIL' | Add-Content -LiteralPath $status
    $_.Exception.Message | Set-Content `
        -LiteralPath (Join-Path $ResultDir 'failure.txt') -Encoding UTF8
    throw
}
