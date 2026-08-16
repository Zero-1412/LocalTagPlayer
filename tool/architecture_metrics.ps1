[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent $scriptDirectory
}

function Get-RelativePath([string]$Path) {
    return $Path.Substring($ProjectRoot.Length).TrimStart('\', '/') -replace '\\', '/'
}

function Get-DartFiles([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.dart')
}

$sourceRoot = Join-Path $ProjectRoot 'lib/src'
$sourceFiles = Get-DartFiles $sourceRoot
$lineMetrics = foreach ($file in $sourceFiles) {
    [ordered]@{
        path = Get-RelativePath $file.FullName
        lines = (Get-Content -LiteralPath $file.FullName).Count
    }
}
$sourceLineTotal = 0
foreach ($metric in $lineMetrics) {
    $sourceLineTotal += [int]$metric.lines
}

$trackedFiles = @(
    'lib/src/services/library/library_store.dart'
    'lib/src/services/library/library_data_backup_service.dart'
    'lib/src/services/library/video_content_similarity_service.dart'
    'lib/src/services/media/thumbnail_service.dart'
    'lib/src/services/media/media_details_service.dart'
    'lib/src/pages/library/library_page.dart'
    'lib/src/pages/player/player_page.dart'
)
$trackedMetrics = foreach ($relative in $trackedFiles) {
    $absolute = Join-Path $ProjectRoot $relative
    if (Test-Path -LiteralPath $absolute) {
        [ordered]@{
            path = $relative
            lines = (Get-Content -LiteralPath $absolute).Count
        }
    }
}

$presentationFiles = Get-DartFiles (Join-Path $sourceRoot 'features') |
    Where-Object { (Get-RelativePath $_.FullName) -match '/presentation/' }
$presentationImportPattern = @'
(?:import|export)\s+['"][^'"]*features/([^/]+)/presentation/
'@
$crossFeatureImports = foreach ($file in $presentationFiles) {
    $path = Get-RelativePath $file.FullName
    $match = [regex]::Match($path, '/features/([^/]+)/presentation/')
    if (-not $match.Success) { continue }
    $feature = $match.Groups[1].Value
    $source = Get-Content -Raw -LiteralPath $file.FullName
    foreach ($import in [regex]::Matches($source, $presentationImportPattern)) {
        if ($import.Groups[1].Value -ne $feature) {
            "{0} -> {1}" -f $path, $import.Groups[1].Value
        }
    }
}

$metrics = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    sourceFiles = $sourceFiles.Count
    sourceLines = $sourceLineTotal
    trackedFiles = @($trackedMetrics)
    filesOver1000Lines = @($lineMetrics | Where-Object { $_.lines -gt 1000 } | Sort-Object lines -Descending)
    crossFeaturePresentationImports = @($crossFeatureImports)
    phase0Artifacts = [ordered]@{
        adr = Test-Path -LiteralPath (Join-Path $ProjectRoot 'docs/architecture/ADR_002_PHASE_0_ARCHITECTURE_FOUNDATION.md')
        legacyFixture = Test-Path -LiteralPath (Join-Path $ProjectRoot 'test/support/legacy_library_fixture.dart')
        contractTest = Test-Path -LiteralPath (Join-Path $ProjectRoot 'test/architecture_phase0_contract_test.dart')
    }
}

if ($AsJson) {
    $metrics | ConvertTo-Json -Depth 8
    exit 0
}

Write-Output ('source files : {0}' -f $metrics.sourceFiles)
Write-Output ('source lines : {0}' -f $metrics.sourceLines)
Write-Output ''
Write-Output 'tracked files:'
$metrics.trackedFiles | ForEach-Object { Write-Output ('  {0,5} {1}' -f $_.lines, $_.path) }
Write-Output ''
Write-Output ('files > 1000 lines: {0}' -f $metrics.filesOver1000Lines.Count)
$metrics.filesOver1000Lines | ForEach-Object { Write-Output ('  {0,5} {1}' -f $_.lines, $_.path) }
Write-Output ('cross-feature presentation imports: {0}' -f $metrics.crossFeaturePresentationImports.Count)
Write-Output ('phase0 artifacts: adr={0}, fixture={1}, contract={2}' -f `
    $metrics.phase0Artifacts.adr, $metrics.phase0Artifacts.legacyFixture, $metrics.phase0Artifacts.contractTest)
