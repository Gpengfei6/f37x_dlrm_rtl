[CmdletBinding()]
param(
    [Parameter()]
    [string]$VivadoExe = "",

    [Parameter()]
    [string]$ResultDir = "results/stage2f"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Resolve-RepositoryChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    if ([System.IO.Path]::IsPathRooted($Candidate)) {
        $fullCandidate = [System.IO.Path]::GetFullPath($Candidate)
    }
    else {
        $fullCandidate = [System.IO.Path]::GetFullPath(
            (Join-Path -Path $RepositoryRoot -ChildPath $Candidate)
        )
    }

    $rootWithSeparator = $RepositoryRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $fullCandidate.StartsWith(
            $rootWithSeparator,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Generated directory must be a child of the repository: $fullCandidate"
    }

    return $fullCandidate
}

function Resolve-VivadoExecutable {
    param(
        [Parameter()]
        [string]$RequestedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (Test-Path -LiteralPath $RequestedPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $RequestedPath).Path
        }

        $requestedCommand = Get-Command -Name $RequestedPath -ErrorAction SilentlyContinue
        if ($null -ne $requestedCommand) {
            return $requestedCommand.Source
        }

        throw "Vivado executable was not found: $RequestedPath"
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:XILINX_VIVADO)) {
        $candidates.Add((Join-Path $env:XILINX_VIVADO "bin/vivado.bat"))
    }
    $candidates.Add("D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat")
    $candidates.Add("D:\Xilinx\Vivado\2022.1\bin\vivado.bat")
    $candidates.Add("C:\Xilinx\Vivado\2022.1\bin\vivado.bat")

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    foreach ($commandName in @("vivado.bat", "vivado")) {
        $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "Vivado was not found. Pass -VivadoExe or set XILINX_VIVADO."
}

function Read-KeyValueStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $status = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $separator = $line.IndexOf("=")
        if ($separator -gt 0) {
            $key = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1)
            $status[$key] = $value
        }
    }
    return $status
}

$projectRoot = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $PSScriptRoot -ChildPath "..")
).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$resolvedResultDir = Resolve-RepositoryChildPath `
    -Candidate $ResultDir `
    -RepositoryRoot $projectRoot
$resolvedVivado = Resolve-VivadoExecutable -RequestedPath $VivadoExe

$logsDir = Join-Path $projectRoot "logs"
[System.IO.Directory]::CreateDirectory($logsDir) | Out-Null
$vivadoLog = Join-Path $logsDir "vivado_stage2f_post_route.log"
$consoleLog = Join-Path $logsDir "stage2f_post_route_console.log"
$tclScript = Join-Path $projectRoot "scripts/run_stage2f_post_route.tcl"
$statusPath = Join-Path $resolvedResultDir "stage2f_post_route_status.txt"
$requiredArtifacts = @(
    "post_synth.dcp",
    "post_opt.dcp",
    "post_place.dcp",
    "post_route.dcp",
    "post_route_timing_summary.rpt",
    "post_route_utilization.rpt",
    "post_route_route_status.rpt",
    "post_route_drc.rpt",
    "post_route_methodology.rpt",
    "post_route_clock_utilization.rpt",
    "post_route_high_fanout.rpt",
    "post_route_congestion.rpt",
    "post_route_power.rpt"
)

if (-not (Test-Path -LiteralPath $tclScript -PathType Leaf)) {
    throw "Stage 2F Tcl driver is missing: $tclScript"
}

Write-Host "Stage 2F local Artix-7 post-route precheck"
Write-Host "Repository : $projectRoot"
Write-Host "Vivado     : $resolvedVivado"
Write-Host "Result dir : $resolvedResultDir"
Write-Host "Part       : xc7a200tfbg484-2"
Write-Host "Clock      : 10.000 ns (100 MHz)"

