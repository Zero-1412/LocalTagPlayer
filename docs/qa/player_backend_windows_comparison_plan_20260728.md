# Windows 三后端对照测试方案（MediaKit / fvp / 当前 MPV）

日期：2026-07-28
状态：设计完成，尚未执行
适用平台：Windows 10 / 11 x64

## 1. 目标

在不修改生产分支业务代码、不改变 `PlayerBackend` contract、不改变 filtered queue
语义的前提下，对以下三个后端进行可重复、可审查的 Windows 对照测试：

| 后端 ID | 测试对象 | 边界 |
| --- | --- | --- |
| `mediaKit` | 当前 `MediaKitPlayerBackend` | 使用正式 `PlayerPage` 与现有 MediaKit 依赖 |
| `fvp` | 基于 `fvp` / libmdk 的 QA-only `PlayerBackend` 适配器 | 仅在隔离临时克隆中应用测试补丁，不提交、不进入安装包 |
| `windowsNativeMpv` | 当前 `WindowsNativePlayerBackend` 的 libmpv Windows 路径 | 使用正式 `PlayerPage` 与当前 MPV 渲染路径 |

“当前后端”在本方案中明确指 `WindowsNativePlayerBackend`，不把 MediaKit 重复记为
第三个候选。若执行时产品默认后端已经改变，仍按上述实现身份分组，不按设置页显示名称
重新解释历史数据。

`windowsNativeMpv` 的主结果必须使用 `baselineCommit` 上正式可交付的 MPV surface。
如果同一提交同时存在 Flutter Texture 与显式 child HWND QA 路径，两者必须写成独立
`surfaceMode` 分组；child HWND 只补充其专属硬件能力证据，不得混入正式 Texture 的
首帧、CPU/GPU、内存或稳定性分位数，也不增加成第四个后端参与总分。

本方案回答五个问题：

1. 三个后端分别能否稳定播放目标容器、编码、分辨率和异常文件。
2. 用户可感知的首帧时间、连续切换和 filtered queue 跳转是否可靠。
3. CPU、GPU、显存、进程内存和帧呈现压力有何差异。
4. 实际硬件解码、渲染、HDR、多 GPU 与回退路径支持到什么程度。
5. 性能收益是否足以覆盖新增二进制、许可证、维护和迁移成本。

## 2. 第一性原理与非目标

```text
Product goal protected:
  测试服务于标签驱动的本地视频发现与连续播放，不把产品改造成专业播放器。

Core loop part protected:
  媒体库当前可见筛选结果 -> sourcePlaylist -> PlayerPage -> PlayerBackend。

Must not change:
  SQLite、FilterQuery、TagQueryService、filtered queue 内容/顺序、当前 index、
  返回媒体库的筛选状态、缩略图/媒体详情队列、用户数据和生产安装包。

Smallest safe change:
  生产工作树只增加测试设计和未来测试资产；fvp 只在隔离临时克隆中适配。

Fewest safe tokens:
  复用现有稳定性矩阵、正式 PlayerPage 测试入口和已有进程指标采集方式。
```

本轮不评估字幕、音轨切换、逐帧、A-B loop、VR、网络直播、DRM 或运动补帧。
HDR 只作为硬件/色彩链能力检查，不扩展产品功能。

## 3. 受保护行为清单

所有后端必须通过同一组页面级证据，组件能够单独运行不等于通过：

- 播放器接收媒体库当前可见筛选结果，不能回退到全局媒体库。
- `sourceVideoIds`、右侧队列 ID 与顺序在切换前后保持一致。
- 当前项、实际已打开项和 `playingIndex` 一致，显示语义保持 `1/N`。
- 右侧二级标签切换只能在来源 filtered queue 内产生子队列。
- 返回媒体库后保留原筛选、搜索、排序和滚动状态。
- 正常、异常、超时和被更新请求取消后都不能残留 pending open。
- 失败文件之后打开正常文件，后端必须恢复，不要求重启应用。
- 连续切换期间后台缩略图任务仍遵守现有降负载规则。
- 全屏、队列显隐、控制层、错误面板和返回路径保持可达。

