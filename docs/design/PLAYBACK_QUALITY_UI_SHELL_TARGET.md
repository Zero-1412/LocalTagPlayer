# 视频画质与增强 UI 外壳 Before/After 目标

## 页面定位

这是设置中的视频画质与增强工作区。它承载画面比例、缩放、输出色彩范围、流畅度提升、
压缩画质增强、暗部细节和 HDR 转 SDR 等应用级播放偏好；设置页只提交类型化快照，具体
播放器能力、设备门槛、回滚和诊断仍由既有播放服务与播放器会话拥有。

## Before / After

| Before | After | 目的 |
| --- | --- | --- |
| 比例、缩放、色彩、流畅度、增强和能力状态全部包在通用 `Card` 中 | 收敛为带 Semantics 的“视频画质与增强工作区”实色 surface | 建立稳定的设置详情边界，减少卡片墙感 |
| 默认 Card 阴影承载整页层级 | 使用不透明深色 surface、弱描边、统一圆角和稳定挂载 key | 与播放基础设置共享 Calm Desktop Media Workspace 材质 |
| HDR 转 SDR 与流畅度插值确认混在普通控件流中 | 保留原控件顺序，并让确认/撤销继续位于同一工作区内 | 视觉收敛不削弱播放稳定性保护和即时反馈 |
| 只读能力状态行与可操作偏好没有明确工作区末端 | 保留两个能力状态行作为工作区末端的诊断摘要 | 区分已启用能力与用户可调整的播放偏好，避免伪开关 |

## 保护边界

- 保留 `settings.playbackQuality.card`、各项 `settings.playbackQuality.*` key、控件顺序、默认值、
  `onChanged` 回调和现有说明文案；新增 `settings.playbackQuality.workspaceSurface` 作为页面挂载锚点。
- HDR 转 SDR 开启仍必须经过原确认 Dialog；关闭仍直接保存关闭状态。
- 流畅度提升仍由原 `PlaybackSmoothMotionDropdown` 负责确认、设置提交、Snackbar 撤销和卸载期间的安全保护。
- 不在设置页启动解码、FFprobe、媒体库查询或播放器命令；不修改 `PlayerBackend`、播放会话、filtered
  playback queue、ThumbnailService、媒体详情/缓存队列、schema、stable identity 或用户数据。

## 验收条件

- 100%、125%、150% 文字缩放下，所有设置说明、确认入口、开关、能力状态和滚动区域完整可读。
- 实色 surface 与弱描边在 high contrast 下仍能表达边界；reduced motion 不新增移动或持续动画。
- HDR 转 SDR 确认/取消/关闭、流畅度提升确认/撤销、Dropdown、Switch、键盘 focus 和页面返回保持原语义。
- 设置首页 → 视频画质与增强 → 返回路径可达；focused、全量测试、analyze、Windows debug build 和
  真实窗口检查通过。
