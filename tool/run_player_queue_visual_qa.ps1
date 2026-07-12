param(
  [string]$Flutter = 'E:\flutter\bin\flutter.bat',
  [string]$Profile = "$env:TEMP\ltp_blueprint_compare\profile",
  [string]$Output = "$env:TEMP\ltp_blueprint_compare\screenshots_no_uia"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Output | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$Output\*.ready", "$Output\*.png"

# Pixel capture only. This script never queries or enables Windows UI Automation.
$captureJob = Start-Job -ArgumentList $Output -ScriptBlock {
  param($Output)
  Add-Type -AssemblyName System.Drawing
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpWindowCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
  [LtpWindowCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

  foreach ($name in @(
    'player-queue-initial'
    'player-queue-collapsed'
    'player-queue-restored'
    'player-controls-hidden'
    'player-fullscreen-queue'
  )) {
    $marker = Join-Path $Output "$name.ready"
    while (-not (Test-Path -LiteralPath $marker)) { Start-Sleep -Milliseconds 100 }
    $process = Get-Process local_tag_player | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
    $rect = New-Object LtpWindowCapture+RECT
    if (-not ([LtpWindowCapture]::GetWindowRect($process.MainWindowHandle, [ref]$rect))) {
      throw 'Failed to read player window rectangle.'
    }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
    $graphics.Dispose()
    $screenshotPath = Join-Path $Output "$name.png"
    $bitmap.Save($screenshotPath)
    $bitmap.Dispose()
  }
}

$env:LOCAL_TAG_PLAYER_DATA_DIR = $Profile
$env:LOCAL_TAG_PLAYER_SCREENSHOT_DIR = $Output
& $Flutter test integration_test/player_queue_screenshot_test.dart -d windows
$testExitCode = $LASTEXITCODE
Wait-Job $captureJob -Timeout 15 | Out-Null
Receive-Job $captureJob
Remove-Job $captureJob -Force
exit $testExitCode
