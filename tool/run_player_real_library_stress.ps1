param(
  [string]$Flutter = 'E:\flutter\bin\flutter.bat',
  [int]$DurationSeconds = 1800,
  [int]$Seed = 20260713,
  [string]$Output = "$env:TEMP\ltp_real_library_stress"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Output | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue "$Output\*.ready", "$Output\*.png", "$Output\*.csv", "$Output\stress.done"

# 只读取进程指标并写入压测目录，不创建 UIA 客户端。

$monitorJob = Start-Job -ArgumentList $Output -ScriptBlock {
  param($Output)
  $metrics = Join-Path $Output 'process-metrics.csv'
  'timestamp,cpu_seconds,threads,working_set_mb,private_mb,handles,responding' | Set-Content $metrics
  while (-not (Test-Path -LiteralPath (Join-Path $Output 'stress.done'))) {
    $process = Get-Process local_tag_player -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $process) {
      $line = '{0},{1:F3},{2},{3:F1},{4:F1},{5},{6}' -f `
        $(Get-Date -Format o),
        $process.TotalProcessorTime.TotalSeconds,
        $process.Threads.Count,
        ($process.WorkingSet64 / 1MB),
        ($process.PrivateMemorySize64 / 1MB),
        $process.HandleCount,
        $process.Responding
      Add-Content -LiteralPath $metrics -Value $line
    }
    Start-Sleep -Seconds 15
  }
}

# 只按 marker 保存窗口像素，不查询、启用或关闭应用语义树。

$captureJob = Start-Job -ArgumentList $Output -ScriptBlock {
  param($Output)
  Add-Type -AssemblyName System.Drawing
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpStressWindowCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
  [LtpStressWindowCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
  $captured = @{}
  while (-not (Test-Path -LiteralPath (Join-Path $Output 'stress.done'))) {
    foreach ($marker in Get-ChildItem -LiteralPath $Output -Filter '*.ready' -ErrorAction SilentlyContinue) {
      if ($captured.ContainsKey($marker.FullName)) { continue }
      $process = Get-Process local_tag_player -ErrorAction SilentlyContinue |
        Where-Object MainWindowHandle -ne 0 |
        Select-Object -First 1
      if ($null -eq $process) { continue }
      $rect = New-Object LtpStressWindowCapture+RECT
      if (-not ([LtpStressWindowCapture]::GetWindowRect($process.MainWindowHandle, [ref]$rect))) { continue }
      $bitmap = [System.Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
      $graphics.Dispose()
      $bitmap.Save((Join-Path $Output "$($marker.BaseName).png"))
      $bitmap.Dispose()
      $captured[$marker.FullName] = $true
    }
    Start-Sleep -Milliseconds 200
  }
}

$env:LOCAL_TAG_PLAYER_STRESS_SECONDS = $DurationSeconds.ToString()
$env:LOCAL_TAG_PLAYER_STRESS_SEED = $Seed.ToString()
$env:LOCAL_TAG_PLAYER_STRESS_OUTPUT = $Output
try {
  & $Flutter test integration_test/player_real_library_stress_test.dart -d windows
  $testExitCode = $LASTEXITCODE
} finally {
  New-Item -ItemType File -Force -Path "$Output\stress.done" | Out-Null
  Wait-Job $monitorJob, $captureJob -Timeout 20 | Out-Null
  Receive-Job $monitorJob, $captureJob
  Remove-Job $monitorJob, $captureJob -Force
}
exit $testExitCode
