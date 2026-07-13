# Windows 原生播放器边界

## 当前状态

`NativePlayerBridge` 已提供以下稳定骨架：

- `local_tag_player/native_player` 方法通道。
- Flutter外部像素纹理注册、帧通知和注销。
- 单工作线程串行处理`open/play/pause/stop/seek/rate/volume/property/dispose`。
- 轻量状态快照与确定性命令确认。
- 显式环境开关`LOCAL_TAG_PLAYER_BACKEND=windows-native-stub`。

假后端只显示2×2棋盘格，用于验证纹理与生命周期，不执行真实媒体解码。默认路径仍为`MediaKitPlayerBackend`。

## libmpv与D3D11接入约束

真实实现不得直接引用本机Pub Cache或`build/windows`中的临时头文件和导入库。进入生产A/B前必须提供可重复构建的固定版本依赖：

```text
windows/native_player/third_party/libmpv/include
windows/native_player/third_party/libmpv/lib
windows/native_player/third_party/libmpv/bin
windows/native_player/third_party/angle/include
windows/native_player/third_party/angle/lib
windows/native_player/third_party/angle/bin
```

后续内部替换顺序：

1. 命令线程独占单个`mpv_handle`并处理事件。
2. 创建单个`mpv_render_context`，禁止页面或Dart直接持有句柄。
3. 通过ANGLE/D3D11共享纹理向Flutter提供GPU surface。
4. 纹理注销完成后释放render context，再终止mpv实例。
5. 原生层节流输出位置、缓冲、实际硬解、AV offset和掉帧指标。

默认后端只能在同媒体A/B满足退出无残留、视频/音频持续推进和资源不单调增长后切换。
