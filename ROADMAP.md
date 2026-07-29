# ROADMAP.md

## 2026-07-29 渐进式整体架构重构

- [x] 完成外部资料研究、代码规模审计、受保护行为清单与目标依赖方向。
- [x] 分离 `main`、bootstrap 组合根和 Flutter 应用壳。
- [x] 以更新功能完成首个 `domain/data/presentation` 纵向切片和依赖合同。
- [x] 完成网页端独立架构评审，建立渐进迁移 ADR 和兼容导出、跨 feature、文件预算门禁。
- [x] Phase 2A-1：提取设置首页无状态导航叶节点，保持原状态 owner、Route 和入口 Key。
- [x] Phase 1.5：建立受保护交互清单、查询追踪、版本化快照协议和 11,000 条基准数据。
- [x] Phase 2：按无状态 UI、普通设置、只读诊断、缓存修改、备份恢复五步解耦。
- [x] Phase 3：按数据修订、选择/视图、排序、查询/计数、QueueSnapshot、扫描/导入六步迁移。
- [x] Phase 4：按会话、event bridge、控件、native 生命周期、诊断五步迁移。
- [x] Phase 5：先收窄 Repository 使用面，再在事务安全前提下评估 `LibraryStore`
  物理拆分。
- [x] Phase 6：删除已经归零的 `src/app.dart` 兼容导出面；测试具体 import 从 Phase 2
  起随改动持续推进。

完整方案与阶段门禁见 `docs/architecture/ARCHITECTURE_REFACTOR_2026_07_29.md`。

## 2026-07-29 代码体积治理

- [x] 对齐 Effective Dart、Flutter 职责分离与 Google 小变更/评审标准。
- [x] 建立项目本地 200 行最佳实践、500 行警戒线和 1000 行强制重构线。
- [x] 超过 500 行的既有 presentation 文件登记只降不升预算，禁止新增超标文件。
- [x] 拆出最近播放与标签编辑叶节点，降低 `library_widgets.dart` 的依赖与冲突面。
- [x] 拆出 sidebar 通用条目、左右面板转场与 top bar 结果视图切换器；
  `library_widgets.dart` 降到 3348 行。
- [x] 把全部 8 个超过 1000 行的 presentation 文件纳入有序强制治理清单。
- [x] 拆分 `library_widgets.dart` 的 sidebar 容器与 top bar 搜索/筛选状态区域；
  聚合文件降到 1917 行，全部新组件低于 500 行。
- [x] 启动 `library_page.dart` 治理，先迁出播放解码器/渲染器设置叶节点；
  页面预算从 5747 行降到 5391 行。
- [x] 继续迁出原始码流缓存、播放画质/流畅度、删除文件设置和缓存失败状态叶节点；
  `library_page.dart` 预算降到 4686 行，全部新叶节点低于 500 行。
- [x] 迁出“播放与解码”主卡、全屏队列开关和快捷键展示区；只传入快照与回调，
  `library_page.dart` 预算降到 4487 行，controller、确认、冲突校验与业务命令不迁移。
- [x] 迁出设置 Route 外壳与缓存诊断卡装配；两个叶节点分别为 82/69 行，
  `library_page.dart` 预算降到 4443 行，section 状态和缓存命令 owner 不迁移。
- [x] 将标签 helper、选择工具栏、顶栏附件控件和 focused harness 拆为 200 行内叶子；
  `library_widgets.dart` 从 1917 行降到 962 行，退出 1000 行强制重构清单。
- [x] 继续迁出添加标签与清空进度/解除目录确认对话框；只返回用户意图，
  `library_page.dart` 预算降到 4293 行，标签与目录命令 owner 不迁移。
- [ ] 下一批继续按只读状态/纯展示一致性边界拆分 `library_page.dart`，随后依次治理播放器页面、
  视频结果、播放器队列侧栏、标签发现面板、
  标签管理页和 missing/relink 页面。

## 2026-07-28 默认 MPV 容器合成

- [x] 默认 MPV 改为 libmpv Flutter Texture，与 MediaKit 共享同一个播放器容器；
  child HWND 不再覆盖 Flutter 队列、控制条和弹层。
- [x] MPV Texture 固定使用 `d3d11va-copy` 并验证真实硬解读回；非 copy
  `windows-native-hwnd` 继续作为显式 NVIDIA QA 路径。
- [x] 验证普通/全屏队列开合即时重排、控制条浮层、随机右键与设置弹层无黑块。
- [x] 删除全屏顶部队列语境条；filtered queue、当前 index、导航和返回路径不变。
- [x] 完成 100%/125%/150%/200%/100% 模拟 DPI 与 6 次全屏快速往返。
- [ ] 在两块不同缩放显示器间补齐真实物理 DPI 门禁；当前测试机只有单块 100% 屏。
- [x] 完成 MediaKit/MPV 各 30 分钟长播和 18 次快速切换；停滞均为 0，最大总
  掉帧为 0/2（预算 5），自动门禁通过并归档报告。

## 2026-07-28 MPV HWND 动态控制区回归修复

- [x] child HWND 使用完整视频占位矩形，控制条改为 native region 动态让出。
- [x] 修复首入/切换时旧 surface 几何导致的错位和重复条带。
- [x] 修复右键菜单定位与真实边界测量，保持菜单外视频实时播放。
- [x] 完成真实低码率 1080P 弹层、播放推进、零 copy 和零掉帧验证。
- [ ] 后续补齐 125% / 150% / 200% 实机 DPI、全屏切换和长播矩阵。

## 2026-07-28 双后端稳定性门禁

- [x] 为 MediaKit 与 Windows MPV 建立同构的全屏、DPI metrics、快速切换和长播
  自动矩阵，并生成按后端分离的 JSON 报告。
- [x] 快速切换使用正式 PlayerPage latest-request 链，保护 filtered queue、当前
  index 和最终打开项。
- [x] macOS/Linux 保持 MediaKit 回退；MPV 开放前必须先有各自原生 PlayerBackend。
- [ ] 在至少两块不同缩放显示器间分别对 MediaKit/MPV 完成真实移窗 DPI 门禁。
- [x] 发布候选构建按默认参数完成每个后端 30 分钟长播；MediaKit/MPV 分别
  561/561、562/562 个采样推进，停滞 0，最大总掉帧 0/2。

