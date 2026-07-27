# PlayerService 显示同步插值验证

## 目标与边界

本轮只接入 mpv 普通显示同步插值，解决源帧率与显示刷新率不匹配时的规律性顿挫。
它使用相邻原始帧，不是 NVIDIA、SVP、RIFE 或其它 AI 生成中间帧。Windows 原生
libmpv 与 MediaKit 继续作为 `PlayerBackend` 同级实现，Flutter 页面不能取得
具体 Player、mpv handle、D3D11 纹理或 HWND。

## 实现

- `PlaybackSettings` 保存 `off/displayInterpolation`，旧文件默认关闭。
- 设置页启用前确认，保存后提供撤销；当前 Route 不热拆后端。
- `PlayerService` 按固定顺序写入
  `video-sync=display-resample → tscale=oversample → interpolation=yes`。
- 只有三个属性完整读回才报告配置已确认；逐帧运行态继续单独读取
  `display-sync-active`。失败立即先关闭 `interpolation`，再恢复基础同步参数，
  媒体打开不能被可选能力阻断。
- Windows runner 快照只返回固定的 `video-sync`、`interpolation`、`tscale` 和
  `display-sync-active`，不回传原生日志或媒体路径。
- 播放器沿用两秒健康采样；缓冲、掉帧、视频停滞或音频停滞只回滚当前媒体，
  全局偏好留到下一条媒体重新验证。

## 自动验证

- focused tests：旧设置迁移、持久化往返、属性写入顺序、读回失败回滚、确认、
  撤销及弹窗等待期间 Route 释放。
- Windows 原生 focused test：四个属性由 runner 快照到 Dart 后端可读。
- `flutter analyze`：通过，无问题。
- 全量测试：295 项通过，3 项显式真实媒体库基准跳过。
- Windows Debug C++ 构建：通过。
- 真实 Debug 窗口：依次点击“设置 → 视频画质与增强 → 流畅度提升”，入口默认
  关闭；启用前确认文案明确非 AI 生成帧，确认后档位与辅助说明同步更新并出现
  “撤销”，撤销后恢复关闭。截图检查未见位置错误、遮挡、溢出或对比度问题。

## 尚未完成的真实门禁

- 需要在 Windows 原生后端分别以 24/25/30fps 片源对 60/120Hz 显示运行长播
  关闭/开启 A/B，记录 `display-sync-active`、总/解码/输出掉帧、音视频停滞和
  主观规律性顿挫。
- 只有多帧率长播稳定后，才考虑把默认档从关闭调整为自动；运动补帧继续作为
  独立 Windows 插件评估，不能复用本档名称冒充。
