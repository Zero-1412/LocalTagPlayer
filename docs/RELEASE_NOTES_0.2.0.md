# Local Tag Player 0.2.0

## 更新内容

- 新增正式版远程更新提醒：启动后异步检查 GitHub 最新正式 Release。
- 发现更高版本时展示版本标题和完整更新说明。
- Windows 优先打开对应 x64 安装器；没有匹配资产时回退到 Release 页面。
- 离线、网络超时或 GitHub 限流不会阻塞本地媒体库启动。
- 完善 Windows 安装器、macOS DMG、第三方许可与签名/公证发布流程。

## 数据安全

- 不修改 SQLite schema、标签来源或筛选语义。
- 不修改 filtered queue、PlayerBackend 或缓存队列。
- 安装和升级不会删除媒体库数据库、标签、收藏或播放记录。

## 签名状态

本次公开包由 GitHub Actions Release 模式构建。仓库尚未配置 Windows Authenticode 与 Apple notarization 凭据时，产物不具备相应平台签名或公证；下载后请使用随附 SHA-256 文件校验完整性。
