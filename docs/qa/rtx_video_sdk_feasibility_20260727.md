# RTX Video SDK 接入可行性评估

日期：2026-07-27

## 结论

RTX Video SDK 在 Windows 与 RTX 20 系列及以上显卡上具备技术可行性，但当前不适合直接进入产品实现。现阶段只把既有入口明确标注为“GPU 高质量缩放（非 NVIDIA AI）”，继续使用 libmpv 的 `ewa_lanczossharp`、`lanczos`、sigmoid 与 resize-only 属性；不下载、不提交、不分发 NVIDIA SDK，也不修改 `PlayerBackend`。

正式立项前必须依次解除三个阻断：

1. 登录下载 RTX Video SDK 1.1，保存下载包摘要，并由发布负责人核对包内实际 EULA、第三方声明与公开 RTX SDK 家族许可是否一致。
2. 在隔离的 Windows 原生实验后端验证同一 D3D11 device/LUID 上的输入纹理、输出纹理、颜色格式、同步和释放；不能让 Dart 或 Flutter UI 逐帧搬运视频。
3. 在 NVIDIA、非 NVIDIA 独显和仅核显三类机器上验证能力探测、运行失败回退、掉帧与退出资源门禁，再决定是否增加独立的 RTX Video 设置。

## 官方能力边界

