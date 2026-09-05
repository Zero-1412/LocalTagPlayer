# 2026-09-05 查询正确性、PR 门禁与隔离基线

## 范围与受保护行为

基于 ec03948 修复查询候选，不修改 schema v2、FilterQuery/TagQueryService 语义、
folder/manual/locked 来源、来源 filtered queue、播放器默认后端或用户媒体文件。
页面入口、菜单、快捷键、持久化和返回路径没有删除授权，本轮不删除或替换 UI 子树。

## 正确性证据

- 先添加真实 SQLite 和异步乱序测试，旧实现 9 项失败，15 项通过。
- Unicode 反例：`😀a` 的 UTF-16 长度为 3、码点数为 2；内存命中而旧 FTS 漏项。
- 别名反例：`say"hello`、`back\slash` 被 JSON 转义后索引，无法匹配用户输入。
- 异步反例：旧候选在新 revision 配置后返回，污染新缓存；取消、dispose 和 epoch 失效后仍排序/诊断。
- 修复使用码点长度、JSON 解码后的别名、异步返回后的身份检查。保留最终 Dart 校验、失败回退和发布检查。
- 新增/改名/别名修改/删除/再新增、损坏 JSON 回滚与重试均以真实 SQLite 验证。
- 删除源码字符串式 tag ID 测试，改为真实查询 stable-ID 集合断言。

## 索引测量与优化依据

使用历史 QA profile 的 11,164 条记录，经 SQLite backup API 生成 `.local/qa/query-20260905`
副本。不直接复制运行中用户数据库，不修改用户 profile。测量机器 Flutter 3.44.4 / Dart 3.12.2，
Windows；以下是 Dart JIT/测试模式的索引数据，不是 UI Profile 时延保证。

| 场景 | 修复合并前 | 合并后 |
| --- | ---: | ---: |
| 同 revision 并发请求数 | 8 | 8 |
| 真实重建事务数 | 8 | 1 |
| 整组完成时间（单次观察） | 5281.772 ms | 801.322 ms |
| 30 次热 ensureFresh P50 | 0.066 ms | 0.057 ms |
| 热 ensureFresh P95 | 0.088 ms | 0.114 ms |
| 热 ensureFresh P99 | 0.183 ms | 0.227 ms |

热路径微小耗时未证明提升；优化依据是消除 7 次重复完整重建。并发回归先确认旧实现
8 次重建，再验证新实现 1 次；跨 revision 串行、失败共享和恢复重试有真实事务测试。
不引入增量索引或新 schema。过期候选返回后的额外排序次数由回归确认从 1 次降为 0 次；
已开始的 SQLite 工作仍自然收尾，不能把请求失效描述为数据库操作已取消。

真实库现有查询基准另测得：首次候选索引 388.783 ms，完整过滤平均 75.849 ms，
候选加最终校验平均 0.586 ms；3 个词、每词 5 次，stable-ID 集合相同。
这些是有限样本，不替代冷/热交互 P95/P99 与扫描并发基线。

复测命令（先准备带 `.query-baseline-profile` 的隔离副本）：

```powershell
$env:PATH = (Resolve-Path windows/tools/sqlite).Path + ';' + $env:PATH
dart run tool/benchmark_library_search_index.dart <隔离profile> <结果.json>
$env:LOCAL_TAG_PLAYER_DATA_DIR = '<隔离profile>'
$env:LOCAL_TAG_PLAYER_BASELINE_SCAN = '1'
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/library_query_interaction_baseline_test.dart -d windows
```

## CI 与分批状态

