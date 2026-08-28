param(
    [string]$PythonExe = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$resultDir = Join-Path $repoRoot 'results\stage2n_a15_5\local_preparation_v1'
$statusPath = Join-Path $resultDir 'a15_5_local_preparation_v1_status.txt'
$transcriptPath = Join-Path $resultDir 'command_transcript.log'
$xoSelfTestLog = Join-Path $resultDir 'xo_validator_self_test.log'
$xclbinSelfTestLog = Join-Path $resultDir 'xclbin_validator_self_test.log'

$expectedBranch = 'work/stage2n-a15-hbm-pipeline-integration'
$authorizationBaseline = '0c705a360a036785e4c949185fcb5cc1dcc4f07f'
$acceptedWrapperHash = 'c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1'

$preparationStatus = 'NOT_RUN'
$pythonSyntax = 'NOT_RUN'
$xoSelfTest = 'NOT_RUN'
$xclbinSelfTest = 'NOT_RUN'
$bashSyntax = 'NOT_RUN'
$failReason = 'NONE'
$branch = 'NOT_RECORDED'
$head = 'NOT_RECORDED'
$transcriptStarted = $false

function Write-Status {
    $lines = @(
        'A15_5_FLOW=LOCAL_PREPARATION_V1'
        "A15_5_LOCAL_PREPARATION=$preparationStatus"
        "A15_5_PYTHON_SYNTAX=$pythonSyntax"
        "A15_5_XO_VALIDATOR_SELF_TEST=$xoSelfTest"
        "A15_5_XCLBIN_VALIDATOR_SELF_TEST=$xclbinSelfTest"
        "A15_5_BASH_SYNTAX=$bashSyntax"
        'A15_5_TARGET_XO_BUILD=NOT_RUN'
        'A15_5_TARGET_XO_VALIDATION=NOT_RUN'
        'A15_5_TARGET_LINK=NOT_RUN'
        'A15_5_XCLBIN=NOT_RUN'
        'A15_5_PHYSICAL_HBM=NOT_VALIDATED'
        'A15_5_FPGA_DEVICE_ACCESS=NONE'
        'A15_5_NETWORK_ACCESS=NONE'
        'A15_5_SERVER_ACCESS=NONE'
        'A15_5_READY_FOR_BOARD=NO'
        "FAIL_REASON=$failReason"
        "GIT_BRANCH=$branch"
        "GIT_HEAD=$head"
        'KERNEL=dlrm_f37x_rtl_kernel_stage2n_a15_v1'
        'COMPUTE_UNIT=dlrm_a15_1'
        'TARGET_PART=xcvu37p-fsvh2892-2L-e'
        'PLATFORM_VBNV=inspur_f37x_xdma_201920_3'
        'REQUESTED_CLOCK_MHZ=100'
        'CONNECTIVITY=dlrm_a15_1.m_axi_gmem:HBM[0]'
        'M_AXI_MASTER_COUNT=1'
        'KERNEL_ARGUMENT_COUNT=1'
        'TABLE_BASE_OFFSET=0x304'
    )
    Set-Content -LiteralPath $statusPath -Value $lines -Encoding ascii
}

function Assert-Contains {
    param([string]$Text, [string]$Fragment, [string]$Description)
    if (-not $Text.Contains($Fragment)) {
        throw "missing $Description"
    }
}

function Resolve-Python {
    if ($PythonExe) {
        return (Resolve-Path -LiteralPath $PythonExe).Path
    }
    $candidates = @()
    $bundled = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $bundled) {
        $candidates += $bundled
    }
    foreach ($name in @('python.exe', 'python3.exe', 'python', 'python3')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command -and $command.CommandType -ne 'Alias') {
            $candidates += $command.Source
        }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        & $candidate --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return $candidate
        }
    }
    throw 'no working Python 3 executable found'
}

if (Test-Path -LiteralPath $resultDir) {
    throw "refusing to overwrite existing result directory: $resultDir"
}
New-Item -ItemType Directory -Path $resultDir | Out-Null

