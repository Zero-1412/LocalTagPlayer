# fvp / raw media-kit / 当前后端 Windows 同法 A/B
>
> 状态：历史 QA/实验记录。当前门禁与优先级以 `docs/qa/`、`ROADMAP.md` 和 QA manifest 为准。

日期：2026-07-29

## 结论

**本轮不把正式播放内核从 media-kit 替换为 fvp。**

fvp 在同一台 Windows 机器、同一组样本和同一套进程采集方法下，8/8 有效样本、
30/30 次交错队列跳转均成功；它的渲染帧快照耗时、峰值内存和 Release 目录体积也都
优于本轮 media-kit 组。因此 fvp 已经是值得继续保留的 Windows 性能专项候选。

但当前证据仍不足以支持替换：

1. 三者的截图 API 实现成本不同，`firstRenderedFrameMs` 包含整帧截图编码与 Dart
   解码，不等于纯粹的合成器首帧；当前后端自己的结构化首帧中位数约为 197 ms，
   明显低于它的截图中位数约 731 ms。
2. fvp 组合为 fvp `0.37.3` 加手工固定的 MDK `0.36.0`，不是插件默认 nightly
   组合；还没有形成正式依赖锁定、升级和安全更新策略。
3. 当前后端提供同一 `NativePlayer` 上的首帧代次、稳定错误码、实际解码器、释放阶段、
   滤镜事务和回滚诊断；fvp 本轮只能从日志确认 MFT，不能通过统一边界确认物理 adapter。
4. 本轮只有一次暖态 Release 运行。CPU/GPU 均值还受运行时长与当前后端每次销毁的
   Windows 原生释放宽限影响，不能据此宣称某后端持续功耗更低。

决策是：**media-kit 继续作为正式内核；fvp 不进入业务代码，只保留隔离 A/B 资格。**

## 测试边界

本轮没有修改媒体库、`PlaybackSession` 或 filtered queue 的所有权。隔离 harness
只消费同一份匿名有序清单，模拟播放器收到当前过滤队列后连续跳转：

```text
filtered result order
-> same ordered manifest
-> one reused backend/player
-> 30 interleaved opens
-> rendered-pixel evidence
```

覆盖范围：

| 类别 | 样本 |
| --- | --- |
| 容器 | MKV、MP4、AVI、MOV、WebM |
| 编码 | H.264、HEVC Main10、AV1、VP9、MPEG-4 Part 2 |
| 分辨率 | 720p、1080p、3840×2160 60 fps |
| 异常 | 破损 MP4、缺失 MKV |
| 连续操作 | 每个有效样本 seek；同一实例 30 次交错队列跳转 |

正式产品的 filtered queue 来源、内容、顺序、当前 index 和返回媒体库状态由既有
`PlaybackSession` / `PlayerPage` 回归保护；A/B 后端没有获得重建业务队列的权力。

## 环境与固定版本

| 项目 | 实测值 |
| --- | --- |
| CPU | AMD Ryzen 9 7900X，24 逻辑处理器 |
| 内存 | 64 GiB |
| GPU 1 | AMD Radeon Graphics，驱动 `32.0.13018.6` |
| GPU 2 | NVIDIA GeForce RTX 4070 SUPER，驱动 `32.0.15.9597` |
| fvp | `0.37.3`，commit `ac3c397c5430db6146562974dd5db69d80662bbf` |
| MDK | GitHub Release `v0.36.0`，替代不可重复的 mutable nightly 下载 |
| raw media-kit | 项目当前锁定的 media-kit/libmpv 依赖，不经过产品 facade |
| 当前后端 | `PlayerService -> MediaKitPlayerBackend -> 同一 NativePlayer` |

三个 harness 都以 Flutter Windows Release 构建。外部 PowerShell 采集器使用同一
500 ms 采样周期，记录进程 CPU、Working Set、Private Bytes、GPU Video Decode、
GPU 3D 和整个 Release 目录体积。

## 指标定义与限制

- `initializedMs`：后端打开调用完成或初始化状态就绪。
- `firstRenderedFrameMs`：播放开始后，后端截图首次返回含非零 RGB 像素的完整分辨率
  图像。三组采用相同判定，但底层截图 API 成本不同。