`.github/workflows/core-regression.yml` 固定 Flutter 3.44.4，在 lib/test/windows/依赖变更的
PR 与 push 运行真实查询、过滤队列、稳定身份、Store 备份恢复、侧栏统计和架构测试。
工作流源码可确认触发范围；提交 a80d6f5 已实际触发且通过
[核心回归](https://github.com/Zero-1412/LocalTagPlayer/actions/runs/33940430933)、
[Agent 治理](https://github.com/Zero-1412/LocalTagPlayer/actions/runs/33940430935) 和
[macOS/Linux 桌面验证](https://github.com/Zero-1412/LocalTagPlayer/actions/runs/33940430941)。
这验证工作流执行成功，不推断分支保护已配置。

1. 查询正确性：实现和回归已完成。
2. CI：门禁已接入，路线图依赖状态已同步。
3. 大库交互：Profile 页面功能路径已执行通过；操作时延达到当前目标，但分阶段慢帧、冷启动重复
   样本和长跑尚未闭环，不能宣布完整 L2/L3 性能通过。
4. 索引优化：同代次合并已测量并实现；增量索引暂不推进。
5. 恢复/交付：旧库迁移、备份与数据恢复由 focused/full tests 验证；安装升级、原生目录选择器
   取消和系统级点击仍需独立环境证据。不得覆盖当前正在运行的用户安装版本来凑验收。

## 验证记录

本机全量 710 项通过、4 项既有跳过；flutter analyze 0 问题，Windows Debug build 通过。
Agent eval 目录验证和 29 项工具单测通过。最终增量静态分析 0 问题，恢复正式入口的 Windows Debug 构建通过。
所有 Dart 格式化命令成功退出，无格式化超时。

Profile 使用 Ryzen 9 7900X、约 64 GB 内存、RTX 4070 SUPER、Windows 11、3840×2160
显示器、150% 缩放；应用逻辑 surface 约 1585×863。MediaKit Texture 保持正式默认。
历史副本缓存已预热，OS 磁盘缓存未控制；下表不冒称系统冷启动统计。

| 操作 | N | P50 ms | P95 ms | P99 ms |
| --- | ---: | ---: | ---: | ---: |
| 本次 profile 启动 | 1 | 785.913 | 785.913 | 785.913 |
| 本次首次搜索（含索引） | 1 | 968.482 | 968.482 | 968.482 |
| 热搜索 | 29 | 139.715 | 171.538 | 180.568 |
| 排序 | 20 | 138.245 | 151.509 | 153.936 |
| 标签筛选 | 20 | 168.257 | 206.642 | 207.422 |
| root 进入 / 子目录进入 | 各 1 | 36.896 / 23.211 | 同单次值 | 同单次值 |
| 子目录返回 root / 返回媒体库 | 各 1 | 46.221 / 221.287 | 同单次值 | 同单次值 |
| 播放返回 | 1 | 204.886 | 204.886 | 204.886 |
| 扫描期间搜索 | 10 | 111.601 | 147.544 | 147.544 |

功能断言通过：播放器 playlist stable-ID 列表等于来源结果；播放返回保留查询；扫描后原有
stable-ID 集合完整保留；本轮 unavailable 列表为空。原生鼠标和 IME 未验证，输入是显式注册的
Flutter 测试输入协议。首次搜索接近 1 秒，是需要继续优化/采样的冷索引成本，不能用热平均值掩盖。

判定：热搜索/标签/排序 P95 <500 ms、P99 <1 s；路径和播放返回本次 <1 s，但 N=1 不能证明稳定
分位数。全阶段共 451 帧，P50=15.463 ms、P95=105.858 ms、P99=135.513 ms，95 帧 >33.3 ms。
这包含启动、标签面板动画、路径与播放器路由、扫描，不能套用正常滚动阶段的 16.7 ms/1% 门槛后
声称通过。完整性能验收保持未闭环；下一步必须按阶段收集 build/raster/total 并归因长帧。

运行中的测试驱动修正也已留证：integration_test 默认不注册模拟输入；历史副本可能弹出
“发现新增视频”，需通过生产“稍后”按钮关闭；一级标题只展开，筛选通过默认专辑条目执行。
未通过改生产行为绕过这些场景。先前失败日志不作为性能样本，最终有效日志为临时目录
`ltp_interaction_baseline8.log`。基准摘要和 surface 截图位于 `.local/qa/query-20260905/evidence`，
不提交含真实媒体信息的数据库、截图或日志。

## 对抗式复核

- schema: unchanged，使用既有派生索引事务；无 migration。
- FilterQuery / TagQueryService: unchanged；候选先保守筛选，最终语义 owner 不变。
- filtered queue、thumbnail/media queue: unchanged；索引重建合并不改变媒体任务调度。
- user data: preserved；所有运行时写入使用隔离 profile，扫描不删除媒体文件。
- prompt impact: satisfies first principles，优先修复找不到视频和重复索引工作。
- protected behaviors: preserved；未删除 Widget、Route、菜单或 callback。
- unauthorized feature removal: none。
- mount and reachability: 生产 LibraryPage 与 PlayerPage 的 Finder 点击、队列断言和 surface 证据。
- validation: 上述精确结果；原生点击、隔离安装升级与完整性能验收仍列为缺口。

## 后续人工验收路径

在可丢弃 Windows 用户/VM 安装旧版本，导入测试媒体，记录 stable ID、manual 标签、收藏、
播放进度；经应用内升级安装候选版，复核数据与返回筛选状态。媒体库“添加目录”打开原生选择器后
取消，验证 root/视频/标签数量不变；设置页逐项打开再返回，检查主要菜单、对齐与窗口边框截图。
当前工具原生应用控制不可用，Flutter Finder 不替代此证据。
