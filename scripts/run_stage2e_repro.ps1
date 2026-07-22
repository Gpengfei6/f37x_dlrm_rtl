param(
  [string]$VivadoExe = "",
  [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$ResultDir = Join-Path $ProjectRoot "results/stage2e"
$LogDir = Join-Path $ProjectRoot "logs/stage2e"
New-Item -ItemType Directory -Force -Path $ResultDir, $LogDir | Out-Null

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText(
    $Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Write-Summary($Summary) {
  $Path = Join-Path $ResultDir "stage2e_repro_summary.json"
  Write-Utf8NoBom $Path (($Summary | ConvertTo-Json -Depth 8) + [Environment]::NewLine)
}

function Resolve-Executable([string]$Candidate) {
  if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
  if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
    return (Resolve-Path -LiteralPath $Candidate).Path
  }
  $Command = Get-Command $Candidate -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $Command) { return $null }
  if ($Command.Source) { return $Command.Source }
  return $Command.Definition
}

function Invoke-Logged {
  param(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$LogName
  )
  try {
    $Output = & $Executable @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    if ($null -eq $ExitCode) { $ExitCode = 0 }
  } catch {
    $Output = @($_.Exception.ToString())
    $ExitCode = -1
  }
  $Text = $Output | Out-String
  Write-Utf8NoBom (Join-Path $LogDir $LogName) $Text
  $Output | ForEach-Object { Write-Output $_ }
  return [pscustomobject]@{ exit_code = $ExitCode; output = $Text }
}

function Find-VivadoCandidates {
  $Candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($VivadoExe)) {
    $Candidates += $VivadoExe
  } else {
    if (-not [string]::IsNullOrWhiteSpace($env:XILINX_VIVADO)) {
      $Candidates += (Join-Path $env:XILINX_VIVADO "bin/vivado.bat")
      $Candidates += (Join-Path $env:XILINX_VIVADO "bin/vivado")
    }
    $Candidates += @(
      "vivado",
      "C:\Xilinx\Vivado\2020.2\bin\vivado.bat",
      "D:\Xilinx\Vivado\2020.2\bin\vivado.bat",
      "C:\Xilinx\2020.2\Vivado\bin\vivado.bat",
      "D:\Xilinx\2020.2\Vivado\bin\vivado.bat",
      "D:\vivado2020\Vivado\2020.2\bin\vivado.bat",
      "D:\vivado2020\vivado2020forwins\Vivado\2020.2\bin\vivado.bat"
    )
  }
  $ResolvedCandidates = @()
  foreach ($Candidate in $Candidates | Select-Object -Unique) {
    $Resolved = Resolve-Executable $Candidate
    if ($null -ne $Resolved -and $ResolvedCandidates -notcontains $Resolved) {
      $ResolvedCandidates += $Resolved
    }
  }
  return $ResolvedCandidates
}

$GitRevision = (& git rev-parse HEAD).Trim()
$VivadoCandidates = @(Find-VivadoCandidates)
if ($VivadoCandidates.Count -eq 0) {
  $Summary = [ordered]@{
    status = "NOT_RUN"
    reason = "No local Vivado executable was found in PATH, XILINX_VIVADO, or known 2020.2 install paths."
    expected_vivado_version = "2020.2"
    detected_vivado_version = $null
    git_revision = $GitRevision
    steps = @()
  }
  Write-Summary $Summary
  [Console]::Error.WriteLine("run_stage2e_repro: NOT_RUN - $($Summary.reason)")
  exit 2
}

$VivadoPath = $null
$DetectedCandidates = @()
$CandidateIndex = 0
foreach ($CandidatePath in $VivadoCandidates) {
  $VersionLogName = "vivado_version_$CandidateIndex.log"
  $VersionRun = Invoke-Logged $CandidatePath @("-version") $VersionLogName
  $VersionMatch = [regex]::Match($VersionRun.output, "Vivado v\.?(\d{4}\.\d+)")
  $CandidateVersion = if ($VersionMatch.Success) {
    $VersionMatch.Groups[1].Value
  } else {
    "UNKNOWN"
  }
  $DetectedCandidates += [pscustomobject]@{
    executable = $CandidatePath
    version = $CandidateVersion
    exit_code = $VersionRun.exit_code
    log = "logs/stage2e/$VersionLogName"
  }
  if ($VersionRun.exit_code -eq 0 -and $CandidateVersion -eq "2020.2") {
    $VivadoPath = $CandidatePath
    break
  }
  $CandidateIndex += 1
}

