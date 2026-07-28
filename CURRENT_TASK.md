# CURRENT_TASK.md

## 2026-07-28 全应用功能与动画对抗式压测

- 完整 307 项测试、静态分析和 Windows Debug build 通过；主窗口覆盖搜索、六种排序、
  标签父子选择、标签面板、网格/列表与设置五类子页，真实窗口完成 12 轮视图切换和
  30 次设置子页往返。
- MediaKit / MPV 各执行 6 次全屏往返、100 次快速视频切换和 120 秒长播；两后端
  停滞均为 0，最大掉帧分别为 0/2，队列、设置和 seek P95 均低于 23ms。
- 网格卡片补齐与列表一致的稳定播放语义；标签压力脚本改为每次点击前重新解析节点，
  并遵守标签选择后自动折叠的既有交互，不再复用 stale index。
- 真实 MPV 全屏发现原生 child HWND 会在 Flutter 提交顶栏卸载帧前切换尺寸，导致顶部
  摘要像素残留；全屏命令现在等待 `endOfFrame` 后再进入原生全屏，最终实窗的普通全屏
  和全屏队列稳定帧均无摘要残留。
- SQLite、`FilterQuery` / `TagQueryService`、filtered queue、缓存队列和用户数据未改。
  真实跨物理 125%/150%/200% DPI 与隔离媒体根中的破坏性操作仍是人工门禁。证据见
  `docs/qa/adversarial_full_app_stress_20260728.md`。

## 2026-07-28 MPV Texture 交互卡顿与色彩范围核验

- Windows 原生 Texture 的 Flutter 描述符读取不再等待 MPV 工作线程完成整帧绘制、
  D3D11 复制和插件处理；新增独立句柄/尺寸锁，只在 `SetSize` 与销毁时短暂同步。
- 播放进度拖动改为松手后只提交最终 seek；键盘连按在 80ms 尾随窗口内累计最新目标，
  不再把一串马上过期的位置逐项送入解码器。
- 宽屏播放列表继续保留原显隐动画和 filtered queue，列表子树增加重绘隔离；渲染器
  切换提示保留确认与撤销，并在 4 秒后自动收起。
- 同三类低码率片源的 Debug 前后矩阵：列表收放 P95 `47.311 → 14.719ms`，
  设置弹层 `52.285 → 21.391ms`，连续 seek `505.127 → 15.636ms`；raster P95
  从约 39ms 降到约 1.6ms，10 秒阶段停滞 0、最大总掉帧仍为 2。
- 用户同一 1920×1080/60 文件的运行时链为 `limited + BT.709 → output auto`；
  片源元数据与 mpv 标准自动映射一致，未加入会裁切高光的全局提亮。
- Computer Use 真实窗口复测在目标选择阶段被用户物理 Esc 中止；自动集成窗口、
  focused tests 和构建证据已完成，齿轮/列表/进度/全屏仍需下一次人工点击截图复核。

## 2026-07-28 默认 MPV 改为播放器容器 Texture 渲染

- Windows 用户选择 MPV 后，默认创建 libmpv Flutter Texture 表面；MediaKit 与 MPV
  现在只替换播放器容器内部的视频表面，不再把 child HWND 叠在整个 Flutter 页面上方。
- MPV Texture 在后端边界把 `d3d11va` 请求收敛为 `d3d11va-copy`，避免 ANGLE 无法
  消费非 copy D3D11VA 帧时静默回退软件解码；真实门禁已读回
  `hwdec-current=d3d11va-copy`。
- 播放列表收起/展开会立即重排视频表面；控制条、设置浮层和随机位置右键菜单均在同一
  Flutter 合成树中覆盖实时视频，不再依赖 HWND region 挖洞。
- 全屏右侧播放列表可见且可命中，画面同步缩放；删除已获授权的全屏顶部队列语境条，
  底部控制条继续作为浮层显示。
- `windows-native-hwnd` 环境覆盖仍保留为 NVIDIA VSR/HDR 与原生 D3D11 的显式 QA
  路径；默认 Texture 容器不宣称 NVIDIA VSR/HDR 已激活。
- 100%/125%/150%/200%/100% 模拟 DPI、6 次全屏往返、队列开合和短播门禁通过；
  本机只有一块 100% 缩放显示器，真实跨物理 DPI 继续保持
  `pending-physical-cross-dpi`。
- MediaKit 与 MPV 各 30 分钟长播均通过：播放推进分别为 561/561、562/562 个采样，
  停滞均为 0，最大总掉帧分别为 0 与 2（预算 5）；两后端 18 次快速切换、全屏、
  队列开合和模拟 DPI 均通过，实际硬解均为 `d3d11va-copy`。

## 2026-07-28 MPV HWND 单侧黑边、首入错位与右键暗框回归修复

- Windows MPV child HWND 始终保持与 Flutter 视频占位区相同的完整矩形；控制条显示时通过
  native region 让出底部 128 逻辑像素，隐藏后只保留 3 像素进度条，不再永久缩短视频窗口。
- runner 在应用 region 前先提交本轮 surface 几何，修复初次进入或快速切换视频时使用上一帧
  坐标造成的错位、重复条带。
- 右键菜单按视口剩余边距定位，并在路由挂载后重试测量真实菜单项边界；弹层只裁剪覆盖区，
  视频继续播放，不再出现纯黑暗框。
- Windows HWND 同步缓存纳入顶部和底部动态 airspace，确保控制条 128 → 3 的变化立即下发。
- 干净构建将 FFmpeg 固定到 BtbN 月末保留构建，版本仍为 8.1.2 LGPL shared，恢复可重复下载。
- focused tests、`flutter analyze`、Windows Debug build、真实低码率 1080P integration test 与
  Debug 真实窗口点击/截图均通过；MediaKit、filtered queue、SQLite、标签、缓存和用户数据未改。

## 2026-07-28 MPV 画面视口与 Flutter 弹层实时共存

- 普通窗口不再沿用全屏顶部 64 逻辑像素 airspace；MPV 自动比例视口增加该高度，
  保持完整画面且不改变“铺满”会等比裁边的既有语义。全屏顶部队列语境仍保留
  64 像素，底部控制条仍保留 128 像素。
- 设置与右键菜单不再隐藏整个 child HWND，也不使用截图或冻结帧。PlayerPage
  通过 `PlayerOverlaySurfaceBoundary` 发送弹层逻辑矩形，runner 使用
  `SetWindowRgn` 只从视频 HWND 中减去实际覆盖区域；矩形外视频继续实时播放。
- 设置面板在主页面、更多页面和内部选项切换时回报真实布局边界；右键菜单挂载后
  用两个菜单项的真实全局矩形收紧首帧估算。未知尺寸的模态弹窗继续完整让出，
  嵌套弹层用栈恢复上一层策略。
- 真人低码率 1080P 的 Windows integration test 验证设置/右键期间
  `native-surface-visible=true`、播放头推进、`d3d11va` 非 copy 与 0 Flutter
  纹理复制；真实 Debug 点击截图确认普通画面更大，主设置、更多设置和右键菜单
  无黑屏、遮挡、错位或队列穿透。
- `flutter analyze`、focused tests 与 Windows Debug build 通过。SQLite、
  `FilterQuery` / `TagQueryService`、filtered queue、MediaKit、缓存队列和用户
  数据未改变。证据见 `docs/qa/mpv_hwnd_overlay_region_20260728.md`。

## 2026-07-28 MediaKit / MPV 双后端稳定性矩阵

- 新增统一 Windows 稳定性矩阵：同一组匿名真实片源分别验证 MediaKit 与 MPV 的
  正式全屏状态机、DPI metrics、latest-request 快速切换和长播诊断，报告明确记录
  `playerBackend`，不再混用两个后端的结论。
- 快速切换门禁只通过 PlayerPage 正式队列跳转链发起请求；匿名快照验证 filtered
  source queue 的身份、顺序、当前 index 与最终打开项没有漂移，不包含本地路径。
- 默认发布门禁为每个后端长播 30 分钟、快速切换 18 次、总掉帧预算 5 帧。本机用
  真人面部、动画渐变、暗场三段 650 kbps 1080P 完成 15 秒短门禁：两后端四类自动
  场景均通过，5/5 长播采样推进、停滞 0、最大总掉帧 0。
- 本机只有单显示器，真实跨显示器 DPI 未执行，因此汇总发布状态保持
  `pending-physical-cross-dpi`；模拟 Flutter metrics 通过不能冒充真实跨屏通过。
- macOS/Linux 继续只允许 MediaKit。两平台若要开放 MPV，必须先分别实现各自原生
  `PlayerBackend` 并通过同类矩阵，Windows child HWND 不能作为其完成证据。
- 证据与运行方法见
  `docs/qa/player_backend_stability_matrix_20260728.md`。

## 2026-07-28 用户选择 MediaKit / MPV 与 NVIDIA 自动增强

- 设置页“播放”新增唯一的两态渲染器选择：`MediaKit 兼容渲染` 与
  `MPV 容器渲染`。高影响切换必须确认，只影响下一次进入播放器，并提供撤销；
  旧 `automatic` 设置迁移为 MPV，不再向用户显示平台自动选择。
- Windows 在用户选择 MPV 且硬件解码开启时创建 libmpv Flutter Texture
  后端；选择 MediaKit 时明确走兼容后端。非 Windows 或关闭硬解时仍安全回退
  MediaKit，因为当前没有对应的平台 MPV 实现，界面会解释该限制。
- 播放器齿轮已删除 NVIDIA VSR/HDR 两个手动开关。MPV 后端会在进入媒体后根据
  活动 NVIDIA 适配器、原生 D3D11 请求能力、源尺寸、显示分辨率、HDR 信号与
  10-bit 输出自动决定；这项结论现在只属于显式 `windows-native-hwnd` QA 路径，
  默认 Texture 不显示或宣称 NVIDIA VSR/HDR 已激活。
- 原生桥新增 `video-params/w` / `video-params/h` 固定快照，解决自动策略此前
  无法判断 1080P→4K 放大需求的问题；属性未就绪时归零，不沿用上一条视频。
- 真人面部、动画渐变、暗场三类 650 kbps 1080P 实测均自动请求 VSR+HDR，
  驱动回读均为 `active`，最大总掉帧 0、音视频停滞 0。设置页 Windows
  integration test 完成真实下拉、确认、状态切换和两张截图，未见遮挡、溢出或
  状态歧义。
- 画质门禁报告新增 `playerBackend` 与 `rendererPreference`，后续 MediaKit /
  MPV 结果分开统计。filtered queue、当前 index、返回状态、SQLite、标签、
  缓存队列和用户数据保持不变。证据见
  `docs/qa/player_backend_selection_nvidia_auto_20260728.md`。

## 2026-07-28 NVIDIA VSR/HDR 自动让路与激活判定

- 两个产品入口保留：固定 mpv 的 `d3d11vpp` 已能实际调用 NVIDIA VSR 与
  TrueHDR；NVIDIA App 显示“开、未激活”只表示当前没有满足触发条件或没有被其
  状态页识别，不能据此删除功能。
- 压缩画质增强或暗场增强不再让开关不可点击。开启 NVIDIA 时只在当前播放会话
  暂停冲突的 CPU `lavfi`，不改用户持久偏好；关闭、请求失败或性能回滚后归还
  滤镜所有权并重新采样。
- 不读取、不代改 NVIDIA App 的全局开关；产品以固定 mpv 日志归一化后的
  `NVIDIA VSR/HDR 驱动确认: active` 为真实运行证据。