try {
    Start-Transcript -LiteralPath $transcriptPath | Out-Null
    $transcriptStarted = $true
    Set-Location -LiteralPath $repoRoot

    $branch = (git branch --show-current).Trim()
    $head = (git rev-parse HEAD).Trim()
    if ($branch -ne $expectedBranch) {
        throw "wrong branch: $branch"
    }
    git merge-base --is-ancestor $authorizationBaseline HEAD
    if ($LASTEXITCODE -ne 0) {
        throw 'A15.5 authorization baseline is not an ancestor of HEAD'
    }

    $requiredFiles = @(
        'config/stage2n_a15_5_target_v1.cfg'
        'scripts/package_stage2n_a15_5_rtl_kernel_v1.tcl'
        'scripts/build_stage2n_a15_5_target_xo_v1.sh'
        'scripts/link_stage2n_a15_5_target_v1.sh'
        'scripts/report_stage2n_a15_5_vitis_post_route_v1.tcl'
        'scripts/validate_stage2n_a15_5_xo_v1.py'
        'scripts/validate_stage2n_a15_5_xclbin_v1.py'
        'scripts/run_stage2n_a15_5_local_preparation_v1.ps1'
        'docs/STAGE2N_A15_5_TARGET_XO_XCLBIN_PREPARATION_V1.md'
    )
    foreach ($relative in $requiredFiles) {
        $path = Join-Path $repoRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "required A15.5 file missing: $relative"
        }
    }

    $wrapper = Join-Path $repoRoot 'rtl\f37x\dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv'
    $actualWrapperHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $wrapper).Hash.ToLowerInvariant()
    if ($actualWrapperHash -ne $acceptedWrapperHash) {
        throw 'accepted A15.4 wrapper SHA256 changed'
    }

    $cfgLines = Get-Content -LiteralPath (Join-Path $repoRoot 'config\stage2n_a15_5_target_v1.cfg') |
        ForEach-Object { ($_ -split '#', 2)[0].Trim() } |
        Where-Object { $_ }
    $expectedCfg = @(
        '[connectivity]'
        'nk=dlrm_f37x_rtl_kernel_stage2n_a15_v1:1:dlrm_a15_1'
        'sp=dlrm_a15_1.m_axi_gmem:HBM[0]'
    )
    if (($cfgLines -join "`n") -ne ($expectedCfg -join "`n")) {
        throw 'A15.5 connectivity file is not the exact one-CU/one-HBM[0] contract'
    }

    $packageText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'scripts\package_stage2n_a15_5_rtl_kernel_v1.tcl')
    Assert-Contains $packageText 'set top_name "dlrm_f37x_rtl_kernel_stage2n_a15_v1"' 'A15.4 package top'
    Assert-Contains $packageText 'set target_part_name "xcvu37p-fsvh2892-2L-e"' 'target part'
    Assert-Contains $packageText '$address_block TABLE_BASE 0x304 64 read-write' 'TABLE_BASE package register'
    Assert-Contains $packageText 'set_required_bus_parameter $m_axi_gmem DATA_WIDTH 128' '128-bit memory data width'
    Assert-Contains $packageText 'set_required_bus_parameter $m_axi_gmem ADDR_WIDTH 64' '64-bit memory address width'
    $sourceCount = ([regex]::Matches($packageText, '\[source_path\s+\$root_dir\s+[^\]\s]+\]')).Count
    if ($sourceCount -ne 17) {
        throw "package source count is $sourceCount, expected 17"
    }

    foreach ($shellRelative in @(
        'scripts\build_stage2n_a15_5_target_xo_v1.sh'
        'scripts\link_stage2n_a15_5_target_v1.sh'
    )) {
        $shellText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $shellRelative)
        Assert-Contains $shellText 'set -Eeuo pipefail' "$shellRelative fail-closed mode"
        Assert-Contains $shellText 'work/stage2n-a15-hbm-pipeline-integration' "$shellRelative branch gate"
        Assert-Contains $shellText 'xcvu37p-fsvh2892-2L-e' "$shellRelative target part"
        $activeCode = (($shellText -split "`r?`n") |
            ForEach-Object { ($_ -split '#', 2)[0] }) -join "`n"
        foreach ($forbidden in @('xbutil', 'xbmgmt', 'ssh ', 'scp ', 'rsync ', '/home/chaosuan')) {
            if ($activeCode.ToLowerInvariant().Contains($forbidden.ToLowerInvariant())) {
                throw "$shellRelative contains forbidden active operation: $forbidden"
            }
        }
    }

    $python = Resolve-Python
    "PYTHON=$python"
    $validators = @(
        'scripts\validate_stage2n_a15_5_xo_v1.py'
        'scripts\validate_stage2n_a15_5_xclbin_v1.py'
    )
    foreach ($relative in $validators) {
        $absolute = Join-Path $repoRoot $relative
        & $python -c "import pathlib; p=pathlib.Path(r'$absolute'); compile(p.read_text(encoding='utf-8'), str(p), 'exec')"
        if ($LASTEXITCODE -ne 0) {
            throw "Python syntax check failed: $relative"
        }
    }
    $pythonSyntax = 'PASS'

    & $python (Join-Path $repoRoot 'scripts\validate_stage2n_a15_5_xo_v1.py') --self-test 2>&1 |
        Tee-Object -LiteralPath $xoSelfTestLog
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $xoSelfTestLog -Pattern 'A15_5_XO_VALIDATOR_SELF_TEST=PASS' -SimpleMatch -Quiet)) {
        throw 'XO validator self-test failed'
    }
    $xoSelfTest = 'PASS'

    & $python (Join-Path $repoRoot 'scripts\validate_stage2n_a15_5_xclbin_v1.py') --self-test 2>&1 |
        Tee-Object -LiteralPath $xclbinSelfTestLog
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $xclbinSelfTestLog -Pattern 'A15_5_XCLBIN_VALIDATOR_SELF_TEST=PASS' -SimpleMatch -Quiet)) {
        throw 'xclbin validator self-test failed'
    }
    $xclbinSelfTest = 'PASS'

    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($null -ne $bash) {
        foreach ($relative in @(
            'scripts/build_stage2n_a15_5_target_xo_v1.sh'
            'scripts/link_stage2n_a15_5_target_v1.sh'
        )) {
            & $bash.Source -n (Join-Path $repoRoot $relative)
            if ($LASTEXITCODE -ne 0) {
                throw "bash -n failed: $relative"
            }
        }
        $bashSyntax = 'PASS'
    } else {
        $bashSyntax = 'NOT_RUN'
        'BASH_SYNTAX_NOTE=bash executable is unavailable in the local Windows environment'
    }

    $preparationStatus = 'PASS'
    Write-Status
} catch {
    $preparationStatus = 'FAIL'
    $failReason = $_.Exception.Message.Replace("`r", ' ').Replace("`n", ' ')
    Write-Status
    throw
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
    Set-Location -LiteralPath $repoRoot
}

Get-Content -LiteralPath $statusPath
