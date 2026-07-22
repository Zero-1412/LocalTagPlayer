# CURRENT_TASK.md

> 本文件只保存当前活跃任务、最近稳定基线、已确认阻塞和下一步入口。已完成的详细记录进入 `CHANGELOG.md` 与对应 Chat 文档。

## 活跃任务

### 2026-07-22 播放器 GPU 画质超分

- 目标：在播放器进度条齿轮设置中提供可即时开关的画质超分，同时保持视频播放、filtered queue 与 Flutter UI 响应流畅。
- 当前状态：代码、持久化、focused tests、全量测试、静态分析与 Windows Debug 构建已完成；显式启动 Debug 路径时 Windows 应用激活实际路由到已安装 Release 进程，随后又检测到用户正在窗口输入，自动化按安全规则中止，因此仍需补做新构建的准确人工点击与截图复验。
- 当前打包的 libmpv `v0.36.0-403` 不包含新版 Intel/NVIDIA `d3d11vpp scaling-mode` 厂商扩展；本轮使用其已支持的 `ewa_lanczossharp` GPU 高质量上采样，不宣称 RTX/Intel AI 超分。
- 设置默认关闭；开启后显式使用 `scaler-resizes-only=yes`，仅在源画面需要放大时运行，高质量亮度缩放与 sigmoid 变换留在 GPU renderer，Flutter UI 不处理视频帧。
- 关闭后恢复 Lanczos 基线；每次媒体 open 前后重新应用设置，播放诊断显示开关、实际 `scale` 与 resize-only 状态。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、解码设置或用户标签/收藏数据。

### 2026-07-21 GitHub 首次公开发布与隐私收口

- 目标：让首次访问仓库的人能理解产品目的、特色功能、技术框架和架构边界，并通过 GitHub Release 获取 Windows / macOS 安装包。
- 当前状态：README、隐私过滤和 `v0.1.0` GitHub Release 已完成；Actions 运行 `29821115757` 的版本解析、Windows、macOS 与公开发布 job 全部成功。
- README 已按“问题场景 → 核心闭环 → 特色能力 → 技术栈 → 架构思想 → 下载/隐私/边界”重写，明确本项目不是 VLC / PotPlayer 的替代品。
- `vX.Y.Z` 标签发布改为 Windows 与 macOS 双端成功后原子创建 Release，同时上传 `.exe`、`.dmg` 和两份 SHA-256；普通分支与手动构建不创建公开 Release。
- 已清理公开 `master` 历史中的个人邮箱、本机用户名/盘符路径和 `.codex/config.toml`，提交者统一为 GitHub noreply 身份；公开分支和标签均只引用脱敏后的历史。
- 本地开发配置和路径上下文继续保留，但由 `.gitignore` 隔离；数据库、日志、媒体样本、环境变量、签名证书、安装包和本地私有配置均加入上传过滤。
- 定向审计未发现已跟踪的媒体文件、数据库、日志、环境变量、私钥、签名证书或 API token。公开仓库仍包含随桌面包使用的 FFmpeg/FFprobe 第三方二进制，属于依赖与许可证审查项，不是个人隐私。
- 公开 Release：Windows x64 安装器 108,566,180 字节，SHA-256 `74b733522c32eef027d9c1b0e846d3bfc6d740e6725fb30544a6f0f1e03c6ea6`；macOS DMG 42,757,651 字节，SHA-256 `6bbdf24c2b288dab2277bc3592557595f31c3bca37abaa7268c15c3b7bb8320a`。

### 2026-07-21 Windows / macOS 正式版安装包

