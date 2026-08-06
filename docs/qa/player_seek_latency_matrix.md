# 播放器真实 seek 延迟矩阵门禁

本门禁衡量本产品已支持的本地发现播放器交互，不把目标扩展为 PotPlayer 或 VLC 的完整专业播放器。它保护精确恢复入口和方向键语义：精确恢复只做一次 absolute seek，方向键短按只在 KeyUp 做一次精确 seek，只有长按产生 `KeyRepeat` 后才允许关键帧预览。普通鼠标点击进度条走独立的关键帧 latest-only 交互路径，由 focused 测试保护其快速点击不堆积。

## 覆盖与口径

矩阵必须完整覆盖 12 例：`1080p/4k × h264/hevc/av1 × short-gop/long-gop`。每例先由 `ffprobe` 验证视频流编码和像素尺寸；短 GOP 最大关键帧间隔不得超过 1.1 秒，长 GOP 不得少于 4 秒。脚本随后运行正式 `MediaKitPlayerBackend` 的 Texture 输出，在两次预热后采集 7 次精确随机 seek，从后端调用到位置实际接近目标（750 ms 容差）的端到端耗时计算 p50/p95/max。

解码器路径记录为证据而非先验。硬件不支持时允许软件回退参加门禁，但必须为该机器设置独立、明确的预算；不得根据请求的 `hwdec` 参数推测实际硬解。

## 本机 manifest

媒体路径不得提交。创建一个本机 JSON（建议放在 `.local/qa/`）并为每个 case 填写真实样本和预算：

```json
{
  "cases": [
    {
      "id": "1080p-h264-short-gop",
      "path": "D:\\qa-media\\h264-1080p-gop30.mp4",
      "codec": "h264",
      "width": 1920,
      "height": 1080,
      "gop": "short-gop",
      "p95BudgetMs": 500
    }
  ]
}
```

其余 11 个 ID 必须正好为：

```text
1080p-h264-long-gop   1080p-hevc-short-gop   1080p-hevc-long-gop
1080p-av1-short-gop   1080p-av1-long-gop     4k-h264-short-gop
4k-h264-long-gop      4k-hevc-short-gop      4k-hevc-long-gop
4k-av1-short-gop      4k-av1-long-gop
```

推荐初始 p95 预算为 1080p 短/长 GOP `500/1200 ms`、4K 短/长 GOP `800/1800 ms`；它们是回归门槛，不是跨设备的性能承诺。第一次在目标机器建立基线后，只能在有真实结果和原因记录时调整预算。

## 执行

```powershell
.\tool\run_player_seek_latency_matrix.ps1 -Manifest .\.local\qa\player_seek-latency-matrix.json
```

输出位于未跟踪的 `artifacts/player_seek_latency_<timestamp>/`：每个 case 的日志和不含路径的 `summary.json`。矩阵通过正式精确恢复入口测量：临时静音但不暂停视频时钟；精确 seek 返回后才采样基线，Windows 正式 Texture 还必须观察到 `native-rendered-frames` 递增才计入完成。非原生路径可回退 `estimated-frame-number`，但结果必须标记为估算证据，不能与 Texture 已渲染结果混算。任一样本缺失、probe 与 manifest 不符、GOP 分类不符、后端未确认位置/新帧或 p95 超预算都会使门禁失败。

## 录屏与 `PLAYER_SEEK_TRACE` 对齐

当真实媒体库出现“预览帧先到、连续播放稍后恢复”的间歇性问题时，录屏应以 30fps 或更高的固定帧率保存到未跟踪的 `.local/qa/`，并在启动录制时写入 UTC 毫秒侧车记录。调试日志中的同一 `trace` 必须按以下顺序出现：

```text
key_up
exact_seek_start
exact_seek_complete
new_video_frame | new_video_frame_timeout
audio_restore_start
audio_restore_complete
```

每条事件的 `mono_us` 只用于计算节点间隔；`wall_utc_ms` 只用于和录屏侧车记录建立时间锚点。若 `exact_seek_complete` 已出现而 `new_video_frame` 明显延后，说明解码/呈现恢复慢；若 `new_video_frame` 已出现但连续画面仍静止，则需要继续检查 Texture 呈现或播放器时钟，不能把单一预览帧当作恢复完成。

## 长 GOP 策略校准

脚本同时写出 `long_gop_policy.json`。它用六个长 GOP case 的最高 p95 推荐页面的运行时档位：

- `<= 750ms`：64ms（约 15fps）预览，750ms 最终新帧阈值；
- `<= 1200ms`：96ms（约 10fps）预览，1200ms 阈值；
- `> 1200ms`：125ms（约 8fps）预览，1800ms 阈值。

运行时不为交互额外扫描媒体 GOP；它保留 latest-only 合并并以同一会话的关键帧 seek 耗时选择上述档位。只有持有完整 12-case manifest 的机器产出结果后，才可以调整这些校准边界。

若超过最终新帧阈值仍无帧号变化，播放器保留临时静音而不播放旧落点音频；下一次 seek 会建立新会话。`frame_evidence=native-rendered-texture` 表示原生桥已经完成共享纹理复制并标记 Flutter Texture 可用，`estimated-frame-number-fallback` 只表示兼容路径的 mpv 估算，录屏分析不得把两者视为同等的屏幕呈现证据。该失败路径写入 `PLAYER_SEEK frame_presentation_timeout`，供诊断而非作为成功收敛。
