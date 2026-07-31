# 新版 ANGLE 与 D3D11VA 渲染边界复核（2026-07-27）
>
> 状态：历史 QA/实验记录。当前门禁与优先级以 `docs/qa/`、`ROADMAP.md` 和 QA manifest 为准。

## 结论

- 新版 Google ANGLE 本身可以在当前 RTX 4070 SUPER 上完成
  `EGL ↔ D3D11 shared texture` 互操作。
- 但 MediaKit 的 `libmpv OpenGL render API → ANGLE → Flutter DXGI
  shared handle` 边界仍不能给解码器提供非 copy D3D11VA 硬件帧。
- mpv 0.36 和隔离 mpv 0.41 都出现同一结果：请求属性为
  `hwdec=d3d11va`、`gpu-hwdec-interop=d3d11va`，实际
  `hwdec-current=no`。
- 原生子 HWND 路径使用 mpv 0.41 的 `gpu-next + D3D11` 后，
  `hwdec-current=d3d11va`、解码/输出掉帧均为 0，证明显卡、驱动、
  mpv 和片源具备非 copy 能力；阻断位于当前 Flutter Texture / OpenGL
  render API 边界。
- 因 MediaKit 门禁失败，本轮没有运行三类片源六组 NVIDIA A/B，也没有调整
  `d3d11vpp`、`scaling-mode` 或其它画质滤镜。

## 隔离构建来源

| 项目 | 固定值 |
|---|---|
| ANGLE 官方仓库 | `https://chromium.googlesource.com/angle/angle/` |
| ANGLE 提交 | `c3ede28106e957254509e36fe94a838c761c77d0` |
| depot_tools 提交 | `571fb811a3a9e24afccbaf3191a2afaeeab17d78` |
| Chromium build 子仓库提交 | `ad76126f62c1a8f7b6a6285ca796e1dcf54a727a` |
| 构建目录 | `.local/qa/angle-interop/checkout/out/ReleaseD3D11` |
| 目标 | x64、Release、Clang、静态组件、仅 D3D11 |

`args.gn`：

```gn
is_debug=false
is_component_build=false
target_cpu="x64"
is_clang=true
angle_enable_d3d11=true
angle_enable_gl=false
angle_enable_vulkan=false
angle_enable_wgpu=false
angle_enable_null=false
angle_build_all=false
symbol_level=1
```

当前 ANGLE main 要求 Windows SDK 10.0.26100，本机只安装 10.0.22621。
为保持系统不变，隔离 checkout 的 Chromium `build` 子仓库仅作三处 QA
兼容补丁：

- `vs_toolchain.py`：SDK 改为 `10.0.22621.0`；
- `toolchain/win/setup_toolchain.py`：SDK 改为 `10.0.22621.0`；
- `config/win/BUILD.gn`：NTDDI 改为 SDK 22621 支持的
  `NTDDI_WIN10_NI`。

因此本轮产物应描述为“固定 ANGLE 新版源码 + SDK 22621 隔离兼容补丁”，
不能描述成未修改的官方发布包。Google ANGLE 没有适合直接升级依赖的稳定
GitHub Release；正式依赖仍保持固定旧包。

产物摘要：

| 文件 | SHA-256 |
|---|---|
| `libEGL.dll` | `7E336B4C67463910F5B6AFAB41B96DE2BB505198F08FAC1D06B6AF966AA09C9C` |
| `libGLESv2.dll` | `FF44067025024B6EB1C6238D765D93B1EFDF12A43593B4C97CB13B948D3C3BC0` |

## ANGLE 最小互操作探针

`tool/angle_d3d11_interop_probe.cpp` 不启动播放器，只验证：

1. 创建硬件 D3D11 设备和 BGRA shared texture；
2. 创建 ANGLE D3D11 EGL display；
3. 通过 `EGL_DEVICE_EXT` 读取 ANGLE D3D11 device；
4. 比较两个设备的 DXGI adapter LUID；
5. 用共享句柄创建 EGL pbuffer；
6. GLES clear 后由 D3D11 staging texture 读回像素。

结果：

```text
ANGLE_VENDOR=Google Inc. (NVIDIA)
ANGLE_EGL_VERSION=1.5 (ANGLE 2.1.1 git hash: c3ede28106e9)
EGL_INITIALIZED=1.5
D3D_FEATURE_LEVEL=0xb100
EGL_ANGLE_DEVICE_D3D=1
EGL_ANGLE_SHARED_TEXTURE=1
ADAPTER_LUID_MATCH=1
PIXEL_BGRA=191,127,32,255
RESULT=PASS
```

这只证明 ANGLE/D3D11 互操作存在，不能替代 libmpv 的
`hwdec-current` 证据。