获授权删除清单：无。
任何后端若只能通过删除上述行为完成接入，直接判定不适合，不进入性能比较。

## 4. 隔离与可复现构建

### 4.1 固定基线

开始执行前必须满足：

- 生产工作树干净，或明确选择一个已提交的 `baselineCommit`。
- 三组结果记录相同的 commit、Flutter/Dart 版本、`pubspec.lock` SHA-256、
  Windows SDK、MSVC、CMake、GPU 驱动和测试素材 manifest SHA-256。
- 三个后端使用独立工作目录、独立 `build` 目录和独立输出目录。
- Release 性能测试与 Debug 诊断测试分开，不能把 Debug 数值用于后端排名。

当前工作树存在未提交播放器改动时不得直接生成正式对比结论。应先由改动所有者完成
验证和提交，再从同一 `baselineCommit` 建立隔离克隆。

### 4.2 fvp 隔离适配

fvp 不写入生产 `pubspec.yaml`，也不修改正式组合根。执行器应：

1. 从 `baselineCommit` 创建临时克隆。
2. 在临时克隆中应用版本固定、带 SHA-256 的 QA 补丁。
3. 补丁只允许增加 fvp 依赖、QA-only `FvpPlayerBackend`、组合根测试注入和诊断映射。
4. 适配器必须实现现有 `PlayerBackend` 最小 contract，队列仍由 PlayerPage 持有。
5. 记录补丁 SHA-256、fvp 版本、libmdk 版本、下载地址和许可证清单。
6. 测试结束删除临时克隆；不得把 fvp 二进制复制到生产 bundle。

如果 fvp 无法在不改变 filtered queue 或页面生命周期的情况下适配，结果记为
`integration-blocked`，不能用独立 demo 的播放成功冒充产品链路通过。

### 4.3 两种包体积口径

必须同时报告：

- `shippingBundleBytes`：当前真实产品 Release bundle，包含实际会随产品分发的全部后端。
- `exclusiveBackendBundleBytes`：隔离构建中只保留该后端所需二进制的 Release bundle。

同一个多后端安装包中切换设置不会改变包体积，因此不能把 MediaKit 和 MPV 设置态的
同一目录重复测量后宣称两者体积相同。体积统计需分别给出：

- 整个 Release 目录；
- 排除 `.pdb` 后的可分发目录；
- 压缩归档或 Inno Setup 安装包；
- 相对不含视频后端的空壳构建增量；
- 原生 DLL、codec/SDK 与 Flutter/Dart 资产分项。

## 5. 测试环境

每轮开始写入 `environment.json`：

```text
Windows edition/build
CPU 型号、物理核、逻辑核
内存容量与频率
GPU 列表、显存、驱动、WDDM、活动 adapter LUID
显示器数量、分辨率、刷新率、缩放比例、HDR 开关
媒体所在磁盘型号、接口、文件系统、可用空间
电源模式、电源连接状态
Flutter/Dart、MSVC、Windows SDK、CMake
后端、依赖版本、commit、补丁 SHA-256
```

控制条件：

- 接通电源，固定 Windows 电源模式；不在不同电源模式之间混用数据。
- 测试前空闲 60 秒，记录而不静默关闭 Defender、录屏、同步或驱动增强。
- 固定窗口尺寸、显示器、刷新率和系统缩放；跨 DPI 作为单独阶段。
- 绑定精确 PID，不能按进程名聚合其它 Flutter、mpv 或测试进程。
- 每个后端至少五轮；采用拉丁方顺序轮换后端，避免温度与缓存顺序偏差。
- 主结论使用 Release 构建；Debug 只用于属性、日志和页面语义取证。

冷启动分两种口径：

- `appCold`：新进程、新后端实例，允许 Windows 文件缓存存在，是默认可重复口径。
- `diskWarm`：同一文件已经播放过，再新建后端实例。

