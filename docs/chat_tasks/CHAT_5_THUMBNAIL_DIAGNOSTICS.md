# CHAT_5_THUMBNAIL_DIAGNOSTICS.md

## 2026-07-13 可见缩略图 Future 与旧 4K 缓存解码

- 可见卡片现在等待真正的优先队列任务，同一 cache key 复用一个完成 Future；FFmpeg 生成完成即刷新，不再依赖下一次列表 rebuild。
- build 阶段移除同步 `existsSync`，历史 4K fallback JPEG 通过 `cacheWidth=384` 限制解码尺寸。
- 后台请求从 cache key/JPEG 验证起就计入 500 上限，避免大批差量在入队前一次启动数千个异步检查。
- 设置缓存诊断补充“后台请求”，与已入队数、活动并发数分开显示。

## 2026-07-13 Flutter与原生播放器缓存归因

- 生命周期阶段记录ImageCache字节数、条目数、live/pending数量；五轮保持约93–100 MiB，排除为数百MiB高位保留主因。
- mpv demux state记录缓存时长与total/fw bytes，stop后清零；诊断不启动FFprobe或详情探测Player。
- 不为降低进程数字强制清空缩略图ImageCache，避免返回媒体库后重新解码图片造成可见卡顿。

## 2026-07-13 播放诊断禁止派生探测 Player

- 播放诊断和右侧队列只读取已缓存媒体详情，打开弹窗或快速滚动不能启动 FFprobe 或 media_kit 兜底探测。
- 诊断新增视频帧号、音频 PTS、两路停滞事件及退出阶段时间点，避免只用瞬时 AV offset 判断流畅度。
- 本轮未修改缓存 schema、缩略图失效规则或 filtered queue 来源。

## 2026-07-12 设置页缓存统计增强

- 缩略图缓存明确显示总数、已缓存、缺失、失败、活动任务/并发上限、排队任务和平均耗时。
- 右上角刷新入口使用图标加“刷新统计”文字，不再仅依赖用户猜测图标含义。
- 仅重新编排已有 `CacheStats`，未改变缩略图任务限流、重试、缓存 key 或 FFmpegBackend 边界。

当前版本：`0.2.2`
状态：第一阶段完成
负责人：Chat 5 / 缩略图 + 诊断 + FFmpegBackend

## 规划来源

主要来源：

```text
<private-planning-document>
```

如果本文档与该文件冲突，以外部规划为准。

## 范围

负责 FFmpeg / FFprobe 接入、缩略图缓存队列、媒体探测缓存、重试 / 失败报告、异常文件列表、诊断卡片和 `FFmpegBackend` 实现。

允许：

- `ThumbnailService`。
- `MediaDetailsService`。
- 被 `FFmpegBackend` 包装前的 `ExternalMediaTools`。
- 未来 `platform/ffmpeg`。
- 缓存功能需要的缓存诊断视图。
- 缓存相关 repository 规划。

禁止：

- 标签筛选逻辑。
- 播放页主结构。
- SQLite 标签 schema，除非缓存相关字段已协调。
- 在平台 / backend 层外散落 Windows exe 路径。

## P0 / P1 任务

- 播放期间保持缩略图队列保守。
- FFmpeg / FFprobe 发现和执行必须经过 `FFmpegBackend`。
- 展示 FFmpeg / FFprobe 可用性、路径和版本。
- FFprobe 输出保持精简且可缓存。
- 为失败的缩略图 / 媒体探测任务增加重试。
- 增加清除失败记录。
- 增加异常文件列表。
- 把诊断页改进成可操作卡片。
- 保留当前 Windows bundled tool 行为，并放在 backend 后面。

## 新对话提示

```text
这是 Chat 5 / 缩略图 + 诊断 + FFmpegBackend。项目路径：<project-root>。
请先阅读：
- PROJECT.md
- ARCHITECTURE.md
- CURRENT_TASK.md
- ROADMAP.md
- <private-planning-document>
- docs/chat_tasks/CHAT_5_THUMBNAIL_DIAGNOSTICS.md

职责：缩略图缓存、媒体信息探测、FFmpeg/FFprobe backend、失败重试、异常文件和诊断 UI。
不要修改标签筛选语义、播放器主结构或无关 SQLite schema。
修改代码后运行：
- flutter analyze
- flutter build windows --debug
```

## 变更记录

- `0.2.2`：修复可见卡片不等待生成完成的问题；同一 cache key 合并任务，限制入队前后台请求，并对历史 4K JPEG 按卡片尺寸解码。
- `0.2.1`：验收修复：现有缩略图缓存文件会先验证 JPEG 标记和长度，0-byte 或截断文件会被丢弃；重试和清除失败动作在已有任务运行或缓存队列活跃时禁用。
- `0.2.0`：完成第一阶段缓存诊断：FFmpeg/FFprobe 通过 `DesktopFFmpegBackend` 兼容适配层调用；工具版本可见；缩略图兜底先写临时文件再替换；后台缩略图队列限流；媒体探测队列状态可见；诊断页可重试失败、清除失败记录并列出异常文件。
- `0.1.0`：从 `local_tag_player_flutter_cross_platform_plan_v2.md` 创建任务；Chat 5 负责 Thumbnail + Diagnostics + FFmpegBackend。
# 2026-07-13 播放期间后台探测收敛

- 播放器进入后仍沿用既有缩略图队列暂停边界。
- 队列快速滚动不再创建会访问磁盘的完整条目；播放后的 FFprobe 预取只处理当前视频，不再探测前后窗口。
- 缓存 key、JPEG 有效性检查、失败重试和 FFmpegBackend 均未改变。

# 2026-07-13 MediaProbeBackend 原生批处理

- 新增与 `FFmpegBackend` 分离的 `MediaProbeBackend`，提供 `probeBatch` 和 `cancelGeneration`；请求只携带 videoId、路径及数据库已有 size/mtime，结果不回传路径或媒体帧。
- Windows runner 使用固定 FFmpeg 8.1 LGPL shared libraries，首次探测才延迟加载；单工作线程限流，执行中任务由 FFmpeg interrupt callback 响应 generation 取消。
- `MediaDetailsService` 不再重复生成 fingerprint，也不再用临时 media_kit Player 兜底；SQLite 写入继续由 Dart Repository 回调完成。
- 缩略图仍只传路径/缓存 key/结果状态，未跨边界传未压缩位图，既有缩略图队列和失败重试语义不变。
