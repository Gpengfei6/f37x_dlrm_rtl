[CmdletBinding()]
param(
    [string]$SourceRoot = "_local_recovery/stage2n_a16_2_final_evidence",
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        throw "Python is not on PATH; pass -PythonExe with a local Python 3 executable"
    }
    $PythonExe = $pythonCommand.Source
}
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw "PythonExe does not exist: $PythonExe"
}

$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$allowedSource = [IO.Path]::GetFullPath(
    (Join-Path $repoRoot "_local_recovery")) + [IO.Path]::DirectorySeparatorChar
if (-not ($source + [IO.Path]::DirectorySeparatorChar).StartsWith(
        $allowedSource, [StringComparison]::OrdinalIgnoreCase)) {
    throw "SourceRoot must remain under repository _local_recovery"
}

$destination = Join-Path $repoRoot `
    "docs/evidence/stage2n_a16_2/final_acceptance_v1"
$temporary = Join-Path $repoRoot `
    "_local_recovery/stage2n_a16_2_final_import_work_v1"
if ((Test-Path -LiteralPath $destination) -or
    (Test-Path -LiteralPath $temporary)) {
    throw "Refusing to overwrite an existing import destination or work directory"
}

function Find-OneFile([string]$Name, [string]$PathPattern = "") {
    $matches = @(Get-ChildItem -LiteralPath $source -File -Recurse |
        Where-Object {
            $_.Name -eq $Name -and
            ($PathPattern -eq "" -or $_.FullName -match $PathPattern)
        })
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $Name ($PathPattern); found $($matches.Count)"
    }
    return $matches[0]
}

function Copy-Required([string]$SourceBase, [string]$Relative,
                       [string]$DestinationBase) {
    $inputPath = Join-Path $SourceBase $Relative
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Required compact evidence is missing: $inputPath"
    }
    $outputPath = Join-Path $DestinationBase $Relative
    $outputDir = Split-Path -Parent $outputPath
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Copy-Item -LiteralPath $inputPath -Destination $outputPath
}

$xoStatus = Find-OneFile "a16_2_target_xo_v1_status.txt"
$linkStatus = Find-OneFile "a16_2_target_link_v1_status.txt"
$hostLog = Find-OneFile "host.log" "stage2n_a16_2.*physical_latency_v1"
$hostBuildStatus = Find-OneFile "host_build_status.txt" "stage2n_a16_2"
$xoRoot = $xoStatus.Directory.FullName
$linkRoot = $linkStatus.Directory.FullName
$runRoot = $hostLog.Directory.FullName
$runName = $hostLog.Directory.Name

New-Item -ItemType Directory -Path $temporary | Out-Null

$xoFiles = @(
    "a16_2_target_xo_v1_status.txt",
    "a16_2_target_xo_v1_sources.sha256",
    "a16_2_target_xo_v1_artifacts.sha256",
    "kernel_xml_inside_xo.xml",
    "component_xml_inside_xo.xml",
    "logs/tool_versions.log",
    "logs/xo_metadata_validation.log"
)
foreach ($file in $xoFiles) {
    Copy-Required $xoRoot $file (Join-Path $temporary "target_xo_v1")
}

$linkFiles = @(
    "a16_2_target_link_v1_status.txt",
    "a16_2_target_link_v1_sources.sha256",
    "a16_2_target_link_v1_artifacts.sha256",
    "dlrm_f37x_rtl_kernel_stage2n_a16_v1.xclbin.info",
    "link_contract.txt",
    "xclbin_connectivity.json",
    "xclbin_mem_topology.json",
    "xclbin_ip_layout.json",
    "logs/tool_versions.log",
    "logs/xo_metadata_validation.log",
    "logs/xclbin_metadata_validation.log",
    "post_route/post_route_metrics.txt",
    "post_route/post_route_check_timing.rpt",
    "post_route/post_route_utilization.rpt",
    "post_route/post_route_drc.rpt",
    "post_route/post_route_methodology.rpt"
)
foreach ($file in $linkFiles) {
    Copy-Required $linkRoot $file (Join-Path $temporary "target_link_v1")
}

$runFiles = @(
    "runner.log",
    "host.log",
    "latency_validation.log",
    "dlrm_f37x_rtl_kernel_stage2n_a16_v1.xclbin.info",
    "pre_device_query.txt",
    "post_host_query.txt"
)
$normalizedRun = Join-Path $temporary ("physical_latency_v1/" + $runName)
foreach ($file in $runFiles) {
    Copy-Required $runRoot $file $normalizedRun
}
Copy-Item -LiteralPath $hostBuildStatus.FullName `
    -Destination (Join-Path $temporary "host_build_status.txt")

$validator = Join-Path $repoRoot `
    "scripts/validate_stage2n_a16_2_final_evidence_v1.py"
$validationLog = Join-Path $temporary "imported_evidence_validation.log"
& $PythonExe $validator --evidence-root $temporary --repo $repoRoot 2>&1 |
    Tee-Object -FilePath $validationLog
if ($LASTEXITCODE -ne 0) {
    throw "Imported evidence validation failed; work directory retained at $temporary"
}

$manifest = Join-Path $temporary "IMPORTED_EVIDENCE_SHA256.txt"
Get-ChildItem -LiteralPath $temporary -File -Recurse |
    Where-Object { $_.FullName -ne $manifest } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($temporary.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
        "$hash  $relative"
    } | Set-Content -LiteralPath $manifest -Encoding ascii

& $PythonExe $validator --evidence-root $temporary --repo $repoRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Manifest revalidation failed; work directory retained at $temporary"
}

Move-Item -LiteralPath $temporary -Destination $destination
Write-Output "A16_2_COMPACT_EVIDENCE_IMPORT=PASS"
Write-Output "DESTINATION=$destination"
Write-Output "A16_2_FINAL_ACCEPTANCE_REVIEW_REQUIRED=YES"