$previousResultDir = $env:STAGE2F_RESULT_DIR
$vivadoOutput = @()
$vivadoExitCode = 1
$vivadoArguments = @(
    "-mode",
    "batch",
    "-nojournal",
    "-log",
    $vivadoLog,
    "-source",
    $tclScript
)
try {
    $env:STAGE2F_RESULT_DIR = $resolvedResultDir
    Push-Location $projectRoot
    try {
        $vivadoOutput = @(
            & $resolvedVivado @vivadoArguments 2>&1 |
                ForEach-Object { $_.ToString() }
        )
        $vivadoExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($null -eq $previousResultDir) {
        Remove-Item Env:STAGE2F_RESULT_DIR -ErrorAction SilentlyContinue
    }
    else {
        $env:STAGE2F_RESULT_DIR = $previousResultDir
    }
}

$consoleText = ($vivadoOutput -join [Environment]::NewLine) +
    [Environment]::NewLine
Write-Utf8NoBom -Path $consoleLog -Text $consoleText
$vivadoOutput | ForEach-Object { Write-Host $_ }

if (-not (Test-Path -LiteralPath $vivadoLog -PathType Leaf)) {
    throw "Vivado did not create its log: $vivadoLog"
}

$vivadoLogLines = [System.IO.File]::ReadAllLines($vivadoLog)
$errorCount = @($vivadoLogLines | Where-Object { $_ -match '^ERROR:' }).Count
$criticalWarningCount = @(
    $vivadoLogLines | Where-Object { $_ -match '^CRITICAL WARNING:' }
).Count

if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
    throw "Stage 2F status file is missing (Vivado exit $vivadoExitCode): $statusPath"
}

$statusText = [System.IO.File]::ReadAllText($statusPath)
if ($statusText -notmatch '(?m)^ERROR_COUNT=') {
    throw "Stage 2F status is missing ERROR_COUNT: $statusPath"
}
if ($statusText -notmatch '(?m)^CRITICAL_WARNING_COUNT=') {
    throw "Stage 2F status is missing CRITICAL_WARNING_COUNT: $statusPath"
}
$statusText = [System.Text.RegularExpressions.Regex]::Replace(
    $statusText,
    '(?m)^ERROR_COUNT=.*$',
    "ERROR_COUNT=$errorCount"
)
$statusText = [System.Text.RegularExpressions.Regex]::Replace(
    $statusText,
    '(?m)^CRITICAL_WARNING_COUNT=.*$',
    "CRITICAL_WARNING_COUNT=$criticalWarningCount"
)
Write-Utf8NoBom -Path $statusPath -Text $statusText

$firstStatusLine = [System.IO.File]::ReadLines($statusPath) |
    Select-Object -First 1
$status = Read-KeyValueStatus -Path $statusPath
$requiredFields = @(
    "TOP",
    "PART",
    "CLOCK_PERIOD_NS",
    "SYNTH_STATE",
    "OPT_STATE",
    "PLACE_STATE",
    "PHYS_OPT_STATE",
    "ROUTE_STATE",
    "SETUP_WNS_NS",
    "SETUP_TNS_NS",
    "SETUP_FAILING_ENDPOINTS",
    "HOLD_WHS_NS",
    "HOLD_THS_NS",
    "HOLD_FAILING_ENDPOINTS",
    "UNROUTED_NETS",
    "LATCH_COUNT",
    "TOTAL_LUTS",
    "LOGIC_LUTS",
    "LUTRAMS",
    "SRLS",
    "FFS",
    "RAMB36",
    "RAMB18",
    "DSP_BLOCKS",
    "ERROR_COUNT",
    "CRITICAL_WARNING_COUNT",
    "DRC_ERROR_COUNT",
    "DRC_CRITICAL_WARNING_COUNT",
    "METHODOLOGY_CRITICAL_WARNING_COUNT",
    "POWER_REPORT_STATE",
    "TIMING_STATE"
)
foreach ($field in $requiredFields) {
    if (-not $status.ContainsKey($field)) {
        throw "Stage 2F status is missing required field: $field"
    }
}

