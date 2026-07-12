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
  Add-Type -AssemblyName System.Windows.Forms

  foreach ($name in @('player-queue-collapsed', 'player-queue-restored')) {
    $marker = Join-Path $Output "$name.ready"
    while (-not (Test-Path -LiteralPath $marker)) { Start-Sleep -Milliseconds 100 }
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
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
