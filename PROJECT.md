# PROJECT.md

## 项目

Local Tag Player

## 路径

```text
<project-root>
```

## 项目目标

做一个面向大量本地缓存视频的 Tag 驱动检索播放器。用户本地视频约 11000 条、约 8T，过去主要依赖 PotPlayer 和手动文件夹分类。现在应用目标不是替代 PotPlayer / VLC，而是把本地目录扫描进库，通过分组 Tag、标签别名、组合筛选、收藏、搜索和筛选结果播放队列快速查找和连续播放。

## 规划来源

后续产品方向、模块优先级和跨平台路线以以下文件为准：

```text
<private-planning-document>
```

当前项目实现只代表已有状态；如果旧实现习惯与该规划冲突，以该规划为准，并通过 `ROADMAP.md` 和对应 Chat 任务文档落地。

## 技术栈

- Flutter Windows 桌面应用
- Dart
- media_kit / media_kit_video：播放内核
- SQLite：媒体库索引
- FFmpeg：缩略图生成
- FFprobe：媒体信息读取
- sqflite_common_ffi：SQLite 访问

## 当前平台

当前主要开发目标是 Windows。未来可能多端，但 Windows 相关工具不能直接复用到 Android / iOS，需要按平台重新接入原生库或插件。

## 核心用户需求

- 添加一个或多个本地视频目录。
- 递归扫描大量视频文件。
- 一级标签来自根目录下第一层文件夹名，作为 `folder` 来源的初始 Tag。
- 二级标签来自一级目录下的第二层文件夹名，作为 `folder` 来源的初始 Tag。
- 一级目录下没有二级目录的视频归入“默认专辑”。
- 后续真正的检索系统以播放器自己的分组 Tag 数据库为准，不只依赖文件夹树。
- 标签筛选必须快速、直观，目标是网页式分组筛选。
- 筛选逻辑默认采用不同标签组 AND、同组标签 OR、排除标签 NOT。
- 搜索应匹配文件名、路径、标签名和标签别名。
- 收藏可以跨标签保存喜欢的视频。
- 播放器右侧显示当前筛选结果队列，支持快速切换视频。
- 播放器右侧顶部显示当前一级标签下的同级二级标签。
- 缩略图和媒体信息要缓存，不应每次打开重复读取。
- 播放时缩略图后台任务应暂停或降负载，避免卡顿。
- 视频身份最终应走 `videoId + fingerprint + mutable path`，路径失效时标记 `missing`，不立即删除用户整理过的 Tag、收藏和播放记录。

## 运行命令

```powershell
cd <project-root>
flutter pub get
flutter run -d windows
```

## 验证命令

每次代码修改后至少执行：

```powershell
flutter analyze
flutter build windows --debug
```

## 编码约定

- 修改前先读相关代码，不凭历史记忆改。
- 用户工作区可能有未提交修改，不要回滚用户修改。
- 优先保持现有架构和现有 UI 风格。
- UI 文案使用中文。
- 新增或修改代码时，为后续维护容易误解的规则、平台边界、异步流程添加简短注释；避免解释显而易见的代码。
- 变更后检查是否存在乱码字符。
- 大功能完成后更新 CURRENT_TASK.md 和 CHANGELOG.md。
- 新开功能 Chat 时必须读取 ROADMAP.md 和对应 docs/chat_tasks/CHAT_*.md，并在对应模板中迭代版本号和变更点。


## 多 Chat 协作边界

- Chat 1 / Architecture + Cross Platform Boundary：负责 `main.dart` 拆分、模块边界、底层接口、跨端路线、项目规则和架构版本记录。
- Chat 2 / Tag Model + Filter Engine + Media Library：负责 SQLite、扫描、folder/manual Tag、分组 Tag、别名、FilterQuery、稳定身份、missing/relink 规划。
- Chat 3 / Media Library Tag UI：负责网页式 Tag 检索首页、筛选 Chips、结果数量、保存筛选入口和第一阶段响应式结构。
- Chat 4 / Player Filter Queue + PlayerBackend：负责筛选结果播放队列、PlayerBackend、硬解、诊断和右侧列表，不优先做专业播放器增强。
- Chat 5 / Thumbnail + Diagnostics + FFmpegBackend：负责 FFmpeg/FFprobe、缩略图缓存队列、失败重试、异常文件、缓存诊断和 FFmpegBackend 落地。
- Chat 6 / Tag Manager + Batch Tagging：负责标签管理、重命名、合并、别名、批量打标签。
- Chat 7 / Responsive UI + Platform Polish：负责最终视觉统一、完整响应式布局和 macOS/Linux 适配点。
- 所有 Chat 修改后都要更新对应文档；涉及底层边界的变更必须更新 `ARCHITECTURE.md` 的架构基线版本和变更点。

## 已知注意事项

- 当前已完成第一阶段 `part` 文件拆分，后续需要继续抽平台接口和独立 import 模块。
- media_kit 暴露的播放诊断信息有限，精确掉帧和 AV offset 需要进一步接 mpv/native stats。
- FFmpeg/FFprobe 已内置到 Windows 构建目录，但发布时要注意授权。





