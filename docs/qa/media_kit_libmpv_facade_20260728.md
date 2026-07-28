# MediaKit Texture + 同实例 libmpv 增强验证

## 结论

生产播放使用 `PlayerService -> MediaKitPlayerBackend -> media_kit_video Texture`。
常规命令走 media_kit API，高级画质属性写入该播放器已经持有的同一个
`NativePlayer`。自研 Windows MPV Texture/child HWND 不再是产品默认后端。

## 第一性原理

- 只有一个解码器、一个播放时钟、一个 Texture 和一个 mpv_handle。
- Flutter 弹层、侧栏、动画与控制栏继续由同一合成树处理。
- 标准 MPV 属性和滤镜不需要绕过 media_kit；原生 D3D11 纹理注入或 NVIDIA 专属
  能力才进入独立平台 QA 边界。

## 真实片源验证

运行：

```powershell
$env:LOCAL_TAG_PLAYER_MEDIA_KIT_SAMPLE='<本机匿名真实片源>'
flutter test integration_test/media_kit_libmpv_facade_test.dart -d windows --timeout 2m
```

结果：

- 正式 `buildVideoSurface` 已挂入 Widget 树，media_kit 返回有效 Texture ID。
- 播放位置超过 1 秒并在下一采样继续推进。
- `scale=lanczos` 与 `cscale=lanczos` 从同一 NativePlayer 读回。
- `hwdec-current` 为 D3D11VA 路径。
- 测试约 7 秒通过，先卸载 Video/Texture，再完成原生播放器释放。

首次试跑出现白色窗口，是测试只创建后端、未挂载 Video widget；它不能作为产品
白屏或播放失败证据。测试已增加可见视频表面与标题覆盖层，修正后通过。

## 回归结果

- `flutter analyze`：通过。
- `flutter test`：312 项通过，3 项按环境跳过。
- `flutter build windows --debug`：通过，并在 integration test 后重新构建正式
  `main.dart` 入口。
- 正式 Debug exe 启动后取得有效主窗口句柄，再按精确 PID 结束验证进程。
- Computer Use 只读检查被用户物理 Esc 中止，因此本轮没有把自动点击或新增截图
  冒充完成；可见视频集成测试与用户提供的首次白屏截图共同定位了测试挂载错误。

## 自研后端保留范围

Windows 自研桥接继续保留给显式 QA，并把固定 50ms 全属性轮询改成 wakeup callback、
观察属性与 128 个事件的限额批次。该路径可继续研究原生 D3D11/NVIDIA，但不得因为
存在实现就恢复为普通用户默认后端。

## 未改变

- SQLite schema 与用户数据
- `FilterQuery` / `TagQueryService`
- filtered queue 的来源、顺序与当前 index
- 缩略图和媒体详情队列
- 播放器快捷键、返回路径、侧栏与弹层功能