## 2026-07-28 MediaKit / MPV 用户选择与自动 NVIDIA

- [x] 设置页仅提供 MediaKit / MPV 两态选择，移除用户不可理解的 automatic；
  切换需要确认、下一播放器 Route 生效并可撤销。
- [x] Windows 组合根按用户偏好创建 MediaKit 或原生 child HWND MPV；非
  Windows 与关闭硬解继续安全回退 MediaKit，不伪造尚不存在的平台后端。
- [x] 播放器齿轮移除 VSR/HDR 手动开关；MPV 根据 NVIDIA、D3D11、源/输出
  尺寸、HDR 与 10-bit 条件自动请求，未知能力保守关闭。
- [x] 原生快照补齐源宽高；三类低码率 1080P 自动会话均为 VSR/HDR
  `active`、0 总掉帧、0 音视频停滞。
- [x] 设置页真实 Windows integration test 完成 MediaKit / MPV 下拉、确认、
  特色说明和截图；画质报告增加后端字段，门禁可分后端汇总。
- [ ] 在 macOS/Linux 拥有可维护的原生 MPV 后端前，保持 MediaKit 安全回退；
  不因设置模型已支持 MPV 就宣称跨平台实现完成。

## 2026-07-28 NVIDIA 发布范围收敛

- [x] 把固定 mpv 驱动链上的 RTX 视频超分与 RTX Video HDR 定义为当前 Windows
  可交付能力；移除产品“实验”文案，但保持默认关闭、会话级和既有门禁/回滚。
- [x] 修正 VSR A/B 为固定第 12 秒、相同最终 Windows 表面截图；真人面部、动画
  渐变、暗场六组性能和视觉门禁全部通过。
- [x] 明确 VSR 不作为日常默认：低码率偏软且被放大时按需开启；真人压缩纹理可能
  变硬，暗场收益很小。
- [x] 将 NVOFA 插帧降级为独立长期研究，不作为播放器发布门禁。
- [x] 停止原任务自动继续 patched libmpv D3D11 hwframe 钩子或独立 FFmpeg
  D3D11VA 后端；未来只有显式重启 NVOFA 研究时再评估。

## 2026-07-28 child HWND 生命周期通过，零拷贝 NVOFA 性能未通过

- [x] 8 次跨进程与 12 次同进程 child HWND 生命周期通过；覆盖真实 D3D11VA
  出帧、弹层显隐、重复创建/释放和幂等 dispose，无 Application Error 或孤儿
  进程。原始孤例无法归因到原生桥，不再凭猜测修改线程次序。
- [x] 增加默认关闭、仅 QA 环境变量可请求的 `d3d11va-zero-copy=yes`；读回、
  12 轮会话和交替压缩 `vf` 兼容门禁通过。
- [ ] 完成真实全屏、跨物理 DPI 与快速队列切换 soak；当前跨 DPI 仍只有确定性
  几何回归，不能把普通窗口生命周期结果扩大解释。
- [ ] **独立长期研究、非发布门禁：**修复 NVOFA 真实帧前置性能回归。零拷贝
  六组 A/B 在开始前连续记录 140/138 新增掉帧并停止，产品入口继续关闭。
- [ ] **独立长期研究、非自动后续：**如未来显式重启 NVOFA 研究，再评估隔离
  patched libmpv 的 D3D11 hwframe 只读钩子，证明连续纹理、subresource、LUID
  和时间戳。
- [ ] **独立长期研究、非自动后续：**只有上述钩子被证明不可维护时，才在现有
  `PlayerBackend` 后评估独立 FFmpeg D3D11VA 后端；不得把平台纹理暴露给
  Flutter 页面或 `PlayerService`。

## 2026-07-28 NVOFA 遮挡与连续运动门禁已通过

- [x] 用双向 cost/一致性拒绝低可靠向量，并在 flow-grid 局部邻域补全无效向量。
- [x] 保留平均主导的保守中点 warp，增加遮挡有效性和低有效性像素的图像域
  hole filling；确定性门禁锁定旧基线 128/90/117、新增矢量补洞 90 和图像
  补洞 201。
- [x] 真人面部、动画渐变、暗场六组，以及快速横移、细栅栏、固定字幕、运动
  模糊、切镜十组均通过 24→48fps、0 总掉帧、0 停顿、同 LUID 与固定帧审查。
- [x] 把一次未稳定复现的 child HWND `0xc0000005` 启动崩溃纳入多轮
  启动/退出与同进程重复会话；普通窗口生命周期已通过。全屏、跨物理 DPI 和
  快速切换仍按上方独立门禁保留，产品入口继续关闭。
- [ ] 继续消除 VapourSynth 软件帧、CUDA 光流回读、D3D11 输入上传和最终平面
  读回；当前开放近似不能称为 NVIDIA FRUC SDK 或全程 non-copy 插帧。

## 2026-07-28 NVOFA 同 GPU Compute 门禁已通过

- [x] child HWND 的 mpv D3D11 适配器已用 DXGI 唯一名称选择，并以 LUID 精确
  匹配 CUDA/NVOFA；多 GPU 不再依赖默认枚举序号。
- [x] 双向中点采样和融合已迁到同 LUID 的 D3D11 Compute，任一 GPU 阶段失败
  会触发现有滤镜回滚，不保留隐式 CPU 慢路径。
- [x] 真人面部、动画渐变、暗场的直接实时门禁与 off/on 六组 20 秒 A/B 全部
  通过：24/48fps、0/0 总掉帧、0 音视频停滞、适配器 LUID 一致。
- [ ] 移除 VapourSynth 软件帧、CUDA 光流回读和最终平面读回；在没有安全的
  D3D11 NVOFA 公开接入边界前，不把当前实现描述成零复制硬件插帧。
- [x] 增加前后向一致性、遮挡有效性、矢量/图像域补洞，以及快速平移、细栅栏、
  字幕、运动模糊和切镜压力门禁；仍因生命周期与 non-copy 边界未完成而不切换
  默认后端或开放持久化入口。

## 2026-07-28 NVIDIA TrueHDR 驱动路径已接入

- [x] 固定 mpv 的 `nvidia-true-hdr` 已在 Windows 原生 D3D11VA 非 copy 链实际
  启用，并由 NVIDIA 驱动日志、10-bit PQ/BT.2020 HDR 活动信号和三类片源六组
  A/B 共同确认。
