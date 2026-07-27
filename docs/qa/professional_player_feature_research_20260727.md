# 专业播放器画质与硬件能力调研

## 采用原则

Local Tag Player 不复制 PotPlayer/VLC 的全部功能，而是把专业播放器能力放在
`PlayerService` 后面，按“硬件证据、可回退、跨平台隔离、真实 A/B”逐项接入。
Windows 优先使用原生 libmpv/D3D11；macOS/Linux 继续保留 MediaKit，直到对应
平台有独立验证过的后端。

## 能力清单与顺序

| 能力 | 参考实现 | 本项目策略 | 状态 |
|---|---|---|---|
| NVIDIA RTX Super Resolution | mpv `d3d11vpp scaling-mode=nvidia` | 原生 D3D11VA 非 copy、驱动日志确认、掉帧回滚 | 已集成并通过六组 A/B |
| 低码率伪影修复 | NVIDIA RTX Video SDK Artifact Reduction | 本机插件、零分发 SDK、同设备 D3D11 纹理；许可通过后再发布 | 待 SDK 包内 EULA/ABI |
| SDR → HDR | RTX Video SDK 或 mpv/libplacebo tone mapping | 先区分显示器 HDR 信号与算法实际运行，禁止名称推断 | 已有保守 mpv 实验，SDK 待评估 |
| 普通帧同步插值 | mpv `video-sync=display-resample` + `interpolation` | 类型化档位、属性读回、掉帧回滚；不宣传为 AI 补帧 | 已接入，待多帧率长播 |
| 运动补帧 | VapourSynth/SVP/RIFE | 独立 Windows 插件；需要模型许可、延迟、音画同步和 24→60 长播门禁 | 高风险后续 |
| GLSL/libplacebo 着色器 | mpv `glsl-shaders` | 只安装许可明确、固定摘要的着色器包，提供顺序和一键回滚 | 下一阶段评估 |
| 去隔行 | mpv `d3d11vpp deint` | 仅对标记为隔行的内容自动启用，优先驱动自适应模式 | 中优先级 |
| ICC/色彩管理/HDR 输出 | mpv gpu-next/libplacebo | 提供自动/受管选项，保留输出范围与实际显示信号诊断 | 中优先级 |
| Intel Video Super Resolution | mpv `scaling-mode=intel` | 与 NVIDIA 使用同一类型化能力，不按显卡名称猜测 | 待 Intel 实机 |
| 跨平台硬解/渲染 | mpv hwdec、Vulkan/VideoToolbox | 平台后端各自实现，页面只消费 PlayerService | 架构已具备 |

## 从热门播放器学习的边界

- [mpv.net](https://github.com/mpvnet-player/mpv.net)证明 Windows 前端可以把
  libmpv 的缩放、色彩管理、帧时序、插值和 HDR 组织为用户可理解的能力；本项目
  学习其“薄 GUI + 完整 libmpv 能力”方向，不复制 .NET UI。
- [MPC-HC](https://github.com/clsid2/mpc-hc)把高级画质交给独立视频渲染器，
  说明解码、渲染和 UI 必须分层；本项目对应为
  `PlayerService → PlayerBackend → Windows renderer`。
- [media_kit](https://github.com/media-kit/media-kit)适合跨平台基础播放，但其
  Windows OpenGL/ANGLE Texture 边界无法提供本项目需要的非 copy D3D11VA；
  因此仅保留为通用后端，不再承担 Windows 专有增强。
- [mpv 官方手册](https://mpv.io/manual/master/)是滤镜、着色器、插值、HDR
  和硬解选项的唯一语义基线；第三方配置只作为交互灵感，不能替代官方行为验证。

## 下一步

1. 把 Windows 原生 libmpv 渲染器做成可持久化、可撤销的设置，并完成普通窗口
   鼠标、全屏、跨 DPI、快速切换、截图与退出门禁后再提升为 Windows 默认。
2. 对已接入的“关闭 / 显示同步插值”运行 24/25/30fps 到 60/120Hz 的长播 A/B；
   运动补帧插件另立 contract，继续明确区分 mpv 插值与 AI 生成中间帧。
3. 建立固定摘要的着色器包格式与许可清单，先评估 FSRCNNX/Anime4K 类缩放，
   不与 NVIDIA VSR 同时启用。
4. RTX Video SDK 继续沿用本机零分发插件路线；拿到正式包后实现 Artifact
   Reduction / Super Resolution / SDR→HDR，并保留非 NVIDIA 回退。
