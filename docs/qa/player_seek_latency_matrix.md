# 播放器真实 seek 延迟矩阵门禁

本门禁衡量本产品已支持的本地发现播放器交互，不把目标扩展为 PotPlayer 或 VLC 的完整专业播放器。它保护两件具体行为：进度条松手只做一次精确 seek；方向键短按只在 KeyUp 做一次精确 seek，只有长按产生 `KeyRepeat` 后才允许关键帧预览。

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

输出位于未跟踪的 `artifacts/player_seek_latency_<timestamp>/`：每个 case 的日志和不含路径的 `summary.json`。任一样本缺失、probe 与 manifest 不符、GOP 分类不符、后端未确认位置或 p95 超预算都会使门禁失败。