- [x] VSR 与 TrueHDR 使用一个原子 `d3d11vpp`，联合模式不强制 NV12；任一模式
  失败恢复先前组合，播放压力回滚当前会话。
- [x] 产品入口区分“RTX 视频超分”和“RTX Video HDR”，默认关闭、仅会话保存，
  不把普通 GPU 缩放或 NVOFA 光流冒充 RTX Video。
- [ ] 用支持峰值亮度读取的 HDR 显示链补齐实际 nits、桌面录屏/相机观感与长播
  功耗；当前 DXGI 峰值为 0.0 nits，只能确认 HDR 信号而不能完成显示器校准。
- [ ] RTX Video SDK Artifact Reduction 仍需 NVIDIA 账户/许可与本机 SDK；
  继续使用不分发厂商文件的插件原型，不能因 TrueHDR 驱动扩展已可用而跳过许可。

## 2026-07-28 NVOFA 硬件 execute 门禁已通过

- 当前 RTX 4070 SUPER 已实际完成 NVOFA CUDA session、GPU buffer 和
  `nvOFExecute`，不再只凭 DLL 导出或 GPU 名称判断可用。
- 公开 BSD-3-Clause NVOFA 头文件仅用于固定提交的本机 QA 下载；正式应用仍
  零分发 NVIDIA SDK，产品能力也不会把该 primitive 冒充插帧 active。
- 下一阶段仍是中间帧所有权：优先使用用户明确接受许可后提供的 Optical Flow
  SDK FRUC，实现连续前后帧、目标时间戳、生成帧输出与失败回退；若 FRUC 无法
  接入 VapourSynth，再设计独立多帧 ABI v2，不破坏单帧 ABI v1。
- FRUC 完成后必须重新验证 seek、快速切换、退出、音视频同步和三类自然片源六组
  A/B；RTX Video SDK 的 VSR、Artifact Reduction、SDR→HDR 继续作为另一插件，
  不与硬件补帧混称。

## 2026-07-28 官方 R78 与 NVOFA 驱动门禁已通过

- 官方 VapourSynth R78 已完成隔离安装和真实 H.264 帧、seek、reload 透传验证；
  “先证明完整帧链，再接 NVIDIA FRUC”这一前置门禁已通过。
- Windows runner 已证明当前 RTX 4070 SUPER 驱动提供 NVOFA API 5.0 与 D3D11
  入口；该结果只开放下一阶段原型资格，不代表已有生成中间帧的实现。
- 下一阶段分成两个互不冒充的本机插件：
  1. Optical Flow SDK 5.0 FRUC：负责连续帧、时间戳与中间帧；
  2. RTX Video SDK 1.1：负责 VSR、压缩伪影消除与 SDR→HDR。
- 两个 SDK 都先采用“不分发 NVIDIA 文件”的本机原型。用户完成 NVIDIA 账户与
  许可流程并提供 SDK 后，才编译插件、验证 D3D11 设备/LUID、seek、切换、退出、
  非 NVIDIA 回退、多片源 A/B、掉帧和音视频同步；未通过前不增加用户可启用入口。

## 2026-07-28 NVIDIA 硬件补帧与外部运行时路线

- 已建立 `PlayerService → PlayerMotionInterpolationBoundary → Windows libmpv
  → VapourSynth` 的强类型、本机可插拔边界；外部绝对路径、结构化 `vf` 合成、
  错误回退和真实输出帧率门禁均已落地。
- NVIDIA 硬件补帧的准确目标改为 Optical Flow SDK 的 NVOFA FRUC，而不是把 RTX
  Video Super Resolution/HDR SDK 当作插帧 API。现有 NVIDIA VSR 继续由
  `d3d11vpp scaling-mode=nvidia` 提供；RTX Video HDR 已由固定 mpv 的
  `nvidia-true-hdr` 驱动扩展单独接入，但仍不是补帧 API。
- 官方 VapourSynth R78 透传送帧已经完成；下一阶段接一个不分发厂商文件的本机
  FRUC/VapourSynth 插件，必须读回输出帧率、测三类自然片源、掉帧、音视频同步、
  seek/切换/退出和失败回退后，才增加用户入口。
- 单帧 D3D11 插件 ABI v1 继续服务超分/降噪类原位处理，不扩充为补帧 ABI；
  若 VapourSynth 无法承载 FRUC 的 D3D11 纹理，再另立拥有前后帧、时间戳和输出
  队列的 ABI v2，不能破坏现有插件。

## 2026-07-27 普通显示同步插值

- 已把 `off/displayInterpolation` 作为类型化能力接入 `PlayerService`，并由后端
  读回 `video-sync/interpolation/tscale` 后确认实际状态。
- 该档只解决源帧率与显示刷新率不匹配的顿挫，不宣传为运动补帧或 AI 生成帧；
  缓冲、掉帧和停滞继续触发当前媒体回滚。
- 下一阶段在 Windows 原生后端完成多帧率长播与真实显示 A/B 后，再单独定义
  运动补帧插件 contract；不得把 VapourSynth/SVP/RIFE 模型或延迟控制塞进
  `PlayerService` 通用命令层。

## 2026-07-27 播放器应用层与平台后端解耦

- 已建立 `PlayerPage → PlayerService → PlayerBackend` 三层边界；MediaKit 与
  Windows libmpv 只在组合根成为同级候选，页面不再选择或取得具体后端。
- Windows GPU、HWND、D3D11 与本机视频增强继续作为 libmpv 后端可选能力，不进入
  filtered queue、标签查询或跨平台 UI 业务。
- 下一阶段先把仍用于诊断和画质协调的字符串属性收敛为类型化能力/快照，再考虑把
  Windows libmpv 提升为默认后端；不得以 PlayerService 重新暴露具体 Player 或
  VideoController。
- 参考实现只采纳 media_kit 的“控制核心/视频嵌入分离”和开源播放器的服务生命周期
  所有权，不复制其页面穿透具体 NativePlayer 的耦合。

## 2026-07-22 播放画质第二阶段协调器与第三阶段能力门槛

