param(
  [Parameter(Mandatory = $true)]
  [string]$Manifest,
  [string]$Flutter = 'flutter',
  [string]$FFprobe = '',
  # 默认只门禁正式 MediaKit Texture；HWND 只能用于同机呈现链路对照，绝不改变默认后端。
  [ValidateSet('mediaKit', 'hwnd')]
  [string]$Backend = 'mediaKit',
  [string]$Output = '',
  [switch]$PreflightOnly,
  [switch]$Resume,
  [ValidateRange(0, 30)]
  [int]$CaseCooldownSeconds = 5,
  [ValidateRange(1, 3)]
  [int]$MaxAttemptsPerCase = 2
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
  throw "Seek latency manifest not found: $Manifest"
}
if (-not $FFprobe) {
  $FFprobe = Join-Path $PSScriptRoot '..\windows\tools\ffmpeg\bin\ffprobe.exe'
}
if (-not (Test-Path -LiteralPath $FFprobe -PathType Leaf)) {
  throw "ffprobe not found: $FFprobe"
}
if (-not $Output) {
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $Output = Join-Path $PSScriptRoot "..\artifacts\player_seek_latency_$stamp"
}
$Output = [System.IO.Path]::GetFullPath($Output)
if ((Test-Path -LiteralPath $Output) -and -not $Resume) {
  throw "Output directory already exists: $Output"
}
if ($Resume -and -not (Test-Path -LiteralPath $Output -PathType Container)) {
  throw "Resume output directory does not exist: $Output"
}

$manifestData = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$cases = @($manifestData.cases)
$expectedIds = @(
  foreach ($resolution in @('1080p', '4k')) {
    foreach ($codec in @('h264', 'hevc', 'av1')) {
      foreach ($gop in @('short-gop', 'long-gop')) {
        "$resolution-$codec-$gop"
      }
    }
  }
)
if ($cases.Count -ne $expectedIds.Count -or
    @($cases.id | Sort-Object -Unique).Count -ne $expectedIds.Count -or
    @($expectedIds | Where-Object { $_ -notin $cases.id }).Count -ne 0) {
  throw 'Manifest must contain exactly 12 1080p/4k x H.264/HEVC/AV1 x short-gop/long-gop cases'
}

function Get-VideoProbe {
  param([string]$Path)
  $raw = & $FFprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of json -- $Path
  if ($LASTEXITCODE -ne 0) { throw 'ffprobe could not read matrix sample' }
  $probe = $raw | ConvertFrom-Json
  $stream = @($probe.streams) | Select-Object -First 1
  if ($null -eq $stream) { throw 'Matrix sample has no video stream' }
  return $stream
}

function Get-MaxGopSeconds {
  param([string]$Path)
  $raw = & $FFprobe -v error -select_streams v:0 -show_entries packet=pts_time,flags -of csv=p=0 -- $Path
  if ($LASTEXITCODE -ne 0) { throw 'ffprobe could not read matrix GOP' }
  $keyframes = @(
    $raw | ForEach-Object {
      $parts = $_ -split ',', 2
      if ($parts.Count -eq 2 -and $parts[1] -match 'K') { [double]$parts[0] }
    }
  )
  if ($keyframes.Count -lt 2) { throw 'Matrix sample has insufficient keyframes to verify GOP' }
  $largest = 0.0
  for ($index = 1; $index -lt $keyframes.Count; $index++) {
    $largest = [Math]::Max($largest, $keyframes[$index] - $keyframes[$index - 1])
  }
  return $largest
}