- 真人面部、动画渐变、暗场三类真实低码率 1080P 联合验证均为 VSR/HDR
  `active`、最大总掉帧 0、音视频停滞 0、无自动回滚；关闭后的偏好恢复门禁也
  通过。证据见 `docs/qa/nvidia_auto_activation_20260728.md`。
- 一次 Windows integration test 在播放器构造早期出现现有的原生
  `0xc0000005` 启动抖动，同条件重跑和后续三组均通过；未把它归因于 NVIDIA
  滤镜，继续作为 child HWND 生命周期风险记录。

## 2026-07-28 Windows Debug 双击无窗口修复

- 已稳定复现：集成测试后的 Debug exe 进程存活且响应，但
  `MainWindowHandle=0`，应用事件中没有崩溃；经 `flutter run` 重建正式入口后
  同一路径立即产生可见窗口。
- 根因是 Windows integration test 复用
  `build/windows/x64/runner/Debug` 并留下测试入口；此前验证顺序为“正式 build
  → integration test”，导致最终交付目录不是正式 `main.dart`。
- 新增 `tool/verify_windows_debug_package.ps1`：交付前重新执行
  `flutter build windows --debug`，再按精确 PID 双击验证进程未退出且主窗口
  句柄非零，最后只关闭该 QA 进程。
- 产品启动代码、默认 MediaKit、Windows 增强后端、filtered queue、SQLite、
  标签、缓存队列和用户数据均未修改。
- `flutter analyze`、299 项全量测试（另 3 项按既有条件跳过）、最终 Windows
  Debug build 和 `-SkipBuild` 双击复验均通过；最终交付目录的主窗口标题为
  `local_tag_player`。

## 2026-07-28 NVIDIA 发布范围收敛与 VSR 日常开启结论

- 固定 mpv `v0.41.0-908-g48e6c35c0` 的 NVIDIA RTX 视频超分与 RTX Video HDR
  作为现阶段 Windows 可交付能力；界面移除“实验”文案，但两个能力继续默认关闭、
  仅会话保存，并保留硬件/源信号门禁、滤镜互斥、性能回滚和非 NVIDIA 回退。
- A/B 工具改为在固定第 12 秒通过进程绑定的
  `PrintWindow(PW_RENDERFULLCONTENT)` 捕获最终 Windows 表面，并强制 off/on
  同尺寸；此前不同时间、不同渲染尺寸的 `mpv screenshot video` 不再作为观感
  证据。
- 真人面部、动画渐变、暗场三类自然低码率 1080P 六组 20 秒 A/B 均为 0 总
  掉帧、0 音视频停滞且 VSR 开启组由驱动确认 active。肉眼结果是：真人/动画
  边缘有收益，但真人压缩纹理也会变硬；暗场收益很小。因此 VSR 保持默认关闭，
  仅建议在低码率画面偏软且被放大时按需开启。
- NVOFA 插帧降级为独立长期研究，不进入产品、不进入安装包、不再阻塞播放器
  发布。patched libmpv D3D11 hwframe 钩子与独立 FFmpeg 后端也不再由原任务
  自动继续；只有未来显式重启 NVOFA 研究时才重新评估。
- 默认 MediaKit、其他平台、插件 ABI v1、filtered queue、SQLite、标签、缓存
  队列和用户数据均未改变。证据见
  `docs/qa/nvidia_vsr_daily_ab_20260728.md`。
- `flutter analyze`、298 项全量测试（另 3 项按既有条件跳过）、Windows Debug
  build、PowerShell 语法和真实播放器齿轮点击/截图均通过；VSR/HDR 标题、说明、
  循环开关及“更多播放设置”无错位、遮挡或溢出。

## 2026-07-28 child HWND 生命周期与 D3D11VA 零拷贝边界

- 8 次独立进程 airspace 测试全部通过，Application Error 和孤儿进程均为 0；
  新增同进程真实 HWND 回归，默认 4/12 轮、零拷贝 12 轮以及幂等 dispose 均通过。
- 原始 `0xc0000005` dump 的故障地址在运行时生成代码区且栈已损坏，不能指向
  `NativePlayerBridge`、libmpv 或 NVOFA；没有证明原生缺陷，因此未修改生产
  销毁次序。
- `LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA=1` 才请求并读回
  `d3d11va-zero-copy=yes`。默认正式会话保持 `no`；压缩清晰增强 `vf` 交替挂载
  可继续出帧且输出掉帧为 0，但不代表软件滤镜内部没有下载/上传。
- 三类片源六组零拷贝 NVOFA A/B 在前置真实帧性能门禁连续产生 140/138 新增
  掉帧后停止，未生成可复用摘要；产品插帧入口继续关闭。
- 公开 libmpv render API 没有 D3D11 帧接口，VapourSynth R4 只提供软件平面；
  本节当时记录的 patched libmpv 下一步已被上方发布范围收敛取代，不再自动继续。
- 详细证据见
  `docs/qa/windows_hwnd_lifecycle_zero_copy_boundary_20260728.md`。

## 2026-07-28 NVOFA 遮挡有效性与两级补洞

- 参考 NVIDIA FRUC Programming Guide 的阶段顺序，把原先单段 Compute 扩展为
  三段 QA 管线：低分辨率 flow-grid 前后向校验与局部矢量补洞、逐平面中点 warp
  与遮挡有效性、只对低有效性像素执行的图像域 hole filling。它是仓库自研的开放
  近似实现，不下载、不链接也不冒充 NVIDIA FRUC SDK。
- 新增/扩展确定性 D3D11 探针，旧基线仍为 zero=128、motion=90、
  unreliable-side=117；单个坏光流格经矢量补洞恢复为 90，高反差显露边界经
  图像域补洞由中灰风险值修复为 201。三段任一步失败仍让整条 QA 滤镜回滚，
  没有 CPU 静默慢路径。
- 当前插件 SHA-256
  `aaea83ae158818755b1ea7846a7363f3b583c8a68f6c87f6c22ea5a0fc986f31`
  下，真人面部、动画渐变、暗场六组，以及快速横移、2px 细栅栏、固定字幕、
  运动模糊、重复切镜十组，均为 off/on 24/48fps、总掉帧 0/0、音视频停滞
  0/0，并命中 RTX 4070 SUPER LUID `00000000:00017093`。
- 固定奇数帧人工 A/B 未发现新增五官撕裂、动画翼缘暗边、暗场亮斑、细线断裂或
  字幕笔画漂移；切镜 off/on SSIM 为 0.999906，没有跨场景混合。运动模糊样本
  本身含五帧曝光，单帧不能证明产品级稳定收益，因此产品入口继续关闭。
- A/B schema 5 可由清单驱动匿名压力片源，明确区分“运行时门禁通过”和“产品
  可启用”。mpv 未提供 decoder/output 分项掉帧时保留 `null`，不再把不可用
  冒充 0；真实 `totalDroppedFrames=0` 仍是强制门禁。
- 连续压力首轮在尚未启用插件的 off 组出现一次 child HWND 原生宿主
  `0xc0000005` 启动崩溃；同条件最小复现与最终 16 组均通过，但该生命周期偶发
  问题仍阻止产品开放。下一步应做多轮启动/退出与快速切换 soak，并继续去除
  VapourSynth 软件帧、CUDA 光流回读和最终平面读回。
- 默认 MediaKit、Windows 后端选择、产品 UI、插件 ABI v1、filtered queue、
  SQLite、标签、缓存队列和用户数据均未改变；QA 插件、R78 与 NVIDIA 文件仍
  无 install、无 bundle。
- `flutter analyze`、297 项全量测试（另 3 项按既有条件跳过）、Windows Debug
  build、三段 D3D11/真实帧探针和 PowerShell 语法均通过；正式 Debug bundle
  48 个文件中未发现 NVOFA、CUDA、VapourSynth、VSScript 或 Optical Flow 文件。

## 2026-07-28 NVOFA cost 与前后向一致性保护

- NVOFA 会话现在显式请求前向/后向 `UINT8` cost，并把两侧 cost 与 S10.5 光流
  一起上传到同 LUID 的 D3D11 Compute。shader 在目标位置检查
  forward/backward residual 与硬件 cost，输出帧记录
  `LTPNVOFAConsistencyProtected=1`。
- 第一版“按置信度强选单侧 + 二次反推光流”虽然通过 24→48fps、零掉帧等技术
  门禁，却在动画翼缘产生肉眼可见的锯齿暗拖影，因此已被拒绝，没有进入提交。
- 最终实现保留已验证的中点取样，平均合成占 85%，一致性只允许把两侧比例限制
  在 42.5%–57.5%；确定性 D3D11 探针得到 zero=128、motion=90、
  unreliable-side=117。相对旧版动画截图 SSIM 为 0.9981、PSNR 为 57.68 dB，
  而被拒绝的强加权版本仅为 0.9943 / 40.44 dB，且肉眼回归明确。
- 最终三类 650 kbps 1080P、六组 20 秒 A/B 均为 off/on 24/48fps、总掉帧
  0/0、视频与音频停滞 0/0，并命中 RTX 4070 SUPER 的精确 LUID
  `00000000:00017093`；真人、动画和暗场开启截图人工复核均无新增明显伪影。
- QA 脚本只复用同时具备报告、完整截图和 `All tests passed!` 日志的单组证据，
  且记录的插件 SHA-256 必须等于当前二进制；最终六组都绑定
  `4b55e595947f7e77988e4c3bfcbc1c35064e4c041088b7aabc044777e6b588db`。
  失败、不完整或旧 hash 组仍强制执行。
- 这仍不是完整 FRUC：cost/一致性只能识别风险，尚无遮挡 mask、矢量补洞和
  图像域显露区域补洞。产品入口继续关闭，插件/R78/NVIDIA 文件仍不安装、不
  打包；下一步应在隔离 QA 链实现补洞并审查连续快速运动，而不是继续放大权重。

## 2026-07-28 NVOFA 同 LUID D3D11 Compute 合成

- Windows child HWND 初始化时通过 DXGI 1.6 高性能顺序选择可创建 D3D11
  Feature Level 11+ 的 NVIDIA 适配器；mpv 用唯一适配器描述设置
  `d3d11-adapter`，CUDA 再用 `cuDeviceGetLuid` 精确匹配同一个 LUID，不再固定
  CUDA device 0。多块同名 NVIDIA 卡会安全拒绝，可用环境变量显式选择 LUID。
- RTX 4070 SUPER 真机确认 mpv D3D11、CUDA/NVOFA 与新增 Compute 设备均为
  `00000000:00017093`；活动 GPU 诊断来源改为
  `windows-native-mpv-selected-d3d11-adapter`，不再借用尚未创建的 ANGLE 设备。
- 中间帧的双线性采样与双向融合已从 CPU `parallel_for` 迁移到 D3D11
  Compute Shader。输入软件平面、S10.5 双向光流和最终输出仍需上传/读回，因此
  准确边界是“同 GPU 硬件光流 + GPU warp”，不是全程 non-copy。
- D3D11 初始化、shader 编译、资源上传、dispatch 或读回任一步失败都会让
  VapourSynth 滤镜报错并触发现有会话回滚；没有静默 CPU 慢路径。
- 三类 650 kbps 1080P 的 4 秒门禁分别用时 3.996 / 3.998 / 3.995 秒，均完成
  24→48fps、seek、reload、`d3d11-warp=passed` 且窗口内无新增掉帧。
- 真人面部、动画渐变、暗场各 off/on 20 秒六组再次全部通过：off/on 为
  24/48fps、总掉帧 0/0、音视频停滞 0/0，六组均使用相同精确 LUID，六张截图
  均正常出画，进程退出生命周期完整。