不得使用来源不明的“清空 standby list”工具制造磁盘冷启动。需要真正磁盘冷启动时，
单独重启 Windows，并把该轮标为 `rebootCold`。

### 5.1 采集工具与统一时钟

执行器必须把工具版本和 SHA-256 写入 `execution-plan.json`：

- `ffprobe`：生成素材 manifest，并在播放前复核容器、codec、profile、bit depth、
  FPS、时长和 HDR 元数据。
- PresentMon：采集目标 PID 的 present、displayed FPS 和 frame time；固定版本与参数。
- Windows PDH/Performance Counter：以 PID 映射采集 Process、GPU Engine 和
  GPU Process Memory，不能依赖可能重名的 `_Total` 或进程实例名称。
- `Get-Process -Id <pid>` 或等价 Win32 API：复核 Working Set、Private Bytes、
  handles 和线程数。
- Windows Graphics Capture：仅采集应用窗口视频 ROI，用于用户可感知首帧与
  surface 正确性，不采集桌面其它区域。
- WER 与 Windows Application Error：按测试时间窗和精确 PID 检查 crash。

测试驱动、PresentMon 和窗口捕获都必须记录 `QueryPerformanceCounter` 频率及启动同步
标记。汇总器先把各数据源换算到同一单调时间轴，再计算首帧和切换延迟；UTC 只用于
文件关联。无法完成 QPC 对齐时，首帧结果标记为 `timing-inconclusive`，不能参与排名。

CPU 统一换算：

```text
cpuNormalizedPct =
  Process % Processor Time / logicalProcessorCount
```

保留原始值和归一化值。GPU 需分别汇总目标 PID 的 `engtype_3D`、`engtype_Copy`、
`engtype_VideoDecode` 与 `engtype_VideoProcessing`，不能把整机 GPU 总占用写成播放器
占用。

## 6. 素材矩阵

### 6.1 正常素材

每段素材 30 至 120 秒；除遗留 AVI 外，同时准备可重复生成的合成样本和匿名自然片源。

| ID | 容器 | 视频编码 | 规格 | 目的 |
| --- | --- | --- | --- | --- |
| `N01` | MP4 | H.264 High | 1080p30、8-bit、AAC | 最小兼容基线 |
| `N02` | MKV | H.264 High | 1080p60、8-bit、AAC | MKV 与高帧率 |
| `N03` | MOV | H.264 High | 1080p、VFR、AAC | MOV 与可变帧率 |
| `N04` | AVI | MPEG-4 Part 2 | 720p30、MP3 | 遗留容器兼容 |
| `N05` | MP4 | HEVC Main | 1080p30、8-bit、AAC | HEVC 基线 |
| `N06` | MKV | HEVC Main10 | 4K60、10-bit、AAC | 4K、Main10、硬解压力 |
| `N07` | MOV | HEVC Main10 | 4K30、10-bit、AAC | MOV/HEVC |
| `N08` | MP4 | AV1 Main | 1080p30、8-bit、AAC | AV1 解码能力 |
| `N09` | MKV | AV1 Main | 4K60、10-bit、AAC | AV1 4K 硬件能力 |
| `N10` | WebM | VP9 Profile 0 | 1080p60、8-bit、Opus | VP9 基线 |
| `N11` | WebM | VP9 Profile 2 | 4K30、10-bit、Opus | VP9 10-bit |
| `N12` | MP4 | H.264 High | 4K60、高码率、AAC | 高码率 4K 压力 |
| `N13` | MKV | HEVC Main10 HDR10 | 4K60、BT.2020/PQ | HDR/色彩链检查 |
| `N14` | MP4 | H.264 | 1080p、无音轨 | 无音轨恢复 |
| `N15` | M4A/黑屏视频对照 | AAC 或静态视频 | 短时 | 区分音频推进与真实视频首帧 |

`N04` 用来验证 AVI，而不是把 MPEG-4 Part 2 纳入产品的必需硬解能力。每段素材的
`manifest.json` 必须包含相对路径、SHA-256、容器、codec/profile、pixel format、
bit depth、宽高、实际/平均 FPS、时长、码率、音轨和 HDR 元数据。

