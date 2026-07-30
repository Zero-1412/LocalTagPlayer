# 原生 Texture 稳定尺寸与小窗口控制条门禁（2026-07-30）

## 结论

- 899 dp 及以下播放器控制区改为三层紧凑布局：进度、传输控制、左右功能入口。
  文件定位、音量、上一项、播放/暂停、下一项、截图、设置、全屏和队列均保留。
- MediaKit Texture 默认按 Widget 的 BoxFit 物理目标选择稳定 16:9 档位：
  640×360、960×540、1280×720、1600×900、1920×1080。
- 使用 420 ms 去抖、1100 ms 最小请求间隔、90% 降档滞回和 3000 ms 原生回报
  超时；前一代 Texture 未确认前不允许继续请求。
- 三类低码率内容和两次缩放门禁通过后，生产默认启用稳定档位自适应。
  `FilterQuality.low`、`dscale=bilinear`、`correct-downscaling=no` 保持不变。

## 布局与可达性

修复前，700×520 会话的控制条左右 Row 分别溢出 104 px 和 102 px。修复后，
700×520 与 899×650 真实 Windows integration 窗口均无 `RenderFlex overflow`。

899×650 下真实鼠标停留显示紧凑控制条并点击设置入口。首次截图发现固定 300 dp
设置面板可能因齿轮移到靠左位置而产生负 left；随后为面板右侧偏移增加可视区上界，
复测确认标题、循环开关和“更多播放设置”完整可见。队列仍挂载在播放器右侧，
隐藏进度条、所有按钮 Key、filtered queue、当前 index 和返回路径未改变。

截图证据保存在未入库的本机 QA 目录：

- `.local/qa/compact-controls-899/.../native-output-adaptive-complete-window.png`
- `.local/qa/compact-controls-settings-click-post/.../native-output-adaptive-player-settings.png`

## 原生尺寸 A/B

固定条件：700×520 逻辑表面、DPR 1.50、同一 650 kbps 自然片源、每模式 20 秒、
固定 12 秒窗口帧。fixed 保持 1920×1080；adaptive 收敛到 640×360。Widget 的
BoxFit 物理目标为 435×245 px，Flutter 合成倍率由 0.227× 提高到 0.680×。

| 内容 | 总掉帧/停滞/未响应 | GPU P95 差值 | GPU committed P95 差值 | Private P95 差值 | 视频区 SSIM |
| --- | --- | ---: | ---: | ---: | ---: |
| 真人面部 | 0 / 0 / 0 | +0.4 pct | -21.5 MiB | -12.7 MiB | 0.993825 |
| 动画渐变 | 0 / 0 / 0 | +0.1 pct | -21.4 MiB | -5.2 MiB | 0.988722 |
| 暗场 | 0 / 0 / 0 | -0.5 pct | -18.3 MiB | -2.2 MiB | 0.999943 |

视频区 PSNR 分别为 46.397、37.480、73.884 dB；三组固定帧目视均未见可感知的
锐度、色带、暗部或边缘退化。性能自动门禁要求 adaptive GPU P95 不高于 fixed
2 个百分点、GPU committed/private P95 不高于 fixed 32 MiB、掉帧不增加超过 1、
无停滞/未响应、Texture 请求与代次一致，三组全部通过。

完整原始报告保存在：

- `.local/qa/native-output-size-ab-full/native-output-size-ab-summary.json`

## DPI、快速缩放与 Texture 生命周期

门禁在真实 Windows MediaKit Texture 后端中执行，DPR 由 1.50 往返 2.00，再以
60 ms 间隔连续改变窗口尺寸并返回初始大小。两次独立会话结果：

| 门禁 | DPI 请求/代次 | 快速缩放请求/代次 | 失败 | 掉帧 | 播放推进 | Flutter P95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 第 1 次 | 2 / 2 | 2 / 2 | 0 | 0 | 5458 ms | 38.529 ms |
| 第 2 次 | 2 / 2 | 2 / 2 | 0 | 0 | 5583 ms | 49.256 ms |

两次都经历 640×360 → 1600×900 → 640×360 的 DPI 往返，以及
640×360 → 1280×720 → 640×360 的快速缩放；最终尺寸和 DPR 均恢复，播放持续推进，
无音视频停滞。当前测试机只完成 Flutter View 模拟 DPR 往返，未把它冒充为双显示器
物理移窗门禁；真实跨显示器复测仍需具备不同缩放比例的第二块屏幕。

## 验证与边界

- `flutter test`：471 项通过，3 项既有 benchmark 跳过。
- `flutter analyze`：零问题。
- `flutter build windows --debug`：成功。
- Windows 真实后端：三类 A/B 共 6 个会话、缩放门禁 2 个会话、899 dp 控制条和
  设置入口真实点击通过。
- schema、`FilterQuery`、`TagQueryService`、filtered queue、缩略图/media queue
  和用户数据均未改变。

## 下一步

稳定档位让 libmpv 可能真正承担 1920×1080 到较小 Texture 的缩小。下一任务应在
adaptive 默认路径重新运行 `dscale` / `correct-downscaling` A/B；只有最终窗口像素
确实变化、画质收益稳定且 GPU/显存门禁通过时，才重新讨论其生产默认。
