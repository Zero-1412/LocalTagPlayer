# 播放器项目学习与 fvp Windows 首轮实测

日期：2026-07-28

## 1. 结论

本轮没有修改现有业务代码，也没有改变播放器选择逻辑。

结论按用户指定的顺序如下：

1. **Harmonoid 值得学习媒体库的启动、扫描反馈、搜索分组和视图状态持久化，但不能照搬音乐分类模型或输入组件。**
2. **当前 `PlayerBackend` 对产品所需的单媒体播放、表面所有权、资源释放和 filtered queue 分层已经完整；对三后端实测所需的首帧、结构化错误、活动解码器与可取消打开证据仍不完整。**
3. **当前 filtered queue 的运行时语义比 Namida 更符合本产品，但跨进程状态恢复没有闭环：`PlaybackSession` 有模型和仓储，却没有调用者，`filterQuery` 也没有真正落盘。**
4. **fvp 在本机首轮真实 Windows 测试中通过全部 8 个有效样本、2 个异常样本和 30 次交错跳转，但证据还不足以替换 media-kit。它应继续作为 Windows 性能专项候选，而不是立即成为默认后端。**

## 2. 研究基线

本轮固定研究以下源码版本：

| 项目 | 提交 |
|---|---|
| Harmonoid | `78759d11c881b566dac01356f7b8a3eddf4ef0d4` |
| media-kit | `b29d407a4e3990dde2b35b152920383a11076b03` |
| Namida | `c609eeaecb2b39ef907d3dc06fa9963099b3bb8b` |
| fvp | `ac3c397c5430db6146562974dd5db69d80662bbf`，包版本 `0.37.3` |

Harmonoid 使用 PolyForm Strict License。以下内容只提炼产品模式和边界，不复制其源码。

主要源码证据：