### 6.2 异常素材

| ID | 异常 | 期望 |
| --- | --- | --- |
| `E01` | 0-byte `.mkv` | 有界失败，无崩溃 |
| `E02` | 截断 MP4，`moov` 缺失 | 有界失败并显示原因 |
| `E03` | 截断 MKV 尾部 | 能播到损坏点或有界失败 |
| `E04` | 随机字节伪装成 `.avi` | 有界失败 |
| `E05` | 只有音轨但扩展名为视频 | 不得把音频推进误记为视频首帧 |
| `E06` | 不存在路径 | 立即失败 |
| `E07` | 打开过程中被重命名/移走 | 不崩溃，下一正常文件可恢复 |
| `E08` | 无权限文件 | 明确失败，不无限 loading |
| `E09` | 异常时间戳/长 GOP | seek 与首帧不永久停滞 |
| `E10` | 后端不支持的 codec | 明确区分“不支持”与“文件损坏” |

异常文件不得进入仓库；只提交生成脚本和 manifest 模板，实际文件位于 `.local/qa`。

## 7. 测试阶段

### 7.1 环境与硬件预检

先验证：

- 测试样本 SHA-256 与 manifest 一致。
- 显卡和驱动支持哪些 D3D11/DXVA 解码配置。
- 所有后端实际选择同一块 GPU；多 GPU 时记录 adapter LUID。
- 后端报告值、Windows GPU Engine 和实际视频推进三者能互相印证。
- 硬件不支持的 codec 标记为 `host-unsupported`，不能算作后端失败。

### 7.2 首帧时间

同时记录三个时间，禁止只用 `openPath` Future 完成冒充首帧：

```text
openAcceptedMs:
  PlayerPage 接受新请求到 PlayerBackend.openPath 返回。

firstProgressMs:
  请求发出到媒体 position 首次稳定大于 0。

firstPresentedFrameMs:
  请求发出到 Windows 最终窗口视频 ROI 首次出现目标帧。
```

`firstPresentedFrameMs` 是用户感知主指标。采集优先使用 Windows Graphics Capture
或 PresentMon/后端 presented-frame counter；若后端无法暴露计数，则以 60Hz 以上
窗口捕获检测视频 ROI 从占位帧切换到带唯一色卡的第一帧。音频推进、texture ID 创建、
duration 可用和“正在播放”状态都不能单独作为首帧证据。

每个正常样本、每后端执行：

- `appCold` 五次；
- `diskWarm` 五次；
- 报告 median、P90、P95、max、超时和失败次数；
- 1080p 与 4K 分组，不能混成一个平均数。

### 7.3 稳态播放与资源

- 每个正常样本先播放 60 秒。
- `N06`、`N09`、`N12`、`N13` 各播放 5 分钟。
- 每个候选后端继续复用现有 30 分钟长播门禁。
- 每 500ms 采样进程和 GPU 指标，每 2 秒采样后端诊断。

必须记录：

```text
CPU raw / logical-core-normalized median、P95、max
Working Set、Private Bytes、Commit Size
GPU 3D / Copy / Video Decode / Video Processing 利用率
GPU dedicated/shared memory
presented FPS、frame time P50/P95/P99
decode/output/total dropped frames
buffering、video stalled、audio stalled、AV sync
实际 hwdec、renderer/API、adapter LUID
```

CPU/GPU 使用率是同机相对排名指标，不设置跨机器统一绝对冠军线。掉帧、停滞和恢复
属于可靠性硬门。

### 7.4 连续切换

分成两种，避免“只打开最后一项”的正确优化掩盖逐项切换失败：

1. `latest-request burst`
   - 12 个正常样本组成队列；
   - 每 70ms 发出一次跳转，共 100 次；
   - 执行 10 轮；
   - 每轮只要求最终请求被打开，但要求队列身份、顺序和最终 index 完全正确。