- `telemetryFirstFrameMs`：仅当前正式后端可用；Texture 就绪后结合本代 mpv 帧号、
  视频参数或位置推进记录，不等待 JPEG 截图。
- 切换耗时：同一后端实例按完全相同的 30 项交错顺序打开，记录上述截图证据。
- CPU/GPU 百分比是整个进程运行期均值和采样峰值；当前后端的 5.2 秒原生释放宽限会
  拉低均值、拉长总时长，因此均值只描述本轮运行，不用于单独决定替换。
- GPU 计数器证明进程触发了 Video Decode / 3D 引擎，但没有把引擎实例映射为可审核的
  物理 adapter；硬件支持结论必须同时参考解码器回读或日志。

## 结果

### 有效样本与首帧

单位：毫秒。

| 样本 | fvp 渲染帧 | raw media-kit 渲染帧 | 当前后端渲染帧 | 当前后端结构化首帧 |
| --- | ---: | ---: | ---: | ---: |
| MP4 / H.264 / 1080p | 148 | 765 | 760 | 309 |
| MKV / H.264 / 1080p | 163 | 587 | 833 | 236 |
| AVI / MPEG-4 Part 2 / 1080p | 312 | 558 | 602 | 143 |
| MOV / H.264 / 1080p | 146 | 643 | 768 | 203 |
| MKV / HEVC Main10 / 1080p | 129 | 588 | 701 | 202 |
| WebM / VP9 / 720p | 150 | 411 | 407 | 166 |
| MKV / AV1 / 720p | 142 | 356 | 384 | 167 |
| MP4 / H.264 / 4K60 | 180 | 1995 | 1799 | 191 |
| 成功 / seek | 8/8 | 8/8 | 8/8 | 8/8 |
| 中位数 | 149 | 588 | 731 | 197 |

最重要的反证是 4K 样本：当前后端结构化首帧为 191 ms，但完整截图证据为
1799 ms。它证明本轮截图指标显著包含截图管线成本，不能把 fvp 与 media-kit 的
截图差值直接解释为用户看到首帧的全部差值。

### 异常文件

| 后端 | 破损 MP4 | 缺失 MKV |
| --- | --- | --- |
| fvp | 24 ms，安全 `PlatformException` | 1 ms，安全 `PlatformException` |
| raw media-kit | 4400 ms，`unsupported_or_invalid_media` | 4386 ms，`open_failed` |
| 当前后端 | 4367 ms，`unsupported_or_invalid_media` | 8 ms，`missing_file` |

A/B 首轮发现当前后端把缺失文件交给 libmpv 后，约 4.4 秒才收到泛化错误。正式后端现
在进入 libmpv 前检查存在性，立即记录路径无关的 `missing_file`，同一代次只计一次
失败；Windows 集成测试确认错误流不包含本机目录。破损但存在的文件仍交给 libmpv
判断，当前约 4.4 秒，后续若优化必须保持可取消、路径脱敏和最新请求优先。

### 连续切换、进程资源与包体

| 指标 | fvp | raw media-kit | 当前后端 |
| --- | ---: | ---: | ---: |
| 30 次切换失败率 | 0% | 0% | 0% |
| 切换渲染帧中位数 | 154 ms | 608 ms | 521 ms |
| 切换渲染帧 P95 | 244 ms | 1230 ms | 1037 ms |
| CPU 整机均值 | 1.866% | 3.542% | 1.446%* |
| Video Decode 均值 / 峰值 | 10.549% / 47.336% | 3.814% / 24.197% | 1.409%* / 28.963% |
| GPU 3D 均值 / 峰值 | 2.770% / 5.035% | 3.156% / 11.186% | 1.183%* / 14.592% |
| Working Set 峰值 | 383.8 MiB | 520.5 MiB | 526.9 MiB |
| Private Bytes 峰值 | 437.0 MiB | 678.0 MiB | 695.3 MiB |
| Release 目录 | 41.7 MiB | 74.2 MiB | 76.4 MiB |
| 进程总时长 | 13.435 s | 37.701 s | 89.263 s |

`*` 当前后端均值包含独立样本销毁后的 Windows 原生释放宽限，只能与它自己的后续同法
运行比较。峰值内存和包体不依赖这个均值稀释，fvp 在本轮确有明显优势。