- 1080p / 4K × GPU 硬解 / CPU 软件解码的真实基线已经建立；第二阶段只开放默认关闭的自动协调器，不提供独立常开高开销滤镜。
- 自动协调器按实时掉帧、缓冲、停滞、FPS 与缓存余量逐级启用去块、`hqdn3d` 时空降噪和适度锐化，并以分辨率/解码路径基线限制最高档。
- 第三阶段 AI 超分、时域降噪、运动补帧、HDR 映射和 Vulkan / Compute Shader 的共同前置条件改为“当前 PlayerBackend 明确报告设备/渲染能力”；未知能力不得按 GPU 品牌或型号推测为支持。
- `PlayerBackend` 的 DXGI 设备矩阵与实际渲染 LUID 已完成分层：系统能力不能替代活动设备，当前 MediaKit D3D11 纹理已精确匹配 RTX 4070 SUPER。
- 1080p / 4K Compute 帧预算已建立，两档 P95 均低于 60fps 的 25% 预留切片；第三阶段只保留 HDR 动态映射这一个默认关闭的可选能力，仍由 HDR 源、精确活动 LUID、Compute 能力和会话压力共同门控。运动补帧继续保持未启动。
- 固定 HDR10/PQ 样本已完成 300 秒长播：记录期 60 个诊断样本均为 0 掉帧、0 停滞，HDR 会话保持 `hable + hdr-compute-peak=yes`；DXGI 明确当前输出为 3840×2160、8 bit、BT.709 全范围且 HDR 信号未活动，因此结论是 HDR 源映射到 SDR 输出，不冒充 HDR 直通。
- HDR 运行时压力保护已完成：新增掉帧、缓冲或音视频停滞立即恢复自动映射；FPS、缓存或帧推进中等压力连续两次才回滚，并只锁存当前媒体会话，不修改用户全局开关。
- 暗部增强已完成独立 SDR 关闭/开启 A/B：两态各 60 秒均为 0 掉帧、0 停滞，GPU Engine P95 均为 5.0%，且 Limited 黑位保持 `YMIN=16`。当前作为默认关闭的独立开关，只允许明确 SDR、1080p 及以下和实际硬解会话，压力出现时自动回滚。

## 2026-07-18 Apple 式全应用 UI 第二阶段启动

- 采用 Apple 的目的、控制、熟悉、灵活、简洁、工艺和愉悦原则，把全应用统一为平静、精确、内容优先的桌面媒体体验；不复制 macOS，不把全窗口毛玻璃当成目标。
- 新增 `$ltp-apple-ui-design` 和 `docs/design/APPLE_UI_MIGRATION.md`，先统一 token、无障碍与基础组件，再按媒体库、播放器、维护页、全局细节和跨平台逐阶段迁移。
- UI 迁移不得改变标签层级、查询语义、filtered queue、播放器/缓存队列或用户数据；每个阶段都必须通过 focused tests、完整 analyze/build、真实点击截图和大媒体库性能检查。
- 下一步只执行 Phase 0：共享颜色/材质/排版/圆角/动效 token，以及 reduced motion、high contrast 和文字缩放基线；不同时重写页面信息架构。

## 2026-07-16 备份检查、导出与低写放大启动完成

- 设置页可显式检查 SQLite、快照结构和当前视频覆盖差异，并导出不含路径或媒体文件的版本化 JSON。
- 正常关闭启动只消费增量队列；异常退出、未完成、首次和重新开启时保守全量。条件 UPSERT 继续保证全量核对不会重写未变化快照。
- 下一步可在明确用户需求后增加便携 JSON 导入预览；导入必须先展示记录数、冲突与 fingerprint 歧义，默认只读预览且不得覆盖现有较新依赖。

## 2026-07-16 视频依赖独立备份完成

- 默认开启独立 SQLite 备份，覆盖稳定身份、收藏、播放状态与非 folder 标签；视频文件、缩略图和媒体详情缓存不重复复制。
- 全量游标和增量队列可跨重启续跑，播放器会话期间暂停；root detached 与显式单视频删除保持不同的快照生命周期。
- identity 重建后的自动恢复采用扫描侧/备份侧 fingerprint 双侧唯一保护，歧义文件不自动合并。
- 完整性检查、可选导出位置和启动写放大优化已由上方阶段完成。

## 2026-07-16 root detached 身份保护完成

- root 移除不再硬删 SQLite 视频行和标签关系；新增 detached 状态把“是否由当前目录管理”与 missing、stable identity 和用户数据解耦。
- 重新添加相同目录按 path 恢复，目录或文件移动后按唯一 fingerprint 恢复；收藏、手动标签、播放进度、媒体详情和缓存继续绑定原 videoId。
- detached 不进入常规筛选或 filtered queue，过期媒体探测不能把它重新激活；标签管理保留归档引用以防误删。
- 下一步为 detached 归档提供只读数量与显式“永久清理归档”入口，危险清理必须再次确认并默认不执行。

## 2026-07-15 冷扫描阶段进度与播放资源协调

- 目录发现与 fingerprint 已拆分：总量未知时只显示发现数，候选确定后使用确定型进度、速度和 ETA；真实冷启动阶段耗时继续写入隐私安全 JSONL。
- 播放期间自动暂停只读扫描并在退出后原位恢复，优先保护视频解码和 UI 输入；不通过继续提高媒体探测并发掩盖机械盘瓶颈。
- 11,163 项热缓存强制 fingerprint 对照为发现 24ms、校验 1,444ms、首次提交 1,995ms；下一步在重启后真实冷盘使用中继续收集 HDD/SSD 多轮样本，再决定是否需要进一步调整 fingerprint 读取布局。
- SQLite schema、stable identity、标签过滤、filtered queue 与 PlayerBackend 均保持不变。

## 2026-07-15 大目录导入分阶段进度与批量媒体解析

- 大目录添加先显示“正在发现并校验视频”；扫描提交后视频列表立即可筛选、滚动和播放，同时在当前筛选结果区显示媒体信息已处理数/总数和百分比。
- 媒体详情从逐文件原生调用、逐文件 SQLite upsert 改为最多 8 条有限批次；可见卡片仍独立优先，新扫描会取消旧探测，避免扫描与后台解析争抢磁盘。
- 完成或失败均计入已处理进度，全部结束后自动恢复“全部视频 · xx 个结果”；异常文件继续保留失败原因和重试入口。
- SQLite schema、stable identity、`FilterQuery` / `TagQueryService`、filtered queue 和缩略图队列语义不变。

