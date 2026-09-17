# Stage 2N-A18.1 — four-slot runtime lookup-index local XSim runner.
# Modeled on scripts/run_stage2n_a17_2_public_kernel_xsim_v1.ps1
# Local RTL/XSim only. Does not SSH, program, reset, or write docs/evidence.
#
# Existence of sources is NOT a compile/elaborate/sim pass.
# A local Vivado 2022.1 result is never reported as a 2020.2 target build.

[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [string]$VivadoBin = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if ([string]::IsNullOrWhiteSpace($VivadoBin)) {
    $candidates = @(
        'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
        'C:\Xilinx\Vivado\2022.1\bin',
        'C:\Xilinx\Vivado\2020.2\bin'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $c 'xvlog.bat')) {
            $VivadoBin = $c
            break
        }
    }
}

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim  = Join-Path $VivadoBin 'xsim.bat'
if (-not (Test-Path -LiteralPath $xvlog)) {
    Write-Output 'COMPILE=NOT_RUN'
    Write-Output 'ELAB=NOT_RUN'
    Write-Output 'SIM=NOT_RUN'
    Write-Output 'XSIM=NOT_RUN'
    Write-Output 'REASON=Vivado/XSim not found locally; installer was not invoked'
    exit 2
}

$toolVersion = 'UNKNOWN'
Push-Location $env:TEMP
try {
    $verOut = & $xvlog --version 2>&1 | Out-String
} finally {
    Pop-Location
}
if ($verOut -match 'v(20\d{2}\.\d)') {
    $toolVersion = $Matches[1]
} elseif ($VivadoBin -match 'Vivado\\([^\\]+)\\bin') {
    $toolVersion = $Matches[1]
}
Write-Output "TOOL=Vivado/XSim $toolVersion (local path $VivadoBin)"
if ($toolVersion -ne '2020.2') {
    Write-Output 'NOTE=local tool is not the 2020.2 target toolchain; do not call this a 2020.2 build pass'
}

$requiredRtl = @(
    'rtl/common/rv_fifo.sv',
    'rtl/common/runtime_relu_quant.sv',
    'rtl/compute/mac_lane.sv',
    'rtl/memory/banked_activation_buffer.sv',
    'rtl/memory/local_weight_provider.sv',
    'rtl/compute/vector_dot_product_core.sv',
    'rtl/compute/dense_layer_engine.sv',
    'rtl/control/mlp_sequence_controller.sv',
    'rtl/top/dlrm_f37x_rtl_kernel.sv',
    'rtl/interaction/dlrm_feature_interaction_engine.sv',
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv',
    'rtl/control/mlp_sequence_controller_segmented.sv',
    'rtl/pipeline/dlrm_internal_pipeline_controller.sv',
    'rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv',
    'rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv',
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv',
    'rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv',
    'rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv',
    'rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv',
    'tb/tb_dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv'
)