$failures = New-Object System.Collections.Generic.List[string]
if ($vivadoExitCode -ne 0) {
    $failures.Add("Vivado exited with code $vivadoExitCode")
}
if ($firstStatusLine -ne "STAGE2F_RUN_COMPLETE") {
    $failures.Add("run marker is $firstStatusLine")
}
if ($status["TOP"] -ne "mlp_sequence_controller") {
    $failures.Add("TOP=$($status['TOP'])")
}
if ($status["PART"] -ne "xc7a200tfbg484-2") {
    $failures.Add("PART=$($status['PART'])")
}
if ($status["CLOCK_PERIOD_NS"] -ne "10.000") {
    $failures.Add("CLOCK_PERIOD_NS=$($status['CLOCK_PERIOD_NS'])")
}
foreach ($stateField in @(
        "SYNTH_STATE",
        "OPT_STATE",
        "PLACE_STATE",
        "PHYS_OPT_STATE",
        "ROUTE_STATE"
    )) {
    if ($status[$stateField] -ne "COMPLETE") {
        $failures.Add("$stateField=$($status[$stateField])")
    }
}
if ($status["UNROUTED_NETS"] -ne "0") {
    $failures.Add("UNROUTED_NETS=$($status['UNROUTED_NETS'])")
}
if ($status["SETUP_FAILING_ENDPOINTS"] -ne "0") {
    $failures.Add(
        "SETUP_FAILING_ENDPOINTS=$($status['SETUP_FAILING_ENDPOINTS'])"
    )
}
if ($status["HOLD_FAILING_ENDPOINTS"] -ne "0") {
    $failures.Add(
        "HOLD_FAILING_ENDPOINTS=$($status['HOLD_FAILING_ENDPOINTS'])"
    )
}
if ($status["TIMING_STATE"] -ne "TIMING_MET") {
    $failures.Add("TIMING_STATE=$($status['TIMING_STATE'])")
}
if ($status["DRC_ERROR_COUNT"] -ne "0") {
    $failures.Add("DRC_ERROR_COUNT=$($status['DRC_ERROR_COUNT'])")
}
if ($status["ERROR_COUNT"] -ne "0") {
    $failures.Add("ERROR_COUNT=$($status['ERROR_COUNT'])")
}
foreach ($artifactName in $requiredArtifacts) {
    $artifactPath = Join-Path $resolvedResultDir $artifactName
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        $failures.Add("required artifact is missing: $artifactName")
    }
}

Write-Host ""
Write-Host "Stage 2F status summary"
Write-Host "Route       : $($status['ROUTE_STATE'])"
Write-Host "Unrouted    : $($status['UNROUTED_NETS'])"
Write-Host "Setup       : WNS $($status['SETUP_WNS_NS']) ns, TNS $($status['SETUP_TNS_NS']) ns, failing $($status['SETUP_FAILING_ENDPOINTS'])"
Write-Host "Hold        : WHS $($status['HOLD_WHS_NS']) ns, THS $($status['HOLD_THS_NS']) ns, failing $($status['HOLD_FAILING_ENDPOINTS'])"
Write-Host "Resources   : LUT $($status['TOTAL_LUTS']), FF $($status['FFS']), RAMB36 $($status['RAMB36']), RAMB18 $($status['RAMB18']), DSP $($status['DSP_BLOCKS'])"
Write-Host "Latch       : $($status['LATCH_COUNT'])"
Write-Host "DRC errors  : $($status['DRC_ERROR_COUNT'])"
Write-Host "Log markers : ERROR $($status['ERROR_COUNT']), CRITICAL WARNING $($status['CRITICAL_WARNING_COUNT'])"
Write-Host "Timing      : $($status['TIMING_STATE'])"
Write-Host "Status file : $statusPath"

if ($failures.Count -ne 0) {
    throw "Stage 2F acceptance failed: $($failures -join '; ')"
}

Write-Host "run_stage2f_post_route: PASS"
