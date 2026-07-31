# MediaKit Texture 缩小画质 A/B（2026-07-30）
>
> 状态：历史 QA/实验记录。当前门禁与优先级以 `docs/qa/`、`ROADMAP.md` 和 QA manifest 为准。

## 目标

验证正式 MediaKit Texture 路径在低码率视频缩小显示时，显式设置 `dscale` 与
`correct-downscaling` 是否能带来可见收益，并据此决定是否修改生产默认。

## 第一性原理与边界

- 测试必须复用正式 `PlayerService -> MediaKitPlayerBackend -> NativePlayer/libmpv`
  实例，不能创建第二个播放器或用离线 FFmpeg 结果冒充应用画面。
- 三组只改变 GPU renderer 的缩小属性；媒体、固定时间点、窗口、硬解、filtered queue
  和其它增强设置保持一致。
- 本项目打包的 mpv 0.36 手册说明：`dscale` 只在 libmpv 执行缩小时生效；未设置时
  跟随 `scale`，而兼容默认的双线性缩小会让 `correct-downscaling` 被忽略。真实 Debug
  诊断进一步确认本机当前值为 `bilinear/no`。参考：
  [mpv 0.36 官方选项手册](https://github.com/mpv-player/mpv/blob/v0.36.0/DOCS/man/options.rst)。

## A/B 配置

| 模式 | `dscale` | `correct-downscaling` | 目的 |
|---|---|---|---|
| A：当前行为 | `bilinear` | `no` | 固定打包 mpv 0.36 的实际读回 |
| B：高质量缩小 | `lanczos` | `yes` | 候选生产默认 |
| C：关闭校正 | `lanczos` | `no` | 隔离采样半径校正 |

样本使用既有三类 650 kbps、1920×1080、24 fps 自然片源：真人面部、动画渐变和暗场。
每组真实播放 20 秒，在 12 秒固定帧暂停并由 PID 绑定的 `PrintWindow` 保存最终窗口。

## 结果

三类内容、九次真实会话全部确认：

- 正式后端为 MediaKit Texture，实际硬解为 `d3d11va-copy`。
- 请求的 `bilinear/lanczos` 与 `yes/no` 均从同一 NativePlayer 成功读回。
- 解码/总掉帧最大值均为 0；视频/音频停滞与窗口无响应样本均为 0。
- GPU 利用率 P95：A 为 4.5%–4.6%，B 为 4.5%–4.8%，C 为 4.6%–4.8%。
- GPU committed P95：A 三类均为 322.1 MiB；B 为 381.2–440.2 MiB，C 为
  381.2–446.4 MiB。候选卷积缩小增加了资源占用，但没有造成掉帧。
- 三类 A/B/C 最终窗口 PNG 在各自内容内 SHA-256 完全相同；
  对视频有效画面做两两 SSIM 也全部为 `1.000000`。
- 完整 461 项测试通过，3 项既有 benchmark 跳过；`flutter analyze` 与 Windows Debug
  build 通过。真实 Debug 窗口右键打开诊断并滚动确认 `bilinear/no` 可见，新增字段无截断、
  遮挡或溢出。

完整匿名数据位于 `.local/qa/downscale-quality-ab/downscale-ab-summary.json`，可用
`tool/run_downscale_quality_ab.ps1` 重建。`.local` 证据不进入 Git。

## 结论

生产默认保持 `dscale=bilinear`、`correct-downscaling=no`，不改为候选
`lanczos/yes`。

属性读回成功只证明 libmpv 接受了配置，不能证明它参与最终窗口缩小。当前 NativePlayer
继续输出 1920×1080 Texture，窗口内的缩小发生在 Flutter/Windows 合成层，因此三种
libmpv 缩小配置得到逐字节相同的最终窗口。候选配置还增加了 GPU committed，因此
没有必要制造一个“已部署但无观感”的设置。

## 下一步

先在正式纹理边界同时记录 `native-surface-width/height`、视频 Widget 目标尺寸与 DPI，
确认每帧实际缩小所有权；再评估：

1. Flutter Texture 合成采样是否能使用更合适的质量策略；
2. MediaKit 输出尺寸能否安全跟随视频区域而不引入纹理重建、掉帧和 DPI 抖动；
3. 只有 libmpv 真正承担缩小时，才重跑 `hermite` / `lanczos` /
   `correct-downscaling` A/B 并重新决定默认值。
