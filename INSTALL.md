# 安装与升级指南

Local Tag Player 当前提供 Windows x64 安装器、macOS DMG，以及 Linux 源码构建支持。
请只从本仓库的 [GitHub Releases](https://github.com/Zero-1412/LocalTagPlayer/releases)
下载安装包，不要使用第三方重新打包的文件。

当前公开安装包尚未进行 Windows Authenticode 签名或 macOS Developer ID
签名与 Apple 公证，因此系统可能显示安全提醒。继续安装前，请先核对 Release
页面随附的 SHA-256；校验失败时不要运行安装包。

## 选择下载文件

| 平台 | 下载文件 |
| --- | --- |
| Windows x64 | `LocalTagPlayer-<version>-windows-x64-setup.exe` 与 `SHA256SUMS-windows.txt` |
| macOS | 当前未公证版本为 `LocalTagPlayer-<version>-macos-unnotarized.dmg`，同时下载 `SHA256SUMS-macos.txt` |
| Linux | 暂无正式安装包，请按下文从源码构建 |

`<version>` 表示 Release 版本号，例如 `0.2.4`。

## 校验 SHA-256

SHA-256 可以发现下载损坏或文件与 Release 清单不一致，但不能代替平台代码签名。
只有文件名和完整的 64 位哈希值都与对应 `SHA256SUMS` 文件一致时，才继续安装。

### Windows

把安装器和 `SHA256SUMS-windows.txt` 放在同一目录，在该目录打开 PowerShell，
并把示例中的 `<version>` 替换为实际版本号：

```powershell
$installer = ".\LocalTagPlayer-<version>-windows-x64-setup.exe"
(Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLower()
Get-Content -LiteralPath ".\SHA256SUMS-windows.txt"
```

### macOS

把 DMG 和 `SHA256SUMS-macos.txt` 放在同一目录，在终端执行：

```bash
shasum -a 256 "LocalTagPlayer-<version>-macos-unnotarized.dmg"
cat "SHA256SUMS-macos.txt"
```

未来已签名版本的 DMG 文件名可能不再包含 `-unnotarized`，届时请使用 Release
页面展示的实际文件名。

## Windows 安装

Windows 安装器支持 Windows 10 1809 及更高版本的 x64 系统，安装到当前用户目录，
不要求管理员权限。

1. 完成 SHA-256 校验并确认完全一致。
2. 双击 Windows x64 安装器，按简体中文向导完成安装。
3. 如果 Windows SmartScreen 显示未知发布者，只在文件来自本仓库且哈希匹配时，
   选择“更多信息”，再次核对文件名，然后选择“仍要运行”。
4. 不要为了安装本应用关闭 SmartScreen，也不要降低系统的全局安全设置。

如果系统没有提供“仍要运行”，或者文件名、来源、哈希任一项不一致，请停止安装并
重新从 GitHub Releases 下载。

## macOS 安装

1. 完成 SHA-256 校验并确认完全一致。
2. 打开 DMG，把 `Local Tag Player.app` 拖入 `Applications`。
3. 首次启动被 Gatekeeper 阻止后，打开“系统设置”→“隐私与安全”。
4. 在安全提示区域找到 Local Tag Player，选择“仍要打开”，再在确认对话框中选择
   “打开”。

只应对已经核对来源与哈希的安装包执行上述操作。本指南不建议使用 `xattr`
批量移除隔离属性，也不建议关闭 Gatekeeper。

## Linux 源码构建

Linux 当前没有正式安装包，产品体验和性能基线仍以 Windows 为主。开始前请安装
Flutter stable 与 Linux 桌面构建工具，并用 `flutter doctor` 确认 Linux toolchain
可用。

Ubuntu / Debian 可安装与项目 CI 一致的系统依赖：

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev \
  libmpv-dev mpv libsqlite3-dev
```

获取源码并运行：

```bash
git clone https://github.com/Zero-1412/LocalTagPlayer.git
cd LocalTagPlayer
flutter pub get
flutter run -d linux
```

需要 Release 构建时执行：

```bash
flutter build linux --release
```

x64 Linux 的默认产物位于
`build/linux/x64/release/bundle/local_tag_player`；其它架构的目录名称可能不同。

## 升级与数据保留

升级前先关闭 Local Tag Player，并按新版本 Release 页面重新核对安装包哈希。

- Windows：直接运行新版本安装器覆盖安装。安装器会尝试关闭仍在运行的应用。
- macOS：打开新版本 DMG，把应用拖入 `Applications` 并确认替换旧版本。
- Linux：拉取目标版本源码后重新执行 `flutter pub get` 和 Release 构建。

数据库、设置、标签、收藏和播放记录保存在系统应用数据目录，而不是程序安装目录。
正常覆盖安装和 Windows 卸载不会主动清理这些用户数据。需要额外保障时，可在应用的
“设置”→“视频数据备份”中执行“立即备份”并导出备份；该备份不包含原始视频文件。

如果准备降级到旧版本，请先导出备份。数据库升级后不能假定旧版本仍可安全读取。

## 常见阻塞

### 哈希不一致

不要运行文件。删除安装包和校验文件，清除浏览器中未完成的下载，再从官方 Release
重新下载；仍不一致时请提交 Issue。

### Windows 安装器提示应用仍在运行

保存当前播放进度并退出应用；必要时在任务管理器确认 `local_tag_player.exe`
已经结束，然后重新运行安装器。不要在应用仍写入数据库时强制覆盖程序文件。

### macOS 没有显示“仍要打开”

先从 `Applications` 启动一次应用，让 Gatekeeper 生成对应提示，再立即检查
“系统设置”→“隐私与安全”。不要使用批量移除隔离属性的命令绕过系统检查。

### Linux 构建找不到 GTK、mpv 或 SQLite

重新检查 `flutter doctor`，并确认已安装 `libgtk-3-dev`、`libmpv-dev`、`mpv`
和 `libsqlite3-dev`。其它发行版请安装对应名称的开发包。

### 需要提交 Issue

请附上操作系统版本、安装包文件名、SHA-256 校验结果和可复现步骤。提交日志或截图前，
先移除用户名、绝对媒体路径、视频标题和其它个人信息。
