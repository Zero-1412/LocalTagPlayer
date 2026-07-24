# media_kit_video 2.0.1 Windows 独立迁移实验

## 决策

本实验只存在于 `codex/media-kit-2-migration-experiment`。在合并前必须保留稳定纹理 descriptor 补丁；不能把 pubspec 升级等同于迁移完成。

上游 2.0.1 的 GPU 与软件纹理回调仍通过成员 `texture_id_` 查询 map。快速切换或销毁期间该 ID 可以变化，而 Flutter 回调生命周期可能晚于 native output 销毁。项目补丁改为在注册时捕获稳定 descriptor；output 销毁后回调返回空指针，map 记录保持到 `UnregisterTexture`。

参考：

- [media_kit_video 2.0.1](https://pub.dev/packages/media_kit_video/versions/2.0.1)
- [media_kit 原生事件观察 PR #1429](https://github.com/media-kit/media-kit/pull/1429)
- [Flutter 3.44 hotfixes](https://github.com/flutter/flutter/wiki/Hotfixes-to-the-Stable-Channel)
- [Windows 默认 Impeller 变更 #188140](https://github.com/flutter/flutter/pull/188140)
- [FFmpeg 8.1 filters](https://ffmpeg.org/ffmpeg-filters.html)

## Windows Profile 基线

环境保持 Flutter 3.44.4、Dart 3.12.2、Visual Studio 2022 17.13.6，不切换 SDK。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_player_real_library_stress.ps1 `
  -Profile -DurationSeconds 75 -Seed 20260724 -KeepRawArtifacts
```

结果：3 轮真实媒体打开、队列滚动、两次 seek、全屏往返、诊断与退出全部通过；1227 帧，build P95 1.863ms、raster P95 2.245ms、total P95 13.023ms、total max 189.551ms，超过 16.7ms 共 37 帧，超过 33.3ms 共 8 帧。三轮实际硬解均为 D3D11VA，解码掉帧、视频停滞、音频停滞均为 0。

该结果是未来 Flutter Windows 渲染、输入、VS 工具链或 Impeller 默认值变化的对照基线，不代表当前切换 Impeller。

## FFmpeg 8.1.2 缩略图 A/B

两份 H.264/yuv420p 样本分别为 1920×1080 与 3840×2160；每种路径先预热一次，再取 5 次中位数。输出宽度固定为 384，与产品缩略图口径一致。

| 样本 | 软件 | D3D11 硬解 + CPU 缩放 | D3D12 硬解 + GPU 缩放 |
|---|---:|---:|---:|
| 1080p | 326.651ms | 421.624ms | 468.339ms |
| 4K | 94.721ms | 280.603ms | 330.691ms |

当前设备上两样本均由软件路径胜出。`scale_d3d11` 还会在目标纹理创建阶段失败；D3D12 虽可成功输出，但初始化、上传/回读和单帧进程成本抵消了缩放收益。因此不修改缩略图正式路径，也不把 GPU 逻辑扩散到 FFprobe、媒体详情或播放器。
