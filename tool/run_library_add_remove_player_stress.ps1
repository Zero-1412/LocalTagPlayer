param(
  [string]$Flutter = 'E:\flutter\bin\flutter.bat',
  [string]$Ffmpeg = '<project-root>\windows\tools\ffmpeg\bin\ffmpeg.exe',
  [string]$SourceProfile = "$env:APPDATA\com.example\local_tag_player\LocalTagPlayer",
  [string]$RootPath = 'X:\test-media',
  [int]$Cycles = 10,
  [int]$Seed = 20260714,
  [int]$ReleaseTailSeconds = 60,
  [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Output) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $Output = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\artifacts')) "library_add_remove_stress_$stamp"
}
if (Test-Path -LiteralPath $Output) {
  throw "输出目录已存在，拒绝覆盖：$Output"
}
if (-not (Test-Path -LiteralPath $SourceProfile)) {
  throw "真实媒体库 profile 不存在：$SourceProfile"
}
if (-not (Test-Path -LiteralPath $RootPath)) {
  throw "真实媒体目录不存在：$RootPath"
}
if (-not (Test-Path -LiteralPath $Ffmpeg)) {
  throw "随构建供应的 FFmpeg 不存在：$Ffmpeg"
}

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$profile = Join-Path $Output 'profile'
New-Item -ItemType Directory -Force -Path $profile | Out-Null

# 复制数据库和缩略图到可丢弃 profile；媒体文件仍从 X:\test-media 原地只读，不复制 5.9 TB 内容。
& robocopy $SourceProfile $profile /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XF library.db-shm library.db-wal /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) {
  throw "隔离 profile 复制失败，robocopy exit code=$LASTEXITCODE"
}
Set-Content -LiteralPath (Join-Path $Output 'phase.current') -Value 'test_start|0'