包体差异主要来自 fvp 的 `ffmpeg-8.dll + mdk.dll` 与 media-kit 的约 29.8 MB
`libmpv-2.dll` 加 ANGLE/Vulkan 软件回退组件。当前后端比 raw media-kit 多出的约
2.2 MiB 还包含 SQLite、窗口管理等真实应用依赖。

## 硬件功能支持度

| 能力 | fvp / MDK | media-kit / 当前后端 |
| --- | --- | --- |
| H.264 | MFT，D3D11-aware；1080p 与 4K60 通过 | `d3d11va-copy` 通过 |
| HEVC Main10 | HEVC Video Extension MFT 通过 | `d3d11va-copy` 通过 |
| VP9 | VP9 Video Extension MFT 通过 | `d3d11va-copy` 通过 |
| AV1 | AV1 Video Extension MFT 通过 | 播放通过；回读为 `libdav1d` 与 `d3d11va-copy`，证据存在歧义 |
| AVI / MPEG-4 Part 2 | AMD D3D11 Hardware MFT 日志并播放通过 | 播放通过，`hwdec-current=no` |
| 实际物理 adapter | 本轮公共 API 未确认 | 项目能力矩阵可独立查询；本 A/B 进程样本未绑定适配器证据 |
| 高级滤镜与回滚 | 未接入产品边界 | 同一 `NativePlayer` 上有事务、逐项回读、回滚与安全诊断 |
| 资源释放遥测 | 本轮无统一契约 | Player dispose、原生等待、总耗时分段可见 |

AV1 的 media-kit 回读同时出现软件 decoder 名与硬解状态，不能在没有帧上下文/adapter
证据时宣称 AV1 已由某块 GPU 硬解。fvp 的 MFT 日志也只能确认被选择的解码组件，
不能据此声称使用 RTX 4070 SUPER。

## 后端边界结论

本次 A/B 反向证明当前边界方向正确：

- `PlayerBackend` 主 contract 无需为了 fvp 扩张；
- filtered queue 继续由 `PlaybackSession` / 页面状态拥有；
- 首帧、错误、解码器与释放留在可选只读遥测边界；
- libmpv 高级滤镜继续复用当前 `NativePlayer`，不创建第二实例；
- fvp 若进入下一阶段，只能实现实验 adapter，不能让插件 playlist 接管业务队列。

## 对抗式审查

```text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: unchanged; A/B 只消费匿名有序清单
thumbnail/media queue: unchanged
user data: preserved
PlayerBackend contract: unchanged; MediaKit 缺失文件只增加安全快速失败
protected behaviors: 播放、seek、30 次连续切换、同实例滤镜和释放路径均保留
unauthorized feature removal: none
mount and reachability: 既有 PlayerPage/PlaybackSession 回归不变，Windows 后端集成通过
validation: 三组 Release harness 通过；正式项目测试、analyze/build 见任务记录
```

验证附注：

- `player_backend_telemetry_test.dart` 3/3 通过；
- Windows `media_kit_libmpv_facade_test.dart` 的缺失文件真实按钮点击、遥测、错误流与
  释放 1/1 通过，真实媒体用例在未提供本机路径时按设计跳过；
- `flutter analyze` 与正式 Windows Debug build 通过；
- 额外补跑的既有 `player_queue_screenshot_test.dart` 在首次点击前因当前 QA 数据缺少
  `qa.video.play.purple-grid` 夹具失败；`player_renderer_settings_test.dart` 在首次点击前
  因旧文案 `MPV 容器渲染` 不再存在而失败。两项均未修改，不能作为本次后端回归证据。

## 下一步计划

1. 不实现 fvp 产品切换入口；先把隔离 harness 固定为可重复的 5 次冷启动、20 次暖启动。
2. 把渲染首帧改为两后端都能提供的 compositor/texture presentation 证据，减少截图 API
   成本偏差。
3. 为 fvp 增加结构化 decoder、adapter、错误码和释放完成证据；做不到则不进入 adapter。
4. 单独优化 media-kit 的破损文件取消/超时，不把缺失文件的快速失败扩张为格式猜测。
5. 只有 fvp 在重复运行中保持切换失败率不退化，并在首帧、峰值内存或包体至少一个核心
   指标持续占优，才讨论默认关闭的实验 adapter。
