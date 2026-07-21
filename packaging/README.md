# 桌面正式版打包

当前应用版本以 `pubspec.yaml` 为唯一来源。`0.1.0+1` 对应安装包版本 `0.1.0`。

## Windows

先生成完整 Release bundle，再用 Inno Setup 编译安装器：

```powershell
flutter build windows --release --build-name 0.1.0
iscc /DMyAppVersion=0.1.0 /DMySourceDir=<Release绝对路径> /DMyOutputDir=<产物绝对路径> packaging/windows/local_tag_player.iss
```

安装器采用当前用户目录安装，不要求管理员权限；卸载只移除安装文件和快捷方式，不清理用户数据库、标签、收藏或播放记录。

## macOS

`.github/workflows/release-packages.yml` 在 macOS runner 上构建 Release `.app`，完成进程启动检查后生成带 `Applications` 快捷入口的 `.dmg`。

当前仓库没有 Windows Authenticode 证书、Apple Developer ID Application 证书和 notarization 凭据，因此流水线产物会明确标记为未签名或未公证。对外公开分发前必须配置两端签名，并重新验证签名、macOS Gatekeeper 和 Windows SmartScreen 行为。