## 2026-07-15 媒体库文件导入与目录删除入口

- 空媒体库中央提供大号“添加视频文件”入口，系统选择器支持多选；媒体库结果区支持从资源管理器拖入视频或目录，并在悬停时显示明确释放反馈。
- 文件父目录与拖入目录先归并为最上层 root，已受现有 root 覆盖的文件只重新扫描；Repository 批量注册全部新 root 后只执行一轮扫描，避免大媒体库重复遍历。
- 目录管理删除与左侧 root 移除复用同一协调入口；当时采用移除索引、关系和缓存但不删除磁盘视频的策略，现已由 2026-07-16 的 detached 身份归档策略取代。

## 2026-07-14 页面依赖收窄与跨平台 runner

- `LibraryPage` 已从完整组合根依赖图收窄为页面级应用服务、文件系统 contract 和播放器路由所需 factory；路径、FFmpeg、Repository 及 debug 配置不再暴露给页面。
- macOS/Linux runner、平台 media_kit 库与 GitHub Actions build/start smoke 已接入；对应宿主会执行 adapter contract、debug build 和启动存活检查。
- SQLite schema/写入、标签筛选、stable identity、filtered queue 与缓存队列继续由 Dart 业务层统一拥有。

## 2026-07-14 独立 Dart library 迁移完成

- 57 个 `part` / `part of` 已全部清零；Store 私有协作、播放器与缩略图实现、应用服务、页面和 widgets 均使用显式 import。
- 组合根依赖图、Repository/facade 和平台 adapter 均有独立 contract/fake 测试；架构测试阻止重新引入 `part`。Windows analyze/build、96 项测试与真实窗口标签/目录 smoke 已通过。
- 下一步聚焦收窄 `LibraryPage` 对组合根依赖图的使用，并在 macOS/Linux 宿主执行构建与 adapter 验证；SQLite、标签筛选和 stable identity 继续由 Dart 单写拥有。

## 2026-07-14 独立 Dart library 迁移第二批完成

- `part` 从 57 降至 35；领域模型/契约、DatabaseProvider、扫描与媒体平台边界、播放辅助和窗口服务已独立。
- 下一批先拆 Store 的 metadata/tag/scan coordinator 私有协作，再拆播放器实现，最后处理页面与 widgets。
- macOS/Linux adapter 已接入组合根；对应 build 必须在各自宿主 runner 验证。

## 2026-07-13 SQLite hydration 与 Rust 扫描边界完成

- 分阶段诊断确认约 40 秒并非普通 SQLite 查询或对象 hydration，而是启动维护中的无条件 NOCASE 相关回填；修复后真实副本加载低于 1 秒，真实窗口首帧约 1.42 秒。
- Rust `LibraryScanBackend` 已作为 Windows 只读 sidecar 接入，运行时失败回退 Dart；SQLite 仍由 Dart Repository 单写，不引入双端 migration/transaction 风险。
- 父子 root 重叠按最上层 root 和 pathKey 去重；首次提交把历史 root 上下文统一到当前文件树，第二轮 11,133 条稳定态端到端 240 毫秒且零差量。
- 下一步只在真实 NAS/掉盘环境评估 watcher 事件丢失与周期性全量 reconciliation；在证据出现前不让 watcher 直接标记 missing，也不迁移 SQLite 或标签查询到 Rust。

## 2026-07-13 原生核心服务渐进路线决策

- D3D11/ANGLE 最终调查未达到 Private/GPU P95 为 MediaKit 110% 以内的门槛，默认播放器继续使用 MediaKit，C++ 播放器只保留实验 A/B，不继续扩大剩余生命周期改造。
- Windows 原生核心先落地独立 `MediaProbeBackend`，使用 FFmpeg C API 批处理与 generation 取消；SQLite、标签查询和用户数据继续由 Dart Repository 独占。
- 该阶段“暂不引入 Rust”的结论已被后续 hydration 修复与稳定态 A/B 更新：Rust 仅作为可回滚只读扫描边界接入，SQLite 单写和用户数据所有权不变。

## 2026-07-13 Windows 原生播放器 A/B 第一阶段完成

- 已固定供应 libmpv/ANGLE、补齐许可证，并贯通单会话、共享纹理、串行命令和原生诊断。
- 同媒体短测证明原生链路可播放、可 seek、可退出且无音视频停滞，但 GPU committed 峰值未优于默认 MediaKit，暂不切换生产默认值。
- 已完成同一 4K 长视频三组 480 秒分阶段 A/B，并收敛动态纹理、渲染判定和缓存预算；原生 CPU/工作集有收益，但 Private/GPU committed 仍高于 MediaKit，暂不切换默认后端。
- 下一步只调查一次额外 D3D11/ANGLE device context 与驱动 committed 来源；若 Private/GPU P95 无法进入 MediaKit 的 110% 以内，则停止默认替换路线，仅保留实验后端。

## 2026-07-12 窗口恢复、快捷键设置与统一 UI 完成

- 桌面窗口恢复上次尺寸和最大化状态，状态通过平台边界写入独立 JSON。
- 播放器快捷键提示迁入设置页，可修改并在冲突时交换绑定；播放器页面不再常驻提示栏。
- 统一全局 Dialog、PopupMenu、Menu、BottomSheet 和 SnackBar 视觉；播放器使用独立暗色主题。

## 2026-07-12 设置页信息架构增强完成

- 继续观看改为默认行为设置，减少逐条打开弹窗；默认直接恢复，保留从头和每次询问。
- 常用解码策略与高级具体后端分层，缓存统计改为可直接判断完成度和队列状态的数字列表。
- 下一步保持功能冻结，观察用户是否需要调整默认恢复行为或进入高级解码选项。

## 2026-07-11 第四阶段轻量播放体验完成

- 在不改变 filtered queue 来源的前提下提供随机、单曲循环和列表循环，默认顺序播放仍在队尾停止。
- 提供有限倍速档位和少量高频快捷键；全屏仅保留必要的队列上下文与标签入口。
- 字幕、音轨等专业播放器能力不预建，等待真实用户反馈和使用证据。

## 2026-07-11 批量 Relink 审计与失败恢复完成

