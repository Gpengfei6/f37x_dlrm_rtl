param(
  [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path "logs", "results", "work" | Out-Null

$script:TestResults = @()

function Add-Result {
  param(
    [string]$Name,
    [string]$Category,
    [string]$Status,
    $ExitCode,
    [string]$Command,
    [string]$Log,
    [string]$Reason = ""
  )
  $script:TestResults += [pscustomobject]@{
    name = $Name; category = $Category; status = $Status
    exit_code = $ExitCode; command = $Command; log = $Log; reason = $Reason
  }
}

function Invoke-Logged {
  param(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$LogPath
  )
  try {
    $Output = & $Executable @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    if ($null -eq $ExitCode) { $ExitCode = 0 }
  } catch {
    $Output = @($_.Exception.ToString())
    $ExitCode = -1
  }
  $Text = ($Output | Out-String)
  [System.IO.File]::WriteAllText((Join-Path $ProjectRoot $LogPath), $Text,
    [System.Text.UTF8Encoding]::new($false))
  $Output | ForEach-Object { [Console]::WriteLine($_.ToString()) }
  return [pscustomobject]@{ exit_code = $ExitCode; output = $Text }
}

function Get-Tool([string]$Name) {
  return $Toolchain.tools | Where-Object { $_.name -eq $Name } |
    Select-Object -First 1
}

function Get-TestDefinitions {
  return @(
    [pscustomobject]@{ name="tb_rv_fifo"; sources=@("rtl/common/rv_fifo.sv") },
    [pscustomobject]@{ name="tb_saturating_round"; sources=@("rtl/common/saturating_round.sv") },
    [pscustomobject]@{ name="tb_relu_quant"; sources=@("rtl/common/saturating_round.sv","rtl/common/relu_quant.sv") },
    [pscustomobject]@{ name="tb_dot_product_core"; sources=@("rtl/compute/dot_product_core.sv") },
    [pscustomobject]@{ name="tb_dense_layer_core"; sources=@("rtl/common/saturating_round.sv","rtl/common/relu_quant.sv","rtl/compute/dot_product_core.sv","rtl/compute/dense_layer_core.sv") },
    [pscustomobject]@{ name="tb_embedding_mem_model"; sources=@("rtl/memory/embedding_mem_model.sv") },
    [pscustomobject]@{ name="tb_minimal_recommendation_pipeline"; sources=@("rtl/common/saturating_round.sv","rtl/common/relu_quant.sv","rtl/compute/dot_product_core.sv","rtl/compute/dense_layer_core.sv","rtl/memory/embedding_mem_model.sv","rtl/pipeline/minimal_recommendation_pipeline.sv") },
    [pscustomobject]@{ name="tb_dlrm_minimal_top"; sources=@("rtl/include/dlrm_config_pkg.sv","rtl/common/saturating_round.sv","rtl/common/relu_quant.sv","rtl/compute/dot_product_core.sv","rtl/compute/dense_layer_core.sv","rtl/memory/embedding_mem_model.sv","rtl/pipeline/minimal_recommendation_pipeline.sv","rtl/top/dlrm_minimal_top.sv") }
  )
}

function Invoke-RtlPackedCompare([string]$SuiteName) {
  $RtlOutput = "results/rtl_top_outputs.hex"
  if (-not (Test-Path -LiteralPath $RtlOutput)) {
    Add-Result "${SuiteName}_top_compare" "rtl_comparison" "SKIPPED" $null `
      "" $RtlOutput "Top simulation did not produce an output file"
    return
  }
  if (-not $Python.available) {
    Add-Result "${SuiteName}_top_compare" "rtl_comparison" "SKIPPED" $null `
      "" "logs/toolchain.json" "Python unavailable"
    return
  }
  $Report = "results/${SuiteName}_compare_report.json"
  $Log = "logs/${SuiteName}_top_compare.log"
  $Arguments = @("-B", "python/compare_results.py", "--rtl", $RtlOutput,
    "--expected", "tests/expected/top_expected.json", "--report", $Report)
  $Comparison = Invoke-Logged $Python.path $Arguments $Log
  $Status = if ($Comparison.exit_code -eq 0) { "PASS" } else { "FAIL" }
  Add-Result "${SuiteName}_top_compare" "rtl_comparison" $Status `
    $Comparison.exit_code ($Python.path + " " + ($Arguments -join " ")) $Log
}

# Tool detection itself is logged and never installs anything.
$ToolLog = "logs/toolchain_console.log"
$CheckArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
  (Join-Path $PSScriptRoot "check_toolchain.ps1"),
  "-OutputPath", (Join-Path $ProjectRoot "logs/toolchain.json"))
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
  $CheckArgs += @("-PythonExe", $PythonExe)
}
$PowerShellPath = (Get-Process -Id $PID).Path
$ToolProbe = Invoke-Logged $PowerShellPath $CheckArgs $ToolLog
$Toolchain = Get-Content -LiteralPath "logs/toolchain.json" -Raw -Encoding UTF8 |
  ConvertFrom-Json

$Python = Get-Tool "python"
if ($Python.available) {
  $PythonCommands = @(
    [pscustomobject]@{ name="python_regression"; args=@("-B","scripts/run_python_tests.py"); log="logs/python_regression_console.log" },
    [pscustomobject]@{ name="python_reference"; args=@("-B","python/reference_model.py"); log="logs/python_reference_console.log" },
    [pscustomobject]@{ name="python_packed_compare"; args=@("-B","python/compare_results.py","--rtl","results/python_selfcheck.hex","--expected","tests/expected/top_expected.json","--report","results/python_compare_report.json"); log="logs/python_compare_console.log" }
  )
  foreach ($Item in $PythonCommands) {
    $Run = Invoke-Logged $Python.path $Item.args $Item.log
    $Status = if ($Run.exit_code -eq 0) { "PASS" } else { "FAIL" }
    Add-Result $Item.name "python" $Status $Run.exit_code `
      ($Python.path + " " + ($Item.args -join " ")) $Item.log
  }
} else {
  Add-Result "python_suite" "python" "SKIPPED" $null "" "logs/toolchain.json" `
    "No executable Python command passed its version probe"
}

$Definitions = Get-TestDefinitions
$Iverilog = Get-Tool "iverilog"
$Vvp = Get-Tool "vvp"
if ($Iverilog.available -and $Vvp.available) {
  New-Item -ItemType Directory -Force -Path "work/iverilog" | Out-Null
  Remove-Item -LiteralPath "results/rtl_top_outputs.hex" -Force -ErrorAction SilentlyContinue
  foreach ($Definition in $Definitions) {
    $OutputPath = "work/iverilog/$($Definition.name).vvp"
    $Arguments = @("-g2012", "-Wall", "-s", $Definition.name,
      "-o", $OutputPath) + $Definition.sources + @("tb/$($Definition.name).sv")
    $CompileLog = "logs/iverilog_compile_$($Definition.name).log"
    $Compile = Invoke-Logged $Iverilog.path $Arguments $CompileLog
    $CompileStatus = if ($Compile.exit_code -eq 0) { "PASS" } else { "FAIL" }
    Add-Result "iverilog_compile_$($Definition.name)" "rtl_compile" `
      $CompileStatus $Compile.exit_code ($Iverilog.path + " " + ($Arguments -join " ")) $CompileLog
    if ($Compile.exit_code -ne 0) { continue }

    $RunLog = "logs/iverilog_$($Definition.name).log"
    $Simulation = Invoke-Logged $Vvp.path @($OutputPath) $RunLog
    $HasPass = $Simulation.output.Contains("$($Definition.name): PASS")
    $SimulationStatus = if ($Simulation.exit_code -eq 0 -and $HasPass) { "PASS" } else { "FAIL" }
    Add-Result "iverilog_$($Definition.name)" "rtl_simulation" `
      $SimulationStatus $Simulation.exit_code ($Vvp.path + " " + $OutputPath) $RunLog `
      $(if ($HasPass) { "" } else { "PASS marker missing" })
  }
  Invoke-RtlPackedCompare "iverilog"
} else {
  Add-Result "iverilog_suite" "rtl_simulation" "SKIPPED" $null "" `
    "logs/toolchain.json" "iverilog and/or vvp unavailable"
}

$Verilator = Get-Tool "verilator"
if ($Verilator.available) {
  Remove-Item -LiteralPath "results/rtl_top_outputs.hex" -Force -ErrorAction SilentlyContinue
  foreach ($Definition in $Definitions) {
    $MDir = "work/verilator_$($Definition.name)"
    $BinaryName = $Definition.name
    if ($env:OS -eq "Windows_NT") { $BinaryName += ".exe" }
    $Arguments = @("--binary", "--timing", "-Wall", "--top-module",
      $Definition.name, "--Mdir", $MDir, "-o", $BinaryName) +
      $Definition.sources + @("tb/$($Definition.name).sv")
    $CompileLog = "logs/verilator_compile_$($Definition.name).log"
    $Compile = Invoke-Logged $Verilator.path $Arguments $CompileLog
    $CompileStatus = if ($Compile.exit_code -eq 0) { "PASS" } else { "FAIL" }
    Add-Result "verilator_compile_$($Definition.name)" "rtl_compile" `
      $CompileStatus $Compile.exit_code ($Verilator.path + " " + ($Arguments -join " ")) $CompileLog
    if ($Compile.exit_code -ne 0) { continue }

    $BinaryPath = Join-Path $ProjectRoot (Join-Path $MDir $BinaryName)
    $RunLog = "logs/verilator_$($Definition.name).log"
    $Simulation = Invoke-Logged $BinaryPath @() $RunLog
    $HasPass = $Simulation.output.Contains("$($Definition.name): PASS")
    $SimulationStatus = if ($Simulation.exit_code -eq 0 -and $HasPass) { "PASS" } else { "FAIL" }
    Add-Result "verilator_$($Definition.name)" "rtl_simulation" `
      $SimulationStatus $Simulation.exit_code $BinaryPath $RunLog `
      $(if ($HasPass) { "" } else { "PASS marker missing" })
  }
  Invoke-RtlPackedCompare "verilator"
} else {
  Add-Result "verilator_suite" "rtl_simulation" "SKIPPED" $null "" `
    "logs/toolchain.json" "verilator unavailable"
}

$Verible = Get-Tool "verible-verilog-lint"
$AllRtl = @(
  "rtl/include/dlrm_config_pkg.sv", "rtl/common/rv_fifo.sv",
  "rtl/common/saturating_round.sv", "rtl/common/relu_quant.sv",
  "rtl/compute/dot_product_core.sv", "rtl/compute/dense_layer_core.sv",
  "rtl/memory/embedding_mem_model.sv",
  "rtl/pipeline/minimal_recommendation_pipeline.sv",
  "rtl/top/dlrm_minimal_top.sv"
)
if ($Verible.available) {
  $Lint = Invoke-Logged $Verible.path $AllRtl "logs/verible_stage1.log"
  $LintStatus = if ($Lint.exit_code -eq 0) { "PASS" } else { "FAIL" }
  Add-Result "verible_lint" "rtl_lint" $LintStatus $Lint.exit_code `
    ($Verible.path + " " + ($AllRtl -join " ")) "logs/verible_stage1.log"
} else {
  Add-Result "verible_lint" "rtl_lint" "SKIPPED" $null "" `
    "logs/toolchain.json" "verible-verilog-lint unavailable"
}

$Vivado = Get-Tool "vivado"
$Xvlog = Get-Tool "xvlog"
$Xelab = Get-Tool "xelab"
$Xsim = Get-Tool "xsim"
if ($Vivado.available -and $Xvlog.available -and $Xelab.available -and $Xsim.available) {
  Remove-Item -LiteralPath "results/rtl_top_outputs.hex" -Force -ErrorAction SilentlyContinue
  $XsimArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    (Join-Path $PSScriptRoot "run_xsim_stage1.ps1"),
    "-VivadoExe", $Vivado.path)
  $XsimRun = Invoke-Logged $PowerShellPath $XsimArgs "logs/xsim_stage1_console.log"
  $XsimStatus = if ($XsimRun.exit_code -eq 0) { "PASS" } else { "FAIL" }
  Add-Result "xsim_stage1_suite" "rtl_simulation" $XsimStatus `
    $XsimRun.exit_code ($PowerShellPath + " " + ($XsimArgs -join " ")) `
    "logs/xsim_stage1_console.log"
  if (Test-Path -LiteralPath "results/xsim_stage1_summary.json") {
    $XsimDetail = Get-Content -LiteralPath "results/xsim_stage1_summary.json" `
      -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($Test in $XsimDetail.tests) {
      $Category = if ($Test.stage -eq "COMPILE" -or $Test.stage -eq "ELAB") {
        "rtl_compile"
      } else {
        "rtl_simulation"
      }
      Add-Result ("xsim_{0}_{1}" -f $Test.name, $Test.stage.ToLower()) `
        $Category $Test.status $Test.exit_code "See XSim Tcl log" `
        $(if ($Test.stage -eq "COMPILE") { "logs/xvlog_stage1.log" } `
          elseif ($Test.stage -eq "ELAB") { "logs/xelab_$($Test.name).log" } `
          else { "logs/xsim_$($Test.name).log" })
    }
  }
  Invoke-RtlPackedCompare "xsim"
} else {
  Add-Result "xsim_stage1_suite" "rtl_simulation" "SKIPPED" $null "" `
    "logs/toolchain.json" "vivado/xvlog/xelab/xsim toolchain incomplete"
}

# Write the summary before collecting it into a validation bundle.
function Write-Summary {
  $PassCount = @($script:TestResults | Where-Object { $_.status -eq "PASS" }).Count
  $FailCount = @($script:TestResults | Where-Object { $_.status -eq "FAIL" }).Count
  $SkipCount = @($script:TestResults | Where-Object { $_.status -eq "SKIPPED" }).Count
  $Overall = if ($FailCount -gt 0) { "FAIL" } elseif ($PassCount -gt 0) { "PASS" } else { "SKIPPED" }
  $GitRevision = "UNKNOWN"
  $Git = Get-Tool "git"
  if ($Git.available) {
    try { $GitRevision = (& $Git.path rev-parse HEAD 2>$null).Trim() } catch { }
  }
  $Summary = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    git_revision = $GitRevision
    overall_status = $Overall
    counts = [ordered]@{ pass = $PassCount; fail = $FailCount; skipped = $SkipCount }
    gate1_satisfied = $false
    gate1_note = "Requires review of real compiler/elaboration/simulation logs; Python PASS is insufficient."
    toolchain = $Toolchain.tools
    tests = $script:TestResults
  }
  [System.IO.File]::WriteAllText(
    (Join-Path $ProjectRoot "results/validation_summary.json"),
    (($Summary | ConvertTo-Json -Depth 9) + [Environment]::NewLine),
    [System.Text.UTF8Encoding]::new($false))
  return $Summary
}

$null = Write-Summary
if ($Python.available) {
  $CollectorArgs = @("-B", "scripts/collect_validation_bundle.py",
    "--prepare-handoff", "--collect-logs")
  $Collector = Invoke-Logged $Python.path $CollectorArgs "logs/collect_validation_bundle.log"
  $CollectorStatus = if ($Collector.exit_code -eq 0) { "PASS" } else { "FAIL" }
  Add-Result "collect_validation_bundle" "packaging" $CollectorStatus `
    $Collector.exit_code ($Python.path + " " + ($CollectorArgs -join " ")) `
    "logs/collect_validation_bundle.log"
} else {
  Add-Result "collect_validation_bundle" "packaging" "SKIPPED" $null "" `
    "logs/toolchain.json" "Python unavailable"
}
$FinalSummary = Write-Summary

Write-Output ("run_all_local: {0} PASS={1} FAIL={2} SKIPPED={3}" -f `
  $FinalSummary.overall_status, $FinalSummary.counts.pass,
  $FinalSummary.counts.fail, $FinalSummary.counts.skipped)
if ($FinalSummary.overall_status -eq "FAIL") { exit 1 }