$missing = @()
foreach ($rel in $requiredRtl) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $rel))) {
        $missing += $rel
    }
}
if ($missing.Count -gt 0) {
    Write-Output 'COMPILE=NOT_RUN'
    Write-Output 'ELAB=NOT_RUN'
    Write-Output 'SIM=NOT_RUN'
    Write-Output 'XSIM=NOT_RUN'
    Write-Output 'REASON=required frozen A13/A14/A16/A17 RTL is missing from this worktree'
    $missing | ForEach-Object { Write-Output "MISSING=$_" }
    exit 3
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$ResultDir = Join-Path $RepoRoot "results\stage2n_a18\$stamp"
New-Item -ItemType Directory -Path $ResultDir | Out-Null
Write-Output "RESULT_DIR=$ResultDir"

$sources = @($requiredRtl | ForEach-Object { Join-Path $RepoRoot $_ })
$tcl = Join-Path $RepoRoot 'scripts\run_stage2n_a18_variable_index_xsim_v1.tcl'
$top = 'tb_dlrm_f37x_rtl_kernel_stage2n_a18_v1'

$requiredMarkers = @(
    'A18_1_DEFAULT_INDEX_RESET=PASS'
    'A18_1_CASE_A_DEFAULT_37_40_GOLDEN36=PASS'
    'A18_1_CASE_B_ROWS_1_2_3_4=PASS'
    'A18_1_CASE_C_ROWS_0_63=PASS'
    'A18_1_CASE_C_ALL_SEVEN=PASS'
    'A18_1_CASE_D_TWO_TASKS=PASS'
    'A18_1_CASE_E_BUSY_WRITE_AND_RESTART=PASS'
    'A18_1_CASE_F_BACKPRESSURE_BANK3_FIRST=PASS'
    'A18_1_CASE_G_RRESP_ERROR=PASS'
    'A18_1_CASE_H_OOB_64=PASS'
    'A18_1_CASE_H_OOB_FFFFFFFF=PASS'
    'STAGE2N_A18_VARIABLE_INDEX_XSIM_V1_PASS'
)

function Write-StatusFile {
    param([string[]]$Lines)
    $Lines | Set-Content -LiteralPath (Join-Path $ResultDir 'status.txt')
}

Push-Location $ResultDir
$compile = 'NOT_RUN'
$elab = 'NOT_RUN'
$sim = 'NOT_RUN'
try {
    $env:PATH = "$VivadoBin;" + $env:PATH
    & $xvlog --sv @sources 2>&1 | Tee-Object -FilePath 'xvlog.console.log' | Out-Host
    if ($LASTEXITCODE -ne 0) {
        $compile = 'FAIL'
        throw "xvlog failed $LASTEXITCODE"
    }
    $compile = 'PASS'

    & $xelab $top -s a18_variable_index_test --timescale 1ns/1ps 2>&1 |
        Tee-Object -FilePath 'xelab.console.log' | Out-Host
    if ($LASTEXITCODE -ne 0) {
        $elab = 'FAIL'
        throw "xelab failed $LASTEXITCODE"
    }
    $elab = 'PASS'

    & $xsim a18_variable_index_test -tclbatch ($tcl.Replace('\', '/')) 2>&1 |
        Tee-Object -FilePath 'xsim.console.log' | Out-Host
    $xsimExit = $LASTEXITCODE
    if ($xsimExit -ne 0) {
        $sim = 'FAIL'
        throw "xsim exit $xsimExit"
    }

    $log = Get-Content -LiteralPath 'xsim.console.log'
    $missingMarkers = @()
    foreach ($m in $requiredMarkers) {
        if (-not ($log | Where-Object { $_ -eq $m })) {
            $missingMarkers += $m
        }
    }
    if ($missingMarkers.Count -gt 0) {
        $sim = 'FAIL'
        throw ("xsim exit 0 but missing TB markers: " + ($missingMarkers -join ','))
    }
    if ($log | Where-Object { $_ -like 'A18_XSIM_RUN_ERROR=*' }) {
        $sim = 'FAIL'
        throw 'xsim exit 0 but Tcl reported A18_XSIM_RUN_ERROR'
    }

    $sim = 'PASS'
    Write-StatusFile @(
        "TOOL=Vivado/XSim $toolVersion"
        'COMPILE=PASS'
        'ELAB=PASS'
        'SIM=PASS'
        'XSIM=PASS'
        "RESULT_DIR=$ResultDir"
        'NOTE=local tool result; not a 2020.2 target build'
        'STAGE2N_A18_VARIABLE_INDEX_XSIM_V1_PASS'
    )
    Write-Output 'COMPILE=PASS'
    Write-Output 'ELAB=PASS'
    Write-Output 'SIM=PASS'
    Write-Output 'XSIM=PASS'
    Write-Output "RESULT_DIR=$ResultDir"
}
catch {
    Write-StatusFile @(
        "TOOL=Vivado/XSim $toolVersion"
        "COMPILE=$compile"
        "ELAB=$elab"
        "SIM=$sim"
        'XSIM=FAIL'
        "RESULT_DIR=$ResultDir"
        "ERROR=$($_.Exception.Message)"
    )
    Write-Output "COMPILE=$compile"
    Write-Output "ELAB=$elab"
    Write-Output "SIM=$sim"
    Write-Output 'XSIM=FAIL'
    Write-Output $_
    exit 1
}
finally {
    Pop-Location
}
