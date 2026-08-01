# CURRENT_TASK.md

> 本文件只保存当前任务、最近三项完成记录、稳定基线、阻塞和下一步。
> 完整历史位于 `docs/task_history/`；不得把已完成叙事重新追加到本文件。

## 当前任务

### 2026-08-01 · 应用更新专用网络代理（完成）

- 目标：在设置首页增加独立“网络代理”二级页，配置可持久化的 HTTP 代理，
  加速 GitHub 更新检查和安装包下载；“关于”页不承载代理表单。
- 作用域：仅 `GitHubReleaseUpdateService` 的独立 `HttpClient`；不修改系统代理、媒体播放、
  媒体扫描、FFmpeg、schema、过滤语义、filtered queue 或用户媒体数据。
- 安全边界：只接受无凭据 HTTP `host:port`；拒绝账号密码、路径、查询和非 HTTP 协议。
- 持久化：组合根注入 `AppPaths`，独立保存到 `app_update_proxy_settings.json`，损坏或缺失时回退直连。
- 验证：更新/下载/架构 focused tests 72 项、设置入口 widget test 1 项、`flutter analyze`、
  Windows Debug build 均通过；真实窗口确认独立页面可达、布局完整且“关于”页不再挂载代理表单。

## 最近完成

1. 2026-08-01：完成 `0.2.5+7` 双平台打包、全量门禁与 `v0.2.5` 公开 GitHub Release；
   缺少签名 secrets 的风险已在发布说明和 macOS 文件名中明确标识。
2. 2026-08-01：对齐 PotPlayer 的方向键长按快进节奏，按住期间只做关键帧预览，
   松开时精确收敛最终目标一次，并增加累计目标时间反馈。
3. 2026-07-31：完成 `file_picker` 11.0.2 稳定升级、静态 API 迁移、
   契约测试和 Windows 原生目录选择真实点击；不使用 beta 或依赖覆盖。

## 当前稳定基线

- 产品：Tag 驱动的本地视频发现播放器，不以替代 VLC/PotPlayer 或专业播放器为目标。
- 架构：`Architecture Baseline 0.5.127`。
- 数据：schema、标签来源、查询语义、filtered queue 与用户维护数据保持稳定。
- 版本：`0.2.5+7`；依赖：`file_picker 11.0.2`、`package_info_plus 9.0.1`；后者 10.x
  受稳定版 `win32` 约束冲突阻塞。
- 最近业务验证：486 项测试通过、3 项 benchmark 按设计跳过；
  `flutter analyze`、Windows Debug build 和交互式 seek 真实后端门禁通过。

## 已确认阻塞

- GitHub Support purge 工单尚未确认服务端缓存清理完成；完成后需验证旧 Commit API 返回 404。
- 可信 Windows/macOS 正式签名仍需仓库所有者配置外部证书和 GitHub Actions secrets；
  任何证书、密码或私钥都不得写入仓库。

## 下一步

1. `file_picker 12` 发布稳定版或上游 `win32` 约束收敛后，单独复核
   `package_info_plus` 9 → 10；不得使用 beta 或 `dependency_overrides` 绕过。
2. 如继续精修播放器，使用实体键盘补一次完整的长按验收；应用切换后播放器需先点击
   才重新接收快捷键的问题应作为独立任务调查，不与 seek 语义混改。
3. 代理功能完成后，使用本机代理完成一次 GitHub 检查和安装包下载真实验收；
   仓库签名凭据与 GitHub Support purge 仍按既有独立任务跟进。
