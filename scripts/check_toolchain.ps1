param(
  [string]$PythonExe = "",
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $ProjectRoot "logs/toolchain.json"
}

function Resolve-Executable {
  param([string[]]$Candidates)
  foreach ($Candidate in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
      return (Resolve-Path -LiteralPath $Candidate).Path
    }
    $Command = Get-Command $Candidate -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($null -ne $Command) {
      if ($Command.Source) { return $Command.Source }
      return $Command.Definition
    }
  }
  return $null
}

function Probe-Tool {
  param(
    [string]$Name,
    [string[]]$Candidates,
    [string[]]$VersionArguments
  )
  $LastPath = $null
  $LastExitCode = $null
  $LastOutput = $null
  foreach ($Candidate in $Candidates) {
    $Path = Resolve-Executable @($Candidate)
    if ($null -eq $Path) { continue }
    $LastPath = $Path
    try {
      $Output = (& $Path @VersionArguments 2>&1 | Out-String).Trim()
      $ExitCode = $LASTEXITCODE
      if ($null -eq $ExitCode) { $ExitCode = 0 }
      $LastExitCode = $ExitCode
      $LastOutput = $Output
      if ($ExitCode -eq 0) {
        return [pscustomobject]@{
          name = $Name; available = $true; path = $Path
          version_exit_code = $ExitCode; version = $Output
        }
      }
    } catch {
      $LastExitCode = -1
      $LastOutput = $_.Exception.Message
    }
  }
  return [pscustomobject]@{
    name = $Name; available = $false; path = $LastPath
    version_exit_code = $LastExitCode; version = $LastOutput
  }
}

$PythonCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
  $PythonCandidates += $PythonExe
}
$PythonCandidates += @("python3", "python", "py")

$Tools = @(
  (Probe-Tool "python" $PythonCandidates @("--version")),
  (Probe-Tool "vivado" @("vivado") @("-version")),
  (Probe-Tool "xvlog" @("xvlog") @("-version")),
  (Probe-Tool "xelab" @("xelab") @("-version")),
  (Probe-Tool "xsim" @("xsim") @("-version")),
  (Probe-Tool "iverilog" @("iverilog") @("-V")),
  (Probe-Tool "vvp" @("vvp") @("-V")),
  (Probe-Tool "verilator" @("verilator") @("--version")),
  (Probe-Tool "verible-verilog-lint" @("verible-verilog-lint") @("--version")),
  (Probe-Tool "bash" @("bash") @("--version")),
  (Probe-Tool "git" @("git") @("--version"))
)

$Result = [ordered]@{
  generated_at = (Get-Date).ToString("o")
  project_root = $ProjectRoot
  tools = $Tools
}

$Parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $Parent | Out-Null
$Json = $Result | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($OutputPath, $Json + [Environment]::NewLine,
  [System.Text.UTF8Encoding]::new($false))

$Tools | Select-Object name, available, path, version_exit_code | Format-Table -AutoSize
Write-Output "check_toolchain: wrote $OutputPath"
