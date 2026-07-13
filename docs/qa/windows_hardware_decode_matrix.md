# Windows 硬解兼容矩阵

## 验证环境

- 日期：2026-07-14
- GPU：NVIDIA GeForce RTX 4070 SUPER
- 驱动：595.97
- 默认播放器：MediaKit / libmpv
- 请求硬解：`d3d11va-copy`
- 操作链路：真实媒体库打开、右侧队列滚动、两次随机 seek、全屏往返、诊断采样、退出并等待纹理释放

该矩阵是当前参考环境的真实样本结果，不等价于所有 GPU、驱动和编码 profile 的通用能力表。应用只对“已确认不支持”显示播放前提示，未验证组合保持 unknown。

## 4K 样本矩阵

| 编码 | 样本规格 | 轮次 | 实际硬解 | 视频/音频停滞 | AV offset 范围 | seek 范围 | 结论 |
|---|---:|---:|---|---:|---:|---:|---|
| H.264 | 3840×2160 / 60 fps | 2 | `d3d11va-copy` | 0 / 0 | 0.000005–0.000444 秒 | 26–28 ms | 已验证 |
| HEVC | 3840×2160 / 60 fps | 2 | `d3d11va-copy` | 0 / 0 | 0.000007–0.000013 秒 | 26 ms | 已验证 |
| AV1 | 3840×2160 / 60 fps | 2 | `d3d11va-copy` | 0 / 0 | 0.000035–0.000445 秒 | 25–27 ms | 已验证 |

## 已确认软件回退

| 编码 | 样本规格 | 实际硬解 | 观察结果 | 产品处理 |
|---|---:|---|---|---|
| H.264 | 7680×4320 / 60 fps | `no` | 总掉帧约 4,240，AV offset 约 2.4 秒，持续 CPU 软件解码 | 首次播放和队列切换均在新 open 前提示；可取消或继续软件解码 |

## 代理与转码建议

优先保留源文件，生成独立代理文件并抽查画质、音轨与字幕：

```powershell
ffmpeg -i input.mp4 -map 0:v:0 -map 0:a? -vf scale=3840:-2 -c:v libx264 -preset medium -crf 20 -c:a copy output.proxy-4k.mp4
```

空间优先时可生成 4K HEVC；当前参考环境已通过 4K HEVC 硬解验证：

```powershell
ffmpeg -i input.mp4 -map 0:v:0 -map 0:a? -vf scale=3840:-2 -c:v libx265 -preset medium -crf 22 -c:a copy output.hevc-4k.mp4
```

## 复测方式

为每种编码把真实样本路径仅放入进程环境变量，不写入日志或仓库：

```powershell
$env:LOCAL_TAG_PLAYER_STRESS_MEDIA_PATH='<真实样本路径>'
$env:LOCAL_TAG_PLAYER_STRESS_SECONDS='30'
$env:LOCAL_TAG_PLAYER_STRESS_SEED='20260714'
flutter test integration_test/player_real_library_stress_test.dart -d windows --timeout 8m
```

以 `PLAYER_DIAGNOSTICS` 中的实际硬解、帧推进、音频 PTS、停滞事件、AV offset 和 seek latency 为判定依据，不根据请求参数推测实际硬解。
