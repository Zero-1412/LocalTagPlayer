# MediaKit / MPV 用户选择与 NVIDIA 自动增强验证

> 2026-07-30：本文的后端选择与自动增强属于历史 QA 实验。正式播放路径统一为
> MediaKit Texture，不运行 NVIDIA 原生增强探测；child HWND 的 VSR/HDR 只保留显式
> QA 门禁，不能作为正式应用已激活 NVIDIA 增强的证据。

日期：2026-07-28

## 目标

1. 设置页让用户明确选择 MediaKit 或 MPV，不再展示隐藏的 automatic 策略。
2. 播放器强化按所选后端展示，且不删除镜像、压缩增强、循环和更多设置。
3. 删除 VSR/HDR 手动开关；MPV 会话在能力满足时自动请求 NVIDIA 增强。
4. 画质门禁显式区分播放器后端。

## 实现边界

- `PlayerRendererPreference.automatic` 仅保留为旧数据兼容值；设置页只生成
  `mediaKit` / `windowsLibmpv`。
- Windows + MPV + 硬件解码由组合根解析到 `WindowsNativePlayerBackend`
  child HWND 模式；选择 MediaKit 时保持 MediaKit。非 Windows 或关闭硬解时
  因没有对应原生实现而回退 MediaKit。
- 切换只保存下一播放器 Route 的偏好，不热拆当前 D3D11 设备或 child HWND。
- MPV 专属 GPU 高质量缩放按后端显隐；镜像和压缩画质增强仍可由两种后端使用。
- NVIDIA 自动策略不读取或修改 NVIDIA App 全局配置，也不分发 NVIDIA SDK
  文件。驱动 `active` 回读仍是运行时真值。

## 根因与修复

首次真实自动门禁中，NVIDIA adapter、D3D11、HDR 输出与 10-bit 条件均通过，
但原生后端没有导出媒体源宽高，策略只能得到 `source=nullxnull` 并保守关闭。

原生桥现在读取并固定导出：

```text
video-params/w
video-params/h
```

属性未就绪时归零，避免媒体快速切换时沿用上一条视频尺寸。Dart 后端只把这两个
固定字段加入白名单，没有开放任意 mpv 属性或日志。

## 设置页真实 Windows 交互

命令：

```powershell
$env:LOCAL_TAG_PLAYER_RENDERER_QA_OUTPUT='.local/qa/backend-choice-nvidia-auto/renderer-settings'
flutter test integration_test/player_renderer_settings_test.dart -d windows
```

结果：

- 当前下拉仅出现 `MediaKit 兼容渲染` 与 `MPV 容器渲染`。
- 从 MPV 选择 MediaKit 后出现确认弹窗，确认后内存设置更新为 MediaKit。
- MPV 说明显示 Flutter Texture、MPV 滤镜、GPU 高质量缩放和压缩画质增强；
  不再把显式 child HWND QA 路径的 NVIDIA VSR/HDR 结论套用到产品默认表面。
- MediaKit 说明显示跨平台兼容、镜像、压缩画质增强。
- 两张 1268×714 PNG 均无遮挡、溢出、文字截断或状态歧义：
  `.local/qa/backend-choice-nvidia-auto/renderer-settings/renderer-mpv.png`
  与 `renderer-mediakit.png`。

桌面 Computer Use 复核因检测到用户正在操作目标窗口而立即停止，未继续注入
鼠标；上述隔离 integration test 不读取或改写用户设置。

本文件后续的 NVIDIA 自动门禁结果属于
`LOCAL_TAG_PLAYER_BACKEND=windows-native-hwnd` 显式 QA 路径。默认
`MPV 容器渲染` 使用 `d3d11va-copy` 与 Flutter Texture，只承诺容器合成和 MPV
通用画质能力，不承诺 VSR/HDR 驱动激活。

## 三类低码率自动门禁

样本均为仓库 QA 生成的匿名 1920×1080、650 kbps 自然片源：

| 类别 | 自动决策 | VSR 驱动 | HDR 驱动 | 最大总掉帧 | 视频停滞 | 音频停滞 |
| --- | --- | --- | --- | ---: | ---: | ---: |
| 真人面部 | VSR + HDR | active | active | 0 | 0 | 0 |
| 动画渐变 | VSR + HDR | active | active | 0 | 0 | 0 |
| 暗场 | VSR + HDR | active | active | 0 | 0 | 0 |

三个会话均记录：

```text
source=1920x1080
vendor=4318
outputs=1
canVsr=true
canHdr=true
NVIDIA VSR 驱动确认: active
NVIDIA HDR 驱动确认: active
NVIDIA 自动回滚原因: 无
```

2026-07-27 已完成的三类六组 off/on A/B 仍提供同尺寸最终 Windows 表面与肉眼
结论；本轮重点是补齐源尺寸后验证正式自动路径，不把测试钩子当成产品入口。

## 门禁分流

`player_fixed_quality_baseline_test.dart` 的 JSON 报告新增：

```json
{
  "playerBackend": "mpv",
  "rendererPreference": "windowsLibmpv"
}
```

MediaKit 画质基线写 `playerBackend=mediaKit`。后续汇总必须按该字段分组，不能把
两个渲染边界的掉帧、HDR 或滤镜结论混在一起。

## 保护项

- schema：未改变。
- `FilterQuery` / `TagQueryService`：未改变。
- filtered queue / 当前 index / 返回状态：未改变。
- thumbnail / media queue：未改变。
- 用户数据：保留；切换具备确认与撤销，测试使用隔离内存设置。
- 获授权删除：仅 NVIDIA VSR/HDR 两个手动开关。
- 未授权功能删除：无；镜像、压缩画质增强、单曲循环、列表循环和更多设置均有
  回归证据。

## 最终验证

- `dart format`：任务 Dart 文件格式化完成。
- `flutter analyze`：通过，0 问题。
- `flutter test`：303 项通过，3 项按既有真实媒体库条件跳过。
- `flutter test integration_test/player_renderer_settings_test.dart -d windows`：
  通过，真实下拉、确认、切换和两张渲染边界截图完成。
- 三类 `nvidia-vsr-hdr-on` Windows integration：全部通过；最终复跑报告明确
  写入 `playerBackend=mpv`、`rendererPreference=windowsLibmpv`。
- `flutter build windows --debug`：通过。
- `tool/verify_windows_debug_package.ps1 -SkipBuild`：通过；正式 Debug 入口取得
  可见主窗口，标题为 `local_tag_player`。