# 每秒只读进程、GPU 与进程 I/O；不查询或更改 Flutter 语义树。
$monitorJob = Start-Job -ArgumentList $Output -ScriptBlock {
  param($Output)
  $metrics = Join-Path $Output 'process-metrics.csv'
  'timestamp,phase,cycle,cpu_seconds,threads,working_set_mb,private_mb,handles,responding,io_read_mb_s,io_write_mb_s,gpu_sample_valid,gpu_dedicated_mb,gpu_shared_mb,gpu_committed_mb' | Set-Content $metrics
  while (-not (Test-Path -LiteralPath (Join-Path $Output 'stress.done'))) {
    $started = Get-Date
    $process = Get-Process local_tag_player -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $process) {
      $phase = 'unknown'
      $cycle = 0
      $phaseFile = Join-Path $Output 'phase.current'
      if (Test-Path -LiteralPath $phaseFile) {
        $parts = ((Get-Content -LiteralPath $phaseFile -Raw).Trim()) -split '\|', 2
        if ($parts.Count -ge 1 -and $parts[0]) { $phase = $parts[0] }
        if ($parts.Count -ge 2) { [void][int]::TryParse($parts[1], [ref]$cycle) }
      }
      $gpuDedicated = 0.0
      $gpuShared = 0.0
      $gpuCommitted = 0.0
      $gpuSampleValid = $false
      $ioRead = 0.0
      $ioWrite = 0.0
      try {
        $gpuPrefix = '\GPU Process Memory(pid_' + $process.Id + '_*)\'
        $gpu = Get-Counter -Counter @(
          ($gpuPrefix + 'Dedicated Usage'),
          ($gpuPrefix + 'Shared Usage'),
          ($gpuPrefix + 'Total Committed')
        ) -ErrorAction Stop
        foreach ($sample in $gpu.CounterSamples) {
          if ($sample.Path -like '*\dedicated usage') { $gpuDedicated += $sample.CookedValue } elseif ($sample.Path -like '*\shared usage') { $gpuShared += $sample.CookedValue } elseif ($sample.Path -like '*\total committed') { $gpuCommitted += $sample.CookedValue }
        }
        $gpuSampleValid = $true
      } catch {}
      try {
        $instance = (Get-Counter '\Process(local_tag_player*)\ID Process' -ErrorAction Stop).CounterSamples |
          Where-Object { [int]$_.CookedValue -eq $process.Id } |
          Select-Object -First 1
        if ($null -ne $instance) {
          $name = ($instance.InstanceName -replace '#', '`#')
          $io = Get-Counter -Counter @(
            "\Process($name)\IO Read Bytes/sec",
            "\Process($name)\IO Write Bytes/sec"
          ) -ErrorAction Stop
          foreach ($sample in $io.CounterSamples) {
            if ($sample.Path -like '*\io read bytes/sec') { $ioRead = $sample.CookedValue } elseif ($sample.Path -like '*\io write bytes/sec') { $ioWrite = $sample.CookedValue }
          }
        }
      } catch {}
      $line = '{0},{1},{2},{3:F3},{4},{5:F1},{6:F1},{7},{8},{9:F2},{10:F2},{11},{12:F1},{13:F1},{14:F1}' -f `
        $(Get-Date -Format o), $phase, $cycle,
        $process.TotalProcessorTime.TotalSeconds, $process.Threads.Count,
        ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB),
        $process.HandleCount, $process.Responding,
        ($ioRead / 1MB), ($ioWrite / 1MB), $gpuSampleValid,
        ($gpuDedicated / 1MB), ($gpuShared / 1MB), ($gpuCommitted / 1MB)
      Add-Content -LiteralPath $metrics -Value $line
    }
    $remaining = 1000 - ((Get-Date) - $started).TotalMilliseconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
  }
}

# 关键阶段使用纯窗口像素截图；不创建 Windows UIA 客户端。
$captureJob = Start-Job -ArgumentList $Output -ScriptBlock {
  param($Output)
  Add-Type -AssemblyName System.Drawing
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LtpLibraryStressCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
'@
  [LtpLibraryStressCapture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
  $captured = @{}
  while (-not (Test-Path -LiteralPath (Join-Path $Output 'stress.done'))) {
    foreach ($marker in Get-ChildItem -LiteralPath $Output -Filter 'cycle-*.ready' -ErrorAction SilentlyContinue) {
      if ($captured.ContainsKey($marker.FullName)) { continue }
      $process = Get-Process local_tag_player -ErrorAction SilentlyContinue |
        Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
      if ($null -eq $process) { continue }
      $rect = New-Object LtpLibraryStressCapture+RECT
      if (-not ([LtpLibraryStressCapture]::GetWindowRect($process.MainWindowHandle, [ref]$rect))) { continue }
      $bitmap = [System.Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
      $graphics.Dispose()
      $bitmap.Save((Join-Path $Output "$($marker.BaseName).png"))
      $bitmap.Dispose()
      $captured[$marker.FullName] = $true
    }
    Start-Sleep -Milliseconds 150
  }
}

# 测试完成基线准备后再启动 gdigrab，录制窗口像素；通过 stdin 的 q 正常封装 MKV。
$recordJob = Start-Job -ArgumentList $Output, $Ffmpeg -ScriptBlock {
  param($Output, $Ffmpeg)
  $request = Join-Path $Output 'recorder-start-request.ready'
  $deadline = (Get-Date).AddMinutes(5)
  while (-not (Test-Path -LiteralPath $request) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-Path -LiteralPath $request)) { throw '等待录像启动请求超时' }
  $video = Join-Path $Output 'stress-recording.mkv'
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $Ffmpeg
  $psi.Arguments = "-hide_banner -loglevel warning -nostats -f gdigrab -framerate 30 -draw_mouse 0 -i `"title=local_tag_player`" -c:v libx264 -preset ultrafast -crf 24 -pix_fmt yuv420p `"$video`""
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardError = $true
  $recorder = [System.Diagnostics.Process]::new()
  $recorder.StartInfo = $psi
  if (-not $recorder.Start()) { throw '无法启动 FFmpeg 窗口录屏' }
  $errorOutput = $recorder.StandardError.ReadToEndAsync()
  New-Item -ItemType File -Force -Path (Join-Path $Output 'recorder-ready.ready') | Out-Null
  while (-not (Test-Path -LiteralPath (Join-Path $Output 'stress.done')) -and -not $recorder.HasExited) {
    Start-Sleep -Milliseconds 200
  }
  if (-not $recorder.HasExited) {
    $recorder.StandardInput.WriteLine('q')
    if (-not $recorder.WaitForExit(15000)) { $recorder.Kill() }
  }
  $errorOutput.Result | Set-Content -LiteralPath (Join-Path $Output 'recorder.log')
  if ($recorder.ExitCode -ne 0) { throw "FFmpeg 录屏退出码：$($recorder.ExitCode)" }
}

$env:LOCAL_TAG_PLAYER_DATA_DIR = $profile
$env:LOCAL_TAG_PLAYER_LIBRARY_STRESS_ROOT = $RootPath
$env:LOCAL_TAG_PLAYER_LIBRARY_STRESS_CYCLES = $Cycles.ToString()
$env:LOCAL_TAG_PLAYER_STRESS_SEED = $Seed.ToString()
$env:LOCAL_TAG_PLAYER_RELEASE_TAIL_SECONDS = $ReleaseTailSeconds.ToString()
$env:LOCAL_TAG_PLAYER_STRESS_OUTPUT = $Output
$testExitCode = 1
try {
  & $Flutter test integration_test/library_add_remove_player_stress_test.dart -d windows --timeout 35m *>&1 |
    Tee-Object -FilePath (Join-Path $Output 'stress.log')
  $testExitCode = $LASTEXITCODE
} finally {
  New-Item -ItemType File -Force -Path (Join-Path $Output 'stress.done') | Out-Null
  Wait-Job $monitorJob, $captureJob, $recordJob -Timeout 30 | Out-Null
  Receive-Job $monitorJob, $captureJob, $recordJob
  Remove-Job $monitorJob, $captureJob, $recordJob -Force
  Remove-Item Env:LOCAL_TAG_PLAYER_DATA_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_LIBRARY_STRESS_ROOT -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_LIBRARY_STRESS_CYCLES -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STRESS_SEED -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_RELEASE_TAIL_SECONDS -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_TAG_PLAYER_STRESS_OUTPUT -ErrorAction SilentlyContinue
}

& (Join-Path $PSScriptRoot 'summarize_library_add_remove_stress.ps1') -InputDirectory $Output
exit $testExitCode