2. `settled switch`
   - 12 个正常样本轮换；
   - 等待当前项首帧后再切下一项，共 50 次；
   - 每次都必须产生首帧；
   - 记录每次切换 TTFF、失败、超时、后端重建和资源残留。

`switchFailureRate`：

```text
失败的预期打开次数 / 总预期打开次数
```

被 latest-request 正常取消的旧请求不算失败，但必须单独记录
`supersededRequestCount`，且不能遗留 loading、纹理、句柄或错误面板。

### 7.5 filtered queue 跳转

复用正式 `PlayerPage` 链路，新增结果必须继续兼容现有
`buildStabilitySnapshotForTest` 与 `jumpToQueueIndexForStabilityTest` 语义：

- 小队列：1、2、12 项。
- 大队列：128、1661 项；允许复用样本路径，但每个逻辑项目使用唯一 `videoId`。
- 顺序跳转、首尾跳转、随机跳转各 100 次。
- 右侧二级标签切换至少 30 次，子队列只能来自原 `sourcePlaylist`。
- 返回媒体库再进入播放器 20 次，筛选状态、原队列和当前项保持一致。
- 切换后核对 `sourceVideoIds`、`queueVideoIds`、`currentVideoId`、
  `openedVideoId`、`playingIndex`、pending/open failure。

任何一次来源队列漂移、顺序改变、index 错位或回退全局媒体库，都直接判定该后端
页面集成为失败，不参与性能冠军评选。

### 7.6 异常文件与恢复

每种异常文件、每后端执行 10 次：

1. 从正常文件跳到异常文件。
2. 等待明确失败或超时。
3. 立即跳到另一正常文件。
4. 验证正常文件在阈值内产生首帧，队列和 index 正确。

记录：

- `failureDetectionMs`；
- 错误分类和用户可见原因；
- loading 是否收口；
- 是否发生 crash、hang、WER、原生异常或未处理 Dart 异常；
- 恢复正常文件的 `firstPresentedFrameMs`；
- 后端是否需要重建。

### 7.7 内存与生命周期

完成 100 次 burst、50 次 settled switch 和 20 次 Route 进入/退出后：

- 记录 Private Bytes、Working Set、GPU committed、GDI/USER handles、
  线程数、纹理数和后端实例数。
- 空闲 30 秒后再次采样。
- 检查 WER、Application Error 和原生日志。

允许缓存形成平台，但不允许资源随每次切换单调增长。若无法证明缓存上限，结论标记为
`memory-inconclusive`，不能写“无泄漏”。

### 7.8 包体积

每个隔离工作目录执行相同 Release 命令并记录完整命令行。构建前删除的目标只能是该
隔离工作目录内已验证的 `build`，不得操作真实工作树或共享缓存。

输出：

```text
bundleTotalBytes
bundleWithoutSymbolsBytes
installerBytes
compressedArchiveBytes
backendNativeBytes
codecAndSdkBytes
incrementOverShellBytes
```

同时生成按文件大小降序的前 30 项，识别 libmpv、libmdk、FFmpeg、MediaKit 和
VC runtime 是否被重复打包。

## 8. 硬件功能支持度

每项能力使用证据等级，不接受 README 声明直接算通过：

| 状态 | 含义 |
| --- | --- |
| `H` | 已由后端属性、GPU Engine 和实际播放共同确认硬件路径 |
| `S` | 硬件路径不可用，但软件回退已稳定通过 |
| `N` | 后端明确不支持 |
| `B` | 后端声称支持，但当前主机硬件不支持，无法验证 |
| `U` | 数据不足 |

矩阵至少包含：