- 插件、VapourSynth R78 与 NVIDIA 公开头文件仍为 `EXCLUDE_FROM_ALL` 本机
  QA 资产，没有 install 规则；产品入口、默认 MediaKit、Windows 后端选择、
  插件 ABI v1、filtered queue、SQLite、标签、缓存队列和用户数据均未改变。
- 下一阶段优先消除 VapourSynth 软件帧和光流回读，并加入前后向一致性、遮挡/
  显露区域处理与快速运动连续视频审查；未通过前不开放默认入口。

## 2026-07-28 NVOFA 2× 中间帧本机原型

- 新增显式 `EXCLUDE_FROM_ALL` 的 VapourSynth R78 插件目标。插件只从 System32
  动态加载 `nvcuda.dll` / `nvofapi64.dll`，使用已固定的 NVIDIA BSD-3-Clause
  公开头文件构建；没有 install 规则，也不进入正式 runner 或 Flutter bundle。
- 每个滤镜实例实际执行 A→B 与 B→A 两次 NVOFA Optical Flow，偶数帧保留源帧，
  奇数帧以双向 0.5 warp 合成；切场时复制前帧，禁止跨镜头混合。输出帧属性记录
  是否插值、切场和处理耗时。
- mpv 通过结构化 `vf` 的 `user-data` 传入唯一绝对插件 DLL；脚本显式注册
  VSScript output index 0，并把容器帧率约分后传给插件。24fps→48fps、精确 seek、
  同进程 reload 与关闭回退均通过。
- 初始单线程 CPU warp 在真实 1080P 上 7 秒只推进 3.52 秒并产生 97 个输出掉帧，
  因此未开放入口。按 16 行块并行后，三类 650 kbps 1080P 的 4 秒实时门禁用时
  3.998 / 4.016 / 4.010 秒，窗口内无新增掉帧。
- 真人面部、动画渐变、暗场各 off/on 20 秒六组均为 off 24fps、on 48fps，
  off/on 总掉帧 0/0、音视频停滞 0/0。12.020833 秒固定中间帧人工检查未见明显
  五官双影、动画轮廓撕裂或暗场污染；off/on PSNR 为 46.94 / 26.05 / 53.50 dB，
  证明不是同帧复制，但这些数值不是无真值条件下的质量评分。
- Windows 后端启停命令与状态快照存在不同平台消息时序；强类型边界现在最多等待
  2 秒读回 `requested/active`，仍不以命令发送成功冒充应用成功。
- 当前链仍为 D3D11VA→VapourSynth 软件帧→CUDA luma 上传→NVOFA→CPU warp，
  不属于非 copy D3D11 合成；未增加播放器 UI、持久化键或默认启用。下一阶段必须
  匹配活动 D3D11 LUID 并把 warp 迁到 D3D11 compute，再重跑六组与运动序列审查。
- 默认 MediaKit、Windows 后端选择、现有插件 ABI v1、filtered queue、当前
  index、返回状态、SQLite、标签、缓存队列和用户数据均未改变。
- `flutter analyze`、297 项全量测试（另 3 项按既有条件跳过）和 Windows Debug
  build 通过；正式 Debug bundle 未发现 NVOFA、CUDA、VapourSynth 或 VSScript
  文件，四个新增/扩展 QA 脚本均通过 PowerShell 语法解析。
- 完整证据见 `docs/qa/nvofa_vapoursynth_interpolation_20260728.md`。

## 2026-07-28 NVIDIA RTX Video HDR 驱动实链

- 固定 libmpv `v0.41.0-908-g48e6c35c0` 已确认包含
  `d3d11vpp=nvidia-true-hdr=yes`；通过 NVIDIA D3D11 驱动扩展执行，不下载、
  提交或分发 RTX Video SDK 文件。
- 能力快照分别建模 VSR 与 TrueHDR；HDR 入口只允许 Windows 原生 child HWND、
  非 copy `d3d11va`、固定实现版本、明确 SDR 源且无压缩/暗场 CPU 滤镜冲突。
- 齿轮一级保留原 VSR 稳定键并明确显示“NVIDIA RTX 视频超分（实验）”，新增
  `player.settings.nvidiaVideoHdrExperiment`。两个开关会话级、默认关闭。
- VSR/HDR 由一次完整 `vf` 原子应用；联合开启使用
  `d3d11vpp=scale=2:scaling-mode=nvidia:nvidia-true-hdr=yes`，不强制 NV12。
  新组合被拒绝时恢复之前已确认组合；运行压力复用既有 NVIDIA 回滚。
- 原生桥只匹配固定成功/失败/已是 HDR 文本，返回
  `inactive/requested/active/rejected/ignored-source-hdr`，不泄漏原始 verbose
  日志；同时返回源 primaries/gamma 供 SDR/HDR 门禁。
- 真人面部、动画渐变、暗场各 off/on 20 秒六组均为驱动 `active`、0 总掉帧、
  0 视频/音频停滞；滤镜均无 `format=nv12`。播放期间 DXGI 报告 3840×2160、
  10-bit、PQ/BT.2020、HDR 信号活动；峰值亮度元数据为 0.0 nits，仍不可用于
  显示器亮度校准结论。
- 真实 Debug 点击后的 Flutter 合成层截图确认两个 NVIDIA 入口可达，TrueHDR
  开启态、三行说明、锚点、边界和对比度正常。自定义 runner 未注册系统级
  `captureScreenshot`，因此未把该替代截图描述成 Windows Graphics Capture。
- 默认 MediaKit、渲染器选择、filtered queue、当前 index、返回状态、插件 ABI
  v1、SQLite、标签、缓存队列和用户数据均未改变。
- 完整证据见 `docs/qa/mpv_nvidia_true_hdr_20260728.md`。

## 2026-07-28 NVOFA CUDA 真实硬件执行门禁

- 固定 NVIDIA 官方公开头文件提交
  `edb50da3cf849840d680249aa6dbef248ebce2ca`；QA 脚本按两个原始文件的
  SHA-256 下载到被忽略的 `build` 目录，不提交、不安装、不打包厂商头文件。
- 新增隔离 `ltp_nvofa_cuda_execute_probe`：只从 System32 加载 `nvcuda.dll`
  与 `nvofapi64.dll`，动态建立 CUDA context、NVOFA API 2.0 session 和
  CUdeviceptr 缓冲区，上传两帧水平位移灰度图并实际调用 `nvOFExecute`。
- RTX 4070 SUPER / NVIDIA 595.97 上 Debug 与 Release 均通过；驱动最大 API
  5.0，输出 grid 4、320×192，回读 3840 个非零 S10.5 光流向量。
- 探针目标为 `EXCLUDE_FROM_ALL` 且没有 install 规则；标准应用没有新增 CUDA
  Toolkit、NVIDIA SDK、DLL 或启动时 GPU 会话依赖。
- 该结果只证明硬件光流 primitive 可执行，不表示 FRUC 已生成中间帧，也不表示
  RTX Video SDK 的 VSR、Artifact Reduction 或 SDR→HDR 已接入；现有产品入口
  与能力快照不冒充 active。
- 架构门禁测试覆盖固定提交、摘要校验、System32 加载、真实 execute/非零向量及
  零分发 CMake 约束。
- `flutter analyze`、297 项全量测试（另 3 项按既有条件跳过）与 Windows Debug
  build 通过；Debug bundle 复核没有 NVOFA、CUDA 或 NVIDIA SDK 文件。
- 默认 MediaKit、Windows 后端选择、filtered queue、当前 index、返回状态、
  插件 ABI v1、SQLite、标签、缓存队列和用户数据均未改变。
- 完整证据见 `docs/qa/nvofa_cuda_execute_20260728.md`。

## 2026-07-28 VapourSynth R78 真实帧与 NVOFA 驱动门禁

- 官方 `VapourSynth64-Portable-R78.zip` 已按 GitHub Release 摘要
  `8f12c2436aba6f596cde88d779f923a0bd454899b4bde1dd111b7ebbd8d7c3e3`
  下载并隔离安装到被忽略的 `build` 目录；未修改系统 PATH、注册表或应用包。
- R78 报告 Core R78 / API R4.2；固定 libmpv 的真实帧探针向透传脚本送入
  320×180、24 fps、144 帧 H.264 样本，Debug/Release 均通过实际帧推进、
  精确 seek、同进程 reload，并确认透传帧率不会被标记为插帧 active。
- 新增独立 NVOFA 系统驱动探针和 runner 只读快照。宿主只以
  `LOAD_LIBRARY_SEARCH_SYSTEM32` 加载 `nvofapi64.dll`；本机返回 API 5.0，
  D3D11、D3D12、CUDA、Vulkan 入口均存在。
- `PlayerMotionInterpolationCapability` 只增加驱动状态、API 版本和 D3D11
  可用性；驱动 API 可用不等于 FRUC SDK/插件已接入，也不等于 RTX Video SDK
  的 VSR、伪影消除或 HDR 已完成。
- 两个 QA 目标均为独立 `EXCLUDE_FROM_ALL` 目标，没有 install 规则；正式 runner
  只包含无厂商头文件依赖的系统驱动门禁，不包含 VapourSynth、Python 或 NVIDIA
  SDK 文件。
- NVIDIA Optical Flow SDK 与 RTX Video SDK 下载均要求 NVIDIA 开发者账户/
  许可流程；本轮没有代替用户登录或接受许可，也没有提交或分发厂商文件。
- `flutter analyze`、297 项全量测试（另 3 项按既有条件跳过）与 Windows Debug
  build 通过；真实工作区 Debug 窗口以 `windows-native-hwnd` 进入首个媒体并
  正常出画，Escape 返回 11239 项媒体库，原生 stop/dispose/released 在 57 ms
  内完成，最终进程正常退出。
- 默认 MediaKit、Windows 后端选择、filtered queue、当前 index、返回状态、
  插件 ABI、SQLite、标签、缓存队列和用户数据均未改变。
- 完整证据见 `docs/qa/vapoursynth_r78_real_frames_nvofa_20260728.md`。

## 2026-07-28 Windows 本机运动补偿插帧运行时边界

- 固定 libmpv `v0.41.0-908-g48e6c35c0` 的运行日志确认
  `-Dvapoursynth=enabled`，未知滤镜会被拒绝而 `vapoursynth` 可解析；实际送入
  320×180 H.264 帧后确定当前应用包缺少 `VSScript.dll`，因此此前只有滤镜入口，
  没有完整插帧运行链。
- 新增 `PlayerMotionInterpolationBoundary`。`PlayerService` 只传递强类型能力和
  布尔启停意图；路径、DLL、Python、mpv handle 与第三方日志留在 Windows 原生层。
- runner 只接受两个绝对路径环境变量，安全预加载并校验 `VSScript.dll`；
  `MPV_FORMAT_NODE` 结构化滤镜保留现有去块、降噪、锐化/NVIDIA 图，只替换
  `ltp-motion-interpolation` 标签。脚本/运行时/滤镜失败自动移除并继续原视频。
- `requested` 不冒充真实插帧；只有滤镜标签仍存在且 `estimated-vf-fps` 至少达到
  `container-fps` 的 1.5 倍才进入 `active`。
- 新增不安装、不分发的假 VSScript 宿主探针；本机结果为
  `structured-vf=passed preserve-existing=passed remove=passed`
  `active-revocation=passed reload=passed`。
