param(
  [string]$OutputPath = ".local/qa/gpu-capability-matrix/device-matrix.json"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$resolvedOutput = [System.IO.Path]::GetFullPath(
  (Join-Path $workspace $OutputPath)
)

try {
  Push-Location $workspace
  # dart-define 会稳定传入测试 runner；原生探测不读取媒体库路径。.
  $flutterArguments = @(
    "test"
    "integration_test/gpu_capability_matrix_test.dart"
    "-d"
    "windows"
    "--dart-define=LTP_GPU_MATRIX_OUTPUT=$resolvedOutput"
  )
  & flutter @flutterArguments
  if ($LASTEXITCODE -ne 0) {
    throw "显卡能力矩阵测试失败，退出码 $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $resolvedOutput)) {
  throw "测试通过但未生成显卡能力矩阵: $resolvedOutput"
}
Write-Host "显卡能力矩阵已保存: $resolvedOutput"