- 目标：基于 `pubspec.yaml` 的 `0.1.0+1` 构建 Windows x64 Release 安装器与 macOS Release DMG，不改变业务、数据或播放语义。
- 当前状态：已完成。Windows 本地 Release 安装器、隔离安装/启动/卸载冒烟均通过；独立 macOS runner 已完成 Release 构建、10 秒启动检查、DMG 生成与上传。
- Windows 安装器使用当前用户目录安装，卸载时保留用户数据库、标签、收藏和播放记录。
- macOS bundle identifier 已从模板占位符收敛为 `com.zero1412.localtagplayer`，Finder 展示名为 `Local Tag Player`。
- 仓库当前没有 Windows Authenticode 与 Apple Developer ID / notarization 凭据；生成的安装包必须明确标记为未签名或未公证，不能宣称通过系统信任链。
- Windows 安装器：108,571,720 字节，SHA-256 `0ad9b542bed463d9036111c1a2a7acc2e1e0fe4ff4d4261339665890a506fe36`。
- macOS DMG：42,757,735 字节，SHA-256 `536c53e804e2267ccecc3d6991da66561e25bc6676cf94119e5d3222b03a5094`；Actions 运行 `29815594317` 的 Windows / macOS job 均成功。

### 2026-07-21 媒体卡片文件菜单收口

- 目标：让媒体卡片“更多”只承担当前文件定位与删除，移除与播放器详情重复的标签编辑和文件重命名，并缩小悬浮菜单。
- 当前状态：已完成。
- 网格卡片、紧凑列表和本地目录视图共用“打开文件 / 删除文件”双项菜单；播放器详情中的标签编辑与重命名能力保持不变。
- “打开文件”仍通过 `FileSystemAdapter.revealInFileManager(item.path)` 定位当前卡片的完整视频路径，不打开媒体库 root 或资源目录。
- 菜单宽度限制为 136–156px，条目最小高度 40px，外层垂直留白 4px；真实窗口无遮挡、溢出或文字截断。
- 页面级回归直接记录平台边界收到的路径，并断言等于被点击卡片；同时锁定菜单不再出现“编辑标签 / 重命名文件”。

## 当前稳定基线

- 产品边界：Tag 驱动的本地视频发现播放器，不扩展字幕、音轨、逐帧或 A-B loop 等专业播放器能力。
- 数据边界：SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容与顺序、标签来源语义均未改变。
- 验证：237 项测试通过，3 项显式 benchmark 跳过；GPU 超分设置、属性串行化与后端回归、卡片双项菜单、页面当前路径、文件系统边界回归、`flutter analyze`、Windows debug build 均通过。超分真实点击与截图因检测到用户输入而中止，不能宣称实窗通过。
- 架构基线：`Architecture Baseline 0.5.51`。

## 已确认阻塞

- 外部跨平台规划 `<private-planning-document>` 当前不存在；本轮依照仓库内长期规则和现有跨平台边界实施。
- GitHub 服务端仍暂存重写前的无引用提交对象；公开 refs、普通历史浏览和 clone 均已脱敏，但已知旧哈希仍可通过 Commit API 命中。仓库侧没有删除无引用对象的 API，需由仓库所有者向 GitHub Support 请求 cached views / references purge，完成后再验证返回 404。
- GitHub 仓库顶部 About 简介仍是旧的“替代手动文件夹 + PotPlayer”定位，会进入浏览器标题和搜索摘要；当前 GitHub 连接没有仓库元数据写接口，验收浏览器也未登录。需所有者在仓库首页 About 设置中改为“用标签发现、组合筛选与当前结果队列管理和播放大型本地视频库的 Flutter 桌面应用。”

## 下一步入口

1. 向 GitHub Support 提交重写前提交对象与 cached views 的服务端清除请求，并在仓库 About 设置同步新的单句定位；完成后确认旧 Commit API 返回 404、公开页标题不再显示旧描述。
2. 对外扩大分发前配置 Windows Authenticode 证书、Apple Developer ID Application 证书与 notarization 凭据，重新验证 SmartScreen / Gatekeeper。
3. 补充脱敏的真实产品截图，并确定项目级许可证及 FFmpeg/FFprobe 再分发说明。
