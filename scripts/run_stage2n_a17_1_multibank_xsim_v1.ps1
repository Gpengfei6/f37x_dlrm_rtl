param(
    [string]$VivadoBin = 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
    [string]$ResultDir = ''
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$baseline = 'ec062ba6c8a0a22c29b28abc73e0b94668e03fd7'
if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot ('results\stage2n_a17_1\' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
}
$ResultDir = [IO.Path]::GetFullPath($ResultDir)
if (Test-Path -LiteralPath $ResultDir) { throw "Result directory already exists: $ResultDir" }
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
    'rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv'
    'rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv'
    'tb/tb_dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv'
    'tb/tb_dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv'
)
$sources = @($sourcesRelative | ForEach-Object { Join-Path $repoRoot $_ })
$runtime = Join-Path $PSScriptRoot 'run_stage2n_a17_1_multibank_xsim_v1.tcl'
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
foreach ($path in (@($xvlog, $xelab, $xsim, $runtime) + $sources)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $path" }
}
# All baseline executable assets are frozen. New A17 files are not in baseline.
$protected = @(git -C $repoRoot ls-tree -r --name-only $baseline -- rtl tb host scripts config models python)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate baseline' }
git -C $repoRoot diff --quiet $baseline -- @protected
if ($LASTEXITCODE -ne 0) { throw 'Frozen baseline asset changed' }
$table = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'models/stage2n_a14_embedding_table.json') | ConvertFrom-Json
if ($table.schema -ne 'stage2n_a14_embedding_table_v1' -or
    $table.embedding_rows -ne 64 -or $table.embedding_dimension -ne 8 -or
    $table.row_stride_bytes -ne 16 -or $table.lane_packing -ne 'lane_0_in_bits_15_0') {
    throw 'Canonical embedding table contract mismatch'
}
foreach ($rowId in 0..63) {
    $row = @($table.table | Where-Object { $_.row_id -eq $rowId })
    if ($row.Count -ne 1) { throw "Missing/duplicate canonical row $rowId" }
    foreach ($lane in 0..7) {
        if ($row[0].values[$lane] -ne ($rowId * 8 + $lane - 256)) {
            throw "Canonical row $rowId lane $lane mismatch"
        }
    }
}
New-Item -ItemType Directory -Path $ResultDir | Out-Null
$status = Join-Path $ResultDir 'status.txt'
@(
    'A17_1_LOCAL_XSIM=RUNNING'
    "BASELINE_COMMIT=$baseline"
    "GIT_HEAD=$(git -C $repoRoot rev-parse HEAD)"
    "GIT_BRANCH=$(git -C $repoRoot branch --show-current)"
    'A17_1_TARGET_BUILD=NOT_RUN'
    'A17_1_PHYSICAL_HBM=NOT_VALIDATED'
    'A17_1_PERFORMANCE=NOT_CLAIMED'
    'NETWORK_ACCESS=NONE'
    'SERVER_ACCESS=NONE'
    'FPGA_DEVICE_ACCESS=NONE'
) | Set-Content -LiteralPath $status -Encoding UTF8
$manifestPaths = @($sourcesRelative + @(
    'scripts/run_stage2n_a17_1_multibank_xsim_v1.ps1'
    'scripts/run_stage2n_a17_1_multibank_xsim_v1.tcl'
    'models/stage2n_a14_embedding_table.json'
))
$beforeHashes = @{}
$manifest = @($manifestPaths | ForEach-Object {
    $digest = (Get-FileHash -LiteralPath (Join-Path $repoRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
    $beforeHashes[$_] = $digest
    "$digest  $_"
})
$manifest | Set-Content -LiteralPath (Join-Path $ResultDir 'source_sha256.txt') -Encoding UTF8
$tests = @(
    @('tb_dlrm_hbm_parallel_lookup_stage2n_a17_v1', 'A17_1_PARALLEL_LOOKUP_TEST=PASS'),
    @('tb_dlrm_hbm_pipeline_integration_stage2n_a17_v1', 'A17_1_PIPELINE_INTEGRATION_TEST=PASS')
)
try {
    foreach ($test in $tests) {
        $top = $test[0]
        $testDir = Join-Path $ResultDir $top
        New-Item -ItemType Directory -Path $testDir | Out-Null
        Push-Location $testDir
        try {
            & $xvlog --sv @sources 2>&1 | Tee-Object -FilePath 'xvlog.stdout.log' | Out-Host
            $rc = $LASTEXITCODE
            "${top}_XVLOG_RC=$rc" | Add-Content -LiteralPath $status
            if ($rc -ne 0) { throw "xvlog failed: $top" }
            & $xelab $top -s a17_test --timescale 1ns/1ps 2>&1 | Tee-Object -FilePath 'xelab.stdout.log' | Out-Host
            $rc = $LASTEXITCODE
            "${top}_XELAB_RC=$rc" | Add-Content -LiteralPath $status
            if ($rc -ne 0) { throw "xelab failed: $top" }
            & $xsim a17_test -tclbatch $runtime.Replace('\','/') 2>&1 | Tee-Object -FilePath 'xsim.stdout.log' | Out-Host
            $rc = $LASTEXITCODE
            "${top}_XSIM_RC=$rc" | Add-Content -LiteralPath $status
            if ($rc -ne 0) { throw "xsim failed: $top" }
            $matches = @(Select-String -LiteralPath 'xsim.stdout.log' -Pattern ('^' + [regex]::Escape($test[1]) + '$'))
            if ($matches.Count -ne 1) { throw "Missing or duplicated PASS marker: $top" }
            $failures = @(Select-String -Path 'xvlog.stdout.log','xelab.stdout.log','xsim.stdout.log' -Pattern '^\s*(ERROR|FATAL)\s*:|assertion\s+(failed|failure)')
            if ($failures.Count -ne 0) { throw "Tool errors/assertion failures: $top" }
            $warnings = @(Select-String -Path 'xvlog.stdout.log','xelab.stdout.log','xsim.stdout.log' -Pattern '^\s*WARNING\b')
            "${top}_WARNING_COUNT=$($warnings.Count)" | Add-Content -LiteralPath $status
        } finally { Pop-Location }
    }
    foreach ($path in $manifestPaths) {
        $after = (Get-FileHash -LiteralPath (Join-Path $repoRoot $path) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($after -ne $beforeHashes[$path]) { throw "Source changed during test: $path" }
    }
    git -C $repoRoot diff --quiet $baseline -- @protected
    if ($LASTEXITCODE -ne 0) { throw 'Frozen baseline changed during test' }
    @('FROZEN_EXECUTABLE_ASSETS_UNCHANGED=PASS', 'A17_1_LOCAL_XSIM=PASS') | Add-Content -LiteralPath $status
    Write-Output "A17_1_LOCAL_XSIM=PASS"
    Write-Output "RESULT_DIR=$ResultDir"
} catch {
    'A17_1_LOCAL_XSIM=FAIL' | Add-Content -LiteralPath $status
    $_.Exception.Message | Add-Content -LiteralPath (Join-Path $ResultDir 'failure.txt')
    throw
}