| 能力 | 权重 | 验证方式 |
| --- | ---: | --- |
| H.264 8-bit 硬解 | 3 | 实际 hwdec + Video Decode engine + 1080p/4K |
| HEVC Main/Main10 硬解 | 3 | 同上，区分 8/10-bit |
| AV1 8/10-bit 硬解 | 2 | 同上，区分主机是否支持 |
| VP9 Profile 0/2 硬解 | 2 | 同上 |
| 4K60 稳定呈现 | 3 | FPS、P99 frame time、掉帧、停滞 |
| D3D11 原生渲染 | 2 | renderer/API 与实际 adapter |
| 零拷贝或 copy 路径 | 1 | 明确记录 zero-copy/copy/software，不按名称猜测 |
| HDR10 输入识别 | 1 | BT.2020/PQ 元数据与后端属性 |
| HDR 输出或可靠 tone map | 2 | 显示器状态、输出色彩链和同尺寸截图 |
| 多 GPU 精确选择 | 2 | adapter LUID 与 Windows 进程 GPU 实例一致 |
| 硬解失败安全回退 | 2 | 禁用/不支持硬解后仍可恢复播放 |
| 跨 DPI/刷新率稳定 | 1 | 真实双显示器移窗；模拟 metrics 不能替代 |
| 驱动增强可验证性 | 1 | 只记录实际 active/unsupported，不读取或修改全局设置 |

`hardwareSupportRate` 只在主机实际支持的分母内计算：

```text
已验证 H 项权重 / 当前主机可验证能力权重
```

另行报告 `softwareFallbackRate`。不能用高软件回退率包装成高硬件支持率，也不能因为
测试机没有 AV1 硬解而惩罚后端。

## 9. 数据目录与报告结构

```text
.local/qa/player-backend-comparison/<run-id>/
  environment.json
  sample-manifest.json
  execution-plan.json
  mediaKit/
    events.jsonl
    process-metrics.csv
    gpu-metrics.csv
    presentmon.csv
    backend-report.json
    screenshots/
  fvp/
    ...
  windowsNativeMpv/
    ...
  package-size.json
  hardware-capability-matrix.json
  comparison-summary.json
  comparison-summary.md
```

事件与指标都使用 UTC、单调时间和精确 PID。报告中只保存匿名 sample ID，不写用户
媒体 basename、绝对路径、标签名或其它个人数据。

后端报告最小字段：

```json
{
  "schemaVersion": 1,
  "baselineCommit": "<sha>",
  "backend": "mediaKit | fvp | windowsNativeMpv",
  "buildMode": "release",
  "sampleId": "N06",
  "runIndex": 1,
  "openAcceptedMs": 0,
  "firstProgressMs": 0,
  "firstPresentedFrameMs": 0,
  "actualHwdec": "string",
  "renderer": "string",
  "adapterLuid": "string",
  "switchFailureRate": 0.0,
  "queuePreserved": true,
  "cpuNormalizedP95": 0.0,
  "gpuVideoDecodeP95": 0.0,
  "privateBytesP95": 0,
  "gpuDedicatedBytesP95": 0,
  "droppedFrames": 0,
  "crashCount": 0,
  "hangCount": 0
}
```

## 10. 门禁与排名

### 10.1 必须门禁

任一项失败即淘汰，不用综合分数抵消：

- crash、hang、WER 或未处理原生异常为 0。
- settled switch 失败率为 0/50。
- 10 轮 burst 最终目标、队列顺序和 index 全部正确。
- filtered queue 来源漂移、顺序错误、回退全局列表为 0。
- 异常文件后正常文件恢复成功率 100%。
- 1080p H.264 基线全部产生首帧。
- 当前主机支持的 H.264/HEVC 必需硬解路径可用，或明确、稳定地安全回退。
- 4K60 五分钟阶段无停滞，掉帧率不高于 0.1%。
- 30 分钟长播符合现有最大总掉帧预算。
- fvp 许可证、二进制来源与再分发条件能够完成审查。

首帧建议门槛：

| 场景 | P95 |
| --- | ---: |
| 1080p `appCold` | 不高于 1500ms |
| 1080p `diskWarm` | 不高于 750ms |
| 4K `appCold` | 不高于 2500ms |
| 异常文件失败检测 | 不高于 5000ms |
| 异常后正常文件恢复首帧 | 不高于 2500ms |

