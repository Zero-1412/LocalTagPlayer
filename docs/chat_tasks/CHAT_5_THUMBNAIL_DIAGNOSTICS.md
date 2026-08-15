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

## 非目标

不拥有标签查询、播放队列、stable identity 或原生播放器实现。

历史：`docs/history/chat/CHAT_5_THUMBNAIL_DIAGNOSTICS_THROUGH_2026-07-30.md`。