- `flutter analyze`、297 项全量测试（另 3 项跳过）和 Windows Debug build 通过；
  真实启动工作区 Debug exe 后媒体库正常加载 11239 个视频，“设置 → 返回”点击链
  正常，默认未配置外部运行时没有启动崩溃、遮挡、溢出或错位。
- QA 探针目标标记为 `EXCLUDE_FROM_ALL` 且没有 install 规则；标准 runner 目录确认
  不含假 `VSScript.dll`。
- 本节当时记录的 R78 下载阻断已由上方“R78 真实帧与 NVOFA 驱动门禁”解除；
  NVIDIA NVOFA FRUC SDK 仍需开发者账户和许可确认，尚未下载、提交或分发厂商
  文件。
- filtered queue、当前 index、返回媒体库状态、插件 ABI v1、SQLite、标签、缓存
  队列和用户数据均未改变。
- 验证记录见 `docs/qa/vapoursynth_motion_runtime_20260728.md`。

## 2026-07-27 PlayerService 显示同步插值边界

- 播放设置新增“流畅度提升：关闭 / 显示同步插值”，旧设置缺字段时安全关闭；
  启用前说明这不是 NVIDIA 或其它 AI 生成中间帧，并提供跨 Route 撤销。
- `PlayerPage` 只传递 `PlayerSmoothMotionMode`；`PlayerService` 统一配置
  `display-resample / oversample / interpolation`，不让页面持有 mpv 字符串协议。
- Windows 原生桥补齐四个固定属性读回；只有 `video-sync`、`tscale` 和
  `interpolation` 全部符合预期才标记为配置已确认，逐帧运行态单独展示
  `display-sync-active`；能力不足时关闭插值并继续播放。
- 复用既有两秒健康采样和掉帧/缓冲/停滞熔断；运行期压力只回滚当前媒体，下一条
  媒体仍按用户偏好重新验证，不修改全局设置。
- filtered queue、当前 index、返回媒体库状态、MediaKit/Windows 后端选择、
  插件 ABI、SQLite、缓存队列和用户数据均不改变。
- `flutter analyze`、295 项全量测试与 Windows Debug build 通过；真实 Debug
  窗口已点击“设置 → 视频画质与增强 → 流畅度提升”，确认弹窗、状态文案和撤销
  均可达，最终设置恢复为“关闭”。
- 验证记录见 `docs/qa/player_smooth_motion_20260727.md`。

## 2026-07-27 Windows 播放渲染器用户入口

- `PlaybackSettings` 新增类型化 `rendererPreference`，旧设置缺字段时迁移为
  `automatic`；可选“自动（推荐）/ MediaKit 兼容渲染 / Windows 增强
  （libmpv / D3D11）”。
- 设置首页直接显示当前渲染器，播放与解码页的切换必须确认，保存后提供撤销；
  当前播放不热拆引擎，下次进入播放器 Route 时生效；Snackbar 撤销不依赖已销毁
  的设置控件，退出设置子 Route 后仍可恢复原值。
- 组合根通过 `resolvePlayerBackendSelection` 选择具体后端。Windows 增强使用已
  通过 NVIDIA 六组 A/B 的 child HWND 路径；非 Windows、硬解关闭或异常配置
  安全回退 MediaKit，既有 `LOCAL_TAG_PLAYER_BACKEND` QA 覆盖继续优先。
- 页面仍只传递用户偏好给 `PlayerServiceFactory`，不接触 MediaKit、libmpv、
  HWND 或 D3D11 类型；filtered queue、当前索引、返回状态、SQLite、缓存队列
  和用户数据不变。
- `flutter analyze`、290 项全量测试与 Windows Debug build 通过；真实窗口确认
  持久化 Windows 增强可打开 mpv child HWND，跨 Route 撤销可用，最终偏好已
  恢复为“自动（推荐）”。
- 验证记录见 `docs/qa/windows_renderer_preference_20260727.md`。

## 2026-07-27 Windows 原生 libmpv NVIDIA RTX Super Resolution

- 原生 child HWND 后端现可读取 `mpv-version`、完整 `vf` 与归一化的
  `native-nvidia-vsr-state`；只匹配 mpv verbose 的固定 NVIDIA 成功文本，
  不把可能包含媒体路径的原始日志交给 Flutter。
- `d3d11va → d3d11vpp scaling-mode=nvidia → gpu-next/D3D11` 已在 RTX 4070
  SUPER 上通过真人面部、动画渐变、暗场各关闭/开启 20 秒 A/B；六组均为
  0 掉帧、0 音视频停滞、无回滚，开启组全部由驱动确认 `active`。
- 原生后端补齐滤镜后临时截图；12 张证据帧已生成，开启帧为 3840×2160 并带
  驱动 `RTX VSR` 标记。产品滤镜门禁已开放，但仍只允许 Windows 原生 D3D11
  child HWND、非 copy D3D11VA 且无 CPU `lavfi` 冲突的会话启用。
- 默认 Windows 后端仍未切换；下一步先增加可持久化、可撤销的渲染器选择，并
  完成普通窗口鼠标、跨 DPI 与退出门禁，再决定是否提升为默认。
- 完整记录见 `docs/qa/mpv_nvidia_native_d3d11_20260727.md` 与
  `docs/qa/professional_player_feature_research_20260727.md`。

## 2026-07-27 PlayerService 播放器应用层边界

- 播放器依赖方向改为
  `Flutter PlayerPage → PlayerService → PlayerBackend → MediaKit / Windows libmpv`。
  `LibraryPage` 与 `PlayerPage` 只接收 `PlayerServiceFactory`，具体后端只在组合根
  选择并由服务独占。
- 新增 `PlayerRuntimeAccess`，让自动画质、GPU 检测、HDR、NVIDIA 门禁和内存诊断
  只消费必要的运行时属性；页面不能取得 MediaKit Player、VideoController、
  mpv handle、D3D11 纹理或 HWND。
- `PlayerService` 统一代理播放命令、状态流、视频表面、截图、显卡能力和 child HWND
  弹层显隐，并接管每次 open 前后的类型化比例、缩放、输出范围、HDR 与倍速恢复。
- 默认后端仍为 MediaKit；`windows-native-mpv`、`windows-native-hwnd` 和 stub
  仍只由显式 QA 环境变量启用。filtered queue、当前索引、返回媒体库状态、设置键、
  插件 ABI、SQLite、缓存队列和用户数据均未改变。
- `flutter analyze`、287 项全量测试与 Windows Debug build 已通过；真实窗口复测
  因已打开的安装版检测到用户持续输入而按保护规则中止，未把安装版结果冒充本次
  Debug 证据。仍需人工复测“媒体库卡片 → 播放器 → 齿轮 → 返回媒体库”。

## 2026-07-27 Flutter child HWND airspace 原型

- 新增显式 `LOCAL_TAG_PLAYER_BACKEND=windows-native-hwnd`；默认 Windows
  MediaKit、macOS/Linux 后端选择、`PlayerBackend` contract 均不改变。
- runner 创建双层 child HWND：外层按 Flutter 逻辑矩形和实际 view 客户区换算
  几何并裁剪，内层交给 libmpv `wid + gpu-next + d3d11 + d3d11va`；不注册
  Flutter Texture，诊断中的纹理复制数保持 0。
- Windows 固定依赖已从 mpv 0.36 升级到 `v0.41.0-908-g48e6c35c0`；
  CMake 固定 2026-07-26 归档、SHA-256 和 mpv v0.41.0 许可证，Debug bundle
  已读回同一版本。
- child HWND 对 Flutter view 使用 `HTTRANSPARENT/MA_NOACTIVATE`，真实左键、
  右键、控制条和快捷键均由 Flutter 接收；设置、更多设置、上下文菜单和诊断
  弹层打开前隐藏外层 HWND，关闭后按最后矩形恢复。
- 通用 `auto-safe` 仍保留给默认 MediaKit；显式 HWND 实验在 Dart 与 runner
  两层固定 `d3d11va`，普通应用诊断已确认实际为非 copy `d3d11va`。
- 普通应用完成全屏 2560×1440、连续 PageDown 切换 1→2→3→4、返回媒体库和
  宿主退出；filtered queue 仍为 11164 项，当前索引、标题和画面同步，退出日志
  包含 pause/pop/dispose 完整确认。
- 跨 DPI 修复把 device pixel ratio 纳入矩形去重，逻辑尺寸不变时也会请求
  runner 按新客户区重算物理矩形；focused test 覆盖 100%→150%。当前机器只
  枚举到一个 96 DPI 显示器，真实跨屏门禁仍未完成。
- 因真实跨 DPI 尚无物理证据，三类片源六组 A/B 未重新运行，Windows 默认后端
  继续 MediaKit，NVIDIA filter 继续禁用。完整记录见
  `docs/qa/child_hwnd_airspace_20260727.md`。

## 2026-07-27 新版 ANGLE 与原生 HWND/D3D11 边界复核

- 固定 ANGLE 提交 `c3ede28106e957254509e36fe94a838c761c77d0` 已在
  `.local/qa` 隔离构建；EGL/D3D11 shared texture、ANGLE device、
  adapter LUID 和像素读回探针全部通过。
- 新 ANGLE 分别配合正式 mpv 0.36 与隔离 mpv 0.41 进入 MediaKit 后，
  `hwdec=d3d11va` 和 `gpu-hwdec-interop=d3d11va` 请求值均存在，实际仍为
  `hwdec-current=no`。因此不运行三类片源六组 NVIDIA A/B，不调整滤镜。
- 独立子 HWND + mpv 0.41 的 `gpu-next/D3D11` 路径得到
  `hwdec-current=d3d11va`、0 解码/输出掉帧和正常导出帧，证明阻断位于当前
  Flutter Texture / OpenGL render API 边界。
- 正式 ANGLE/mpv 依赖、MediaKit 插件 ABI、默认回退均未改变；新增入口只接受
  显式 QA 环境变量。
- 下一步只做 Flutter child HWND 的矩形、DPI、z-order、控制条/设置/队列
  airspace 与生命周期原型。完整证据见
  `docs/qa/angle_d3d11_interop_20260727.md`。

## 2026-07-27 播放设置收纳、D3D11VA 边界复核与依赖审计

- 播放器齿轮一级只保留 NVIDIA 实验、循环方式和“更多播放设置”；镜像画面、
  GPU 高质量缩放（非 NVIDIA AI）与压缩画质增强已移入更多页，原键、回调、
  持久化和压缩三档返回路径不变。
- MediaKit Windows 只以 OpenGL render API 接入 libmpv，再经旧 ANGLE 输出
  D3D11 共享纹理；显式提前选择 `gpu-hwdec-interop=d3d11va` 对正式 0.36 和
  隔离 0.41 均无效，实际仍为 `hwdec-current=no`，实验补丁已撤回。
- 非 copy 硬门槛未解决，因此三类片源六组 NVIDIA A/B 没有继续运行，也没有
  调整滤镜参数。下一步只评估隔离升级 ANGLE 或新的 Windows 渲染边界。
- 依赖审计确认 Flutter stable、MediaKit 1.2.6、media_kit_video 2.0.1 与多数
  直接包已是当前版本；mpv 后续已固定升级到 0.41.0 系列。`file_picker` 11、
  `package_info_plus` 10、`flutter_lints` 6 均需独立主版本升级，不在本次混入。
- 完整审计见 `docs/qa/dependency_audit_20260727.md`；纹理证据更新在
  `docs/qa/mpv_nvidia_scaling_isolated_20260727.md`。
