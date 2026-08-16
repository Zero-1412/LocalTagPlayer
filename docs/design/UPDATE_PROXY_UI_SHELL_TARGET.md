# 更新网络代理 UI 外壳 Before/After 目标

## 页面定位

这是“应用更新专用”的网络配置页，不是系统代理管理器，也不影响媒体播放、媒体库扫描、
FFmpeg 或其它用户数据链路。页面视觉要先让用户确认作用范围，再进入代理开关、地址和保存动作。

## Before / After

| Before | After | 目的 |
| --- | --- | --- |
| 单张通用 `Card` 包含所有内容 | 带稳定 Semantics 的“更新网络连接工作区”实色 surface | 与设置首页的导航分组形成清晰的当前详情边界 |
| 标题、范围说明和配置控件层级接近 | 保留标题与范围说明作为工作区首层上下文，配置控件按原顺序位于其后 | 先回答“代理影响什么”，再允许保存 |
| 控件直接依赖外层默认 Material | 由透明 `Material` 承接 `SwitchListTile`、`TextField` 和按钮 | 保留 focus、ink、键盘和禁用态反馈，不改变交互 |
| 状态文字作为普通尾部文本 | 状态保留原 key 和文案，并收敛为低干扰状态表面 | 让读取失败、保存中、保存成功和格式错误就地可辨识 |

## 保护边界

- 保留 `settings.updateProxy`、`settings.updateProxy.card`、开关、地址输入、保存按钮和 status key。
- `AppUpdateProxySettingsService` 仍是唯一读取/保存 owner；代理只作用于更新检查和安装包下载。
- 保留地址规范化、HTTP-only、拒绝账号密码、禁用态和保存中的锁定行为。
- 不修改系统代理、媒体播放、媒体库扫描、FFmpeg、筛选、播放队列、缓存队列、stable identity 或用户数据。
- 不新增连通性测试、网络请求、动画、blur 或保存前的额外副作用。

## 验收条件

- 100%、125%、150% 文字缩放下，范围说明、地址 helper、状态反馈和保存按钮完整可读。
- 实色 surface 与弱描边在 high contrast 下仍能表达边界；reduced motion 不新增移动或持续动画。
- 关闭代理时地址输入保持禁用；保存失败仍显示原始可理解错误；成功保存仍使用原状态文案。
- 设置首页 → 网络代理 → 返回路径可达；focused、全量测试、analyze、Windows debug build 和真实窗口检查通过。
