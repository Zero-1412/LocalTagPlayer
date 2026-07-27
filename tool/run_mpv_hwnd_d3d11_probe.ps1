param(
  [Parameter(Mandatory = $true)]
  [string]$MpvPath,
  [Parameter(Mandatory = $true)]
  [string]$SamplePath,
  [string]$OutputDirectory = ".local/qa/mpv-hwnd-d3d11",
  [ValidateRange(5, 60)]
  [int]$DurationSeconds = 15
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$workspace = Split-Path -Parent $PSScriptRoot
$mpv = [System.IO.Path]::GetFullPath($MpvPath)
$sample = [System.IO.Path]::GetFullPath($SamplePath)
$output = [System.IO.Path]::GetFullPath(
  (Join-Path $workspace $OutputDirectory)
)
if (-not (Test-Path -LiteralPath $mpv -PathType Leaf)) {
  throw "mpv.exe 不存在：$mpv"
}
if (-not (Test-Path -LiteralPath $sample -PathType Leaf)) {
  throw "匿名 QA 片源不存在：$sample"
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

<#
 * 把仅用于本机 QA 的路径转换为 Windows 命令行参数。
 * 该探针不读取用户媒体库；调用方必须显式传入匿名样本和隔离 mpv。
#>
function ConvertTo-QuotedArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  return '"' + $Value.Replace('"', '\"') + '"'
}
<# 向 mpv JSON IPC 写入一个只读请求，并跳过可能先到达的异步事件。 #>
function Invoke-MpvIpc {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.StreamWriter]$Writer,
    [Parameter(Mandatory = $true)]
    [System.IO.StreamReader]$Reader,
    [Parameter(Mandatory = $true)]
    [int]$RequestId,
    [Parameter(Mandatory = $true)]
    [object[]]$Command
  )
  $request = [ordered]@{
    command = $Command
    request_id = $RequestId
  }
  $Writer.WriteLine(($request | ConvertTo-Json -Compress -Depth 6))
  while ($true) {
    $line = $Reader.ReadLine()
    if ($null -eq $line) {
      throw "mpv IPC 在响应请求前关闭。"
    }
    $response = $line | ConvertFrom-Json
    if ($response.request_id -eq $RequestId) {
      return $response
    }
  }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Local Tag Player HWND / D3D11 QA"
$form.ClientSize = [System.Drawing.Size]::new(960, 540)
$form.StartPosition = "CenterScreen"
$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Fill"
$panel.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($panel)
$form.Show()
[System.Windows.Forms.Application]::DoEvents()

# 强制创建子 HWND；mpv 只拥有该窗口内的视频区域，不拥有外层 QA 窗口。
$childHandle = $panel.Handle.ToInt64()
$pipeName = "ltp-mpv-hwnd-$PID-$([Guid]::NewGuid().ToString('N'))"
$pipePath = "\\.\pipe\$pipeName"
$stdoutPath = Join-Path $output "mpv.log"
$stderrPath = Join-Path $output "mpv-error.log"
$screenshotPath = Join-Path $output "hwnd-d3d11.png"
$videoFramePath = Join-Path $output "decoded-video-frame.png"
$reportPath = Join-Path $output "result.json"

$arguments = @(
  "--no-config",
  "--idle=yes",
  "--keep-open=yes",
  "--force-window=yes",
  "--vo=gpu-next",
  "--gpu-api=d3d11",
  "--gpu-context=d3d11",
  "--hwdec=d3d11va",
  "--input-ipc-server=$pipePath",
  "--wid=$childHandle",
  "--msg-level=all=warn,vo/gpu=info,vd=info",
  (ConvertTo-QuotedArgument $sample)
) -join " "

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $mpv
$startInfo.Arguments = $arguments
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo
$standardOutput = $null
$standardError = $null
$pipe = $null
$writer = $null
$reader = $null
$processStarted = $false