if ($null -eq $VivadoPath) {
  $DetectedVersions = ($DetectedCandidates | ForEach-Object {
    "$($_.executable)=$($_.version)"
  }) -join "; "
  $Summary = [ordered]@{
    status = "NOT_RUN"
    reason = "No detected executable is Vivado 2020.2. No regression or synthesis command was run. Detected: $DetectedVersions"
    expected_vivado_version = "2020.2"
    detected_candidates = $DetectedCandidates
    git_revision = $GitRevision
    steps = @()
  }
  Write-Summary $Summary
  [Console]::Error.WriteLine("run_stage2e_repro: NOT_RUN - $($Summary.reason)")
  exit 2
}
$DetectedVersion = "2020.2"

$PythonPath = Resolve-Executable $PythonExe
if ($null -eq $PythonPath) {
  $Summary = [ordered]@{
    status = "NOT_RUN"
    reason = "Python executable was not found: $PythonExe"
    expected_vivado_version = "2020.2"
    detected_vivado_version = $DetectedVersion
    vivado_executable = $VivadoPath
    git_revision = $GitRevision
    steps = @()
  }
  Write-Summary $Summary
  [Console]::Error.WriteLine("run_stage2e_repro: NOT_RUN - $($Summary.reason)")
  exit 2
}

$Steps = @()
function Run-Step {
  param(
    [string]$Name,
    [string]$Executable,
    [string[]]$Arguments,
    [string]$LogName
  )
  $Run = Invoke-Logged $Executable $Arguments $LogName
  $Status = if ($Run.exit_code -eq 0) { "PASS" } else { "FAIL" }
  $script:Steps += [pscustomobject]@{
    name = $Name
    status = $Status
    exit_code = $Run.exit_code
    log = "logs/stage2e/$LogName"
  }
}

Run-Step "phase1_python" $PythonPath @("scripts/run_python_tests.py") "python_phase1.log"
Run-Step "stage2a_python" $PythonPath @("scripts/run_stage2a_python_tests.py") "python_stage2a.log"
Run-Step "stage2b_python" $PythonPath @("scripts/run_stage2b_python_tests.py") "python_stage2b.log"
Run-Step "stage2a_xsim" $VivadoPath @(
  "-mode", "tcl", "-nolog", "-nojournal", "-source", "scripts/run_xsim_stage2a.tcl"
) "vivado_xsim_stage2a.log"
$Stage2bLog = Join-Path $ProjectRoot "logs/xsim_stage2b.log"
Remove-Item -LiteralPath $Stage2bLog -Force -ErrorAction SilentlyContinue
Run-Step "stage2b_xsim" $VivadoPath @(
  "-mode", "tcl", "-nolog", "-nojournal", "-source", "scripts/run_xsim_stage2b.tcl"
) "vivado_xsim_stage2b.log"

$Stage2bExactMarker = $false
if (Test-Path -LiteralPath $Stage2bLog) {
  $Stage2bExactMarker = (Get-Content -LiteralPath $Stage2bLog -Raw).Contains(
    "tb_mlp_sequence_controller: PASS valid=11 invalid=9 total=20")
}
if (-not $Stage2bExactMarker) {
  $Steps += [pscustomobject]@{
    name = "stage2b_exact_marker"
    status = "FAIL"
    exit_code = 1
    log = "logs/xsim_stage2b.log"
  }
} else {
  $Steps += [pscustomobject]@{
    name = "stage2b_exact_marker"
    status = "PASS"
    exit_code = 0
    log = "logs/xsim_stage2b.log"
  }
}

Run-Step "stage2c_ooc_synthesis" $VivadoPath @(
  "-mode", "tcl", "-nolog", "-nojournal", "-source", "scripts/run_synth_stage2c.tcl"
) "vivado_synth_stage2c.log"
Run-Step "stage2e_report_summary" $PythonPath @(
  "scripts/summarize_stage2e_reports.py",
  "--expected-version", "2020.2",
  "--output", "results/stage2e/vivado2020_2_synthesis.json"
) "report_summary.log"

$FailCount = @($Steps | Where-Object { $_.status -eq "FAIL" }).Count
$Summary = [ordered]@{
  status = if ($FailCount -eq 0) { "PASS" } else { "FAIL" }
  expected_vivado_version = "2020.2"
  detected_vivado_version = $DetectedVersion
  vivado_executable = $VivadoPath
  git_revision = $GitRevision
  stage2b_exact_marker = $Stage2bExactMarker
  steps = $Steps
}
Write-Summary $Summary
Write-Output "run_stage2e_repro: $($Summary.status)"
if ($FailCount -ne 0) { exit 1 }
