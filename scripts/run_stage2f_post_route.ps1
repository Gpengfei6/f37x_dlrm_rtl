[CmdletBinding()]
param(
    [string]$VivadoPath = "D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat",
    [string]$Part = "xc7a200tfbg484-2",
    [string]$ResultDir = "results\stage2f",
    [string]$WorkDir = "work\stage2f"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..")
)
$TclScript = Join-Path $RepositoryRoot "scripts\run_stage2f_post_route.tcl"
$LogDirectory = Join-Path $RepositoryRoot "logs"
$ConsoleLog = Join-Path $LogDirectory "vivado_stage2f_post_route.log"

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path $RepositoryRoot $PathValue)
    )
}

function Set-StatusValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatusPath,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Found = $false

    foreach ($Line in Get-Content -LiteralPath $StatusPath) {
        if ($Line -match ("^{0}=" -f [regex]::Escape($Key))) {
            $Lines.Add("$Key=$Value")
            $Found = $true
        }
        else {
            $Lines.Add($Line)
        }
    }

    if (-not $Found) {
        $Lines.Add("$Key=$Value")
    }

    Set-Content `
        -LiteralPath $StatusPath `
        -Value $Lines `
        -Encoding ASCII
}

function Get-StatusMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatusPath
    )

    $Map = @{}

    foreach ($Line in Get-Content -LiteralPath $StatusPath) {
        if ($Line -match "^([^=]+)=(.*)$") {
            $Map[$Matches[1]] = $Matches[2]
        }
        elseif ($Line -match "^STAGE2F_") {
            $Map[$Line] = $true
        }
    }

    return $Map
}

$ResolvedResultDir = Resolve-RepositoryPath -PathValue $ResultDir
$ResolvedWorkDir = Resolve-RepositoryPath -PathValue $WorkDir
$StatusPath = Join-Path $ResolvedResultDir "stage2f_post_route_status.txt"

if (-not (Test-Path -LiteralPath $VivadoPath -PathType Leaf)) {
    throw "Vivado executable was not found: $VivadoPath"
}

if (-not (Test-Path -LiteralPath $TclScript -PathType Leaf)) {
    throw "Stage 2F Tcl script was not found: $TclScript"
}

New-Item -ItemType Directory -Force $LogDirectory | Out-Null

$PreviousResultDir = $env:STAGE2F_RESULT_DIR
$PreviousWorkDir = $env:STAGE2F_WORK_DIR
$PreviousPart = $env:STAGE2F_PART
$VivadoExitCode = $null

try {
    $env:STAGE2F_RESULT_DIR = $ResolvedResultDir
    $env:STAGE2F_WORK_DIR = $ResolvedWorkDir
    $env:STAGE2F_PART = $Part

    Write-Host "============================================================"
    Write-Host "Stage 2F Artix-7 OOC post-route implementation"
    Write-Host "Repository : $RepositoryRoot"
    Write-Host "Vivado     : $VivadoPath"
    Write-Host "Part       : $Part"
    Write-Host "Results    : $ResolvedResultDir"
    Write-Host "Work       : $ResolvedWorkDir"
    Write-Host "Log        : $ConsoleLog"
    Write-Host "============================================================"

    Push-Location $RepositoryRoot
    try {
        & $VivadoPath `
            -mode batch `
            -nolog `
            -nojournal `
            -source $TclScript 2>&1 |
            Tee-Object -FilePath $ConsoleLog

        $VivadoExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:STAGE2F_RESULT_DIR = $PreviousResultDir
    $env:STAGE2F_WORK_DIR = $PreviousWorkDir
    $env:STAGE2F_PART = $PreviousPart
}

if (-not (Test-Path -LiteralPath $ConsoleLog -PathType Leaf)) {
    throw "Vivado console log was not created: $ConsoleLog"
}

$ErrorCount = @(
    Select-String `
        -LiteralPath $ConsoleLog `
        -Pattern "^ERROR:" `
        -CaseSensitive
).Count

$CriticalWarningCount = @(
    Select-String `
        -LiteralPath $ConsoleLog `
        -Pattern "^CRITICAL WARNING:" `
        -CaseSensitive
).Count

if (Test-Path -LiteralPath $StatusPath -PathType Leaf) {
    Set-StatusValue `
        -StatusPath $StatusPath `
        -Key "ERROR_COUNT" `
        -Value ([string]$ErrorCount)

    Set-StatusValue `
        -StatusPath $StatusPath `
        -Key "CRITICAL_WARNING_COUNT" `
        -Value ([string]$CriticalWarningCount)
}

if ($null -eq $VivadoExitCode) {
    throw "Vivado did not return an exit code. See: $ConsoleLog"
}

if ($VivadoExitCode -ne 0) {
    throw "Vivado Stage 2F flow failed with exit code $VivadoExitCode. See: $ConsoleLog"
}

if (-not (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
    throw "Stage 2F status file was not created: $StatusPath"
}

$Status = Get-StatusMap -StatusPath $StatusPath

$RequiredValues = @{
    "ROUTE_STATE" = "ROUTE_COMPLETE"
    "UNROUTED_NETS" = "0"
    "SETUP_FAILING_ENDPOINTS" = "0"
    "HOLD_FAILING_ENDPOINTS" = "0"
    "TIMING_STATE" = "TIMING_MET"
}

if (-not $Status.ContainsKey("STAGE2F_RUN_COMPLETE")) {
    throw "Status file does not contain STAGE2F_RUN_COMPLETE."
}

foreach ($Key in $RequiredValues.Keys) {
    if (-not $Status.ContainsKey($Key)) {
        throw "Status file is missing required key: $Key"
    }

    if ([string]$Status[$Key] -ne [string]$RequiredValues[$Key]) {
        throw (
            "Stage 2F acceptance failed: {0}={1}, expected {2}" -f
            $Key, $Status[$Key], $RequiredValues[$Key]
        )
    }
}

if ($ErrorCount -ne 0) {
    throw "Vivado log contains $ErrorCount anchored ERROR line(s)."
}

Write-Host ""
Write-Host "========== Stage 2F status ==========" -ForegroundColor Cyan
Get-Content -LiteralPath $StatusPath

if ($CriticalWarningCount -ne 0) {
    Write-Warning (
        "Vivado log contains {0} anchored CRITICAL WARNING line(s). " +
        "Review the log before closing Stage 2F." -f
        $CriticalWarningCount
    )
}

Write-Host ""
Write-Host "STAGE2F_POST_ROUTE_FLOW_PASS" -ForegroundColor Green
Write-Host "Status: $StatusPath"
Write-Host "Log:    $ConsoleLog"
