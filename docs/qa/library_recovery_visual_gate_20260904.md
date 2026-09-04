# 媒体库恢复状态 Windows surface 门禁（2026-09-04）

## 结论与证据边界

Flutter 3.47 Windows Debug runner 中的四条生产组件路径均完成挂载、截图、Finder 点击和
回调断言。截图来自真实 Windows runner 的根 `RepaintBoundary`，覆盖实际 Flutter surface，
但不包含系统窗口边框，也不是 Win32 SendInput 鼠标证据。

原生 Computer Use 插件已按规定尝试并恢复一次：应用使用隔离 profile 正常启动且响应，但
插件返回 `apps: []`，运行时也没有文档声明的 `getApp` 方法。Flutter 自带
`IntegrationTestWidgetsFlutterBinding.takeScreenshot` 在 Windows 同样返回
`MissingPluginException(captureScreenshot)`。因此门禁明确使用 surface PNG，不把 Finder
点击冒充原生 UIA/SendInput 点击，也不宣称验证了系统目录选择器。

## 四条结果

| 状态 | 点击/断言 | PNG SHA-256 |
| --- | --- | --- |
| 首次空库 | “选择视频目录”回调恰好一次 | `6ec11dad2e471f4d78b3f41b806c1665417aa00129976dc6c5f9dea88bab6c63` |
| 筛选零结果 | “清除全部筛选”回调恰好一次 | `0ec0b59ed7da9393e7dd999b3c962fd1c745e0c3bf4805005afc525f8a3052c7` |
| 清理确认 | 打开生产确认框，点击“取消”，返回 false 且弹窗关闭 | `70009a2b72308aff135ac5ad7f2b5ad1497870add2a701a10be148c9e88c671b` |
| 启动失败 | 点击“重新加载”，失败页退出并进入 loading | `6e29017ca8053a54d63b14867afc6613125d0fbbd8fad97c16231cda03947de5` |

PNG 位于 ignored 目录 `.local/qa/library-recovery-surface-20260904-d/`，不包含用户媒体、
本机路径或真实 profile 数据。对应可重复门禁为
`integration_test/library_recovery_visual_gate_test.dart`。

## 视觉复核

- 四个状态使用同一深色媒体库画布，进入失败态不再闪到浅色页面。
- 标题、说明与图标对比清楚；空状态主要动作直接可见，次要动作没有抢占层级。
- 清理确认框明确列出标签、收藏、播放记录、进度、备份快照和磁盘文件边界；取消入口清晰。
- 未发现遮挡、裁切、溢出或需要增加动效的问题。

仍需在原生 Computer Use 暴露 App/Window2 接口后补：系统级鼠标点击、文件夹选择器打开/取消、
完整 Settings Route 背景和窗口边框截图。该缺口不影响本轮生产组件与 Windows surface 验收。
