# CHANGELOG.md

本文件只保存未发布变更和版本索引。完整逐项历史位于
`docs/history/changelog/CHANGELOG_HISTORY_THROUGH_2026-07-30.md`；
不要把旧条目复制回根文件。

## Unreleased

### 应用更新

- 设置新增独立“网络代理”二级页，保存的 HTTP 代理同时用于
  GitHub Releases 检查、CDN 重定向和安装包分段下载。
- 代理配置仅支持无账号密码的 HTTP `host:port`，独立保存在应用私有设置文件；
  不修改系统代理，不影响媒体播放、扫描、FFmpeg 或用户媒体数据。

### 0.2.5 公共未签名发布

- 将应用版本更新为 `0.2.5+7`，增加应用内更新弹窗和安装包共用的用户发布说明。
- 远程缺少 Windows/macOS 签名凭据；经用户明确授权，直接发布未签名 Windows 安装器与
  未公证 macOS DMG，发布说明与 macOS 文件名均保留风险标识。
- GitHub Actions `30691208487` 通过分支集成、全量业务、双平台 Release 构建与启动门禁，
  创建 `v0.2.5` 公开 Release，含双平台安装包与各自 SHA256 清单。

### 播放器交互

- 优化方向键长按快进/快退：按住期间使用关键帧预览并累计目标，松开时只执行一次精确 seek，
  避免每次按键重复都触发昂贵的精确解码收敛。
- 进一步柔化长按节奏：短按继续使用配置步长，重复阶段使用受限小步长，并把关键帧预览
  与反馈刷新统一到约 64ms；避免多次 KeyRepeat 合并成十几秒画面跳变和高频整页重建。
- 快进/快退反馈增加累计目标时间；单次 5 秒步进、进度条最终提交、来源 filtered queue、
  播放/暂停意图和返回路径保持不变。

### 依赖兼容

- 将 `file_picker` 从 8.3.7 升至 11.0.2，并把桌面文件选择适配器迁移到
  11.x 静态 API；目录、多文件、单文件和保存路径业务合同保持不变。
- 增加架构契约，禁止恢复已移除的 `FilePicker.platform` 调用。
- `package_info_plus` 保持 9.0.1：其 10.2.1 所需 `win32 ^6.0.1`
  与稳定版 `file_picker 11.0.2` 所需 `win32 ^5.9.0` 无交集；
  不使用 beta 或 `dependency_overrides` 强行升级。

### Agent 治理与上下文

- 为 repo Skill 增加严格 UTF-8、frontmatter、Agent UI 元数据和松散 Markdown 校验。
- 为 `AGENTS.md`、`CURRENT_TASK.md`、bootstrap、Project、Claude 和 Harness 增加
  行数/字符预算，并在相关 pull request/push 上运行零模型成本门禁。
- `CURRENT_TASK.md` 收缩为当前任务、最近三项、稳定基线、阻塞和下一步；
  2026-07-20 至 2026-07-30 的原文无损迁入 task history。
- `AGENTS.md`、`PROJECT.md`、`CLAUDE.md` 和 Agent Harness 建立单一事实源，
  默认核心入口收缩到约 4.2k tokens。
- 修复 CI 仓库位于用户目录下时 Trace 路径遮盖顺序错误，并增加跨平台回归。
- 将 Architecture、Roadmap 和 Changelog 的当前合同与时间线历史分离。
- 将 Chat 1—7、34 份 dated QA 证据、3 份架构完成材料和一次性 media_kit 实验迁入带索引的历史区。
- 建立 37 项 QA 自动化生命周期清单与证据路径门禁；合并 2 个质量包装器，退役 1 个 NVIDIA 包装器，并把 3 个历史视觉/质量脚本移出默认工具路径。
- 移除 QA 脚本中的开发机绝对路径，统一由参数、仓库根目录或 `PATH` 解析运行环境。
- 将 19 个第三方 GitHub Action 引用固定到完整提交 SHA，并新增浮动引用回归门禁。
- 对两个直接依赖 major 升级建立隔离兼容门禁，并在独立批次执行稳定兼容裁决。

### 不受影响的业务边界

- SQLite schema、migration 和用户数据库未修改；
- `FilterQuery` / `TagQueryService` 语义未修改；
- filtered playback queue 和缓存队列未修改；`PlayerBackend` 方法签名未修改，
  仅明确交互式 seek 为预览、精确收敛由调用方在交互结束时发起；
- 除快进/快退目标时间反馈外，UI、标签来源、用户媒体和可达功能未修改。

## 发布版本

- [0.2.5](docs/RELEASE_NOTES_0.2.5.md)
- [0.2.4](docs/RELEASE_NOTES_0.2.4.md)
- [0.2.3](docs/RELEASE_NOTES_0.2.3.md)
- [0.2.0](docs/RELEASE_NOTES_0.2.0.md)

发布产物和摘要以 [GitHub Releases](https://github.com/Zero-1412/LocalTagPlayer/releases)
为准。历史条目是实现证据，不自动代表当前优先级或当前架构合同。
