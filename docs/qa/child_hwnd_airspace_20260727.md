# Flutter child HWND airspace 原型（2026-07-27）

## 结论

普通应用已通过鼠标、弹层、全屏、快速切换和退出门槛，但真实跨 DPI 仍缺少
多显示器物理证据，因此没有进入三类片源六组 A/B，也没有切换默认后端：

- Windows 固定 mpv 已升级为 `v0.41.0-908-g48e6c35c0`，可在正式
  `PlayerPage` 中使用
  `wid + gpu-next + d3d11 + d3d11va`。
- 真人面部、动画渐变、暗场三类低码率 1080P 均为
  `hwdec-current=d3d11va`、0 Flutter 纹理复制、0 总掉帧，播放头持续推进。
- 双层 child HWND 已把视频限制在左侧视频面板，右侧 filtered queue 和底部
  控制条可见；不再出现 mpv 重新配置 `wid` 后越过面板的问题。
- child HWND 使用 `HTTRANSPARENT/MA_NOACTIVATE`，普通应用中的真实鼠标
  齿轮、右键菜单、设置与诊断均可达。2026-07-28 后设置与右键菜单改为只裁剪
  实际覆盖矩形，矩形外实时视频保持可见；未知尺寸模态弹窗仍完整让出。
- `auto-safe` 用户设置不会再把实验会话覆盖为 copy 后端；Dart 与 runner 两层
  固定 `d3d11va`，普通应用诊断确认实际值为 `d3d11va`。
- 2560×1440 全屏、连续 PageDown 切换 1→2→3→4、返回 11164 项媒体库和关闭
  宿主均通过，退出日志记录 pause、Route pop、dispose 开始和结束。
- DPR 已加入几何同步去重，100%→150% focused test 会重新通知 runner；当前
  机器只枚举到一个 96 DPI 显示器，不能把合成测试冒充真实跨屏验证。

因此 `LOCAL_TAG_PLAYER_BACKEND=windows-native-hwnd` 继续只作为 QA 入口，
Windows 默认仍使用 MediaKit，macOS/Linux 完全不变。

## 边界设计

```text
PlayerPage / filtered queue / controls
                |
        WindowsNativePlayerBackend
                |
        Flutter view HWND
                |
      outer video host HWND
      - Flutter 几何
      - airspace 裁剪
      - 可见性
                |
       inner mpv HWND (`wid`)
      - gpu-next
      - D3D11
      - D3D11VA
```

外层 HWND 和内层 HWND 都只存在于显式 `hwnd` 模式。Flutter 发送逻辑画布
矩形与逻辑 view 尺寸，runner 使用实际 Flutter view 客户区计算物理矩形。
integration test 不能调用 `setSurfaceSize` 覆盖离屏画布，否则原生窗口客户区与
可见顶层窗口尺寸不一致。

mpv 可能在媒体加载时重配传入的 `wid`。因此不能把 Flutter 几何直接交给 mpv
窗口；外层宿主负责裁剪，mpv 只使用内部子窗口。child HWND 不再手工转发鼠标
消息：`WM_NCHITTEST` 返回 `HTTRANSPARENT`，`WM_MOUSEACTIVATE` 返回
`MA_NOACTIVATE`，由 Windows 把真实按键状态、双击和捕获语义直接交给 Flutter
view。弹层边界只控制外层 HWND 显隐。

## 验证结果

页面级结果位于：

```text
.local/qa/child-hwnd-airspace/multi-source/
```

| 样本 | `hwdec-current` | Flutter 纹理复制 | 总掉帧 | 播放头 |
|---|---|---:|---:|---:|
| 真人面部 | `d3d11va` | 0 | 0 | 3500 ms |
| 动画渐变 | `d3d11va` | 0 | 0 | 3416 ms |
| 暗场 | `d3d11va` | 0 | 0 | 3625 ms |

共同诊断：

```text
backend=windows-native-hwnd
current-vo=gpu-next-d3d11-child-hwnd
native-surface-kind=child-hwnd
native-surface-visible=true
native-input-forwarding=true
```

普通应用 QA profile 的真实窗口结果：

- 画面、黑边和底部控制条均限制在左侧视频面板；
- 右侧 filtered queue 保持 11164 项，连续切换后的索引、标题和画面一致；
- 物理左键可打开齿轮与“更多播放设置”，中央右键可打开视频信息/诊断菜单；
- 设置与上下文菜单显示时只裁剪实际覆盖矩形，矩形外实时视频继续显示；诊断等
  未知尺寸模态弹窗仍完整让出，关闭后恢复完整 region；
- 全屏客户区为 2560×1440，退出全屏后普通布局恢复；
- 普通 `auto-safe` profile 的诊断为“请求 `d3d11va-copy`、实际
  `d3d11va`”，证明 HWND 边界强制非 copy 已生效；
- 返回媒体库后视频 HWND 消失，关闭窗口后三个播放器释放时间点完整且进程退出。

当前唯一未完成的物理门禁是跨 DPI：系统只枚举到一个
`96×96 DPI / 1.00x` 显示器。focused test 已证明 DPR 改为 1.5 时即使逻辑
尺寸不变也会再次发送矩形，但仍需多 DPI 显示器实测。

## 固定依赖与回退

固定依赖来自 `zhongfly/mpv-winbuild` 2026-07-26 开发归档，版本
`v0.41.0-908-g48e6c35c0`。归档 SHA-256 为
`72b1b348458f632063ed92a967617a078dc05129635a1b929c61d121b0e3a802`，
bundle `libmpv-2.dll` SHA-256 为
`4955444addd87a6be28fd42a8a5508ec76630b406292d7d3e5c8a4ab2ae727b0`。
CMake 同时固定 mpv v0.41.0 GPL/LGPL 许可证来源；构建与 P/Invoke 版本读回通过。

没有修改：

- `PlayerBackend` contract；
- filtered queue 来源、内容、顺序和当前 index；
- SQLite schema、标签查询和用户数据；
- 缩略图/媒体详情队列；
- 本机视频增强插件 ABI；
- 默认 MediaKit 后端。

## 下一步门禁

在讨论 Windows 默认切换前必须完成：

1. 在至少两台不同 DPI 的真实显示器之间移动普通窗口，覆盖 100% / 125% /
   150% / 200%、最大化、全屏与恢复；
2. 补真实滚轮、seek 拖动、最小化和 Alt+Tab 长驻测试；
3. 上述通过后才重新运行真人面部、动画渐变、暗场三类片源六组 A/B；
4. A/B 仍需同时满足非 copy、0 异常掉帧、退出无残留和多片源观感稳定获益，
   才重新评估 Windows 默认后端。

上述全部通过前，不运行 NVIDIA filter 产品 A/B，也不把 Windows 默认后端从
MediaKit 切到原生 mpv。
