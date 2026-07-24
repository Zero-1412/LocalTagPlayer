param(
  [string]$Repository = ".",
  [string]$BaseRef = "HEAD",
  [string]$RemoteName = "origin",
  [string]$MainBranch = "master"
)

$ErrorActionPreference = "Stop"

<#
 * 正式打包前检查所有远程开发分支是否已经进入主分支。
 *
 * 检查同时覆盖正常 merge、祖先关系和补丁等价；仍有独有提交时，会在临时
 * Worktree 中按稳定顺序试合并，从而在不污染真实工作树的前提下暴露分支间冲突。
#>

$repositoryRoot = (Resolve-Path -LiteralPath $Repository).Path
$gitRoot = (& git -C $repositoryRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
  throw "目标不是有效 Git 仓库：$repositoryRoot"
}

if ((& git -C $gitRoot status --porcelain).Count -gt 0) {
  throw "分支集成检查要求干净工作树：$gitRoot"
}

& git -C $gitRoot fetch $RemoteName --prune
if ($LASTEXITCODE -ne 0) {
  throw "无法刷新远程分支：$RemoteName"
}

$baseCommit = (& git -C $gitRoot rev-parse $BaseRef).Trim()
$mainRef = "$RemoteName/$MainBranch"
$mainCommit = (& git -C $gitRoot rev-parse $mainRef).Trim()
if ($LASTEXITCODE -ne 0) {
  throw "无法解析远程主分支：$mainRef"
}

# 标签和手动发布都必须基于远程主分支当前提交，避免验证 A 却打包 B。
if ($baseCommit -ne $mainCommit) {
  throw "待打包提交 $baseCommit 不是 $mainRef 当前提交 $mainCommit"
}

$remotePrefix = "refs/remotes/$RemoteName/"
$remoteBranches = @(
  & git -C $gitRoot for-each-ref `
    "--format=%(refname:short)" `
    "--sort=refname" `
    $remotePrefix |
      Where-Object {
        $_ -and
        $_ -ne "$RemoteName/HEAD" -and
        $_ -ne $mainRef -and
        $_ -notmatch "^$([regex]::Escape($RemoteName))$"
      }
)

$pendingBranches = [System.Collections.Generic.List[string]]::new()
foreach ($branch in $remoteBranches) {
  & git -C $gitRoot merge-base --is-ancestor $branch $BaseRef
  if ($LASTEXITCODE -eq 0) {
    Write-Host "已合并（祖先）：$branch"
    continue
  }

  # cherry-pick 或 rebase 后提交 ID 会变化；没有 `+` 表示补丁内容已经等价进入主分支。
  $uniquePatches = @(
    & git -C $gitRoot cherry $BaseRef $branch |
      Where-Object { $_ -match "^\+" }
  )
  if ($LASTEXITCODE -ne 0) {
    throw "无法比较分支补丁：$branch"
  }
  if ($uniquePatches.Count -eq 0) {
    Write-Host "已合并（补丁等价）：$branch"
    continue
  }
  $pendingBranches.Add($branch)
}

if ($pendingBranches.Count -eq 0) {
  Write-Host "所有远程开发分支均已进入 $mainRef。"
  exit 0
}

Write-Host "检测到未集成远程分支：$($pendingBranches -join ', ')"

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
  "local-tag-player-release-integration-" + [Guid]::NewGuid().ToString("N")
)
try {
  & git -C $gitRoot worktree add --detach $temporaryRoot $BaseRef
  if ($LASTEXITCODE -ne 0) {
    throw "无法创建临时集成 Worktree"
  }
  & git -C $temporaryRoot config user.name "Local Tag Player Release Gate"
  & git -C $temporaryRoot config user.email "release-gate@local.invalid"

  foreach ($branch in $pendingBranches) {
    Write-Host "试合并未进入主分支的内容：$branch"
    & git -C $temporaryRoot merge --no-ff --no-edit $branch
    if ($LASTEXITCODE -ne 0) {
      $conflicts = @(
        & git -C $temporaryRoot diff --name-only --diff-filter=U
      )
      throw "分支 $branch 与累计集成结果冲突：$($conflicts -join ', ')"
    }
  }

  # 即使试合并无冲突，也不能从临时结果直接打包；代码必须先经过主分支审查和提交。
  throw "以下远程分支仍有未进入 $mainRef 的独有提交：$($pendingBranches -join ', ')"
}
finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    & git -C $gitRoot worktree remove --force $temporaryRoot
  }
  & git -C $gitRoot worktree prune
}
