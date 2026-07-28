# Windows child HWND 生命周期与 D3D11VA 零拷贝边界验证

日期：2026-07-28

## 结论

本轮把两个此前混在一起的问题拆开验证：

1. child HWND / libmpv 会话的创建与释放没有复现可归因的生命周期崩溃；
2. `hwdec-current=d3d11va` 不等于解码表面“零 GPU 复制”，mpv 默认仍可能把
   解码表面复制到可采样纹理。

新增的 `LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA=1` 只在隔离测试中请求
`d3d11va-zero-copy=yes`。正式播放器默认仍为 `no`，因为 mpv 官方明确提示直接
采样解码表面可能出现边缘采样错误或驱动问题。

该开关也不等于 NVOFA 已取得解码纹理。当前 VapourSynth 插帧仍经过软件平面，
所以不能描述成全程 non-copy。

## 生命周期证据

### 跨进程

`player_hwnd_airspace_test.dart` 连续运行 8 次，每轮覆盖 child HWND 创建、
`gpu-next / D3D11VA` 真实出帧、Flutter 设置弹层显隐和页面释放。

```text
8 / 8 通过
Application Error = 0
孤儿 local_tag_player.exe = 0
```

摘要位于 `.local/qa/child-hwnd-lifecycle-pre/summary.json`。

### 同进程重复会话

`native_player_bridge_test.dart` 新增真实 HWND 回归，在同一个 runner 进程内重复
执行 `create → open → 出帧 → occlude/unocclude → dispose`：

```text
默认 D3D11VA：4 轮通过
默认 D3D11VA 生命周期基线：12 轮通过
d3d11va-zero-copy=yes：12 轮通过
零拷贝组奇数轮叠加“去块 + hqdn3d + unsharp”：通过
额外幂等 dispose：通过
Application Error = 0
```

测试同时要求 `native-texture-copies=0`、`frame-drop-count=0` 和
`d3d11va-zero-copy` 读回与请求一致。

原始 `0xc0000005` dump 的故障地址位于运行时生成代码区，调用栈已损坏，无法
归因到 `NativePlayerBridge`、libmpv 或 NVOFA。另一次
`flutter_windows.dll + 0x1d7d0` 崩溃来自外部强制终止测试进程，不作为正常退出
证据。没有证明生产原生释放次序存在缺陷，因此本轮没有凭猜测改动线程生命周期。

## 零拷贝术语校正

mpv 官方文档说明，使用 D3D11 硬解和 D3D11 GPU 后端时，默认会从解码表面做一次
GPU→GPU 复制；`d3d11va-zero-copy=yes` 才尝试直接采样解码图像。该选项可能减少
功耗，但也可能触发边缘 padding 或驱动问题：

- <https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst#L3689-L3692>

因此本项目后续区分三层：

```text
hwdec-current=d3d11va
  = 保留 D3D11 硬件帧，不下载成 CPU 解码帧

d3d11va-zero-copy=yes
  = mpv 尝试直接采样解码表面，避免其内部 GPU→GPU 复制

外部 NVOFA 获得 ID3D11Texture2D
  = 仍未建立，不能由前两项推断
```

现有压缩增强是软件 `vf`。它与零拷贝请求可以共存并继续播放，不代表滤镜内部没有
硬件帧下载/上传；本轮测试只证明没有拒绝、停播或新增输出掉帧。

## 三类片源六组复跑

扩展后的 `run_nvofa_motion_ab.ps1 -D3D11VaZeroCopyQa` 会在每组报告中要求
`d3d11va-zero-copy=yes`，并继续记录截图、24→48fps、掉帧、音视频停顿和 LUID。

本轮在进入六组播放器测试前，独立真实帧性能门禁连续两次失败：

```text
media 4.0 s / wall 4.30658 s / 新增掉帧 140
media 4.0 s / wall 4.16257 s / 新增掉帧 138
```

插件 SHA-256 仍为：

```text
aaea83ae158818755b1ea7846a7363f3b583c8a68f6c87f6c22ea5a0fc986f31
```

脚本按设计停止，没有生成或复用六组摘要。该结果阻止零拷贝 NVOFA 路线进入产品，
也不能用此前非零拷贝 A/B 的通过结果替代。

## 为什么当前边界拿不到 D3D11 解码纹理

| 边界 | 当前能拿到的内容 | 限制 |
| --- | --- | --- |
| libmpv `wid` / child HWND | mpv 自己拥有的 D3D11 VO 与 swapchain | 没有逐帧纹理回调 |
| libmpv render API | OpenGL（可由 ANGLE 模拟）或软件输出 | 公开 API 没有 D3D11 帧接口 |
| VapourSynth API R4 | `getReadPtr/getWritePtr` 软件平面 | 没有 D3D11 texture 类型 |
| 单帧插件 ABI v1 | ANGLE 路径的单个已渲染 D3D11 纹理 | 没有前后帧、时间戳和输出调度；child HWND 路径未接入 |
| FFmpeg `AV_PIX_FMT_D3D11` | `AVFrame/AVHWFramesContext` 所有的 D3D11 表面 | 该对象不通过公开 libmpv client/render API 暴露 |

依据：

- mpv 官方示例说明 render API 使用 OpenGL，原生 `wid` 则由 mpv 自己创建并绘制
  视频窗口：<https://github.com/mpv-player/mpv-examples/blob/master/libmpv/README.md#render-api>
- VapourSynth R4 的公开帧访问只有软件指针、stride、宽高与格式，没有 D3D11
  句柄：<https://github.com/vapoursynth/vapoursynth/blob/master/include/VapourSynth4.h#L1929-L1958>
- FFmpeg 的 D3D11 硬件帧类型是 `AV_PIX_FMT_D3D11`：
  <https://ffmpeg.org/doxygen/trunk/hwcontext__d3d11va_8c.html>

mpv 的 `display-swapchain` 只在 D3D11 composition 输出时返回 swapchain 地址，
但它没有提供 NVOFA 所需的“渲染前双帧 + 时间戳 + 提交中间帧”回调，不能把读取
swapchain 指针当成安全的时域处理接口。

## 下一步架构

优先做隔离的 mpv 内部 D3D11 硬件帧钩子原型，而不是继续调整 NVOFA 参数：

```text
PlayerBackend
  └─ WindowsNativePlayerBackend
       └─ patched libmpv QA build
            └─ D3D11 hwframe temporal hook
                 ├─ current / next ID3D11Texture2D + subresource
                 ├─ adapter LUID
                 ├─ source / target timestamps
                 └─ generated frame or deterministic fallback
```

门禁顺序：

1. 只统计连续 `AV_PIX_FMT_D3D11` 帧、subresource、LUID 和时间戳，不做插帧；
2. 证明 seek、快速切换、退出、VSR/HDR 以及无软件 `vf` 时不发生下载；
3. 再连接本机 NVOFA 插件并跑三类片源六组 A/B；
4. 若 mpv 内部钩子维护成本或许可不可接受，再在同一 `PlayerBackend` 后增加独立
   FFmpeg D3D11VA 后端；不能在 UI 或 `PlayerService` 暴露平台对象。

现有单帧插件 ABI v1、默认 MediaKit、filtered queue、SQLite、标签、缓存队列和
用户数据保持不变。
