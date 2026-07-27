# Windows 播放渲染器偏好验证

## 目标

让普通 Windows 用户无需设置 `LOCAL_TAG_PLAYER_BACKEND`，即可在应用设置中
选择已经通过 NVIDIA A/B 的原生 libmpv/D3D11 后端，同时保留 MediaKit 回退。

## 用户入口

路径：

```text
设置
→ 播放与解码
→ 播放渲染器
```

档位：

- 自动（推荐）：当前版本继续选择 MediaKit，等待跨 DPI 长期门禁。
- MediaKit 兼容渲染：显式锁定跨平台兼容后端。
- Windows 增强（libmpv / D3D11）：下次进入播放器使用 child HWND 原生后端，
  可继续启用已验证的 NVIDIA RTX Super Resolution。

切换必须经过确认；保存后 Snackbar 提供“撤销”。当前播放器 Route 不热拆引擎，
避免在解码线程仍活动时销毁 D3D11 device 或 child HWND。

## 组合根规则

`resolvePlayerBackendSelection` 按以下顺序解析：

1. 非 Windows 始终使用 MediaKit。
2. Windows 的三个既有 QA 环境覆盖继续优先。
3. 用户选择 Windows 增强且硬解开启时使用 `windows-native-hwnd`。
4. 自动、MediaKit、硬解关闭和异常持久化值均回退 MediaKit。

页面只传递 `PlayerRendererPreference`，不能构造或取得具体后端。原生资源仍由
`PlayerService → PlayerBackend` 独占。

## 验证清单

- 旧设置无 `rendererPreference`：迁移为自动。
- 新值 JSON 往返：保留 Windows 增强。
- 平台/硬解/QA 覆盖解析：focused test 通过。
- 切换取消：不保存。
- 确认框等待期间设置控件被销毁：取消结果不再调用已销毁 `State.setState`。
- 确认切换：保存 Windows 增强并提示下次进入播放器生效。
- 撤销：只恢复渲染器字段；即使保存后已经退出设置子 Route，仍可从设置主页
  Snackbar 撤销，不会访问已销毁的下拉控件 `State`。
- filtered queue、SQLite、标签、缩略图与用户数据：未修改。

## 2026-07-27 真实窗口结果

- 使用本次 Debug 构建进入“设置 → 播放与解码”，三个渲染器档位、说明文本和
  切换确认框均可见，无溢出或遮挡。
- 选择 Windows 增强后从媒体库打开视频，UI Automation 识别到 mpv child HWND，
  证明持久化偏好无需环境变量即可到达原生后端。
- 首轮实测发现离开设置子 Route 后点击 Snackbar“撤销”会访问已销毁的
  `State.widget`；修复为保存时预先捕获持久化回调和恢复快照。
- 修复后再次实测：切为自动并退出设置子 Route，在设置主页点击“撤销”成功恢复
  Windows 增强；随后再次切换并保存为“自动（推荐）”，设置主页读回自动。
- 最终构建再次实点三个档位与切换确认框，取消后设置主页仍读回“自动（推荐）”。
- 最终保留用户安全默认“自动（推荐）”，未留下 Windows 增强测试偏好。

## 自动验证

- `flutter analyze`：通过，无问题。
- `flutter test`：290 项通过，3 项显式真实媒体库基准跳过。
- `flutter build windows --debug`：通过。