- 已完成预览搜索、隐私安全审计摘要、SQLite 批事务提交和失败项定向重试。
- 已完成预览后目标消失→失败保留→文件恢复→同一预览重试成功的 focused test。
- 下一步：导出结构化审计文件、为超大批次增加分段事务上限，并接入诊断页历史记录。

## 2026-07-11 跨盘迁移与快照队列完成

- 已完成 C:→E: 20 条隔离媒体 soak，以及批量路径前缀替换预览/确认执行。
- 已完成播放快照按 videoId 合并与串行落库，离开播放器前保证 flush。
- 下一步：为批量预览增加搜索/导出审计摘要，并评估 SQLite 事务批量提交与失败重试策略。

## 2026-07-11 Stable Video Identity 播放状态第三阶段完成

- 已完成位置、总时长、完成态的 videoId 持久化，以及继续/从头选择。
- 已将最近播放升级为带进度的继续观看，并完成短视频动态完成阈值。
- 已补齐队列 missing 状态与播放器内 Relink，移动/重命名后继续沿用稳定用户数据。
- 下一步：真实跨盘迁移长时间 soak、批量路径替换预览和播放快照写入合并队列。

## 2026-07-11 Missing/Relink 用户闭环第一步

- 已完成 missing 条目可见列表和经过 fingerprint 校验的单文件 relink。
- 已完成播放器标签编辑键盘导航和 50,000 条当前队列性能基准。
- 下一步：批量路径前缀替换预览、冲突逐项确认、missing 搜索/排序和 relink 审计摘要。

## 2026-07-11 标签播放器差异化第二阶段完成

- 播放器内可完成收藏、manual 标签搜索/新增/移除，并快速使用最近和收藏标签。
- folder 标签只展示路径来源，不允许在播放器中删除。
- 当前队列支持轻量搜索定位；不扫描全库、不改变 filtered queue。
- 文件位置入口已进入桌面平台边界；下一步继续补 missing/relink UI 与播放器标签操作的真实大库耗时采样。

## 2026-07-11 Stable Video Identity 第一阶段完成

- 已完成 `videoId + fingerprint + mutable path` 兼容迁移，旧数据库无需清空。
- 已完成扫描期唯一 fingerprint 自动 relink、歧义拒绝合并和 missing 保留。
- 已完成标签、收藏、最近播放与播放进度随稳定 videoId 保留。
- 下一阶段：提供 missing 列表、单文件手动 relink 与批量路径前缀替换 UI；在真实跨盘目录迁移上补大库性能与冲突审计。

## 规划基准

产品和架构规划以此文件为准：

```text
<private-planning-document>
```

如果本项目文档与旧实现习惯冲突，以跨平台规划文件为准。当前应用状态只代表历史实现，不代表产品方向。

本项目不是 PotPlayer / VLC 替代品。目标是：

```text
标签驱动的本地视频发现播放器
= 本地扫描
+ SQLite 媒体库
+ 多级标签和分组标签
+ 标签别名搜索
+ 网页式筛选体验
+ 筛选结果播放队列
+ 基础播放器
+ 缓存和诊断
+ Flutter 跨平台壳
```

## 核心闭环

所有后续任务都要保护这条闭环：

```text
扫描本地文件夹
-> 派生初始文件夹标签
-> 添加 / 编辑播放器自有标签
-> 区分 folder / manual / rule / filename / import / auto 标签来源
-> 按分组标签和关键字筛选
-> 展示当前筛选 chips 和结果数量
-> 使用筛选结果作为播放队列
-> 播放器消费当前队列
-> 通过标签管理器 / 批量打标修正标签
-> 保持缩略图、媒体信息和诊断稳定
```

## 当前阶段非目标

当前阶段不要把主要精力放在：

- 字幕、音轨、逐帧、A-B loop、滤镜、旋转、高级播放控制。
- 标签发现体验稳定前的过度动画或纯视觉重设计。
- Web 支持。
- 深度 Android / iOS 支持。
- Windows 桌面行为稳定前替换当前桌面应用。

## 架构基线

已完成基线：`Architecture Baseline 0.5.25`

当前目标基线：`Architecture Baseline 0.5.26`

已完成 `0.5.25` 范围：

- `DesktopFileSystemAdapter` 已替换页面的生产文件操作，并把本地目录枚举移出 Widget build。
- `LibraryStore` 已实现真实 `LibraryRepository`，页面通过 `LibraryApplicationFacade` 发起用例。
- 具体文件系统、扫描、媒体探测、播放器和 FFmpeg 实现由 bootstrap composition root 统一选择。
- 文件系统模块、`LayoutSize`、`MediaDetails` 已迁移为独立 import；剩余 `part` 按依赖方向继续迁移。
- SQLite、标签筛选、stable identity、用户数据写入继续由 Dart 独占，不迁往 Rust/C++。

已完成 `0.3.0` 范围：

- 新增 `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider` 轻量接口 stub。
- 新增平台无关的 `TagGroup`、`TagItem`、`FilterQuery`、`PlaybackSession`、`CacheStatus`、`DiagnoseStatus` stub。
- 保持当前 Windows 行为不变。
- 保留当前 `part` 结构作为过渡状态。

已完成 `0.3.1` 范围：

- 在平台无关标签模型中增加标签别名。
- 在 `FilterQuery.matches` 中增加分组 / 排除标签语义。
- 定义不同组 AND、同组 OR、排除 NOT 的匹配行为。
- 让现有媒体库筛选经过 `FilterQuery`，同时保持当前 Windows 行为。

已完成 `0.4.0` 范围：

- 让接口契约对齐跨平台规划，而不是当前实现惯性。
- 新增或细化 `LibraryRepository`、`TagRepository`、`CacheRepository`、`PlaybackRepository` 边界。
- 增加 `compact`、`medium`、`expanded` 共享布局语义。
- 细化 `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider` 契约，不替换当前 Windows 实现。
- 评估导入迁移风险后，继续把 `part` 作为当前过渡结构。
- Architecture 阶段不重写播放器行为、SQLite 查询行为、缩略图队列行为或 UI 流程。

## 必须保持的平台边界

`FileSystemAdapter` 负责：

- 选择目录。
- 检查文件是否存在。
- 递归扫描视频。
- 在文件管理器中定位。
- 路径规范化和相对路径规则。