- 两项 focused widget test、`flutter analyze`、Windows Debug build 通过；
  1268×714 真实 Windows 集成进程从齿轮点击进入更多页并完成 71 秒播放，截图中
  长 GPU 名称自然换行，三个迁移项及相邻比例/倍速/滑杆无遮挡、截断或溢出。

## 2026-07-27 mpv NVIDIA scaling-mode 隔离升级结果

- 独立 `mpv v0.41.0-744-g304426c39` 已证明 D3D11VA、NVIDIA scaling mode 和驱动 RTX Super Resolution 日志成立。
- NVIDIA `d3d11vpp` 与现有 CPU `lavfi` 不能安全串联；直接串联会静默停用压缩滤镜，显式下载又会让放大后的 4K 帧回到 CPU。
- 同一新版 DLL 进入 MediaKit 后，请求 `d3d11va` 的实际值为 `hwdec-current=no`；真人面部第一条开启组即未通过非 copy 硬门槛，因此按规则终止动画渐变与暗场开启组。
- 正式 Windows 包已恢复固定 mpv 0.36.0。代码只预置互斥 `vf` 所有权、读回确认和掉帧回滚；`filterChainValidated=false`，不会真正写入 NVIDIA filter。
- 可复跑工具为 `tool/run_nvidia_scaling_ab.ps1`，完整证据见 `docs/qa/mpv_nvidia_scaling_isolated_20260727.md`。

## 2026-07-27 内嵌 mpv NVIDIA scaling-mode 实验门禁

- Windows 构建继续固定 `media-kit/libmpv-win32-video-build` 2023-09-24 的 mpv 0.36.0；对 Debug bundle 的 `libmpv-2.dll` 做二进制字符串检查，确认包含 `d3d11vpp`，但不包含 `scaling-mode`、NVIDIA RTX Super Resolution 文案或相关扩展 GUID。
- 播放器齿轮新增会话级“NVIDIA 视频增强（实验）”开关，当前明确显示“mpv 0.36.0：有 d3d11vpp；无 NVIDIA scaling-mode”并禁用；不会把 D3D11 解码/渲染误报为 NVIDIA AI 已工作。
- 能力检测优先读取后端 `mpv-version`，不可用时回退项目固定依赖版本；即使本机替换为 mpv 0.39+，在 `d3d11va` 纹理输入、现有 `vf` 链共存和性能回滚完成验证前仍不开放点击。
- 本轮未写入 `d3d11vpp=scale=2:scaling-mode=nvidia`，未升级 libmpv，未修改或调用本机视频增强插件 ABI，也未新增 NVIDIA 文件、持久化设置、解码器变化或 SDK 分发。
- focused 能力/设置/页面挂载测试、`flutter analyze` 与 Windows Debug build 通过；真实 1248×714 Debug 窗口点击媒体卡片、齿轮及禁用开关，入口文案完整、状态不变，相邻设置可达且无溢出、遮挡或错位。

## 2026-07-27 SDK 零分发本机视频增强插件原型

- 实验性 Windows 原生 mpv 后端新增 SDK 中立 ABI v1；只从 `LOCAL_TAG_PLAYER_VIDEO_PLUGIN_PATH` 指定的绝对路径加载可信本机 DLL，不扫描、不安装、不分发插件或 NVIDIA 文件。
- mpv/ANGLE 在原生工作线程完成共享 D3D11 纹理复制后调用插件；宿主先保留同设备原帧备份，插件返回错误时恢复原帧、记录回退并停用当前插件会话，播放继续。
- 默认 MediaKit、`LOCAL_TAG_PLAYER_BACKEND` 显式门禁、`PlayerBackend` contract、filtered queue、缓存队列、SQLite 与用户数据均保持不变。
- QA-only 往返探针和宿主自测没有 install 规则；真实结果为 `round-trip=passed fallback=passed`，标准 Debug bundle 未发现探针、NVIDIA SDK 或同名厂商文件。
- 播放诊断增加插件状态、名称、处理帧、回退数和错误码。隔离低码率 1080P 真实 Windows 页面分别通过正常与第 30 帧故障注入：齿轮、右键诊断均可达，状态为 `active` / `process-failed`，回退后播放头继续推进且总掉帧为 0；截图位于 `.local/qa/local-video-plugin/`。

## 2026-07-27 GPU 高质量缩放命名与 RTX Video SDK 评估

- 播放器齿轮和播放诊断把既有 libmpv 能力明确标注为“GPU 高质量缩放（非 NVIDIA AI）”；设置键、默认值、持久化、mpv 属性和性能回滚不变。
- RTX Video SDK 1.1 公开能力覆盖 DX11、超分、伪影修复和 SDR→HDR，但下载需要 NVIDIA 登录；下载包内实际 EULA、目标代码再分发与 MIT 排除声明是发布前硬阻断。
- 当前 `PlayerBackend.setProperty` 和 `PlayerGpuRenderBoundary` 不暴露逐帧 D3D11 纹理；未来原型只能在实验性 Windows 原生后端复用活动 device/LUID，任何失败无缝回到现有 libmpv 缩放。
- 完整评估见 `docs/qa/rtx_video_sdk_feasibility_20260727.md`；本轮不下载、不提交、不分发 SDK，不改变 filtered queue、缓存队列或用户数据。
- focused test 3/3、`flutter analyze` 与 Windows Debug build 通过；真实 Debug 窗口完成媒体卡片、播放器、控制条和齿轮可达性点击，长名称完整换行且无溢出或遮挡。

## 2026-07-27 三类自然低码率片源 A/B 与 NVIDIA 状态核查

- `Tears of Steel` 真人面部/暗场与 `Sintel` 动画渐变均以 CC BY 3.0 开放片源隔离压制为低码率 1080P；关闭/清晰增强共六轮真实 Windows 播放均为 0 掉帧、0 音视频停滞。
- 清晰增强对动画渐变最有价值，对面部与暗场保持克制；QA-only 额外 0.18 后锐化只改善部分动画轮廓，却让面部压缩纹理和暗场噪点变硬，未达到三类一致获益，GLSL 继续不加入。
- 本机 NVIDIA App 的视频页显示超分辨率关闭、HDR 禁用；播放器虽精确使用 RTX 4070 SUPER 的 `d3d11va-copy`，当前“GPU 画质超分”仍是 libmpv `ewa_lanczossharp`，未接 RTX Video SDK，因此不能宣称 NVIDIA AI 增强已工作。
- 可复跑工具为 `tool/run_natural_compression_quality_ab.ps1`，完整证据与限制见 `docs/qa/player_natural_compression_ab_20260727.md`；未修改正式播放器、filtered queue、PlayerBackend contract、缓存队列或用户数据。

## 2026-07-27 压缩画质增强三档与低码率 1080P A/B

- 播放器齿轮和全局播放画质页统一提供“关闭 / 自动 / 清晰增强”；旧布尔设置安全迁移为关闭或自动，不改变解码器、超分、HDR、暗部增强或 filtered queue。
- 自动档继续沿用现有基线和性能回滚；清晰增强只请求当前分辨率/解码路径允许的最高安全档，检测到掉帧、缓冲或停滞时仍按原规则立即降级。
- 既有去块、时空降噪与轻锐化链路增加保守 mpv GPU 去色带：`iterations=1`、`threshold=24`、`range=12`、`grain=8`；关闭或性能回滚到最低档时同步停用。
- 450 kbps、1920×1080、30fps 固定运动样本完成关闭/清晰增强各 20 秒 Windows 实机基线，两档均为 0 掉帧、0 视频/音频卡顿；同一 12 秒暂停帧的窗口截图位于 `.local/qa/compression-quality-ab/`。
- 局部 A/B 显示增强主要改善棋盘格边缘和轻微压缩波动，未出现明显光晕；现有 `unsharp` 已提供足够清晰度，因此本轮不加入缩放后 GLSL 锐化，后续只在更多真实片源证明收益稳定时复议。

## 2026-07-25 GitHub Actions Node.js 24

- 正式包与跨平台工作流使用的 checkout、artifact 和 GitHub Release 动作已升级到 Node.js 24 版本；不改变构建、签名、公证或发布门禁。
- YAML 语法、Node.js 24 Action 引用和无公开发布的手动正式包流水线均已验证；Debug 门禁、Windows 安装器与 macOS DMG 全部通过且无 Node.js 20 注释。

> 本文件只保存当前活跃任务、最近稳定基线、已确认阻塞和下一步入口。已完成的详细记录进入 `CHANGELOG.md` 与对应 Chat 文档。

## 活跃任务：远程开发分支收口

### 2026-07-25 应用内更新与关于页面

- 应用版本提升为 `0.2.2+4`。Windows 更新安装器在播放器内下载到临时 `.part`，校验 GitHub SHA-256 后才启动；失败文件不会执行。
- 设置首页新增关于入口，展示版本/构建号、正式版渠道和主动检查结果；启动静默检查与 Release 页面降级路径保留。
- focused 更新测试、设置入口测试、276 项全量测试、`flutter analyze` 与 Windows Debug build 已通过（3 项显式 benchmark 按设计跳过）。
- 真实 Windows 窗口已点击“设置 → 关于 → 检查更新”，确认版本 `0.2.2 (4)`、最新正式版反馈、品牌名、位置、对齐、对比度和状态反馈均正常，无遮挡或溢出；待完成独立只读复核。

### 2026-07-25 0.2.1 正式构建

- 应用版本提升为 `0.2.1+3`，正式安装包版本为 `0.2.1`。
- 远程开发分支已全部收口到 `origin/master`，发布提交必须继续保持与远程主线一致。
- GitHub 未配置 Windows/macOS 签名凭据，本次按显式门禁发布未签名、未公证构建，并在 Release 正文和 SHA-256 校验文件中明确交付边界。
- 本地 272 项测试、`flutter analyze`、Windows Debug/Release build 与 Release 进程 10 秒存活响应检查通过；3 项显式真实媒体库 benchmark 按设计跳过。

- 自动清理分支的生产代码已由主线等价实现，通过保留主线内容的祖先合并记录其集成关系，不回退远程更新、发布门禁或新文档。
- `media_kit_video 2.0.1` 实验迁移正在合入主线；继续固定归档 SHA256，并保留 Windows 构建期稳定 GPU/软件 descriptor 补丁与架构合同。
- FFmpeg 8.1.2 缩略图 A/B 仅作为可复跑 QA 工具保留，既有软件缩略图正式路径不变。
- 完整测试、静态分析、Windows Debug 构建与真实启动通过后合入 `master`，再删除两个已处理远程分支并复跑正式打包门禁。

## 活跃任务

### 2026-07-24 正式打包分支集成门禁

- 正式打包前刷新并检查全部远程分支；正常合并、rebase 或 cherry-pick 后的补丁等价均可通过，任何仍有独有提交的分支都会阻断打包。
- 未集成分支只在隔离临时 Worktree 中累计试合并，以发现单分支或分支间冲突；临时合并结果不会直接成为正式包。
- 待打包提交必须与 `origin/master` 当前提交一致；分支门禁通过后继续执行全量测试、静态分析、Windows Debug 构建与 10 秒启动存活检查。
- 当前远程 `codex/auto-remove-missing-unreadable-clean` 与主线存在 `ARCHITECTURE.md` 合并冲突，`codex/media-kit-2-migration-experiment` 也仍有独有提交，因此正式打包会按设计被阻断，远程分支均保留。

### 2026-07-24 远程正式版更新

