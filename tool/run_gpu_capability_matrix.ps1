param(
  [string]$OutputPath = ".local/qa/gpu-capability-matrix/active-device-compute-budget.json"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$resolvedOutput = [System.IO.Path]::GetFullPath(
  (Join-Path $workspace $OutputPath)
)

try {
  Push-Location $workspace
  # Pass the private output path through dart-define; the probe never reads media paths.
  $flutterArguments = @(
    "test"
    "integration_test/gpu_capability_matrix_test.dart"
    "-d"
    "windows"
    "--dart-define=LTP_GPU_MATRIX_OUTPUT=$resolvedOutput"
  )
  & flutter @flutterArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Active GPU and Compute frame-budget test failed: $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $resolvedOutput)) {
  throw "GPU baseline output was not created: $resolvedOutput"
}
Write-Host "GPU baseline saved: $resolvedOutput"