$verifiedCases = @()
foreach ($case in $cases | Sort-Object id) {
  foreach ($property in @('id', 'path', 'codec', 'width', 'height', 'gop', 'p95BudgetMs')) {
    if ($null -eq $case.$property -or "$($case.$property)".Trim().Length -eq 0) {
      throw "Case $($case.id) is missing $property"
    }
  }
  if (-not (Test-Path -LiteralPath $case.path -PathType Leaf)) {
    throw "Local media for case $($case.id) does not exist"
  }
  $probe = Get-VideoProbe -Path $case.path
  if ($probe.codec_name -ne $case.codec -or [int]$probe.width -ne [int]$case.width -or [int]$probe.height -ne [int]$case.height) {
    throw "Actual codec or resolution for case $($case.id) does not match manifest"
  }
  $largestGopSeconds = Get-MaxGopSeconds -Path $case.path
  if ($case.gop -eq 'short-gop' -and $largestGopSeconds -gt 1.1) {
    throw "Case $($case.id) is not short GOP (largest keyframe interval $largestGopSeconds seconds)"
  }
  if ($case.gop -eq 'long-gop' -and $largestGopSeconds -lt 4.0) {
    throw "Case $($case.id) is not long GOP (largest keyframe interval $largestGopSeconds seconds)"
  }

  $file = Get-Item -LiteralPath $case.path
  if ($null -ne $case.PSObject.Properties['sampleIdentity']) {
    $identity = $case.sampleIdentity
    if ([long]$identity.fileSizeBytes -ne [long]$file.Length) {
      throw "Local media identity changed for case $($case.id): file size mismatch"
    }
    $actualWriteUnixMilliseconds =
      ([DateTimeOffset]$file.LastWriteTimeUtc).ToUnixTimeMilliseconds()
    if ([long]$identity.lastWriteUnixMilliseconds -ne $actualWriteUnixMilliseconds) {
      throw "Local media identity changed for case $($case.id): timestamp mismatch"
    }
  }

  $verifiedCases += [pscustomobject]@{
    manifestCase = $case
    probe = $probe
    maxGopSeconds = $largestGopSeconds
    fileSizeBytes = [long]$file.Length
    lastWriteUnixMilliseconds =
      ([DateTimeOffset]$file.LastWriteTimeUtc).ToUnixTimeMilliseconds()
  }
}

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$manifestSha256 = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash.ToLowerInvariant()
$preflight = [ordered]@{
  status = 'pass'
  backend = $Backend
  manifestSha256 = $manifestSha256
  caseCount = $verifiedCases.Count
  samplePathsOmitted = $true
  cases = @($verifiedCases | ForEach-Object {
      [ordered]@{
        id = [string]$_.manifestCase.id
        codec = [string]$_.probe.codec_name
        width = [int]$_.probe.width
        height = [int]$_.probe.height
        gop = [string]$_.manifestCase.gop
        maxGopSeconds = [Math]::Round([double]$_.maxGopSeconds, 3)
        fileSizeBytes = [long]$_.fileSizeBytes
        lastWriteUnixMilliseconds = [long]$_.lastWriteUnixMilliseconds
      }
    })
}
$preflight | ConvertTo-Json -Depth 10 |
  Set-Content -LiteralPath (Join-Path $Output 'preflight-summary.json') -Encoding utf8
Write-Output "PLAYER_SEEK_PREFLIGHT $($preflight | ConvertTo-Json -Compress -Depth 10)"
if ($PreflightOnly) {
  return
}

