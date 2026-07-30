# Local Tag Player 0.2.3

## 本次更新

- 正式播放器统一使用 MediaKit Texture 路径，并收紧媒体打开、属性应用、事件订阅和
  原生资源生命周期，减少切片、连续 seek 与快速缩放时的状态竞态。
- 900 dp 以下播放器控制区改为三层紧凑布局，保留文件定位、音量、播放控制、截图、
  设置、全屏和播放队列等全部既有入口。
- 小窗口播放队列从播放器右侧展开，不再使用位置不符的居中底部弹层；顶部重复队列
  入口已移除，底部控制条成为统一入口。
- MediaKit Texture 会根据视频 Widget 的物理目标选择稳定输出档位，并通过去抖、
  滞回、最小请求间隔、原生确认与超时保护限制 Texture 重建。
- 完成低码率缩小场景的 `dscale`、`correct-downscaling` 与 Flutter 合成采样 A/B。
  当前默认继续使用 `FilterQuality.low` 和 mpv `bilinear/no`，避免没有可见收益的
  GPU 与显存开销。
- 首次启动默认窗口调整为 1600×900，使常用播放器功能与右侧队列在主流桌面显示器上
  更完整地呈现；用户已经保存的窗口尺寸不会被覆盖。
- 完成渐进式展示层拆分与代码体积门禁，保留媒体库筛选、标签维护、filtered queue、
  Missing/Relink、缓存诊断和数据备份的原有所有权边界。

## 画质与稳定性验证

- 三类低码率片源的固定/自适应 Texture A/B 均为 0 掉帧、0 音视频停滞和
  0 未响应；自适应输出降低 GPU committed 占用，同时保持高视频区域相似度。
- 两轮 DPI 往返与快速缩放门禁均为 0 Texture 重建失败、0 掉帧，最终尺寸可恢复到
  初始稳定档位。
- `dscale=lanczos` 与 `correct-downscaling=yes` 在当前正式 Texture 架构下没有改变
  最终窗口像素，却会增加资源占用，因此未设为默认值。

## 数据安全

- 不修改 SQLite schema、标签来源、`FilterQuery` 或 `TagQueryService` 语义。
- 不修改 filtered queue 的来源、当前索引、返回媒体库状态或缓存队列语义。
- 安装与升级不会删除媒体库数据库、手动标签、收藏、播放记录或播放进度。

## 签名状态

本次公开包由 GitHub Actions Release 工作流构建。仓库尚未配置 Windows Authenticode
与 Apple Developer ID / notarization 凭据，因此 Windows 安装包未签名，macOS DMG
未公证。下载后请使用随附的 SHA-256 文件校验完整性。
