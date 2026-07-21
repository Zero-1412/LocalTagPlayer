# 桌面正式版打包

应用版本以 `pubspec.yaml` 为唯一来源。`0.1.0+1` 对应对外安装包版本 `0.1.0`。

## GitHub Release

向远程推送符合 `vX.Y.Z` 形式的标签后，`.github/workflows/release-packages.yml` 会执行以下流程：

1. 分别在 GitHub 托管的 Windows 与 macOS runner 上执行静态分析和 Release 构建。
2. 生成 Windows x64 `.exe` 安装器与 macOS `.dmg`。
3. 为两个安装包生成 SHA-256 校验文件。
4. 只有两个平台全部成功后，才创建对应标签的 GitHub Release 并上传四个资产。

普通的 `master` 打包配置变更和手动触发只生成 Actions 临时产物，不会覆盖或新建公开 Release。

```powershell
git tag -a v0.1.0 -m "Local Tag Player 0.1.0"
git push origin v0.1.0
```

## Windows

本地打包时，先生成完整 Release bundle，再用 Inno Setup 编译安装器：

```powershell
flutter build windows --release --build-name 0.1.0
iscc /DMyAppVersion=0.1.0 /DMySourceDir=<Release绝对路径> /DMyOutputDir=<产物绝对路径> packaging/windows/local_tag_player.iss
```

安装器采用当前用户目录安装，不要求管理员权限。卸载只移除安装文件和快捷方式，不清理用户数据库、标签、收藏或播放记录。

## macOS

工作流在 macOS runner 中构建 Release `.app`，完成进程启动检查后生成带 `Applications` 快捷入口的 `.dmg`。

当前仓库没有 Windows Authenticode 证书、Apple Developer ID Application 证书和 notarization 凭据，因此公开产物会明确标记为未签名或未公证。下载者应核对 Release 中的 SHA-256；大范围分发前仍需配置两端签名，并重新验证 Windows SmartScreen 与 macOS Gatekeeper 行为。