$results = @()
foreach ($verified in $verifiedCases) {
  $case = $verified.manifestCase
  $probe = $verified.probe
  $largestGopSeconds = $verified.maxGopSeconds
  $logPath = Join-Path $Output "$($case.id).log"
  $attemptCount = 0
  $line = if ($Resume -and (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    Select-String -LiteralPath $logPath -Pattern 'PLAYER_SEEK_LATENCY ' |
      Select-Object -Last 1
  } else {
    $null
  }
  if ($null -ne $line) {
    $existingMetric = ($line.Line -replace '.*PLAYER_SEEK_LATENCY ', '') |
      ConvertFrom-Json
    if ([string]$existingMetric.case -ne [string]$case.id -or
        [string]$existingMetric.backend -ne $Backend -or
        [int]$existingMetric.budgetMs -ne [int]$case.p95BudgetMs) {
      $line = $null
    }
  }
  if ($null -eq $line) {
    for ($attempt = 1; $attempt -le $MaxAttemptsPerCase; $attempt++) {
      $attemptCount = $attempt
      if ($CaseCooldownSeconds -gt 0) {
        Start-Sleep -Seconds $CaseCooldownSeconds
      }
      # 每次尝试保留独立证据；只有成功日志才复制为 Resume 可复用的主日志。
      $attemptLogPath = Join-Path $Output "$($case.id).attempt-$attempt.log"
      $env:LOCAL_TAG_PLAYER_SEEK_SAMPLE = $case.path
      $env:LOCAL_TAG_PLAYER_SEEK_CASE = $case.id
      $env:LOCAL_TAG_PLAYER_SEEK_P95_BUDGET_MS = "$($case.p95BudgetMs)"
      $env:LOCAL_TAG_PLAYER_SEEK_BACKEND = $Backend
      try {
        & $Flutter test integration_test/player_seek_latency_gate_test.dart -d windows --timeout 4m *>&1 |
          Tee-Object -FilePath $attemptLogPath
        $runExitCode = $LASTEXITCODE
      } finally {
        Remove-Item Env:LOCAL_TAG_PLAYER_SEEK_SAMPLE -ErrorAction SilentlyContinue
        Remove-Item Env:LOCAL_TAG_PLAYER_SEEK_CASE -ErrorAction SilentlyContinue
        Remove-Item Env:LOCAL_TAG_PLAYER_SEEK_P95_BUDGET_MS -ErrorAction SilentlyContinue
        Remove-Item Env:LOCAL_TAG_PLAYER_SEEK_BACKEND -ErrorAction SilentlyContinue
      }
      $line = if ($runExitCode -eq 0) {
        Select-String -LiteralPath $attemptLogPath -Pattern 'PLAYER_SEEK_LATENCY ' |
          Select-Object -Last 1
      } else {
        $null
      }
      if ($null -ne $line) {
        Copy-Item -LiteralPath $attemptLogPath -Destination $logPath -Force
        $line = Select-String -LiteralPath $logPath -Pattern 'PLAYER_SEEK_LATENCY ' |
          Select-Object -Last 1
        break
      }
      Write-Warning "Seek case $($case.id) attempt $attempt/$MaxAttemptsPerCase failed."
    }
  }
  if ($null -eq $line) {
    throw "Real seek gate failed for case $($case.id) after $MaxAttemptsPerCase attempts"
  }
  $metric = ($line.Line -replace '.*PLAYER_SEEK_LATENCY ', '') | ConvertFrom-Json
  $results += [pscustomobject]@{
    backend = $metric.backend
    case = $case.id
    codec = $probe.codec_name
    width = [int]$probe.width
    height = [int]$probe.height
    maxGopSeconds = [Math]::Round($largestGopSeconds, 3)
    p50Ms = $metric.p50Ms
    p95Ms = $metric.p95Ms
    maxMs = $metric.maxMs
    budgetMs = $metric.budgetMs
    hwdec = $metric.hwdec
    attempts = $attemptCount
  }
}

$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Output 'summary.json') -Encoding utf8

# 只有正式 MediaKit Texture 的六个真实长 GOP p95 才能校准页面默认的预览节流与
# 最终新帧等待档位。HWND 是独立呈现链路实验，不能反向改变正式路径的用户体验参数。
if ($Backend -eq 'mediaKit') {
  $longGopResults = @($results | Where-Object { $_.case -like '*-long-gop' })
  if ($longGopResults.Count -ne 6) {
    throw 'Expected six long-GOP measurements before choosing the seek preview policy'
  }
  $longGopP95Ms = [int](($longGopResults | Measure-Object -Property p95Ms -Maximum).Maximum)
  if ($longGopP95Ms -le 750) {
    $policy = [pscustomobject]@{
      longGopP95Ms = $longGopP95Ms
      previewIntervalMs = 64
      previewFps = 15.6
      finalFrameTimeoutMs = 750
    }
  } elseif ($longGopP95Ms -le 1200) {
    $policy = [pscustomobject]@{
      longGopP95Ms = $longGopP95Ms
      previewIntervalMs = 96
      previewFps = 10.4
      finalFrameTimeoutMs = 1200
    }
  } else {
    $policy = [pscustomobject]@{
      longGopP95Ms = $longGopP95Ms
      previewIntervalMs = 125
      previewFps = 8.0
      finalFrameTimeoutMs = 1800
    }
  }
  $policy | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Output 'long_gop_policy.json') -Encoding utf8
  Write-Output "PLAYER_SEEK_LONG_GOP_POLICY $($policy | ConvertTo-Json -Compress)"
} else {
  Write-Output 'PLAYER_SEEK_LONG_GOP_POLICY skipped=hwnd-qa-only'
}
$results | Format-Table backend, case, p50Ms, p95Ms, maxMs, budgetMs, hwdec