## MediaKit / libmpv 门禁

构建脚本增加两个仅供 QA 的运行时入口：

- `LOCAL_TAG_PLAYER_ANGLE_QA_ROOT`：只替换隔离构建的 ANGLE DLL；
- `LOCAL_TAG_PLAYER_MPV_QA_DLL`：只替换隔离 mpv DLL。

`LOCAL_TAG_PLAYER_ANGLE_INTEROP_QA=1` 时，生成的 MediaKit Windows
源码会在 `mpv_render_context_create` 前请求 `hwdec=d3d11va` 与
`gpu-hwdec-interop=d3d11va`。没有环境变量时不写这些属性，正式固定依赖、
插件 ABI 和回退行为不变。

真人面部低码率 1080P 的两次 20 秒门禁：

| 运行时 | 请求 `hwdec` | 请求 interop | 实际 `hwdec-current` | 结论 |
|---|---|---|---|---|
| 固定 mpv 0.36 + 新 ANGLE | `d3d11va` | `d3d11va` | `no` | 失败 |
| mpv `v0.41.0-744-g304426c39` + 新 ANGLE | `d3d11va` | `d3d11va` | `no` | 失败 |

证据位于：

- `.local/qa/angle-interop/mediakit-mpv036-live-face-evidence/`
- `.local/qa/angle-interop/mediakit-mpv041-live-face-evidence/`

新版 DLL 的实际运行目录摘要与隔离产物一致。`gpu-api` /
`gpu-context` 在 libmpv render API 路径显示 `empty`；决定性失败证据仍是
已明确请求硬解后 `hwdec-current=no`。

## 原生 HWND / D3D11 探针

`tool/run_mpv_hwnd_d3d11_probe.ps1` 创建 WinForms 父窗口和专用子 HWND，
再以 `--wid` 让隔离 mpv 0.41 直接使用：

```text
vo=gpu-next
gpu-api=d3d11
gpu-context=d3d11
hwdec=d3d11va
```

最终结果：

```text
hwdec-current=d3d11va
current-vo=gpu-next
gpu-api=d3d11
gpu-context=d3d11
decoder-frame-drop-count=0
frame-drop-count=0
vo-configured=true
```

mpv 导出的已解码视频帧正常；`CopyFromScreen` 对 D3D 子窗口得到黑色客户区，
说明后续 Flutter 原型不能把普通桌面抓屏作为唯一可见性证据。结果和截图位于
`.local/qa/mpv-hwnd-d3d11/live-face-mpv041-final/`。

mpv 的固定 `render.h` 只公开 OpenGL 和软件 render API，同时明确可用 `wid`
嵌入原生窗口；因此当前仓库不能通过切换 `MPV_RENDER_API_TYPE_D3D11` 解决，
该类型在所用 API 中不存在。

## 原生 HWND 产品化评估

最小下一阶段只做实验后端，不替换默认 MediaKit：

1. runner 在 Flutter view 旁创建专用视频子 HWND；
2. 平台通道只接收物理像素矩形、可见性、DPI、全屏和销毁命令；
3. mpv 使用 `wid + gpu-next + D3D11`，继续由 Flutter 维护
   filtered queue、当前 index、播放命令和返回状态；
4. 先验证窗口边界，再讨论 NVIDIA filter 或 RTX Video SDK。

必须先解决的 Windows airspace 风险：

- 子 HWND 与 Flutter 控制条、设置弹层、右侧队列的 z-order；
- 100% / 125% / 150% / 200% DPI 和跨屏移动；
- 窗口缩放、最大化、全屏、最小化、Alt+Tab；
- 鼠标焦点、快捷键、拖动 seek 与窗口命中；
- 快速切换、Route 返回、宿主关闭时的 HWND/mpv 生命周期；
- 系统抓屏为黑时，播放器截图与自动化 QA 的替代证据。

若不能在不删除或遮挡现有控制条、设置、队列和返回行为的前提下通过这些门禁，
则 HWND 路径不进入产品。不要用“已经实现非 copy”作为牺牲既有 UI 可达性的理由。

## 当前决策

- 不升级正式 ANGLE：新版没有修复当前 MediaKit/libmpv 边界。
- 不开放 NVIDIA 实验：应用内仍没有非 copy D3D11VA。
- 不运行三类片源六组 NVIDIA A/B：前置门禁失败。
- 不继续调滤镜：下一项工作是隔离的 Flutter + child HWND airspace 原型。

参考：

- ANGLE 官方仓库与构建入口：<https://chromium.googlesource.com/angle/angle/>
- ANGLE 官方开发构建说明：
  <https://chromium.googlesource.com/angle/angle/+/main/doc/DevSetup.md>
