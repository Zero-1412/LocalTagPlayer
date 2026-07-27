# Flutter child HWND airspace 原型（2026-07-27）

## 结论

原型只通过了“画面与非 copy 硬解”门槛，没有通过完整 airspace 产品门槛：

- 隔离 mpv `v0.41.0-744-g304426c39` 可在正式 `PlayerPage` 中使用
  `wid + gpu-next + d3d11 + d3d11va`。
- 真人面部、动画渐变、暗场三类低码率 1080P 均为
  `hwdec-current=d3d11va`、0 Flutter 纹理复制、0 总掉帧，播放头持续推进。
- 双层 child HWND 已把视频限制在左侧视频面板，右侧 filtered queue 和底部
  控制条可见；不再出现 mpv 重新配置 `wid` 后越过面板的问题。
- 项目固定 mpv 0.36 在同一路径中停在
  `hwdec-current=unavailable`，不能直接作为正式实现。
- 真实键盘播放/暂停可达，物理鼠标能触发 Flutter hover；但齿轮左键与视频中央
  右键尚未可靠打开设置/诊断弹层。逻辑 `tester.tap` 通过不能替代该证据。

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
窗口；外层宿主负责裁剪，mpv 只使用内部子窗口。鼠标消息从当前子窗口客户区直接
映射到 Flutter view，禁止逐层转换造成坐标重复偏移。

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

真实窗口使用 35 秒真人面部样本循环观察：

- 画面、黑边和底部控制条均限制在左侧视频面板；
- 右侧队列卡片、`1 / 1` 和筛选队列标题未被 HWND 覆盖；
- 键盘 Space 可以暂停/继续；
- 物理鼠标移动能让 Flutter 控制条和齿轮 hover 反馈出现；
- 显式物理左键未稳定打开齿轮设置，中央物理右键也未稳定打开诊断菜单。

最后两项是产品阻断，不以控件仍在 Widget 树或自动化逻辑点击成功替代。

## 固定依赖与回退

固定 mpv 0.36 的同路径没有打开媒体，`hwdec-current` 保持
`unavailable`。隔离 mpv 0.41 只由 `LOCAL_TAG_PLAYER_MPV_QA_DLL` 注入；
三类测试结束后重新执行无 QA 环境变量的 Windows Debug build，bundle
`libmpv-2.dll` 的 SHA-256 与 `ltp_native_deps/mpv` pinned DLL 一致。

没有修改：

- `PlayerBackend` contract；
- filtered queue 来源、内容、顺序和当前 index；
- SQLite schema、标签查询和用户数据；
- 缩略图/媒体详情队列；
- 本机视频增强插件 ABI；
- 默认 MediaKit 后端。

## 下一步门禁

在讨论 Windows 默认切换前必须完成：

1. 用普通应用 QA profile，而非 integration-test harness，复测真实左键、右键、
   滚轮、seek 拖动和焦点；
2. 设置/诊断/上下文菜单显示期间隐藏或裁剪 HWND，关闭弹层后恢复；
3. 100% / 125% / 150% / 200% DPI、跨屏、缩放、最大化与全屏；
4. 快速媒体切换、Route 返回、最小化、Alt+Tab 与宿主退出；
5. 决定正式 Windows mpv 版本并完成固定归档、许可和回退验证。

上述全部通过前，不运行 NVIDIA filter 产品 A/B，也不把 Windows 默认后端从
MediaKit 切到原生 mpv。
