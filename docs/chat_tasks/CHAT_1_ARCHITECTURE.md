# CHAT_1_ARCHITECTURE.md

## 2026-07-24 GitHub 正式版更新边界

- 应用版本提升为 `0.2.0+2`，以 `pubspec.yaml` 作为安装包和运行时版本来源。
- 新增独立 `AppUpdateService` 与 GitHub Releases 实现；首帧后异步检查公开正式 Release，远端版本更高时展示 Release 正文和 Windows 安装器入口。
- 网络错误、离线或 GitHub 限流保持静默，不阻塞媒体库启动，不进入 SQLite、标签、播放器或缓存边界。
- 发布工作流继续以 `vX.Y.Z` 标签创建 Release；更新弹窗只认 Release，不把普通 commit 误报为可安装更新。

当前版本：`0.5.28`
状态：已完成页面依赖收窄并接入 macOS/Linux runner

## 2026-07-14 页面应用服务与跨平台 runner

- `LibraryPage` 不再持有完整 `LocalTagPlayerDependencies`，只消费页面用例服务、文件系统 contract 和转交播放器路由所需 factory。
- 组合根集中创建 `LocalLibraryPageApplicationService`，拥有 AppPaths、Repository loader、FFmpeg、媒体探测 factory 与 debug 配置。
- macOS/Linux Flutter runner 与 CI build/start smoke 已接入；平台 adapter 选择在对应宿主 contract test 中验证。
- GitHub Actions run `29324080724` 已验证 macOS/Linux adapter、静态分析、debug build 与 10 秒启动存活 smoke 全部通过。
- SQLite schema/写入、FilterQuery/TagQueryService、stable identity、filtered queue 与缓存队列继续由 Dart 单写和编排。

## 2026-07-14 全量 library 边界收口

- 57 个 `part` / `part of` 已清零，Store、播放器/缩略图、应用服务与页面/widgets 已按依赖方向迁为独立 import。
- `LocalTagPlayerDependencies` 独立为组合根 contract，页面业务入口继续是 `LibraryApplicationFacade`，平台能力继续通过 adapter/backend 接口注入。
- SQLite schema/写入、标签筛选、stable identity、filtered queue 与缓存队列语义保持在 Dart；Rust/C++ 边界未扩大。
- contract/fake tests 增加零 `part` 守卫；macOS/Linux 构建仍需对应宿主验证。

当前版本：`0.5.26`
状态：进行中
负责人：Chat 1 / 架构与跨平台边界

## 2026-07-14 第二批边界迁移

- 实例化 AppPaths 并落地 DatabaseProvider，Store 不再选择 factory 或数据库路径。
- facade 使用只读集合和明确命令，Tag/Cache/Playback repository 接入同一 Dart SQLite writer。
- 移除静态媒体工具、窗口单例与旧位置 service，debug 环境和诊断写入退出页面。
- 57 个 part 已消除 22 个，剩余 35 个按 Repository/平台→应用服务→页面继续。

## 规划来源

主要来源：

```text
<private-planning-document>
```

如果本文档与该文件冲突，以外部规划为准。

## 范围

负责项目架构、模块边界、跨平台路线、平台接口、本地规则和架构基线版本。

允许：

- `main.dart` 结构、`part` / 未来 import 边界。
- `app/`、`core/`、`models/`、`platform/`、`repositories/` 接口规划。
- 核心模型和共享契约。
- `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider`。
- `LibraryRepository`、`TagRepository`、`CacheRepository`、`PlaybackRepository` 接口规划。
- `LayoutSize`：`compact`、`medium`、`expanded`。
- 架构文档和版本规则。

禁止：

- 重写播放器行为。
- 重写 SQLite 查询逻辑。
- 重写缩略图队列。
- 大范围 UI 重设计。
- 实现 Tag Manager 功能逻辑。

## 已采用任务

P0 / P1：

- 让 Architecture 对齐外部跨平台规划，而不是旧项目惯性。
- 维护已完成的 `Architecture Baseline 0.3.1`。
- 维护已完成的 `Architecture Baseline 0.4.0` 仓储 / 布局边界基线。
- 为低风险 import 迁移和逐步采用 `0.4.0` 契约准备 `Architecture Baseline 0.4.1`。
- 保证标签查询 / 筛选逻辑保持平台无关。
- 保证文件系统、播放器、FFmpeg/FFprobe、数据库位置规则位于平台边界后。
- 在 `ARCHITECTURE.md` 记录每次共享边界变更。

## 新对话提示

```text
这是 Chat 1 / 架构与跨平台边界。项目路径：<project-root>。
请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_1_ARCHITECTURE.md

后续方向以 local_tag_player_flutter_cross_platform_plan_v2.md 为准；当前项目实现只代表历史状态。
职责：负责 main.dart 拆分、模块边界、平台接口、repository 接口、跨平台路线和架构版本记录。
不要重写播放器行为、SQLite 查询、缩略图队列或做大范围 UI 重设计。
当前目标：推进 Architecture Baseline 0.4.1，做低风险 import 迁移或逐步采用 0.4.0 契约。
修改代码后运行：
- flutter analyze
- flutter build windows --debug
```

## 变更记录

- `0.5.25`：实现并接入 `DesktopFileSystemAdapter`；`LibraryStore` 落地为实际 `LibraryRepository`，页面统一依赖 `LibraryApplicationFacade`；具体 backend/repository 工厂移入 bootstrap composition root。文件系统模块、`LayoutSize`、`MediaDetails` 首批脱离 `part`，其余模块继续按依赖顺序渐进迁移。

- `0.5.24`：Windows 原生依赖使用临时文件下载、固定 SHA256 校验、原子落盘和最多三次重试；mpv/ANGLE 的项目校验副本直接提供给 media_kit 插件，避免 Android Studio/CMake 重复下载与坏缓存连锁失败。
- `0.5.23`：为文件较多的一级模块增加职责二级目录；`pages` 分为 library/player/tags，`services` 分为 library/media/player/relink/tags/window，`widgets` 的媒体库组件归入 library。继续保留单一 `app.dart` part library，不改变业务或平台边界。
- `0.4.1`：为后续低风险 import 迁移和逐步采用 `0.4.0` 契约开启下一轮架构基线。
- `0.4.0`：按 `local_tag_player_flutter_cross_platform_plan_v2.md` 重定架构职责，新增 repository 接口 stub、共享 `LayoutSize` / `LayoutBreakpoints`，扩展平台边界方法，并扩展 tag/filter/playback 模型 stub，同时保持 Windows 行为不变。
- `0.3.0`：新增 `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider` 接口 stub 和平台无关 tag/filter/playback/cache/diagnostic 模型 stub，不改变 Windows 行为。
- `0.2.0`：新增 core 边界文档、多 Chat 协作和 roadmap 归属规则。