- 应用版本已提升为 `0.2.0+2`。
- 正式包首帧后异步检查 GitHub 最新正式 Release；发现更高版本时弹窗展示更新内容，并优先打开 Windows x64 安装器。
- 更新网络失败不会阻塞媒体库；SQLite、标签语义、filtered queue、PlayerBackend、缩略图和用户数据保持不变。
- GitHub 仓库当前未配置 Windows/Apple 签名 Secrets；签名/公证标签工作流在凭据补齐前不能产出双平台签名包。
- 工作流增加默认关闭的 `publish_unsigned_release` 手动门禁；只有显式选择时才允许把未签名/未公证产物发布，并在 Release 正文标明状态。
- `flutter analyze`、271 项测试、Windows Debug/Release build 均通过；真实已安装 `0.1.0` 窗口确认同版本 Release 不会误弹提示。

### 2026-07-24 原生纹理退出竞态与独立启动修复

- 目标：优先捕获并符号化原生 crash dump，围绕播放器纹理创建/销毁与退出做 N≥5 复现，再修复独立 EXE 启动、当前页面语义挂载并执行长时压力门禁。
- 原生根因已确认：既有 full dump 为 `0xc0000409`，WinDbg 精确落到 `media_kit_video_plugin` 的 `unordered_map::at`；Flutter 注册纹理时可在描述符写入 map 前同步取帧，回调又读取可变的全局 `texture_id_`，异常越过原生回调边界后终止进程。
- 构建期现从固定 SHA256 的 `media_kit_video 1.3.1` 归档生成 `video_output_ltp.cc`，GPU/软件纹理回调各自捕获稳定描述符，所有权继续由对应 texture ID 的 map 保持到注销完成；不修改 Pub Cache、`PlayerBackend` contract 或播放器队列。
- 播放器页面竞态基线 N=5 为 4 次完整通过、1 次控制条可见性脚本失败；修复后一次完整 900 秒门禁退出码 0，完成 35 个播放器创建/退出循环、0 无响应，门禁 WER 目录 0 dump，seek P95 28ms、dispose P95 5265.7ms。最终候选按用户指令停止，并在进程树收口前完成到第 30 轮、剩余约 140 秒，期间门禁目录 0 dump、日志 0 原生异常。
- 独立 EXE 旧配置无窗口根因是只保存尺寸/最大化、不保存坐标，却在有快照时传入 `center:false`；改为始终居中恢复尺寸后，真实现有配置直接启动 N=5 全部在 0.78–1.05 秒获得可响应 HWND。
- 当前实际挂载的紧凑排序控件补齐字段、方向和 6 个菜单项语义。真实 Windows UIA 点击确认全部 `qa.sort.*` 节点可达，菜单无溢出/遮挡并已恢复用户原“日期/倒序”偏好。
- `flutter analyze`、完整 268 项测试和 Windows Debug build 通过，3 项显式真实媒体 benchmark 按设计跳过。SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缓存队列、稳定身份和用户数据语义均未改变。
- 剩余风险：独立 EXE 启动可见性验证后的整进程关闭在全局 CrashDumps 产生同一 PID 的 `0xc0000005` / `0xc000041d`；本地符号栈显示纹理线程在 registrar 已为空后仍调用 `FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable`。它与已通过的播放器 Route 退出门禁不同，本轮未宣称修复。
- 下一步：优先把宿主关闭纳入独立 WER 门禁并收敛 registrar 生命周期；随后排查压力日志仍输出媒体 basename 的隐私缺口，并用更长门禁确认媒体库空闲阶段句柄缓慢上行是否属于驱动/DevTools 缓存还是可回收资源泄漏。

### 2026-07-23 未授权功能删除事故治理

- 目标：把播放器隐藏态细进度被误删的生产事故转化为仓库级容错，确保重构、布局调整或性能优化不能再次用孤立组件测试掩盖真实功能不可达。
- 当前状态：已完成规则与确定性保护。所有删除默认拒绝，修改前必须建立受保护行为/获授权删除清单，编辑后审计 diff 删除项；关键行为必须同时具备页面/Route 可达性证据与真实点击，证据不足时禁止提交推送。
- 生产或真实窗口发现的未授权功能删除固定升级为 Level 3 `independent`。新增播放器挂载合同测试、Agent 事故回归和 `required_validation_records` 评分硬门，完成项状态或验证方法不匹配直接零分。
- 零模型成本验证为 62 个用例、44/6/12 分布、17 项评分器测试与有效 Skill 目录；修正首轮过弱的 Level 2 预期后，隔离 N=5 回归达到 5/5、平均 100 分、`stable=true`、0 基础设施错误。
- 未修改播放器运行时、SQLite schema、过滤语义、filtered queue、`PlayerBackend`、缓存队列、播放设置、稳定身份或用户数据。

### 2026-07-22 播放器隐藏态细进度回归修复