NVIDIA 当前公开的 [RTX Video SDK 1.1 页面](https://developer.nvidia.com/rtx-video-sdk/getting-started)列出 Super Resolution、Artifact Reduction 和 SDR→HDR，要求 64 位 Windows 10 及以上，支持 DX11、DX12、Vulkan、CUDA，GPU 门槛为 GeForce RTX 20 系列或 NVIDIA RTX 1000（Turing）及以上。页面还明确把低码率块状伪影和色带修复列为 Artifact Reduction 的目标。

这与项目需求相符，但只证明 SDK 能力，不证明 Local Tag Player 已接入。当前实现仅设置 libmpv 缩放属性，NVIDIA App 的工作状态也不能替代应用内 SDK 初始化和每帧执行证据。

## 许可评估

公开的 [NVIDIA RTX SDKs License](https://developer.nvidia.com/gameworks/nvidia_rtx_sdks_license_12apr2021.pdf)允许把 SDK 软件和材料以目标代码形式嵌入具有额外功能的应用分发，但同时要求：

- 不得把 SDK 作为独立产品分发；
- 分发条款至少同等保护 NVIDIA 的权利；
- 不得暗示 NVIDIA 赞助或背书；
- 不得让 SDK 受要求公开源码、允许衍生或免费再分发的开源许可证约束；
- 若下载包附带单独条款或第三方条款，以对应条款为准。

Local Tag Player 源码使用 MIT License。MIT 本身不会自动把外部二进制变成 MIT，但仓库根许可证的宽泛措辞容易让接收者误解 NVIDIA 组件也可自由再分发。因此，如果最终许可允许产品分发，SDK 二进制也必须：

- 不进入公开 MIT 源码仓库；
- 作为独立的专有第三方组件随 Windows 包安装；
- 在 `THIRD_PARTY_NOTICES`、安装包许可与卸载清单中明确排除于 MIT 授权之外；
- 只分发实际需要且包内许可明确允许的文件；
- 若实际下载包要求，在发布前完成 NVIDIA 产品通知或 Application ID 流程。

SDK 1.1 下载目前需要 NVIDIA 账户登录，公开页面没有展示下载包内的全部许可文件。因此本评估不是法律意见，也不能作为发布授权；“核对实际下载包 EULA”是硬阻断。

## D3D11 纹理接入

NVIDIA 的 [NGX Programming Guide](https://docs.nvidia.com/ngx/latest/programming-guide/)证明同类 NGX D3D11 路径需要应用提供 `ID3D11Device`、immediate `ID3D11DeviceContext` 和每帧 `ID3D11Resource`，并明确 API 非线程安全、特性可用性必须运行时查询。RTX Video SDK 1.1 的精确函数、格式和同步约束仍应以登录后包内头文件与样例为准，不能用旧 NGX 接口名称直接实现。

项目当前生产路径是 `MediaKitPlayerBackend -> media_kit/libmpv -> media_kit_video ANGLE D3D11 texture -> Flutter texture`。现有 `PlayerBackend.setProperty` 只能设置 mpv 属性，拿不到逐帧输入/输出纹理；`PlayerGpuRenderBoundary` 也只暴露活动 LUID 和 QA Compute 基线。因此 RTX Video 不能作为 Dart 层的另一个“属性开关”接入。

最小可行的原生插入点应满足：

```text
libmpv 解码/渲染
-> 同一活动 LUID 的 D3D11 输入纹理
-> RTX Video SDK 原生处理
-> D3D11 输出纹理
-> 既有 Flutter 外部纹理
```

建议只在隔离的 `WindowsNativePlayerBackend` 做原型，因为它显式拥有命令线程、`mpv_render_context`、ANGLE surface 和 D3D11 共享纹理。生产 MediaKit 路径隐藏了每帧纹理所有权；直接补丁修改上游插件会扩大构建期补丁、纹理竞态和升级维护风险。原型必须保持：

- SDK 初始化、特性创建、每帧执行和释放都由同一原生串行线程拥有；
- 设备必须与播放器当前活动 LUID 精确一致，禁止跨适配器隐式复制；
- 纹理尺寸或色彩格式变化时重建特性，失败先停用 SDK 再继续原播放器；
- 不在 UI isolate 复制 BGRA/RGB 帧，不通过方法通道逐帧传输；
- 退出顺序纳入既有纹理注销与原生资源释放门禁。

## 非 NVIDIA 回退

不要按显卡名称字符串决定可用性。运行时应依次探测：

1. Windows 平台和 SDK 运行库是否存在；
2. 当前播放器活动 D3D11 LUID 是否唯一匹配受支持的 NVIDIA 适配器；
3. SDK 初始化及目标特性可用性查询是否成功；
4. 输入尺寸、格式、输出尺寸和显存预算是否满足；
5. 当前会话健康采样是否允许继续运行。

任何一步失败都应无缝回到现有 libmpv GPU 高质量缩放；该路径仍不可用时再按既有 Lanczos/Bicubic 基线播放。回退只改变当前会话，不改写用户偏好，不重开媒体，不重排 filtered queue，也不触发媒体详情或缩略图任务。

未来若进入产品，设置模型不应复用当前 `videoSuperResolutionEnabled` 布尔值。建议新增独立提供者枚举，例如“关闭 / 可移植 GPU 缩放 / NVIDIA RTX Video”，并把“不支持、初始化失败、性能回滚”显示为会话状态，避免用户把持久化意图误认为 AI 已实际运行。

## 原型验收门槛

- 许可：下载包 EULA、二进制再分发、MIT 排除声明和 NVIDIA 产品通知全部确认。
- 正确性：D3D11 device/LUID、输入输出纹理、颜色范围、8/10-bit 与尺寸变化都有可复核日志。
- 画质：复用真人面部、动画渐变、暗场三类自然低码率 1080P，同帧比较关闭、libmpv 缩放、RTX Artifact Reduction/Super Resolution。
- 性能：每类至少 20 分钟，记录掉帧、音视频停滞、GPU committed、GPU Video/Compute、进程内存和退出残留。
- 回退：NVIDIA 不支持/初始化失败、AMD、Intel 核显与软件解码均继续播放，入口清楚说明实际提供者。
- 产品保护：SQLite、标签、`FilterQuery` / `TagQueryService`、filtered queue、缓存队列和用户数据完全不变。

## 本轮验证

- focused test 覆盖齿轮入口挂载、完整新文案、旧文案消失、开关回调，以及高质量缩放启停属性的串行与基线恢复，共 3 项通过。
- `flutter analyze` 无问题，`flutter build windows --debug` 成功。
- Windows 真实 Debug 产物路径经进程核对为 `E:\LocalTagPlayer\build\windows\x64\runner\Debug\local_tag_player.exe`；真实点击“媒体卡片 → 播放器 → 控制条 → 齿轮”后，新名称和说明完整可见。
- 长名称在窄齿轮面板内自然分为两行；72px 行高完整容纳名称和说明，右侧开关、相邻“压缩画质增强”、循环项与“更多播放设置”均无重叠、遮挡或溢出。
