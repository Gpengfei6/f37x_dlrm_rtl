param(
  [string]$VivadoExe = "vivado",
  [string]$SummaryPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
  $SummaryPath = Join-Path $ProjectRoot "results/xsim_stage2a_summary.json"
}
New-Item -ItemType Directory -Force -Path "logs", "results" | Out-Null

function Resolve-Executable([string]$Candidate) {
  if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
    return (Resolve-Path -LiteralPath $Candidate).Path
  }
  $Command = Get-Command $Candidate -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $Command) { return $null }
  if ($Command.Source) { return $Command.Source }
  return $Command.Definition
}

$Required = @("xvlog", "xelab", "xsim")
$Missing = @()
foreach ($Name in $Required) {
  if ($null -eq (Resolve-Executable $Name)) { $Missing += $Name }
}
$VivadoPath = Resolve-Executable $VivadoExe
if ($null -eq $VivadoPath) { $Missing += "vivado" }

if ($Missing.Count -gt 0) {
  $Summary = [ordered]@{
    status = "SKIPPED"; exit_code = $null
    reason = "Missing tools: " + ($Missing -join ", ")
    tests = @()
  }
  [System.IO.File]::WriteAllText($SummaryPath,
    (($Summary | ConvertTo-Json -Depth 5) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false))
  Write-Output "run_xsim_stage2a: SKIPPED - $($Summary.reason)"
  exit 2
}

$DriverLog = Join-Path $ProjectRoot "logs/xsim_stage2a_driver.log"
$Output = & $VivadoPath -mode batch -nojournal -nolog `
  -source "scripts/run_xsim_stage2a.tcl" 2>&1
$ExitCode = $LASTEXITCODE
$Output | Out-File -LiteralPath $DriverLog -Encoding utf8
$Output | ForEach-Object { Write-Output $_ }

$Tests = @()
$StatusPath = Join-Path $ProjectRoot "results/xsim_stage2a_status.txt"
if (Test-Path -LiteralPath $StatusPath) {
  foreach ($Line in Get-Content -LiteralPath $StatusPath) {
    if ([string]::IsNullOrWhiteSpace($Line)) { continue }
    $Parts = $Line -split "\s+", 4
    $RawStatus = $Parts[2]
    $Tests += [pscustomobject]@{
      name = $Parts[0]; stage = $Parts[1]
      status = if ($RawStatus -eq "PASS") { "PASS" } else { "FAIL" }
      exit_code = [int]$Parts[3]; detail = $RawStatus
    }
  }
}
$Overall = if ($ExitCode -eq 0 -and
    ($Tests | Where-Object { $_.status -eq "FAIL" }).Count -eq 0) {
  "PASS"
} else {
  "FAIL"
}
$Summary = [ordered]@{
  status = $Overall; exit_code = $ExitCode
  log = "logs/xsim_stage2a_driver.log"; tests = $Tests
}
[System.IO.File]::WriteAllText($SummaryPath,
  (($Summary | ConvertTo-Json -Depth 6) + [Environment]::NewLine),
  [System.Text.UTF8Encoding]::new($false))
Write-Output "run_xsim_stage2a: $Overall"
if ($Overall -eq "FAIL") { exit 1 }