`PlayerBackend` 负责：

- 打开、播放、暂停、跳转、停止和释放。
- 播放状态流。
- 诊断状态流。
- 平台播放器实现细节。

`FFmpegBackend` 负责：

- 定位 FFmpeg / FFprobe。
- 可用性和版本报告。
- 媒体探测。
- 缩略图生成。
- 平台相关可执行文件或库访问。

`DatabaseProvider` 负责：

- 数据库打开和关闭。
- 数据库文件位置。
- schema 版本。
- migration 分发。

平台无关代码不能依赖 Windows、mpv、FFmpeg 可执行文件或具体文件系统 API。

## 标签发现设计

不要止步于当前一级 / 二级文件夹标签树。它只能作为初始来源，后续要建设分组标签。

推荐分组：

```text
作品：原神 / FGO / 东方 / 崩坏三
角色：丽莎 / 雷电将军 / 丝柯克 / miku
类型：3D / MMD / mod / vtuber
来源：Iwara / B站 / 本地录制
质量：720p / 1080p / 4K / H264 / H265
状态：收藏 / 未播放 / 已播放 / 缩略图异常 / 视频信息异常
```

筛选语义：

```text
不同组：AND
同组：OR
排除标签：NOT
关键字：文件名 / 路径 / 标签名 / 标签别名
```

示例：

```text
作品 = 原神
AND (角色 = 丽莎 OR 雷电将军)
AND (类型 = 3D OR MMD)
AND NOT NTR
```

## 目标模型

`TagGroup` 应逐步包含：

- `id`
- `name`
- `displayName`
- `sortOrder`
- `allowMultiSelect`
- `defaultLogic`：`sameGroupOr` 或 `sameGroupAnd`

`TagItem` 应逐步包含：

- `id`
- `name`
- `displayName`
- `groupId`
- `parentId`
- `color`
- `aliases`
- `usageCount`
- `isFavorite`
- `isHidden`
- `sortOrder`

`FilterQuery` 应逐步包含：

- `keyword`
- `includeTagIds`
- `excludeTagIds`
- `selectedGroupTags`
- `sortRule`
- `favoriteOnly`
- `unplayedOnly`
- `errorOnly`

`PlaybackSession` 应逐步包含：

- `sourceFilter`
- `queue`
- `currentIndex`
- `currentVideoId`
- `createdAt`

## 媒体库首页

媒体库首页是标签发现页，不是扁平标签浏览器。

推荐布局：

```text
顶部：搜索文件名 / 路径 / 标签 / 别名
左侧：分组标签筛选栏
中上：当前筛选 chips + 结果数量 + 清空 + 保存智能列表
中部：视频卡片网格
```

必须支持：

- 分组标签筛选。
- 当前筛选 chips，例如 `[原神 x] [丽莎 x] [3D x] [-NTR x]`。
- 每个标签的数量。
- 清空筛选。
- 排除标签。
- 保存当前筛选为智能列表入口。
- 当前筛选结果作为播放队列。

响应式规则：

```text
expanded：常驻左侧筛选栏
medium：可折叠筛选栏
compact：Drawer / BottomSheet 内筛选
```

## 播放页

播放器消费当前筛选结果，不应优先演变成通用专业播放器。

必须支持：

- 右侧队列绑定当前 `FilterQuery` / `PlaybackSession`。
- 当前序号显示，例如 `1/1661`。
- 队列标题或摘要展示当前筛选。
- 返回媒体库时不丢失筛选状态。
- 从右侧队列切换视频。
- 稳定的视频信息入口。
- 稳定的播放诊断入口。
- 后续可复制诊断信息。
- UI 依赖 `PlayerBackend`，不依赖具体播放器内部实现。

当前不优先：

- 字幕。
- 音轨。
- 逐帧。
- A-B loop。
- 滤镜。
- 复杂画面比例控制。

## 文件夹标签与稳定身份

保留当前文件夹派生的一/二级标签，但把它们视为初始 `folder` 来源标签。

目标身份模型：

```text
videoId = 稳定数据库身份
fingerprint = 文件 / 媒体身份
path = 当前可变位置
```

视频标签、收藏、播放记录和播放进度绑定到 `videoId`，不绑定可变 `path`。

未来 `video_tags` 关系应逐步包含：

```text
videoId
tagId
source: manual / folder / rule / filename / import / auto
locked
createdAt
updatedAt
```

规则：

- 手动标签不能因为文件移动而被删除。
- 文件夹标签可以按路径规则重新计算。
- 规则标签和文件名标签由各自系统重新计算。
- 重要标签可以 locked。
- 文件缺失时标记为 `missing`，不立即删除记录。
- relink 和批量路径替换在稳定身份设计之后推进。

## 新导入流程

推荐流程：

```text
监控文件夹出现新视频
-> 扫描发现它
-> 路径规则尽量派生 folder 标签
-> 无法识别时放入 未分类 / 待整理 / 新导入
-> 用户在应用内批量打标签
-> 未来可选：按标签移动文件
```

按标签移动文件是可选能力，不能成为分类的必要条件。

## Chat 执行计划

### Chat 1：架构与跨平台边界

任务文件：`docs/chat_tasks/CHAT_1_ARCHITECTURE.md`

负责架构、契约、模块边界、路由规则和版本记录。

允许：

- `main.dart`、core/model 边界、未来 import 迁移。
- `FileSystemAdapter`、`PlayerBackend`、`FFmpegBackend`、`DatabaseProvider`。
- repository 接口规划。
- 布局尺寸共享契约。
- 文档和版本记录。

禁止：

- 重写播放器行为。
- 重写 SQLite 查询行为。
- 重写缩略图队列。
- 大范围 UI 重设计。

下一步：

- 推进 `Architecture Baseline 0.4.1`，做低风险 import 迁移或逐步采用 `0.4.0` 契约。

### Chat 2：标签模型、筛选引擎与媒体库

任务文件：`docs/chat_tasks/CHAT_2_MEDIA_LIBRARY.md`

负责 SQLite、扫描、文件夹标签、分组标签模型、别名、筛选引擎和稳定身份规划。

P0：

