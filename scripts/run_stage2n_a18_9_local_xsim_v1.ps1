# Local 2022.1 XSim for A18.5 mapper / A18.9 fold / 4-line cache / folded lookup.
# Never a 2020.2 or board result. Does not program or reset.

[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [string]$VivadoBin = "",
    [string]$Test = "all"
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

$tcl = Join-Path $RepoRoot 'scripts\run_stage2n_a18_9_local_xsim_v1.tcl'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$ResultRoot = Join-Path $RepoRoot "results\stage2n_a18_9\$stamp"
New-Item -ItemType Directory -Path $ResultRoot | Out-Null

$tests = @{
    mapper = @{
        Top = 'tb_dlrm_table_bank_mapper_stage2n_a18_5_v1'
        Marker = 'TB_A18_5_MAPPER=PASS'
        Sources = @(
            'rtl/hbm/dlrm_table_bank_mapper_stage2n_a18_5_v1.sv',
            'tb/tb_dlrm_table_bank_mapper_stage2n_a18_5_v1.sv'
        )
    }
    fold = @{
        Top = 'tb_dlrm_t8_pair_fold_stage2n_a18_9_v1'
        Marker = 'TB_A18_9_PAIR_FOLD=PASS'
        Sources = @(
            'rtl/hbm/dlrm_t8_pair_fold_stage2n_a18_9_v1.sv',
            'tb/tb_dlrm_t8_pair_fold_stage2n_a18_9_v1.sv'
        )
    }
    cache4 = @{
        Top = 'tb_dlrm_hbm_bank_line_cache_stage2n_a18_9_v1'
        Marker = 'TB_A18_9_LINE_CACHE=PASS'
        Sources = @(
            'rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv',
            'rtl/hbm/dlrm_hbm_bank_line_cache_stage2n_a18_9_v1.sv',
            'tb/tb_dlrm_hbm_bank_line_cache_stage2n_a18_9_v1.sv'
        )
    }
    folded = @{
        Top = 'tb_dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1'
        Marker = 'TB_A18_9_FOLDED_LOOKUP=PASS'
        Sources = @(
            'rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv',
            'rtl/hbm/dlrm_table_bank_mapper_stage2n_a18_5_v1.sv',
            'rtl/hbm/dlrm_hbm_bank_line_cache_stage2n_a18_9_v1.sv',
            'rtl/hbm/dlrm_t8_pair_fold_stage2n_a18_9_v1.sv',
            'rtl/hbm/dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1.sv',
            'tb/tb_dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1.sv'
        )
    }
}

$order = @('mapper', 'fold', 'cache4', 'folded')
if ($Test -ne 'all') {
    if (-not $tests.ContainsKey($Test)) { throw "unknown test $Test" }
    $order = @($Test)
}

$env:PATH = "$VivadoBin;" + $env:PATH
$failed = $false
foreach ($name in $order) {
    $spec = $tests[$name]
    $dir = Join-Path $ResultRoot $name
    New-Item -ItemType Directory -Path $dir | Out-Null
    Write-Output "A18_9_XSIM_TEST=$name"
    Push-Location $dir
    try {
        $src = @($spec.Sources | ForEach-Object { Join-Path $RepoRoot $_ })
        & $xvlog --sv @src 2>&1 | Tee-Object -FilePath 'xvlog.console.log' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "xvlog $name" }
        $snap = "a18_9_$name"
        & $xelab $spec.Top -s $snap --timescale 1ns/1ps 2>&1 |
            Tee-Object -FilePath 'xelab.console.log' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "xelab $name" }
        & $xsim $snap -tclbatch ($tcl.Replace('\', '/')) 2>&1 |
            Tee-Object -FilePath 'xsim.console.log' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "xsim $name" }
        $log = Get-Content -LiteralPath 'xsim.console.log'
        if ($log | Where-Object { $_ -like 'FAIL *' -or $_ -like '*=FAIL*' }) {
            throw "TB printed FAIL"
        }
        if (-not ($log | Where-Object { $_ -eq $spec.Marker })) {
            throw "missing marker $($spec.Marker)"
        }
        Write-Output "A18_9_XSIM_$($name.ToUpper())=PASS"
        "PASS" | Set-Content 'status.txt'
    }
    catch {
        $failed = $true
        Write-Output "A18_9_XSIM_$($name.ToUpper())=FAIL"
        Write-Output $_
        "FAIL $($_.Exception.Message)" | Set-Content 'status.txt'
    }
    finally {
        Pop-Location
    }
}

Write-Output "RESULT_DIR=$ResultRoot"
Write-Output 'NOTE=local Vivado 2022.1 only; not 2020.2; not FPGA'
Write-Output 'PERFORMANCE=NOT_CLAIMED'
if ($failed) {
    Write-Output 'A18_9_LOCAL_XSIM=FAIL'
    exit 1
}
Write-Output 'A18_9_LOCAL_XSIM=PASS'
exit 0
