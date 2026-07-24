# 桌面正式版打包

应用版本以 `pubspec.yaml` 为唯一来源。`0.1.0+1` 对应对外安装包版本 `0.1.0`。

## GitHub Release

向远程推送符合 `vX.Y.Z` 形式的标签后，`.github/workflows/release-packages.yml` 会执行以下流程：

1. 分别在 GitHub 托管的 Windows 与 macOS runner 上执行静态分析和 Release 构建。
2. 对 Windows 主程序和安装器执行 Authenticode SHA-256 签名、RFC 3161 时间戳与签名验证。
3. 对 macOS `.app` 和 `.dmg` 执行 Developer ID 签名、hardened runtime、Apple notarization 与票据 stapling。
4. 为两个安装包生成 SHA-256 校验文件。
5. 只有两个平台的签名、公证和校验全部成功后，才创建对应标签的 GitHub Release。

普通的 `master` 打包配置变更和手动触发只生成未签名的 Actions 临时产物，不会覆盖或新建公开 Release。标签发布缺少任何签名凭据时会直接失败，不会静默回退为未签名公开包。

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

标签发布需要以下 GitHub Actions secrets：

| Secret | 用途 |
| --- | --- |
| `WINDOWS_CERTIFICATE_BASE64` | 代码签名 PFX 的单行 Base64 |
| `WINDOWS_CERTIFICATE_PASSWORD` | PFX 密码 |

工作流先签名 `local_tag_player.exe`，再生成并签名 Inno Setup 安装器。`packaging/windows/sign_release.ps1` 会把 PFX 临时导入当前用户证书存储，按指纹调用 Windows SDK `SignTool`，完成后立即移除证书，并对每个文件执行 `/pa` 验证。

本地签名示例：

```powershell
./packaging/windows/sign_release.ps1 `
  -CertificatePath <代码签名证书.pfx> `
  -CertificatePassword <证书密码> `
  -Files <待签名文件.exe>
```

GitHub secret 中不得提交 PFX 文件、密码或 Base64 到仓库；只在仓库 `Settings > Secrets and variables > Actions` 中配置。

## macOS

工作流在 macOS runner 中构建 Release `.app`，完成进程启动检查后生成带 `Applications` 快捷入口的 `.dmg`。标签发布由 `packaging/macos/package_notarized.sh` 完成以下步骤：

1. 在临时 keychain 中导入 `Developer ID Application` 证书。
2. 使用 hardened runtime 与安全时间戳重签名 Flutter `.app`，并严格验证嵌套代码签名。
3. 创建并签名 DMG。
4. 使用 App Store Connect **团队 API key** 调用 `notarytool --wait`；个人 API key 不能用于 `notarytool`。
5. 对通过公证的 DMG 执行 `stapler staple`、`stapler validate` 和 Gatekeeper `spctl` 检查。

标签发布需要以下 GitHub Actions secrets：

| Secret | 用途 |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application `.p12` 的单行 Base64 |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `APPLE_SIGNING_IDENTITY` | 完整签名身份，例如 `Developer ID Application: ... (TEAMID)` |
| `APPLE_API_KEY_BASE64` | App Store Connect 团队 API key `.p8` 的单行 Base64 |
| `APPLE_API_KEY_ID` | API key ID |
| `APPLE_API_ISSUER_ID` | API issuer UUID |

Apple 要求直接分发的软件先使用 Developer ID 签名，再提交公证；公证成功后把票据附加到最终分发文件。当前工作流使用 `notarytool`，不使用已经停止接受公证上传的 `altool`。

参考官方文档：

- [Microsoft SignTool](https://learn.microsoft.com/windows/win32/seccrypto/signtool)
- [Apple Developer ID](https://developer.apple.com/support/developer-id/)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [GitHub Actions secrets](https://docs.github.com/actions/security-guides/using-secrets-in-github-actions)

## 许可证与第三方声明

安装包必须保留 Flutter 的 `data/flutter_assets/NOTICES.Z`，以及 `data/licenses/native_player/`、`data/licenses/rust_library_scan/`。更完整的再分发边界见 [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。项目级许可证需要在创建标签前明确选定；第三方组件仍分别受其原始许可证约束。

已经发布的 `v0.1.0` 仍是未签名、未公证的历史产物；只有配置上述 secrets 并创建新标签后，工作流才会生成新的 Authenticode 签名与 Apple 公证包。
