param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern("^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$")]
  [string]$Version,

  [string]$Repository = ".",

  [string]$NotesPath = "",

  [string]$SummaryPath = $env:GITHUB_STEP_SUMMARY
)

$ErrorActionPreference = "Stop"

<#
 * 在正式构建前按应用更新弹窗的真实纯文本结构预览发布说明。
 *
 * 应用当前使用 SelectableText 原样展示 GitHub Release 正文，因此这里禁止会直接
 * 暴露给用户的 Markdown 标题、强调标记、代码标记、裸链接和自动 Changelog。
 * 调用方可以传入 NotesPath 测试候选文件；正式发布默认按版本号读取 docs 目录。
#>

$repositoryRoot = (Resolve-Path -LiteralPath $Repository).Path
$resolvedNotesPath = if ([string]::IsNullOrWhiteSpace($NotesPath)) {
  Join-Path $repositoryRoot "docs/RELEASE_NOTES_$Version.md"
}
else {
  (Resolve-Path -LiteralPath $NotesPath).Path
}

if (-not (Test-Path -LiteralPath $resolvedNotesPath -PathType Leaf)) {
  throw "缺少用户可读发布说明：$resolvedNotesPath"
}

$notes = (Get-Content -LiteralPath $resolvedNotesPath -Raw -Encoding UTF8).
  Replace("`r`n", "`n").
  Trim()
if ([string]::IsNullOrWhiteSpace($notes)) {
  throw "发布说明不能为空：$resolvedNotesPath"
}
if ($notes.Length -gt 2400) {
  throw "发布说明超过 2400 个字符，应用内弹窗不适合承载：$($notes.Length)"
}

$lines = @($notes -split "`n")
$firstContentLine = $lines |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
  Select-Object -First 1
if ($firstContentLine.Trim() -ne "本次更新") {
  throw "发布说明第一段必须是【本次更新】，不能先展示签名或内部实现信息"
}

$updateIndex = [Array]::IndexOf($lines, "本次更新")
$dataSafetyIndex = [Array]::IndexOf($lines, "数据安全")
$packageIndex = [Array]::IndexOf($lines, "安装包说明")
if (
  $updateIndex -lt 0 -or
  $dataSafetyIndex -le $updateIndex -or
  $packageIndex -le $dataSafetyIndex
) {
  throw "发布说明必须依次包含【本次更新】【数据安全】【安装包说明】"
}

$userChanges = @(
  $lines[($updateIndex + 1)..($dataSafetyIndex - 1)] |
    Where-Object { $_ -match "^- " }
)
if ($userChanges.Count -lt 3) {
  throw "【本次更新】至少需要 3 条用户可感知变化，当前只有 $($userChanges.Count) 条"
}

$forbiddenPatterns = [ordered]@{
  "Markdown 标题" = "^\s*#{1,6}\s+"
  "Markdown 强调标记" = "(\*\*|__)"
  "Markdown 代码标记" = "``"
  "裸链接" = "https?://"
  "自动 Changelog" = "(?i)Full Changelog"
}
foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
  if ($notes -match $entry.Value) {
    throw "发布说明包含应用会原样显示的$($entry.Key)：$($Matches[0])"
  }
}

$preview = @"
发现新版本

Local Tag Player $Version

更新内容

$notes

[查看发布页]  [稍后提醒]  [下载并安装]
"@

Write-Host ""
Write-Host "================ 应用内更新弹窗文案预览 ================"
Write-Host $preview
Write-Host "========================================================="
Write-Host "发布说明预览门禁通过：$resolvedNotesPath"

if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
  $summaryDirectory = Split-Path -Parent $SummaryPath
  if (
    -not [string]::IsNullOrWhiteSpace($summaryDirectory) -and
    -not (Test-Path -LiteralPath $summaryDirectory)
  ) {
    New-Item -ItemType Directory -Path $summaryDirectory | Out-Null
  }
  $encodedPreview = [System.Net.WebUtility]::HtmlEncode($preview)
  @"
## 应用内更新弹窗文案预览

<pre>$encodedPreview</pre>

已通过纯文本、章节顺序、用户更新条目数量和弹窗长度门禁。
"@ | Add-Content -LiteralPath $SummaryPath -Encoding UTF8
}