如果所有后端都无法达到门槛，应先确认测试硬件与首帧采集误差，不把相对最优者自动
宣布为可交付。

内存门槛：

- 100 次快速切换后，空闲 30 秒的 Private Bytes 增量不超过基线的 10% 或
  64 MiB，取较大者。
- GDI/USER handle、纹理和后端实例不能随切换次数单调增长。

### 10.2 通过门禁后的评分

| 维度 | 分值 |
| --- | ---: |
| 稳定性、异常恢复、队列正确性 | 30 |
| 格式与编码覆盖 | 20 |
| 首帧与连续切换延迟 | 15 |
| CPU/GPU/内存与帧稳定性 | 15 |
| 硬件功能支持度 | 10 |
| 包体积、许可证、维护与集成成本 | 10 |

评分只用于通过硬门的候选。原始分位数、失败数和能力矩阵必须与总分一起展示。

## 11. 选型规则

默认策略是保留已经通过门禁的当前实现，不因微小基准差异迁移。建议更换后端至少满足：

1. 所有必须门禁通过。
2. 不降低格式覆盖、队列正确性、异常恢复和用户可见错误质量。
3. 至少两项关键指标达到超出测量噪声的改进：
   - 首帧 P95 改善至少 15%；
   - 4K CPU P95 改善至少 15%；
   - 内存 P95 改善至少 15%；
   - 或新增当前必需且稳定的硬件 codec 支持。
4. 包体积和许可证成本可接受。
5. 仍能放在 `PlayerBackend` 边界后，不要求 UI 或过滤引擎理解后端特性。

可能结论不局限于“选一个”：

- MediaKit 作为跨平台兼容后端，Windows MPV 作为增强后端。
- fvp 只有在显著改善 4K/硬解/首帧且许可证可交付时进入后续产品评估。
- `video_player_win` 等其它方案不在本轮三后端范围内，不能临时混入数据。

## 12. 建议执行顺序

1. 固定并记录 `baselineCommit`。
2. 生成/校验正常与异常素材 manifest。
3. 扩展现有双后端矩阵的数据 schema，但不改变原门禁语义。
4. 在隔离临时克隆完成 fvp QA-only 适配。
5. 先跑每后端 15 秒 smoke，确认指标和首帧采集真实有效。
6. 跑格式、首帧、异常恢复、连续切换和 filtered queue。
7. 跑 4K 五分钟与每后端 30 分钟长播。
8. 做真实双显示器跨 DPI、HDR 与多 GPU 人工门禁。
9. 构建三套 Release 独占 bundle 并统计体积。
10. 生成匿名 JSON/Markdown 汇总，执行独立只读复核后再形成选型建议。

## 13. 本设计的已知限制

- `<private-planning-document>` 在仓库中仍是占位符，本轮无法读取；执行选型前若获得
  外部跨平台计划，必须重新检查平台和许可证约束。
- 单台硬件不能证明所有 GPU/驱动组合。正式选型至少应补一台 Intel 核显和一台
  非 NVIDIA 独显机器。
- Windows Graphics Capture/PresentMon 首帧采集需先用已知时间码样本校准误差。
- fvp 的性能声明不能代替本项目实测；libmdk 二进制与再分发条件必须独立审查。
- 真实跨 DPI、HDR 输出和驱动增强不能由模拟 Flutter metrics 代替。

## 14. 对抗式审查模板

```text
schema: unchanged
FilterQuery / TagQueryService: unchanged
filtered queue: unchanged; source/content/order/index evidence attached
thumbnail/media queue: unchanged
user data: preserved; test uses isolated settings and anonymous samples
PlayerBackend contract: unchanged in production; fvp adapter exists only in temporary clone
protected behaviors: preserved
authorized deletion: none
unauthorized feature removal: none
mount and reachability: PlayerPage-level evidence required for every backend
hardware claims: measured / host-blocked / unsupported, README-only claims rejected
package and license: backend-exclusive bundle and redistribution record attached
validation: commands, exit codes, report paths and remaining manual gates recorded
```
