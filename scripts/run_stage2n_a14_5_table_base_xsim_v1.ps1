param(
    [string]$VivadoBin =
        'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin',
    [string]$ResultDir = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..'))

if ([string]::IsNullOrWhiteSpace($ResultDir)) {
    $ResultDir = Join-Path $repoRoot `
        'results\stage2n_a14_5_table_base_xsim_v1'
}
$ResultDir = [System.IO.Path]::GetFullPath($ResultDir)

$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'
$statusPath = Join-Path $ResultDir 'status.txt'
$branch = 'NOT_RECORDED'
$head = 'NOT_RECORDED'
$activeCase = 'PRECHECK'
$resultRootCreated = $false

function Fail([string]$Message) {
    throw "Stage 2N-A14.5 XSim failed: $Message"
}

function Invoke-XSimCase {
    param(
        [string]$Name,
        [string]$Top,
        [string]$Snapshot,
        [string[]]$Sources,
        [string]$PassMarker
    )

    $caseDir = Join-Path $ResultDir $Name
    $workDir = Join-Path $caseDir 'work'
    New-Item -ItemType Directory -Path $workDir | Out-Null

    foreach ($source in $Sources) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            Fail "missing source $source"
        }
    }

    Push-Location $workDir
    try {
        & $xvlog --sv @Sources 2>&1 |
            Tee-Object -LiteralPath (Join-Path $caseDir 'xvlog.log') |
            Out-Host
        $xvlogExit = $LASTEXITCODE
        if ($xvlogExit -ne 0) {
            Fail "$Name xvlog returned $xvlogExit"
        }

        & $xelab $Top -s $Snapshot --timescale 1ns/1ps 2>&1 |
            Tee-Object -LiteralPath (Join-Path $caseDir 'xelab.log') |
            Out-Host
        $xelabExit = $LASTEXITCODE
        if ($xelabExit -ne 0) {
            Fail "$Name xelab returned $xelabExit"
        }

        & $xsim $Snapshot -runall 2>&1 |
            Tee-Object -LiteralPath (Join-Path $caseDir 'xsim.log') |
            Out-Host
        $xsimExit = $LASTEXITCODE
        if ($xsimExit -ne 0) {
            Fail "$Name xsim returned $xsimExit"
        }
    } finally {
        Pop-Location
    }

    $logs = @(
        (Join-Path $caseDir 'xvlog.log'),
        (Join-Path $caseDir 'xelab.log'),
        (Join-Path $caseDir 'xsim.log')
    )
    $passCount = @(
        Select-String -LiteralPath (Join-Path $caseDir 'xsim.log') `
            -SimpleMatch $PassMarker
    ).Count
    $errors = @(
        Select-String -LiteralPath $logs `
            -Pattern '^(ERROR:|FATAL:)' -ErrorAction SilentlyContinue
    )
    if ($passCount -ne 1) {
        Fail "$Name PASS marker missing or duplicated"
    }
    if ($errors.Count -ne 0) {
        Fail "$Name anchored error/fatal count is $($errors.Count)"
    }

    return [pscustomobject]@{
        Name = $Name
        PassMarker = $PassMarker
        ErrorFatalCount = $errors.Count
    }
}

Push-Location $repoRoot
try {
    foreach ($tool in @($xvlog, $xelab, $xsim)) {
        if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
            Fail "missing Vivado simulator tool $tool"
        }
    }
    if (Test-Path -LiteralPath $ResultDir) {
        Fail "result directory already exists: $ResultDir"
    }

    New-Item -ItemType Directory -Path $ResultDir | Out-Null
    $resultRootCreated = $true
    $branch = (git symbolic-ref --short HEAD).Trim()
    $head = (git rev-parse HEAD).Trim()
    @(
        'STAGE2N_A14_5_TABLE_BASE_XSIM=RUNNING'
        "BRANCH=$branch"
        "HEAD=$head"
        'ACTIVE_CASE=PRECHECK'
        'NO_VPP_LINK=1'
        'NO_XCLBIN=1'
        'NO_PHYSICAL_HBM_BINDING=1'
        'NO_FPGA_ACCESS=1'
    ) | Set-Content -LiteralPath $statusPath -Encoding UTF8

    $activeCase = 'lookup_v2'
    $lookupResult = Invoke-XSimCase `
        -Name 'lookup_v2' `
        -Top 'tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2' `
        -Snapshot 'tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2_sim' `
        -Sources @(
            (Join-Path $repoRoot `
                'rtl\hbm\dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv'),
            (Join-Path $repoRoot `
                'tb\tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv')
        ) `
        -PassMarker `
            'tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2: PASS cases=67 valid=64 rejected=3 ar=64 r=64'

    $activeCase = 'wrapper_v2'
    $wrapperResult = Invoke-XSimCase `
        -Name 'wrapper_v2' `
        -Top 'tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2' `
        -Snapshot 'tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2_sim' `
        -Sources @(
            (Join-Path $repoRoot `
                'rtl\hbm\dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv'),
            (Join-Path $repoRoot `
                'rtl\f37x\dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv'),
            (Join-Path $repoRoot `
                'tb\tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv')
        ) `
        -PassMarker `
            'tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2: PASS cases=17 valid=14 rejected=3 ar=14 r=14'

    $status = @(
        'STAGE2N_A14_5_TABLE_BASE_XSIM=PASS'
        "BRANCH=$branch"
        "HEAD=$head"
        'LOOKUP_V2_CASES=67'
        'LOOKUP_V2_VALID_READS=64'
        'LOOKUP_V2_REJECTED_REQUESTS=3'
        'WRAPPER_V2_CASES=17'
        'WRAPPER_V2_VALID_READS=14'
        'WRAPPER_V2_REJECTED_REQUESTS=3'
        'UNALIGNED_BASE_GUARD=PASS'
        'OUT_OF_RANGE_INDEX_GUARD=PASS'
        'ADDRESS_OVERFLOW_GUARD=PASS'
        'TABLE_BASE_READBACK=PASS'
        'HIGH_ADDRESS_ABOVE_4GB=PASS'
        'M_AXI_ADDR_WIDTH=64'
        'M_AXI_DATA_WIDTH=128'
        "LOOKUP_ERROR_FATAL_COUNT=$($lookupResult.ErrorFatalCount)"
        "WRAPPER_ERROR_FATAL_COUNT=$($wrapperResult.ErrorFatalCount)"
        'NO_VPP_LINK=1'
        'NO_XCLBIN=1'
        'NO_PHYSICAL_HBM_BINDING=1'
        'NO_FPGA_ACCESS=1'
    )
    $status | Set-Content -LiteralPath `
        $statusPath -Encoding UTF8
    Write-Output ($status -join [Environment]::NewLine)
} catch {
    if ($resultRootCreated -and
        (Test-Path -LiteralPath $ResultDir -PathType Container)) {
        $failureReason = $_.Exception.Message -replace '[\r\n]+', ' '
        @(
            'STAGE2N_A14_5_TABLE_BASE_XSIM=FAIL'
            "BRANCH=$branch"
            "HEAD=$head"
            "ACTIVE_CASE=$activeCase"
            "FAIL_REASON=$failureReason"
            'NO_VPP_LINK=1'
            'NO_XCLBIN=1'
            'NO_PHYSICAL_HBM_BINDING=1'
            'NO_FPGA_ACCESS=1'
        ) | Set-Content -LiteralPath $statusPath -Encoding UTF8
    }
    throw
} finally {
    Pop-Location
}