try {
  if (-not $process.Start()) {
    throw "无法启动隔离 mpv。"
  }
  $processStarted = $true
  $standardOutput = $process.StandardOutput.ReadToEndAsync()
  $standardError = $process.StandardError.ReadToEndAsync()

  $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
    ".",
    $pipeName,
    [System.IO.Pipes.PipeDirection]::InOut,
    [System.IO.Pipes.PipeOptions]::None
  )
  $pipe.Connect(10000)
  $writer = New-Object System.IO.StreamWriter($pipe)
  $writer.AutoFlush = $true
  $reader = New-Object System.IO.StreamReader($pipe)

  $startedAt = Get-Date
  $requestId = 1
  $hwdecCurrent = "unavailable"
  while (((Get-Date) - $startedAt).TotalSeconds -lt $DurationSeconds) {
    [System.Windows.Forms.Application]::DoEvents()
    $response = Invoke-MpvIpc -Writer $writer -Reader $reader `
      -RequestId $requestId -Command @("get_property", "hwdec-current")
    $requestId++
    if ($response.error -eq "success") {
      $hwdecCurrent = [string]$response.data
    }
    if ($hwdecCurrent -eq "d3d11va") {
      break
    }
    Start-Sleep -Milliseconds 250
  }

  # 硬解属性通常先于首个可见帧就绪；再让出短暂消息循环，避免截到初始化黑帧。
  $visibleFrameDeadline = (Get-Date).AddSeconds(2)
  while ((Get-Date) -lt $visibleFrameDeadline) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 50
  }

  # 窗口截图只证明子 HWND 可见且位置正确；硬解结论只以 mpv 属性为准。
  [System.Windows.Forms.Application]::DoEvents()
  $screenPoint = $form.PointToScreen([System.Drawing.Point]::Empty)
  $bitmap = [System.Drawing.Bitmap]::new(
    $form.ClientSize.Width,
    $form.ClientSize.Height
  )
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen(
      $screenPoint,
      [System.Drawing.Point]::Empty,
      $form.ClientSize
    )
    $bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }

  # D3D 窗口可能被桌面合成器以覆盖层呈现，屏幕复制会得到黑帧；额外让 mpv
  # 导出当前已解码视频帧，以区分“抓屏限制”和“播放器没有输出画面”。
  $videoFrameResponse = Invoke-MpvIpc -Writer $writer -Reader $reader `
    -RequestId $requestId `
    -Command @("screenshot-to-file", $videoFramePath, "video")
  $requestId++

  $properties = [ordered]@{
    "hwdec-current" = $hwdecCurrent
  }
  foreach ($name in @(
      "current-vo",
      "gpu-api",
      "gpu-context",
      "decoder-frame-drop-count",
      "frame-drop-count",
      "vo-configured"
    )) {
    $response = Invoke-MpvIpc -Writer $writer -Reader $reader `
      -RequestId $requestId -Command @("get_property", $name)
    $requestId++
    $properties[$name] = if ($response.error -eq "success") {
      $response.data
    } else {
      "unavailable:$($response.error)"
    }
  }
  $report = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    childHwnd = $childHandle
    sampleName = [System.IO.Path]::GetFileName($sample)
    mpvSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $mpv).Hash
    properties = $properties
    screenshot = $screenshotPath
    decodedVideoFrame = if ($videoFrameResponse.error -eq "success" -and
      (Test-Path -LiteralPath $videoFramePath)) {
      $videoFramePath
    } else {
      "unavailable:$($videoFrameResponse.error)"
    }
    passed = $hwdecCurrent -eq "d3d11va"
  }
  $report | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $reportPath -Encoding UTF8

  Invoke-MpvIpc -Writer $writer -Reader $reader `
    -RequestId $requestId -Command @("quit") | Out-Null
  if (-not $process.WaitForExit(5000)) {
    $process.Kill()
  }
  $standardOutput.Result | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
  $standardError.Result | Set-Content -LiteralPath $stderrPath -Encoding UTF8

  Write-Host "HWND / D3D11 report: $reportPath"
  if (-not $report.passed) {
    throw "HWND / D3D11 非 copy 门禁未通过：hwdec-current=$hwdecCurrent"
  }
} finally {
  # reader、writer 共享同一命名管道；任一包装器都可能先关闭底层流。
  foreach ($resource in @($reader, $writer, $pipe)) {
    if ($null -eq $resource) { continue }
    try {
      $resource.Dispose()
    } catch [System.ObjectDisposedException] {
      # 资源已经由另一个包装器关闭，视为正常清理完成。
    }
  }
  if ($processStarted -and -not $process.HasExited) {
    $process.Kill()
    $process.WaitForExit()
  }
  $process.Dispose()
  $form.Close()
  $form.Dispose()
}