- 目标：恢复完整控制条自动收起后贴在视频底边的 3px 只读播放进度，避免既有功能在未获授权时随控制层重排被删除。
- 当前状态：已完成。历史定位确认提交 `5271f63` 删除了 `PlayerPage` 中独立的 `PlayerHiddenProgressBar` 挂载，但遗留组件与孤立测试；现已按原 Stack 层级恢复，并增加边界注释禁止把它并入透明控制条子树。
- `flutter analyze`、完整 264 项测试与 Windows Debug build 通过，3 项显式真实媒体 benchmark 按设计跳过。真实 Debug 点击覆盖“进入播放器 → 3 秒自动隐藏 → 底部细进度保留 → 鼠标进入底部唤回控制条”，两态截图位于 `.local/qa/player-hidden-progress/`。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend` contract、缓存队列、播放设置、稳定身份或用户数据。

### 2026-07-22 播放器快速切换与预览纹理交接

- 目标：修复播放器连续切换不同分辨率视频时的 Windows 原生闪退，并让快速输入直接收敛到最新选择，不等待旧视频达到可播放状态。
- 当前状态：已完成。媒体卡进入正式播放前会先停止悬停预览媒体输出并取消旧异步代次；缩略图只承担首次进入播放器的冷启动占位，不再参与队列切换或跨媒体复用图片流。
- open worker 在滤镜清理、性能配置、`openPath` 返回和首帧校验等异步边界后都会检查更新请求；旧请求立即退出，损坏媒体总判定窗口仍约 1.5 秒，新选择检测粒度从 250ms 缩短到 80ms。
- Windows 事件日志确认修复前存在 `flutter_windows.dll` 的 `0xc0000005` / `0xc000041d` 原生异常记录。修复后真实悬停预览出画再进入播放器，日志显示预览纹理先释放并销毁，再创建正式播放器纹理。
- 第一轮跨 1080p / 2048×1080 / 4K 往返 20 次稳定；第二轮 20 次毫秒级输入用时 4.19 秒，只完成 5 次实际媒体 open，15 个过期请求被合并，最终第 1 条正常出画。进程保持响应，本轮新增 Application Error 为 0，截图与日志位于 `.local/qa/player-switch-crash-after/`。
- `flutter analyze`、完整 264 项测试和 Windows Debug build 通过。SQLite、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、`PlayerBackend` contract、缩略图调度、稳定身份和用户数据均未改变。

### 2026-07-22 启动后卡片预览与首播冷启动

- 目标：修复应用启动后首次悬停视频卡片永久 loading，并降低首次点击卡片进入播放器时的原生冷启动与 loading 闪烁。
- 当前状态：实现与 focused test 已完成。MediaKit 在 Flutter 首帧提交后统一预热，悬停预览和正式播放器共用可重试的幂等初始化门；悬停 Player 构造也纳入异常保护，失败会释放资源并复位 loading。
- 播放器跳转复用媒体库已验证缩略图覆盖原生纹理接管窗口；open 成功后至少保持 500ms 再按系统动效策略淡出。正常本地打开 800ms 内不闪 loading，真正慢盘或损坏媒体继续显示加载与失败反馈。
- Debug 真实启动测得首帧后 MediaKit 预热约 210ms；真实鼠标悬停连续出画。点击后约 575ms 显示缓存首帧占位且无 loading/黑屏，再约 700ms 由正在播放的原生视频帧接管；截图位于 `.local/qa/hover_preview_cold_start/final-hover-preview.png` 与 `final-player-playing.png`。
- `flutter analyze`、6 项聚焦回归、完整 263 项测试与 Windows Debug build 均通过，3 项显式真实媒体 benchmark 按设计跳过。SQLite、标签查询、filtered queue 内容/顺序、PlayerBackend contract、缩略图调度、稳定身份和用户数据均未改变。

### 2026-07-22 暗部增强闭环与 HDR 能力正式化

- 目标：补齐“画质增强路线”中未完成的 SDR 暗部增强，并将已具备活动 LUID、Compute 门槛和会话回滚的 HDR 映射从内部实验文案收敛为真实可选能力。
- 当前状态：已完成。新增默认关闭的“暗部细节增强”，仅对后端明确报告的 SDR、1080p 及以下、当前硬解会话应用保守 gamma 曲线；未知传递函数、4K 或软解保持关闭。
- 暗部曲线与自动去块/时空降噪/锐化合成单条 `vf` 快照，不在 UI 线程处理视频帧；独立压力计数在新增掉帧、缓冲或停滞时只回滚当前媒体，不改写用户持久开关。
- 最终固定样本 A/B：关闭/开启态各 60 秒、12 个诊断样本，均为 0 掉帧、0 停滞、窗口 0 无响应；进程 GPU Engine P95 均为 5.0%，显存 committed P95 为 299.4 / 300.1 MiB。像素预检保持 Limited 黑位 `YMIN=16`，`YAVG` 从 43.6642 提升到 45.4358。
- 同轮 HDR 60 秒样本在新增 1 个总掉帧后立即恢复 `auto`，验证运行时熔断真实生效。设置页删除内部“画质增强路线”卡，展示暗部增强与“HDR 动态映射”真实开关。
- `flutter analyze`、完整 258 项测试、Windows Debug build 和三组真实 MediaKit 固定样本均通过。Debug 真实点击确认开关可操作、恢复关闭后状态正确，页面无截断、遮挡、错位或溢出；两态截图位于 `.local/qa/settings-quality-completion/`。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 全屏边缘播放列表开关与命中修复

- 目标：提高全屏右缘播放列表的触发可靠性，避免鼠标到达最右边时列表反向消失，并把自动边缘唤出收敛为播放器交互页的单一开关。
- 当前状态：实现与 focused test 已完成。未展开时使用固定 32px 热区；展开后按实际 320–476px 列表宽度加 12px 容错保持，最右透明热区不再覆盖列表；离开完整列表后使用固定 450ms 宽限。
- 设置页删除热区宽度和隐藏延迟滑杆，只保留默认开启的“全屏边缘播放列表”开关。开关关闭只禁用鼠标边缘自动唤出，播放器显式列表按钮仍可使用；旧 JSON 参数继续兼容读取但不再参与运行时命中。
- `flutter analyze`、完整 255 项测试和 Windows Debug build 均通过，3 项显式真实媒体 benchmark 按设计跳过。Debug 真实点击确认：关闭开关时最右缘不触发；开启后约 320ms 展开，最右缘停留超过 850ms 保持，移回画面 700ms 后收起；设置页和全屏覆盖队列均无截断、遮挡、错位或溢出。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 播放器全屏返回与会话恢复

- 目标：播放器从全屏点击返回时，底层主界面和其他页面恢复为窗口最大化；同一应用会话再次进入播放器时恢复全屏。普通最大化进入播放器时继续使用原窗口路径。
- 当前状态：实现与 focused test 已完成。媒体库 Route 只持有内存态的播放器全屏会话标记，不写入 `PlaybackSettings` 或窗口布局文件；播放器返回前以 `window_manager` 实际全屏状态兜底，只有全屏路径执行“退出全屏 → 最大化 → Route 返回”。
- 用户在播放器内手动退出全屏会立即清除会话标记；从普通窗口或最大化窗口返回不会最大化窗口，也不会让下一次播放器误进全屏。
- 最终 `flutter analyze`、完整 255 项测试与 Windows Debug build 通过，3 项显式真实媒体 benchmark 按设计跳过。真实点击确认普通最大化进入/返回、播放器进入全屏、Esc 主动退出后清除恢复状态并在重进时保持窗口播放器；自动化运行时不支持鼠标侧键，直接全屏返回与重进全屏由 focused 状态测试和同一 `_exitPlayer` 代码路径覆盖，仍建议用实体鼠标侧键补一次人工验收。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缓存队列、稳定身份、播放设置或用户数据。

### 2026-07-22 全屏队列语境显隐与 Debug 独立启动

- 目标：全屏底部控制条可见时移除顶部队列语境遮挡，并修复手动双击 Windows Debug 包后进程存在但窗口不出现。
- 当前状态：已完成。全屏队列语境改为与控制条互斥；控制条出现时淡出，3 秒自动收起后恢复，不新增 Timer、队列查询或逐帧视频处理。
- Debug 启动根因是组合根在应用首帧前同步调用 `MediaKit.ensureInitialized()`；独立 exe 卡在该原生加载路径时，Dart VM 中 `_initialized=false`、窗口服务尚未创建。默认 MediaKit 后端现只在真正创建播放器时初始化，原生实验后端不受影响。
- 新 Debug exe 从构建目录直接启动后 864ms 获得非零窗口句柄并保持响应；真实点击覆盖“媒体库首项 → 播放器 → 全屏 → 控制条显示 → 3 秒收起”，两态截图位于 `.local/qa/fullscreen-controls/`。
- focused test、完整 254 项测试、`flutter analyze` 与 Windows Debug build 均通过，3 项显式真实媒体 benchmark 按设计跳过。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缓存队列、稳定身份或用户数据。

### 2026-07-22 HDR 长播、会话回滚与 SDR 暗部基线

- 目标：固定 HDR 样本验证长播观感、掉帧、GPU 功耗和显示输出；运行时压力自动回滚本次 HDR 会话；暗部增强继续使用独立 SDR 基线。
- 当前状态：已完成。主设置页把原“播放与继续观看”拆为“播放与解码”和独立“视频画质与增强”；继续观看、硬解和码流缓存留在前者，比例、缩放、色彩、自动画质、超分与 HDR 实验进入后者，仍共用同一设置快照与保存链。
- Windows DXGI 输出探针现返回每块 adapter 的桌面输出、分辨率、位深、色彩空间、HDR 信号和亮度元数据。当前活动 RTX 4070 SUPER 的 `DISPLAY1` 为 3840×2160、8 bit、`rgb-full-g22-p709`、HDR 信号未活动、峰值 417 nits；本轮 HDR 结论是映射到 SDR 显示输出，不宣称 HDR 直通。
- 固定 1080p HDR10/PQ 样本长播 302 秒，共 60 个 5 秒诊断样本：解码/输出/总掉帧最大值均为 0，停滞 0，全部 `smooth=true`，会话结束仍为 `hable + hdr-compute-peak=yes` 且无自动回滚。进程 GPU Engine 中位/P95 为 6.7% / 9.6%，GPU committed 为 458.5 / 470.4 MiB；NVIDIA-SMI 整卡功耗中位/P95 为 157.77 / 168.31 W，不能冒充进程功耗。
- 固定 1080p SDR 暗部样本长播 182 秒，共 36 个诊断样本：解码/输出/总掉帧最大值均为 0，停滞 0，全部 `smooth=true`。进程 GPU Engine 中位/P95 为 5.1% / 5.7%，GPU committed 为 301.4 / 308.4 MiB；近黑梯度与相邻灰阶可辨，作为暗部增强关闭态原始对照。
- HDR 压力保护复用两秒播放健康样本：新增掉帧、缓冲或音视频停滞立即回滚；帧推进、缓存或 FPS 中等压力连续两次才回滚；seek/暂停不评估，回滚锁存到下一媒体且不改写持久开关。释放期进入退出态，避免销毁停顿误触发。
- 真实点击已覆盖“设置 → 视频画质与增强 → HDR 实验 → 确认 → 关闭”，首页拆分、画质页和两态截图均无截断、遮挡、溢出或状态歧义，证据位于 `.local/qa/hdr-mapping/`；固定样本 JSON、进程指标、后端帧和窗口截图位于 `.local/qa/fixed-quality-baseline/`。
- 最终 `flutter analyze`、完整 253 项测试、Windows Debug build、活动 LUID / Compute / 显示输出 integration test、设置真实点击和固定样本长播/短复测均通过；3 项显式真实媒体 benchmark 按设计跳过。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 原生 GPU 能力矩阵与第三阶段闸门

- 目标：从实际 MediaKit / ANGLE 渲染设备返回活动 adapter LUID，在该 LUID 上建立 1080p / 4K Compute 帧预算，只选择一个第三阶段功能做默认关闭、可回滚实验；暗部增强保持独立观感与性能基线。
- 当前状态：已完成。构建期只替换固定 SHA256 的 MediaKit `ANGLESurfaceManager` 单个源文件，在真实 D3D11 device 创建/销毁处登记 LUID；不修改 Pub Cache，不按枚举顺序、Feature Level、名称或显存占用推断活动显卡。
- 当前设备矩阵：RTX 4070 SUPER（约 11.72 GiB 专用显存）与 AMD Radeon Graphics（约 460 MiB 专用显存）均为 D3D 12_1、Compute 已验证、Vulkan 已匹配；Microsoft Basic Render Driver 标记为软件适配器，不参与活动硬件卡选择。完整证据见 `docs/qa/player_gpu_capability_matrix_20260722.md`。
- 实际生产渲染设备返回 LUID `00000000:00016bec`，精确匹配 RTX 4070 SUPER。D3D11 HDR 类 Compute kernel 在 60fps 的 4.167ms 预留切片下，1080p P95 为 0.036ms、4K P95 为 0.129ms，两档均通过；JSON 位于 `.local/qa/gpu-capability-matrix/active-device-compute-budget.json`。
- 该阶段只选择了“HDR 动态映射”做可回滚验证；后续已保留默认关闭、HDR 源、精确 LUID、Compute 能力与会话压力门槛，并收敛为正式用户文案。运动补帧保持未启动；`hqdn3d` 已以保守时域参数参与时空降噪。
- `tool/run_gpu_capability_matrix.ps1` 可重建活动 LUID、设备矩阵和 1080p / 4K 预算；压测显式触发并在原生后台执行，普通播放启动不运行 Compute 基线。
- 暗部增强不与第三阶段 Compute 功能共用结论；后续已使用固定 SDR 暗场样本完成独立开/关 A/B，并只在 SDR、1080p 及以下、实际硬解边界内提供默认关闭的手动开关。
- 隔离 Windows integration test 真实点击“设置 → 播放与继续观看 → HDR 实验 → 确认 → 关闭”，开启/回滚两态无遮挡、溢出或状态歧义；截图位于 `.local/qa/hdr-mapping/`。真实 MediaKit 会话另行核验 `hable/yes → auto/auto` 回滚。
- 最终 `flutter analyze`、完整 251 项测试、Windows Debug build、活动 LUID / Compute 基线 integration test 与 HDR 两态真实点击 integration test 全部通过，3 项显式 benchmark 按设计跳过。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、稳定身份或用户数据。

### 2026-07-22 自动画质协调器与 GPU 能力检测

- 目标：先建立 1080p / 4K 的 GPU、CPU 与丢帧基线，再让第二阶段去块、降噪和适度锐化只在实时余量允许时动态启用；第三阶段功能必须先经过真实显卡能力检测。
- 当前状态：已完成。主界面“播放与继续观看”设置新增默认关闭的“自动画质协调器”，隔离 Debug 窗口已完成设置开关、1080p / 4K 播放、队列滚动与诊断真实点击。
- 隔离实测稳定段：1080p 硬解 CPU / GPU Engine 中位 64.9% / 43.3%，软解 142.4% / 1.0%，两者解码/总掉帧均为 0；4K 硬解 66.5% / 59.2% 且 0 掉帧，4K 软解 216.1% / 1.0%，出现 27 帧总掉帧与 0.114 秒 AV 偏移。完整口径见 `docs/qa/player_quality_baseline_20260722.md`。
- 协调器复用原播放健康 Timer，每两秒采集扩展样本；连续 8 个健康样本且满足 10 秒冷却才升级。1080p 硬解最高锐化、1080p 软解最高降噪、4K 硬解最高去块、4K 软解保持关闭；新增掉帧、缓冲、停滞或 FPS 压力立即降级。
- 去块、`hqdn3d` 和 `unsharp` 使用 FFmpeg 官方滤镜参数，并作为单条 `vf` 快照经既有 `PlayerBackend` 串行应用；Flutter 不读取视频帧，不新增 UI Timer，不触碰 filtered queue 或后台媒体队列。
- `PlayerGpuCapabilityDetector` 在媒体可播放后读取实际输出驱动、GPU API/上下文、D3D11 Feature Level、当前硬解和 HDR 源信号；后续原生设备矩阵已补齐 Compute / Vulkan 能力，但多卡环境仍须唯一确认活动适配器才可解锁。
- 最终 `flutter analyze`、完整 244 项测试与 Windows Debug build 通过，3 项显式 benchmark 跳过。真实诊断中 1080p GPU 档升至“去块 + 降噪 + 锐化”，4K GPU 档封顶“去块”，两者解码/总掉帧均为 0；截图保存于 `.local/qa/2026-07-22-quality-live/`，不进入仓库。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、PlayerBackend contract、缩略图/媒体详情队列或用户数据。

### 2026-07-22 播放器第一阶段画质能力与队列密度

- 目标：减小播放器队列卡片的无效内间距，并把第一阶段画质、解码、缓存与诊断能力集中到主界面设置页；第二、三阶段只展示真实路线，不提供尚未满足流畅度门槛的假开关。
- 当前状态：已完成。队列卡片横向内边距、序号占位和内容间距已收紧，缩略图与标题略增大，11176 项队列仍按可见项构建。
- 播放设置新增原始高清码流缓存、正确画面比例、Bicubic / Lanczos 缩放和自动 / Limited / Full 输出色彩范围；自动硬解显式允许连续失败三帧后回退软件解码，默认高质量缓存使用 96 MiB 前向与 32 MiB 回看内存窗口，不复制源文件。
- 既有 FFprobe 媒体详情缓存继续负责编码、分辨率与时长；播放诊断补充实际亮度/色度缩放器、源色彩范围、矩阵、原色、传递函数和输出范围，并保留实际硬解、缓存、解码/输出/总丢帧。
- 第二阶段“去块、降噪、适度锐化、暗部增强、自动画质”和第三阶段“AI 超分、时域降噪、运动补帧、HDR 映射、Vulkan / Compute Shader”在设置页标记为待性能基线/能力检测，避免默认打开高开销滤镜导致播放或 UI 卡顿。
- 精确 Debug 真实点击覆盖设置入口、缩放器切换并恢复、播放器入场、队列滚动和播放诊断；实测 `d3d11va-copy`、Lanczos、自动输出范围、源 `limited / BT.709 / BT.1886`，解码与总丢帧为 0，缓存约 111 秒，视频/音频持续推进。
- `flutter analyze`、完整 238 项测试与 Windows Debug 构建通过，3 项显式 benchmark 跳过；截图保存于 `.local/qa/2026-07-22-player-quality/`，不进入公开仓库。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容/顺序、稳定身份、缩略图/媒体详情队列或用户标签/收藏数据。

### 2026-07-22 播放器控制显隐、全屏覆盖队列与快进档位

- 目标：降低播放画面上的常驻遮挡，在不改变 filtered queue 和视频纹理尺寸的前提下提供流畅的全屏覆盖队列、自定义快进快退档位与左上角文字反馈。
- 当前状态：已完成。控制条首次进入默认显示，3 秒无交互后自动收起，仅鼠标进入底部进度区域时重新显示；全屏队列以根层覆盖动画出现并铺满高度，不再挤压或缩放画面。
- 更多播放设置新增 5 / 10 / 15 / 30 / 60 秒离散滑动档位，前进/后退按钮与快捷键统一读取；按键连发只在左上角显示一次轻量文字水印，不再使用中央 HUD。
- 真实 Windows 复测覆盖 1249×714 窗口、2560×1440 全屏、11176 项队列滚动、控制条自动隐藏、快进水印和更多设置。复测发现设置页内部 `AnimatedSwitcher` 与视频纹理叠加会触发 Flutter Windows 引擎访问冲突，改为内容树直接切换后连续打开和停留均稳定。
- Apple 式动效使用 320ms 淡入/短距离右滑和更短退出，动画只改变合成属性；reduced motion 继续缩短/移除位移，不为队列滚动增加全列表动画或新 I/O。
- 最终 `flutter analyze`、完整 238 项测试与 Windows Debug 构建通过，3 项显式 benchmark 跳过。测试后的 GPU 超分开关已恢复关闭。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源/内容/顺序、`PlayerBackend` contract、缩略图/媒体详情队列或用户标签/收藏数据。

### 2026-07-22 播放器 GPU 画质超分

- 目标：在播放器进度条齿轮设置中提供可即时开关的画质超分，同时保持视频播放、filtered queue 与 Flutter UI 响应流畅。
- 当前状态：代码、持久化、focused tests、全量测试、静态分析与 Windows Debug 构建已完成；显式启动 Debug 路径时 Windows 应用激活实际路由到已安装 Release 进程，随后又检测到用户正在窗口输入，自动化按安全规则中止，因此仍需补做新构建的准确人工点击与截图复验。
- 当前打包的 libmpv `v0.36.0-403` 不包含新版 Intel/NVIDIA `d3d11vpp scaling-mode` 厂商扩展；本轮使用其已支持的 `ewa_lanczossharp` GPU 高质量上采样，不宣称 RTX/Intel AI 超分。
- 设置默认关闭；开启后显式使用 `scaler-resizes-only=yes`，仅在源画面需要放大时运行，高质量亮度缩放与 sigmoid 变换留在 GPU renderer，Flutter UI 不处理视频帧。
- 关闭后恢复 Lanczos 基线；每次媒体 open 前后重新应用设置，播放诊断显示开关、实际 `scale` 与 resize-only 状态。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、解码设置或用户标签/收藏数据。

### 2026-07-21 GitHub 首次公开发布与隐私收口

- 目标：让首次访问仓库的人能理解产品目的、特色功能、技术框架和架构边界，并通过 GitHub Release 获取 Windows / macOS 安装包。
- 当前状态：README、隐私过滤和 `v0.1.0` GitHub Release 已完成；Actions 运行 `29821115757` 的版本解析、Windows、macOS 与公开发布 job 全部成功。
- README 已按“问题场景 → 核心闭环 → 特色能力 → 技术栈 → 架构思想 → 下载/隐私/边界”重写，明确本项目不是 VLC / PotPlayer 的替代品。
- `vX.Y.Z` 标签发布改为 Windows 与 macOS 双端成功后原子创建 Release，同时上传 `.exe`、`.dmg` 和两份 SHA-256；普通分支与手动构建不创建公开 Release。
- 已清理公开 `master` 历史中的个人邮箱、本机用户名/盘符路径和 `.codex/config.toml`，提交者统一为 GitHub noreply 身份；公开分支和标签均只引用脱敏后的历史。
- 本地开发配置和路径上下文继续保留，但由 `.gitignore` 隔离；数据库、日志、媒体样本、环境变量、签名证书、安装包和本地私有配置均加入上传过滤。
- 定向审计未发现已跟踪的媒体文件、数据库、日志、环境变量、私钥、签名证书或 API token。公开仓库仍包含随桌面包使用的 FFmpeg/FFprobe 第三方二进制，属于依赖与许可证审查项，不是个人隐私。
- 公开 Release：Windows x64 安装器 108,566,180 字节，SHA-256 `74b733522c32eef027d9c1b0e846d3bfc6d740e6725fb30544a6f0f1e03c6ea6`；macOS DMG 42,757,651 字节，SHA-256 `6bbdf24c2b288dab2277bc3592557595f31c3bca37abaa7268c15c3b7bb8320a`。
- GitHub Support 的 cached views / dangling commit purge 工单已由仓库所有者提交，当前等待 GitHub 后台处理；仓库 About 已更新为标签发现、组合筛选与当前结果队列定位。
- README 已补充三张完全隔离 profile、程序生成演示媒体制作的脱敏截图；截图不含真实媒体、个人路径、观看记录或用户标签。
- 后续标签发布已配置 Windows Authenticode 与 macOS Developer ID / notarization 必过门禁；签名凭据缺失时构建失败，不会发布未签名正式包。`v0.1.0` 仍是未签名、未公证的历史产物。

### 2026-07-21 Windows / macOS 正式版安装包

- 目标：基于 `pubspec.yaml` 的 `0.1.0+1` 构建 Windows x64 Release 安装器与 macOS Release DMG，不改变业务、数据或播放语义。
- 当前状态：已完成。Windows 本地 Release 安装器、隔离安装/启动/卸载冒烟均通过；独立 macOS runner 已完成 Release 构建、10 秒启动检查、DMG 生成与上传。
- Windows 安装器使用当前用户目录安装，卸载时保留用户数据库、标签、收藏和播放记录。
- macOS bundle identifier 已从模板占位符收敛为 `com.zero1412.localtagplayer`，Finder 展示名为 `Local Tag Player`。
- 仓库当前没有 Windows Authenticode 与 Apple Developer ID / notarization 凭据；生成的安装包必须明确标记为未签名或未公证，不能宣称通过系统信任链。
- Windows 安装器：108,571,720 字节，SHA-256 `0ad9b542bed463d9036111c1a2a7acc2e1e0fe4ff4d4261339665890a506fe36`。
- macOS DMG：42,757,735 字节，SHA-256 `536c53e804e2267ccecc3d6991da66561e25bc6676cf94119e5d3222b03a5094`；Actions 运行 `29815594317` 的 Windows / macOS job 均成功。

### 2026-07-21 媒体卡片文件菜单收口

- 目标：让媒体卡片“更多”只承担当前文件定位与删除，移除与播放器详情重复的标签编辑和文件重命名，并缩小悬浮菜单。
- 当前状态：已完成。
- 网格卡片、紧凑列表和本地目录视图共用“打开文件 / 删除文件”双项菜单；播放器详情中的标签编辑与重命名能力保持不变。
- “打开文件”仍通过 `FileSystemAdapter.revealInFileManager(item.path)` 定位当前卡片的完整视频路径，不打开媒体库 root 或资源目录。
- 菜单宽度限制为 136–156px，条目最小高度 40px，外层垂直留白 4px；真实窗口无遮挡、溢出或文字截断。
- 页面级回归直接记录平台边界收到的路径，并断言等于被点击卡片；同时锁定菜单不再出现“编辑标签 / 重命名文件”。

## 当前稳定基线

- 产品边界：Tag 驱动的本地视频发现播放器，不扩展字幕、音轨、逐帧或 A-B loop 等专业播放器能力。
- 数据边界：SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容与顺序、标签来源语义均未改变。
- 验证：247 项测试通过，3 项显式 benchmark 跳过；播放器控制显隐、全屏覆盖队列、快进档位、左上角文字反馈、GPU 超分、自动画质协调与原生显卡设备矩阵回归、`flutter analyze`、Windows debug build 均通过。真实窗口完成设置开关、1080p / 4K 播放、队列滚动与诊断复测；低分辨率超分两态、自动画质和 GPU 设备矩阵诊断截图已保存。
- 架构基线：`Architecture Baseline 0.5.54`。

## 已确认阻塞

- 外部跨平台规划 `<private-planning-document>` 当前不存在；本轮依照仓库内长期规则和现有跨平台边界实施。
- GitHub Support purge 工单已提交，但服务端缓存清理尚未确认完成；处理完成后仍需验证旧提交 API 返回 404。
- 项目级 `LICENSE` 必须由仓库所有者在 `GPL-3.0-or-later` 与 `MIT` 等授权策略中明确选择；第三方声明不能代替项目源码授权。
- 实际生成可信安装包仍需仓库所有者在 GitHub Actions 配置 Windows PFX、Apple Developer ID Application 证书和 App Store Connect 团队 API key；不得把证书、密码、Base64 或私钥提交到仓库。

## 下一步入口

1. 后续播放器视觉复验优先覆盖 Windows 150% 文字缩放与系统 reduced motion，确认全屏覆盖队列、左上角 seek 水印和更多设置仍无溢出、纹理抖动或引擎崩溃。
2. 等待 GitHub Support 完成服务端 purge，随后确认旧 Commit API 返回 404。
3. 确定项目级许可证并提交根目录 `LICENSE`；保留 `THIRD_PARTY_NOTICES.md` 与安装包内第三方许可证。
4. 在 GitHub Actions secrets 配置两端签名凭据，创建新标签并在真实 Windows / macOS 上复验 SmartScreen、Gatekeeper、签名、时间戳、公证票据与校验值。
## 2026-07-24 路径失效自动清理语义修正

- 开关开启时，数据库记录对应路径只要不存在就直接清理，不要求先经过扫描写入 `isMissing`。
- 清理仍只作用于数据库视频行、标签关系和依赖备份；不删除磁盘文件或文件夹。

## 2026-07-28 MPV 命令调度与稳态播放修复

- 目标：解决 MPV 容器渲染下首播/切换等待、列表收放画面抖动、seek 不流畅和偶发
  卡顿，同时保留 MediaKit、filtered queue 与现有播放器 UI。
- 根因：Windows 原生工作线程曾在渲染前连续处理属性命令，每条命令又触发完整状态
  采样；自动压缩增强还会在掉帧回滚后重新升档，形成 CPU `lavfi` 振荡。
- 实现：新增可选 `PlayerPropertyBatchBoundary`，批量下发打开偏好和增强属性；单条
  命令直接返回状态快照；原生工作线程在控制命令前优先消费合并后的渲染请求。
- 性能保护：50/60fps copy-back 基线（含 1080p60、4K60）保持关闭；低帧率增强
  一旦确认带来压力，本媒体锁定关闭直到切换视频。诊断要求连续位置异常或独立
  掉帧/停滞证据，避免单次定时器抖动误报。
- 实测：同一 4K60 样本修复前 19 秒总掉帧从 32 增至 81、AV 偏移约 0.35 秒；
  修复后约 49 秒总掉帧保持 1、AV 偏移约 0.000004 秒、表面重建保持 6。
  真实窗口完成列表收放、连续 seek、快速切换和诊断长采样。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue
  来源/内容/顺序、MediaKit、缩略图/媒体详情队列或用户数据。
