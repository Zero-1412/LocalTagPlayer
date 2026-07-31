# Flutter Texture 合成采样 A/B（2026-07-30）
>
> 状态：历史 QA/实验记录。当前门禁与优先级以 `docs/qa/`、`ROADMAP.md` 和 QA manifest 为准。

## 目标与边界

在正式 `PlayerService -> MediaKitPlayerBackend -> NativePlayer/libmpv ->
media_kit_video Texture` 链路中，同时采集原生 Texture 像素尺寸、Flutter 视频 Widget
逻辑尺寸、DPR、BoxFit 后物理目标尺寸与最终合成倍率，再比较 `FilterQuality.low`、
`medium`、`high` 的画质和资源成本。

测试不创建第二个播放器，不读取用户媒体库，也不修改 filtered queue、播放设置持久化或
VideoController 输出尺寸。生产与 QA 均使用同一个 1920×1080 Texture；三档只改变
Flutter `Texture.filterQuality`。

[Flutter 官方说明](https://api.flutter.dev/flutter/dart-ui/FilterQuality.html)：
`low` 是双线性；`medium` 使用 mipmap，尤其适用于缩小到一半以下；`high` 是最慢的
双三次采样，主要用于大倍率放大，在小于 0.5× 的缩小时可能不如 `medium`。
`Texture` 本身的[默认采样为 `low`](https://api.flutter.dev/flutter/widgets/Texture/filterQuality.html)。

## 尺寸证据

| 场景 | Widget 逻辑尺寸 | DPR | BoxFit 物理目标 | Texture | 合成倍率 |
|---|---:|---:|---:|---:|---:|
| 常规测试窗 1440×900 | 1030×806 dp | 1.50 | 1545×869 px | 1920×1080 px | 0.805× |
| 有效紧凑窗 920×650 | 510×556 dp | 1.50 | 765×430 px | 1920×1080 px | 0.398× |

这证明当前缩小所有权位于 Flutter/Windows 合成层，而不是 libmpv。700×520 与
900×650 会分别触发既有控制条 104/102 px 和 4/2 px 横向溢出，不能作为有效画质
门禁；920×650 是本轮通过布局门禁的最小测试宽度。

## 性能与稳定性

两档缩放、三类 650 kbps 自然片源、三种采样共 18 次真实会话：

- 解码/总掉帧、音视频停滞与窗口无响应均为 0。
- GPU 利用率 P95 均在 4.4%–4.9%，没有稳定的采样档位排序。
- `low` 的 GPU committed P95 为 340.1–349.2 MiB，private P95 为
  635.9–658.9 MiB。
- `medium` 的 GPU committed P95 为 442.9–448.1 MiB，private P95 为
  931.7–987.5 MiB；mipmap 路径稳定增加约 100 MiB GPU committed 和约
  300 MiB private memory。
- `high` 的 GPU committed P95 为 340.2–379.6 MiB，private P95 为
  635.6–704.4 MiB；短样本 CPU 波动较大，没有形成可信的稳定排序。

## 画质

固定 12 秒最终窗口的视频目标区域两两比较：

| 倍率 | low ↔ medium SSIM | low ↔ high SSIM | 观察 |
|---|---:|---:|---|
| 0.805× | 0.99910–0.99927 | 0.99968–0.99977 | 三档肉眼差异极小 |
| 0.398× | 0.99487–0.99732 | 0.99974–0.99977 | medium 抗混叠更强，high 仍几乎等同 low |

0.398× 下，`medium` 相对 `low` 的 Laplacian 方差降低 16.6%–42.1%，说明它确实
抑制高频混叠，但对已经低码率、偏软的素材也会进一步降低边缘细节。它与离线 area
缩小参考的 MAE 在三类内容上都更低，但改善幅度不足以抵消稳定的大额内存成本。
`high` 的 Laplacian 方差只比 `low` 高约 1.9%–5.5%，最终像素仍高度接近，未形成
足以承担更慢算法语义的可见收益。

## 决策

生产继续显式使用 `FilterQuality.low`，不增加用户设置，也不按倍率自动切换
`medium/high`：

1. 0.5×–1.0× 时 low 与 high 已近乎一致；
2. 小于 0.5× 时 medium 的抗混叠有效，但会软化低码率细节并稳定增加约
   100 MiB GPU / 300 MiB private memory；
3. 动态切换采样会扩大高频布局路径，收益不足以证明复杂度合理。

可复测入口为 `tool/run_quality_ab.ps1 -Preset flutter-texture`。匿名原始证据位于
`.local/qa/texture-sampling-ab` 与 `.local/qa/texture-sampling-compact-ab-920`，
不进入 Git。

## 验证

- 完整 466 项测试通过，3 项既有 benchmark 按条件跳过；`flutter analyze` 零问题，
  Windows Debug build 成功。
- 最新 Debug 产物真实执行“媒体库进入播放器 → 视频画面右键 → 诊断检查 → 滚动详细指标”。
  诊断现场显示 1920×1080 px Texture、951.33×568.67 dp Widget、DPR 1.50、
  1427×803 px BoxFit 物理目标、0.743× 合成倍率与 `FilterQuality.low`。
- 截图复核七项新增诊断字段均可读，没有位置、遮挡、对齐、溢出、对比度或状态反馈问题。

## 下一步

优先单独修复 900 dp 以下播放器控制条的既有溢出，再评估让 VideoController 输出尺寸
按稳定档位接近 Widget 物理目标。只有纹理重建、DPI 往返、快速缩放、掉帧和显存门禁
通过后，才能比较“原生输出缩小”与“固定 1080p Texture 后由 Flutter 缩小”的总体成本。
