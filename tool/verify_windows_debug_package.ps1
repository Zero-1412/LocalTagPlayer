param(
  [switch]$SkipBuild,
  [ValidateRange(5, 60)]
  [int]$WindowTimeoutSeconds = 20,
  [ValidateRange(0, 20)]
  [int]$VisibleSeconds = 3
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$debugDirectory = Join-Path $workspace "build/windows/x64/runner/Debug"
$executable = Join-Path $debugDirectory "local_tag_player.exe"

<#
 * Windows integration test 会复用 Debug 输出目录并写入测试入口。交付前必须再次
 * 构建正式 main.dart，否则双击 exe 时进程会等待测试驱动而没有主窗口。
#>
if (-not $SkipBuild) {
  Push-Location $workspace
  try {
    & flutter build windows --debug
    if ($LASTEXITCODE -ne 0) {
      throw "Windows Debug 正式入口构建失败。"
    }
  } finally {
    Pop-Location
  }
}
if (-not (Test-Path -LiteralPath $executable)) {
  throw "Windows Debug 可执行文件不存在：$executable"
}

<#
 * 只检查本脚本启动的精确进程，避免误把其它开发会话的同名窗口当成成功。
 * MainWindowHandle 非零证明正式入口已经越过首帧前初始化并创建可见主窗口。
#>
$process = Start-Process `
  -FilePath $executable `
  -WorkingDirectory $debugDirectory `
  -PassThru
$windowReady = $false
$deadline = (Get-Date).AddSeconds($WindowTimeoutSeconds)
try {
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 100
    $process.Refresh()
    if ($process.HasExited) {
      throw "Windows Debug 进程在主窗口出现前退出，exitCode=$($process.ExitCode)。"
    }
    if ($process.MainWindowHandle -ne 0) {
      $windowReady = $true
      break
    }
  }
  if (-not $windowReady) {
    throw "Windows Debug 进程仍存活，但在 $WindowTimeoutSeconds 秒内没有创建主窗口。"
  }

  Write-Host (
    "Windows Debug click-launch passed: pid={0} title={1}" -f `
      $process.Id, $process.MainWindowTitle
  )
  if ($VisibleSeconds -gt 0) {
    Start-Sleep -Seconds $VisibleSeconds
  }
} finally {
  $process.Refresh()
  if (-not $process.HasExited) {
    $process.CloseMainWindow() | Out-Null
    if (-not $process.WaitForExit(20000)) {
      # 仅终止本脚本创建的精确 PID，防止失败的 QA 会话残留后台进程。
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
  }
}
