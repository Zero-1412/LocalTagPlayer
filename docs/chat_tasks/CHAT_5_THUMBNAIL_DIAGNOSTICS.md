# Chat 5：缩略图、媒体信息与诊断

## 所有权

- `ThumbnailService`、`MediaDetailsService`；
- `FFmpegBackend` / FFprobe 平台访问；
- 缓存 key、有效性、重试、清理和 diagnostics UI。

## 必须保持

- 可见项优先、后台限流并可取消过期任务；
- 0-byte/不完整 JPEG 无效；
- 失败原因可见且可重试；
- 播放活跃时降低后台负载；
- UI 不拼 FFmpeg 路径或拥有 cache invalidation；
- diagnostics dispose 后无 timer/async UI callback。
- 相似视频视觉签名是可重建派生缓存：经 `VisualSignatureCacheRepository` 按 stable `videoId`
  持久化，并以算法版本和媒体 fingerprint/size/mtime 校验有效性；删除时必须由 Repository
  同事务清理，缓存读写失败只能回退重算，不能阻断媒体库或播放器。
- 相似视频进度必须区分首帧预筛和深度时序取帧；深度取帧尚未汇合时不能继续沿用预筛吞吐率计算 ETA，
  也不能让扫描 Future 在仍有深度批次时提前完成。
- 深度取帧按唯一 stable `videoId` 使用连续有界 worker；单个慢视频不得阻塞整批候选对补位，进度以唯一签名
  任务为单位，取帧结束后再以内存签名完成候选比较。
- 深度任务按预计时长/大小采用最长任务优先，相似取帧队列跨视频轮转；视觉签名的 metadata 持久化必须在
  独立串行后台链执行，不得占住 FFmpeg worker。
- 视觉签名判定必须保留时间顺序：首帧仅作廉价预筛，不能单帧直接成组；完整签名需要固定小偏移下的
  30%/50%/70% 中段采样点覆盖，并以保守的最弱边距离生成“视觉匹配度”；公共片头/片尾不能参与主体评分。
  该百分比是人工复核排序指标，不是重复概率；页面展示视觉候选时按百分比从高到低排序。
- 对剪辑/重编码难例保留独立 review 召回层：主体部分通过且标题或媒体元数据足够接近时显示“疑似内容近重复（待复核）”，
  不放宽高置信组、不触发自动删除。
- 相似签名必须在 `ThumbnailService` 内读取临时预览 JPEG 的字节快照，不得把易被 LRU 清理的 `File` 路径
  延后交给 dHash；缓存竞态只允许有限重试或跳过当前采样点，不能让整轮搜索失败。
- 相似视频扫描的 Future 和状态由媒体库 Route 级 controller 持有：首次进入才自动启动，页面退出只
  降低相似取帧并发，不取消进行中的任务；后续进入复用任务/结果，只有用户显式刷新才重跑。播放器活跃
  时视觉调度等待、缩略图批量队列冻结、MediaDetailsService 暂停新 FFprobe，退出后恢复进入播放器前
  的暂停状态。

## 非目标

不拥有标签查询、播放队列、stable identity 或原生播放器实现。

历史：`docs/history/chat/CHAT_5_THUMBNAIL_DIAGNOSTICS_THROUGH_2026-07-30.md`。
