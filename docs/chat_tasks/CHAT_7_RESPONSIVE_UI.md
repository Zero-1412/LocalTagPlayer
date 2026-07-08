# CHAT_7_RESPONSIVE_UI.md

当前版本：`0.2.0`
状态：第一阶段验收完成
负责人：Chat 7 / 响应式 UI + 平台 polish

## 规划来源

主要来源：

```text
<private-planning-document>
```

如果本文档与该文件冲突，以外部规划为准。

## 范围

在核心标签发现 UI 可用后，负责最终视觉一致性、响应式布局补全、平台 polish 和 macOS / Linux 适配说明。

允许：

- 卡片、按钮、弹窗、侧栏的视觉一致性。
- 浅色媒体库风格和深色播放器风格的一致性。
- 完整 `compact`、`medium`、`expanded` 布局行为。
- 桌面端平台 polish 说明。
- Architecture 定义边界后的共享 UI token。

禁止：

- 为等这个阶段而延迟标签发现 UI。
- SQLite schema 修改。
- 核心标签查询行为修改。
- 播放器 backend 或 FFmpeg 内部逻辑修改。
- 当前阶段深度适配 Mobile / Web。

## P1 / P2 任务

- 统一视频卡片。
- 统一按钮。
- 统一弹窗。
- 统一侧栏。
- 保持媒体库和播放器视觉一致。
- 完成响应式布局：
  - `expanded`：常驻筛选 / 侧栏布局。
  - `medium`：可折叠侧栏和侧边 sheet。
  - `compact`：drawer / bottom sheet 筛选和紧凑视频列表 / 卡片布局。
- Windows 稳定后增加 macOS / Linux 适配说明。

## 第一阶段结果

`0.2.0` 已完成：

- 通过 app theme 统一弹窗基线：浅色 surface、边框、8px 圆角和更强标题层级。
- 统一媒体库侧栏间距和动作按钮行为；窄 side sheet 下目录动作会换行而不是 overflow。
- 统一视频卡片行为：响应式网格间距、compact 单列尺寸、稳定底部操作行和固定图标按钮尺寸。
- 统一缓存诊断与媒体库页面间距；compact AppBar 动作折叠进菜单。
- 统一 Tag Manager 基础布局，并实现 `expanded` / `medium` / `compact` 响应式行为：
  - `expanded`：常驻 360px 标签管理侧栏。
  - `medium`：常驻但更窄的 316px 管理侧栏。
  - `compact`：纵向列表 / 详情布局，无横向 overflow。
- 播放器深色队列侧栏仅在宽度允许时常驻；compact 时从 AppBar 打开 bottom sheet。
- 媒体库 compact 筛选 BottomSheet 使用与其它页面一致的浅色 surface 和 8px 顶部圆角。

未改变：

- SQLite schema。
- `TagQueryService`、`FilterQuery` 或 `TagQueryContext`。
- 播放器筛选队列语义、播放器 open worker 或播放 backend。
- 缩略图队列、FFmpeg/FFprobe backend 行为或缓存诊断逻辑。
- Smart List、relink/missing、文件移动、标签删除或标签合并 migration。

## macOS / Linux 适配说明

- FFmpeg bundled tools：当前 Windows 布局期望 `.exe` 工具位于 `tools/ffmpeg/bin`；macOS / Linux 打包需要平台专属二进制、可执行权限、macOS quarantine / signing 检查，以及按平台分离查找顺序。
- sqlite3 动态库：Windows 当前打包 `sqlite3.dll`；macOS / Linux 需要 `.dylib` / `.so` 放在 Flutter desktop 打包和运行时库搜索路径兼容的位置。
- 文件管理器定位：Windows reveal 行为在 macOS 应映射到 Finder `open -R`，在 Linux 映射到具体桌面环境的 reveal/open 命令；无法精确定位时回退打开父目录。
- 窗口尺寸：当前桌面 UX 在 `expanded` 最佳；macOS / Linux 应设置合理最小窗口尺寸，并测试 compact / medium，因为平铺窗口管理器可能产生很窄的桌面窗口。
- 快捷键：验证 macOS 上 Command / Control 约定、Delete / Backspace 差异、功能键行为，以及 Linux 桌面环境中的鼠标侧键可用性。

## 新对话提示

```text
这是 Chat 7 / 响应式 UI + 平台 polish。项目路径：<project-root>。
请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_7_RESPONSIVE_UI.md

职责：视觉一致性、响应式布局、桌面平台 polish 和 macOS/Linux 适配说明。不要修改标签查询语义、播放器 backend、FFmpeg 内部逻辑或 SQLite schema。
修改代码后运行：
- flutter analyze
- flutter build windows --debug
```

## 变更记录

- `0.2.0`：完成第一阶段响应式 UI polish，并增加 macOS / Linux 适配说明。
- `0.1.0`：从 `local_tag_player_flutter_cross_platform_plan_v2.md` 创建任务。