- 实现分组标签模型。
- 实现别名。
- 实现 `FilterQuery`。
- 实现 AND / OR / NOT 筛选语义。
- 关键字搜索覆盖文件名、路径、标签名、别名。
- 结果数量。
- 把筛选结果传给播放器队列。

P1：

- folder / manual / rule / filename / import / auto 标签来源。
- `video_tags.source` 和 `locked`。
- 稳定 `videoId + fingerprint + mutable path`。
- `missing`。
- relink 和批量路径替换。

### Chat 3：媒体库标签 UI

任务文件：`docs/chat_tasks/CHAT_3_MEDIA_LIBRARY_TAG_UI.md`

负责标签发现功能 UI 和第一轮响应式布局。

P0：

- 分组筛选侧栏。
- 当前筛选 chips。
- 结果数量。
- 清空筛选。
- 排除标签 UI。
- 保存智能列表入口。
- 保持点击播放进入筛选队列。
- expanded / medium / compact 结构。

不要等最终视觉 polish 才建设标签发现 UI。

### Chat 4：播放器筛选队列与 PlayerBackend

任务文件：`docs/chat_tasks/CHAT_4_PLAYER.md`

负责播放稳定性、筛选队列消费、播放器诊断和 `PlayerBackend` 实现。

P0/P1：

- 播放器队列是当前筛选结果。
- 播放器显示类似 `1/1661` 的当前序号。
- 右侧队列标题概括当前筛选。
- 返回媒体库保留筛选状态。
- 右侧队列切换保持稳定。
- 播放页逐步迁移到 `PlayerBackend` 后面，不重写播放器核心。

### Chat 5：缩略图、诊断与 FFmpegBackend

任务文件：`docs/chat_tasks/CHAT_5_THUMBNAIL_DIAGNOSTICS.md`

负责缩略图队列、FFprobe 缓存、缓存诊断、失败、重试和 FFmpeg backend 实现。

P0/P1：

- 播放时保持队列负载保守。
- FFmpeg / FFprobe 通过 `FFmpegBackend` 调用。
- 展示可用性、版本和状态。
- 重试失败的缓存任务。
- 清除失败记录。
- 异常文件列表。
- 卡片式诊断页。

### Chat 6：标签管理器与批量打标

任务文件：`docs/chat_tasks/CHAT_6_TAG_MANAGER.md`

负责长期标签维护 UI 和批量操作。

P1：

- 标签管理页。
- 标签搜索。
- 创建 / 重命名 / 删除标签。
- 合并重复标签。
- 别名。
- 标签组。
- hidden / favorite / sort 标签状态。
- 给当前筛选结果批量打标签。
- 批量移除标签。

### Chat 7：响应式 UI 与平台 polish

任务文件：`docs/chat_tasks/CHAT_7_RESPONSIVE_UI.md`

负责核心标签 UX 可用后的最终视觉一致性和平台 polish。

P1/P2：

- 统一卡片、按钮、弹窗、侧栏风格。
- 媒体库浅色模式和播放器深色模式保持一致。
- 完成 `compact`、`medium`、`expanded` 布局。
- macOS / Linux 适配说明。

## 优先级表

### P0

1. 保持 Windows 桌面稳定。
2. 过渡期保留文件夹派生的一/二级标签。
3. 分组标签模型。
4. `FilterQuery`。
5. 组间 AND、组内 OR、排除 NOT。
6. 按文件名、路径、标签名、别名搜索。
7. 标签结果数量。
8. 当前筛选状态 chips。
9. 筛选结果成为播放队列。
10. 从播放器返回时保留筛选状态。
11. 核心平台边界。

### P1

1. 区分 folder / manual 标签来源。
2. `video_tags.source` 和 `locked`。
3. 稳定身份：`videoId + fingerprint + mutable path`。
4. Missing 状态。
5. Relink。
6. 批量路径替换。
7. 标签管理器。
8. 批量打标。
9. 保存筛选 / 智能列表。
10. 最近播放 / 继续播放。
11. 缓存失败重试。
12. 异常文件列表。
13. 诊断卡片。
14. 初始响应式布局。

### P2

1. 自动标签规则。
2. 标签导入 / 导出。
3. 高级搜索语法。
4. 可选按标签移动文件。
5. 高级指纹去重。
6. 高级播放器功能。
7. macOS / Linux 适配。
8. Android / iOS 探索。
9. Web 探索，低优先级。

## 版本规则

- 每个 Chat 拥有 `docs/chat_tasks/` 下的一个任务文档。
- Chat 文档必须跟随本 roadmap 和外部跨平台规划。
- 如果实现与外部规划冲突，更新实现，或在文档中记录临时偏离原因和 owner。
- 修改 `src/core`、平台边界、schema、身份模型或共享服务契约时，必须更新 `ARCHITECTURE.md`。
- 每个实现 Chat 都运行：

```powershell
flutter analyze
flutter build windows --debug
```

## 新对话规则

新开 Chat 时，使用匹配的 `docs/chat_tasks/CHAT_*` 提示。新对话必须先阅读：

- `PROJECT.md`
- `ARCHITECTURE.md`
- `CURRENT_TASK.md`
- `ROADMAP.md`
- `<private-planning-document>`
- 自己的 `docs/chat_tasks/CHAT_*.md`
# 2026-07-27 Windows 专业画质后端增量路线

- [x] 建立 `PlayerService → PlayerBackend → MediaKit / Windows libmpv` 边界。
- [x] 原生 D3D11VA 非 copy 路径启用并由驱动确认 NVIDIA RTX Super Resolution。
- [x] 增加可持久化、可撤销的 Windows 渲染器选择；用户已可在下次进入播放器时
  启用原生 libmpv/D3D11，非 Windows 或硬解关闭时回退 MediaKit。
- [ ] 补齐原生渲染器跨 DPI 长期门禁，再评估 Windows“自动”档是否默认选择
  libmpv；当前自动档继续 MediaKit。
- [ ] 增加“关闭 / 显示同步插值 / 运动补帧插件”流畅度档位，禁止把 mpv
  `interpolation` 宣传为 AI 补帧。
- [ ] 建立带许可证与固定摘要的 GLSL/libplacebo 着色器包格式。
- [ ] 在不分发 NVIDIA 文件的本机插件中接入 RTX Video SDK Artifact Reduction、
  Super Resolution 与 SDR→HDR，并保留非 NVIDIA 回退。
