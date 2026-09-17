# Local 2022.1 XSim for A18.10 folded-inject.
# Never a 2020.2 or board result. Does not program or reset.

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
        'C:\Xilinx\Vivado\2022.1\bin'
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
    Write-Output 'XSIM=NOT_RUN'
    Write-Output 'REASON=Vivado/XSim not found locally; installer was not invoked'
    exit 2
}

$tcl = Join-Path $RepoRoot 'scripts\run_stage2n_a18_10_local_xsim_v1.tcl'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$ResultRoot = Join-Path $RepoRoot "results\stage2n_a18_10\$stamp"
New-Item -ItemType Directory -Path $ResultRoot | Out-Null

$Top = 'tb_dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1'
$Marker = 'TB_A18_10_FOLDED_INJECT=PASS'
$Sources = @(
    'rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv',
    'rtl/hbm/dlrm_table_bank_mapper_stage2n_a18_5_v1.sv',
    'rtl/hbm/dlrm_hbm_bank_line_cache_stage2n_a18_9_v1.sv',
    'rtl/hbm/dlrm_t8_pair_fold_stage2n_a18_9_v1.sv',
    'rtl/hbm/dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1.sv',
    'rtl/hbm/dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1.sv',
    'tb/tb_dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1.sv'
)

$env:PATH = "$VivadoBin;" + $env:PATH
Push-Location $ResultRoot
try {
    $src = @($Sources | ForEach-Object { Join-Path $RepoRoot $_ })
    & $xvlog --sv @src 2>&1 | Tee-Object -FilePath 'xvlog.console.log' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'xvlog' }
    & $xelab $Top -s a18_10_inject --timescale 1ns/1ps 2>&1 |
        Tee-Object -FilePath 'xelab.console.log' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'xelab' }
    & $xsim a18_10_inject -tclbatch ($tcl.Replace('\', '/')) 2>&1 |
        Tee-Object -FilePath 'xsim.console.log' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'xsim' }
    $log = Get-Content -LiteralPath 'xsim.console.log'
    if ($log | Where-Object { $_ -like 'FAIL *' -or $_ -like '*=FAIL*' }) {
        throw 'TB printed FAIL'
    }
    if (-not ($log | Where-Object { $_ -eq $Marker })) {
        throw "missing marker $Marker"
    }
    'PASS' | Set-Content 'status.txt'
    Write-Output 'A18_10_XSIM_INJECT=PASS'
    Write-Output "RESULT_DIR=$ResultRoot"
    Write-Output 'NOTE=local Vivado 2022.1 only; not 2020.2; not FPGA'
    Write-Output 'PERFORMANCE=NOT_CLAIMED'
    Write-Output 'A18_10_LOCAL_XSIM=PASS'
    exit 0
}
catch {
    "FAIL $($_.Exception.Message)" | Set-Content 'status.txt'
    Write-Output 'A18_10_LOCAL_XSIM=FAIL'
    Write-Output $_
    Write-Output "RESULT_DIR=$ResultRoot"
    exit 1
}
finally {
    Pop-Location
}
