# 播放与解码设置 UI 外壳 Before/After 目标

## 页面定位

这是设置中的播放基础工作区。它负责承载恢复策略、正式渲染后端说明、解码器选择和当前
播放会话的流缓存开关；设置 controller、渲染器选择、解码器确认、缓存服务和播放会话
仍由各自的业务 owner 保持，不把播放器队列或解码行为搬进 UI 外壳。

## Before / After

| Before | After | 目的 |
| --- | --- | --- |
| 恢复策略、后端说明和解码器选择包在通用 `Card` 中 | 收敛为带 Semantics 的“播放与解码工作区”实色 surface | 让播放设置成为一个有明确边界的工作区，而不是卡片堆叠 |
| 流缓存开关作为另一个通用 `Card` 单独出现 | 收敛为“播放会话缓存工作区”实色 surface | 把影响当前播放会话的设置与基础解码设置区分开 |
| 页面主要依赖默认 Card 阴影和隐式分组 | 使用稳定挂载 key、弱描边、统一圆角和保留 Material 状态层 | 形成可截图、可聚焦、可维护的设置层级，同时保留键盘与 ink 反馈 |
| 控件顺序和历史 key 没有新的工作区语义 | 保留既有控件顺序、回调、值和历史 key，新增工作区 Semantics/key | 视觉重构不改变恢复、后端、解码器或缓存设置行为 |

## 保护边界

- 保留 `settings.resumeBehavior`、`settings.playback.card`、
  `settings.playbackQuality.streamCache` 和 `settings.playback.streamCache.card` 等既有 key、
  控件顺序、默认值、持久化回调和说明文案。
- `PlaybackSettingsController` / `CacheSettingsPage` 继续拥有设置保存、恢复策略、后端选择、
  解码器确认和缓存开关；UI 只改变展示外壳。
- 正式播放继续统一使用 MediaKit Texture；不挂载伪后端切换入口，不改变 Windows QA 后端边界、
  decoder confirmation、demux window 或播放设置迁移。
- 不修改 `PlayerBackend`、`PlaybackSession`、filtered playback queue、ThumbnailService、
  媒体详情/缓存队列、schema、stable identity 或用户数据。

## 验收条件

- 100%、125%、150% 文字缩放下，恢复策略、后端说明、解码器选择和缓存开关完整可读，页面滚动后
  仍能到达两个工作区。
- 实色 surface 与弱描边在 high contrast 下仍能表达边界；reduced motion 不新增移动或持续动画。
- Dropdown、ExpansionTile、Switch 和页面返回保留原有 focus、键盘、点击反馈与状态语义。
- 设置首页 → 播放与解码 → 返回路径可达；focused、全量测试、analyze、Windows debug build
  和真实窗口检查通过。
