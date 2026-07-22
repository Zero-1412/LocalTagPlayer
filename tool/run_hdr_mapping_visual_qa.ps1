param(
  [string]$OutputPath = ".local/qa/hdr-mapping",
  [string]$ProfilePath = ".local/qa/hdr-mapping/profile"
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $workspace $OutputPath))
$resolvedProfile = [System.IO.Path]::GetFullPath((Join-Path $workspace $ProfilePath))
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
New-Item -ItemType Directory -Force -Path $resolvedProfile | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue `
  (Join-Path $resolvedOutput "settings-playback-split.ready"), `
  (Join-Path $resolvedOutput "video-quality-page.ready"), `
  (Join-Path $resolvedOutput "hdr-mapping-enabled.ready"), `
  (Join-Path $resolvedOutput "hdr-mapping-rollback.ready"), `
  (Join-Path $resolvedOutput "process.pid")

# Pixel capture only. The integration test owns all clicks and never enables Windows UIA.
$captureJob = Start-Job -ArgumentList $resolvedOutput -ScriptBlock {
  param($Output)
  Add-Type -AssemblyName System.Drawing
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpHdrWindowCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
  [LtpHdrWindowCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

  foreach ($name in @(
      "settings-playback-split",
      "video-quality-page",
      "hdr-mapping-enabled",
      "hdr-mapping-rollback"
    )) {
    $marker = Join-Path $Output "$name.ready"
    while (-not (Test-Path -LiteralPath $marker)) { Start-Sleep -Milliseconds 100 }
    $pidPath = Join-Path $Output "process.pid"
    $testPid = [int]((Get-Content -LiteralPath $pidPath -Raw).Trim())
    $process = Get-Process -Id $testPid -ErrorAction Stop
    if ($process.MainWindowHandle -eq 0) {
      throw "HDR QA process has no main window."
    }
    $rect = New-Object LtpHdrWindowCapture+RECT
    if (-not ([LtpHdrWindowCapture]::GetWindowRect(
        $process.MainWindowHandle, [ref]$rect))) {
      throw "Failed to read HDR QA window rectangle."
    }
    $bitmap = [System.Drawing.Bitmap]::new(
      $rect.Right - $rect.Left,
      $rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $deviceContext = $graphics.GetHdc()
    $capturedWindow = [LtpHdrWindowCapture]::PrintWindow(
      $process.MainWindowHandle, $deviceContext, 2)
    $graphics.ReleaseHdc($deviceContext)
    $graphics.Dispose()
    if (-not $capturedWindow) {
      $bitmap.Dispose()
      throw "PrintWindow failed for isolated HDR QA."
    }
    $bitmap.Save((Join-Path $Output "$name.png"))
    $bitmap.Dispose()
  }
}

try {
  Push-Location $workspace
  $env:LOCAL_TAG_PLAYER_DATA_DIR = $resolvedProfile
  $env:LOCAL_TAG_PLAYER_SCREENSHOT_DIR = $resolvedOutput
  & flutter test integration_test/hdr_mapping_settings_test.dart -d windows
  $testExitCode = $LASTEXITCODE
  Wait-Job $captureJob -Timeout 15 | Out-Null
  Receive-Job $captureJob
  Remove-Job $captureJob -Force
  if ($testExitCode -ne 0) {
    throw "HDR mapping visual QA failed: $testExitCode"
  }
} finally {
  Remove-Item Env:LOCAL_TAG_PLAYER_DATA_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_SCREENSHOT_DIR -ErrorAction SilentlyContinue
  Pop-Location
}

foreach ($name in @(
    "settings-playback-split.png",
    "video-quality-page.png",
    "hdr-mapping-enabled.png",
    "hdr-mapping-rollback.png"
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $resolvedOutput $name))) {
    throw "Missing visual QA screenshot: $name"
  }
}
Write-Host "HDR mapping visual QA saved: $resolvedOutput"