- Harmonoid：[MediaLibrary](https://github.com/harmonoid/harmonoid/blob/78759d11c881b566dac01356f7b8a3eddf4ef0d4/lib/core/media_library.dart)、[媒体库设置](https://github.com/harmonoid/harmonoid/blob/78759d11c881b566dac01356f7b8a3eddf4ef0d4/lib/ui/settings/sections/media_library_section.dart)、[分组搜索](https://github.com/harmonoid/harmonoid/blob/78759d11c881b566dac01356f7b8a3eddf4ef0d4/lib/ui/media_library/search/search_screen.dart)；
- media-kit：[Player API](https://github.com/media-kit/media-kit/blob/b29d407a4e3990dde2b35b152920383a11076b03/media_kit/lib/src/player/player.dart)、[PlatformPlayer](https://github.com/media-kit/media-kit/blob/b29d407a4e3990dde2b35b152920383a11076b03/media_kit/lib/src/player/platform_player.dart)、[视频表面](https://github.com/media-kit/media-kit/blob/b29d407a4e3990dde2b35b152920383a11076b03/media_kit_video/lib/src/video/video_texture.dart)；
- Namida：[QueueController](https://github.com/namidaco/namida/blob/c609eeaecb2b39ef907d3dc06fa9963099b3bb8b/lib/controller/queue_controller.dart)、[AudioHandler 状态保存](https://github.com/namidaco/namida/blob/c609eeaecb2b39ef907d3dc06fa9963099b3bb8b/lib/base/audio_handler.dart)；
- fvp：[controller 扩展](https://github.com/wang-bin/fvp/blob/ac3c397c5430db6146562974dd5db69d80662bbf/lib/src/controller.dart)、[Windows decoder 选择](https://github.com/wang-bin/fvp/blob/ac3c397c5430db6146562974dd5db69d80662bbf/lib/src/video_player_mdk.dart)、[MDK v0.36.0](https://github.com/wang-bin/mdk-sdk/releases/tag/v0.36.0)。

## 3. Harmonoid：值得借鉴的媒体库体验

### 3.1 可直接转译到 Local Tag Player 的做法

#### 数据库快启，扫描显式发生

Harmonoid 启动时先从数据库恢复媒体库，只有空库才自动执行完整刷新。这样可以先显示已有内容，再把磁盘扫描作为明确状态处理。

对本项目的价值：

- 打开应用时优先恢复上次媒体库结果，不让大目录扫描阻塞首屏。
- 扫描、刷新和重建应是三个可辨认的动作。
- “重建索引”必须带确认，且不能静默删除 manual/locked tags。

#### 把扫描进度放进日常界面

Harmonoid 会在搜索区域和设置页显示发现文件的进度、已处理数与总数，而不是只在临时弹窗中提示。

对本项目的建议：

- 媒体库搜索区可显示轻量扫描状态，但继续使用稳定的 `TextField` / `TextEditingController`。
- 标签点击先刷新可见结果，扫描统计和标签计数继续延后，不得让进度反馈反向阻塞筛选。
- 扫描期间禁用互相冲突的 root 增删、刷新和重建动作。

#### 搜索结果先给分组预览

Harmonoid 的搜索页按 Album、Artist、Genre、Track 分组，并提供“查看全部”。

本项目不能照搬音乐分类，但可转译为：

- 当前命中视频；
- folder/manual/rule/filename/import/auto 来源分组；
- folder 标签必须保留一级父级路径；
- 每组先显示有限预览，再进入完整结果。

这里必须继续由展示层合并重复标签，不能直接摊平原始 `tags` 索引。

#### 每个视图保存自己的浏览状态

Harmonoid 分别保存排序、网格跨度和桌面列宽，并用局部 notifier 限制 rebuild。

对本项目的价值：

- 媒体库排序、布局密度和滚动状态应分别持久化。
- 排序切换不能触发完整标签计数刷新。
- 搜索栏、排序菜单和滚动 chrome 可以局部刷新，不扩大到整个媒体库列表。

#### 有界读取池与超时

Harmonoid 对 tag reader 使用有界池并设置超时，播放列表刷新也与主媒体扫描分开。

对本项目的价值：

- 扫描、媒体详情和缩略图继续保持独立队列与限流。
- 可见视频优先，后台元数据任务不得与播放争抢 UI 线程。

### 3.2 不应照搬

- 不使用 Harmonoid 的 `SearchBar` / `SearchAnchor` 输入链路；项目硬规则要求稳定的 `TextField` / `TextEditingController`。
- 不引入 Album/Artist/Genre 作为本项目核心信息架构。
- 不把 folder/manual/rule 等标签来源合并成单一音乐标签。
- 不复制“按路径重建即删除旧记录”的语义；stable video identity 和用户维护数据必须保留。
- 不复制源码实现或视觉资产。

## 4. media-kit：当前后端边界核对

### 4.1 已经正确的边界

media-kit 自身同时提供单媒体、playlist、轨道、事件流和视频表面。当前项目没有把这些能力原样泄漏到页面，而是由 `PlayerBackend` / `PlayerService` 收口，方向正确。

| 边界问题 | 当前状态 | 判断 |
|---|---|---|
| filtered queue 由谁拥有 | `PlayerPage` / playback composition 拥有，backend 只接收当前 path | 完整 |
| 当前 index 与队列顺序 | 应用层维护，不使用 media-kit playlist 作为业务真相 | 完整 |
| Player / VideoController 所有权 | `MediaKitPlayerBackend` 独占 | 完整 |
| Texture / Windows 原生表面 | 通过 `buildVideoSurface` 收口 | 完整 |
| play/pause/stop/seek/rate/volume | 稳定命令接口 | 完整 |
| 快速切换 | 页面层 latest-request worker 串行消费最新 path | 完整，但不能中断正在执行的底层 open |
| dispose 与原生释放 | 有 `dispose` 和 `released` | 完整，Windows 5.2 秒 grace period 属于版本性补丁 |
| mpv 高级属性 | 留在 runtime/property 边界后 | 基本完整，但仍是字符串协议 |
| GPU / 插帧 / overlay 可选能力 | 使用独立可选接口 | 完整，不强迫所有后端伪实现 |

因此，不应为了使用 fvp 或原生后端，把 filtered queue 下沉到播放器引擎。引擎 playlist 只能是实现细节，不能成为业务队列真相。

### 4.2 仍缺少的边界

这些缺口不阻塞当前产品播放，却会阻塞严格的三后端对照：

1. **真实首帧事件缺失。** 当前“duration 或 codec 已出现”只能说明媒体可解析，不能证明画面已提交到 Flutter/原生表面。
2. **错误仍是 `Stream<String>`。** 无法稳定区分 missing、unsupported container、unsupported codec、decoder initialization、surface failure、timeout 和 cancelled。
3. **打开结果没有 request identity。** latest-request 在页面层能丢弃旧结果，但底层 `openPath` 不能取消或标识过期打开。
4. **活动解码器证据仍依赖字符串属性。** requested hwdec、实际 decoder、renderer、物理 adapter 和 fallback reason 没有统一类型化快照。
5. **能力与遥测没有统一可选契约。** fvp、media-kit 和当前原生后端若要同表比较，需要共享“首帧、活动解码器、错误码、资源释放完成”的只读证据。

最小后续方向不是扩大 `PlayerBackend` 主接口，而是增加一个可选、只读的 `PlayerBackendTelemetryBoundary`：

- `requestId`；
- `opening / prepared / firstFramePresented / ended / failed / cancelled`；
- 不含本地路径的结构化错误码；
- requested/active decoder、renderer 与 adapter evidence；
- 打开、首帧、停止和完全释放时间戳。

队列、FilterQuery、标签语义仍不得进入该边界。

## 5. Namida：filtered queue 与状态恢复核对

### 5.1 Namida 值得学习的状态分层

Namida 将恢复拆为四类：

- 最新队列：2 秒限流写入，启动时恢复；
- 当前 index：变化时单独持久化，恢复时越界回到 0；
- 单媒体进度：接近结尾 30 秒时清零，避免下次从片尾恢复；
- 按 queue source 保存最近播放项，用于回到某个来源时定位。

启动恢复默认不自动播放，这一点值得保留。

### 5.2 当前项目已经更好的部分

- 播放器消费进入页面时的 `sourcePlaylist`，不会回退到全局媒体库。
- 队列顺序、当前 index、右侧队列和自动下一项共享同一 playback composition。
- 二级标签只能在来源 filtered queue 内进一步收窄。
- 返回媒体库保留过滤状态。
- 快速跳转使用 latest-request worker，不让旧 open 结果覆盖新选择。
- 单视频进度绑定 `videoId`，并已有 ask / continue / restart 行为。

这些语义不应为了模仿 Namida 而改成可随意编辑的通用播放列表。

### 5.3 已确认的恢复缺口

当前代码中：

- `PlaybackSession` 模型存在；
- repository 有 `saveSession` / `loadLastSession`；
- 但全项目没有调用者；
- `PlaybackSession.filterQuery` 没有写入 metadata；
- `queuePaths` 仍以 mutable path 为主；
- 只有 `currentVideoId`，没有完整 `queueVideoIds`；
- 没有显式 `currentIndex`；
- 没有启动恢复入口、版本号、队列来源或恢复失败原因；
- 队列和 index 没有原子快照。

因此当前只能恢复单视频进度，不能在应用重启后恢复“同一个过滤条件、同一顺序、同一 index 的 filtered queue”。

建议的最小闭环：

1. 保存 `sessionVersion`、`filterQuery`、`queueVideoIds`、`currentVideoId`、`currentIndex`、`position`、`wasPlaying`、`savedAt`。
2. 快照以 `videoId` 为主，path 只作诊断或兼容回退。
3. 写入采用 debounce，但 queue、index 和 current item 必须同一次事务提交。
4. 启动只恢复为暂停态，由用户继续播放。
5. 恢复时重新解析 missing/relinked videoId；缺失项跳过并显示原因，不立即删除记录。
6. 若当前媒体库或 FilterQuery 已不可重现，降级到仍可解析的稳定 videoId 队列，并明确提示。

不要照搬 Namida 的 path 身份，也不要把它“队列超过 2000 条不保存”的固定阈值直接带入本项目。

## 6. fvp Windows 隔离实测

### 6.1 环境

| 项目 | 值 |
|---|---|
| Flutter | 3.44.4 stable |
| Dart | 3.12.2 |
| CPU | AMD Ryzen 9 7900X，12C/24T |
| 内存 | 64 GB |
| GPU 1 | AMD Radeon Graphics，驱动 32.0.13018.6 |
| GPU 2 | NVIDIA GeForce RTX 4070 SUPER，驱动 32.0.15.9597 |
| fvp | commit `ac3c397c5430db6146562974dd5db69d80662bbf`，0.37.3 |
| MDK SDK | 官方 GitHub Release v0.36.0 Windows x64 |
| MDK archive SHA-256 | `e93565ba8e614bfb733d4efe90d505ea4c69b54b217b51afe231e7816d98c124` |

说明：fvp 默认 CMake 从 SourceForge mutable nightly 下载 MDK，本机连接停在 0 byte。为完成可重复实测，本轮改用官方 GitHub Release v0.36.0 并记录 SHA-256。它与 fvp 0.37.3 不是严格同版本组合，因此本轮只能作为候选资格测试，不能作为最终替换基准。

### 6.2 测量定义

- `initializedMs`：`VideoPlayerController.initialize()` 完成。
- `firstRenderedFrameMs`：播放开始后，fvp `snapshot(width: 64, height: 36)` 首次返回含非零像素的渲染帧；不是 README 推断，也不是只看 duration。
- `positionAdvancedMs`：position 首次达到 120 ms。
- seek：跳到媒体中点后，实际位置与目标误差小于 1.8 秒。
- 连续跳转：按交错 index 顺序创建、初始化、播放到真实首帧并释放，共 30 次。
- GPU：Windows `GPU Engine(*)\Utilization Percentage` 中该进程的 VideoDecode 与 3D 引擎。

### 6.3 样本结果

| 样本 | 初始化 ms | 真实首帧 ms | position 前进 ms | seek | 活动 decoder |
|---|---:|---:|---:|---|---|
| MP4 / H.264 / 1080p | 43 | 131 | 260 | 通过 | MFT |
| MKV / H.264 / 1080p | 87 | 142 | 292 | 通过 | MFT |
| AVI / MPEG-4 Part 2 / 1080p | 103 | 307 | 520 | 通过 | MFT |
| MOV / H.264 / 1080p | 73 | 129 | 279 | 通过 | MFT |
| MKV / HEVC Main10 / 1080p | 82 | 122 | 293 | 通过 | MFT |
| WebM / VP9 / 720p | 81 | 136 | 286 | 通过 | MFT |
| MKV / AV1 / 720p | 90 | 147 | 293 | 通过 | MFT |
| MP4 / H.264 / 4K60 | 94 | 132 | 303 | 通过 | MFT |

异常文件：

- malformed MP4：25 ms 内返回 `PlatformException(media open error, invalid or unsupported media)`；
- missing MKV：立即返回相同结构化异常；
- 异常信息未把真实本地 path 写入结果。

连续跳转：

- 30 次；
- 失败 0；
- 失败率 0%；
- 真实首帧中位数 141 ms；
- P95 215 ms。

### 6.4 资源与体积

一次完整样本矩阵加 30 次跳转的进程级采样：

| 指标 | 结果 |
|---|---:|
| 总运行时间 | 13.159 s |
| 平均 CPU，占整机 24 逻辑核 | 1.875% |
| 峰值 Working Set | 485.05 MiB |
| 峰值 Private Bytes | 592.37 MiB |
| 平均 VideoDecode | 8.879% |
| 峰值 VideoDecode | 45.827% |
| 平均 3D | 2.223% |
| 峰值 3D | 5.387% |
| Release bundle | 41.74 MiB |
| fvp/MDK/FFmpeg/libass 与附带 codec plugins | 14.93 MiB |

资源数据的限制：

- 测试开启 FINE 级 decoder 日志，并连续创建/释放 controller，峰值内存不是单视频稳态值。
- GPU 计数器只有 7 个约 1 秒粒度样本，适合确认引擎活动，不适合做精细功耗排名。
- fvp 日志确认所有有效样本选择 `MFT`，并出现 D3D11-aware decoder；但公共 API 没有报告实际物理 adapter，不能据此声称使用了 RTX 4070 SUPER。
- HEVC、VP9、AV1 使用本机已安装的 Windows codec extension。换一台机器必须重新测试 fallback。

### 6.5 fvp 决策

本轮结果让 fvp **通过“进入正式 A/B”的资格门槛**，但不支持替换决定。

支持继续研究的证据：

- 容器与 codec 覆盖全部通过；
- 4K60 H.264 得到真实首帧；
- 异常文件失败快；
- 30 次交错切换 0 失败；
- MFT/D3D11 hardware path 与 GPU VideoDecode 活动均有运行时证据；
- native 增量体积 14.93 MiB，可继续优化但不构成立即淘汰。

禁止立即替换的原因：

1. 还没有与当前 backend、media-kit 在同一 release harness、同一媒体、同一测量定义下 A/B。
2. 只有单机单轮，尚无冷启动 5 轮、暖启动 20 轮、长时间播放和 4K HEVC/AV1 压力样本。
3. controller churn 峰值 Private Bytes 达 592.37 MiB，需要区分日志、释放延迟和真实泄漏。
4. 活动物理 GPU 不可由 fvp 公共接口确认。
5. 默认依赖下载是 mutable nightly，本轮还遇到 SourceForge 0-byte 阻塞；必须先固定 MDK URL 与 SHA-256。
6. MDK SDK 的分发与许可仍需单独审查。

## 7. 建议优先级

### P0：先补证据，不换后端

- 给三后端增加可选 telemetry boundary。
- 使用同一 release harness 重跑首帧、CPU/GPU、内存、异常和切换矩阵。
- 固定 fvp 与 MDK 的版本、下载地址和 SHA-256。

### P1：补 filtered queue 跨进程恢复

- 接通 `PlaybackSession` 的保存和加载；
- 序列化 `FilterQuery`；
- 使用完整 `queueVideoIds` + `currentIndex`；
- 原子保存，暂停态恢复；
- missing/relink 按稳定身份协调。

### P2：借鉴 Harmonoid 的媒体库 polish

- 数据库快启；
- 常驻扫描进度；
- 显式 refresh / reindex；
- 分组搜索预览；
- 每视图排序与布局状态持久化。

## 8. 对抗式审查

```text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved
protected behaviors: preserved
unauthorized feature removal: none
mount and reachability: no production code or route changed
prompt impact: research and isolated QA only; no backend replacement
validation:
  isolated flutter analyze: passed
  isolated flutter build windows --release: passed
  isolated real Windows window playback: passed
  8 valid samples: passed
  2 abnormal samples: rejected as expected
  30 queue-style switches: 0 failures
```

## 9. 下一步计划

建立一个仍然不接入生产组合根的三后端 release benchmark runner：

1. 固定同一份样本 manifest 和首帧定义；
2. current/media-kit/fvp 各做 5 次冷启动、20 次暖启动；
3. 每种 codec 单独采 CPU、VideoDecode、3D、Working Set 和 Private Bytes；
4. 记录实际 decoder、renderer、adapter evidence 和 fallback reason；
5. 运行 100 次交错过滤队列跳转及异常文件穿插；
6. 只有 fvp 在稳定性不退化，并在至少一个 Windows 核心指标上有可重复优势时，才讨论实验性 adapter。
