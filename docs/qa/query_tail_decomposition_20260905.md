# 索引 SQL、扫描提交和结果发布尾部拆分 · 2026-09-05

本文保留上一轮原始测量及当时的未提交状态；后续修复与配对验证见 `search_delivery_index_revision_20260905.md`。

## 范围与保护

从第一性原理出发，后续修改进行对抗式审查，任务结束后自己给出下一步计划。
本轮只补可关联的被动时序与隔离实验，不实施增量索引、不改变 revision 推进或扫描提交行为。
基于 `1f11dc5` 加本轮改动；工作树另有 pending 排序任务的页面导航和回归测试改动，不归本轮修改范围。
不修改任何用户媒体文件；仅带 `.query-baseline-profile` 标记的 11,454 条隔离数据库可写。

## 计时口径

- `LOCAL_TAG_PLAYER_BASELINE_TRACE=1` 才启用内存追踪，默认关闭；最多 20,000 条，溢出只计 dropped。
- 只记录静态操作名称、数值请求号、revision、扫描代次、数量与时延，不记录关键字、标题、路径、标签或异常正文。
- Zone 关联跨 await 的父操作；停止/重开会话后旧异步链不得污染新会话。结果、异常实例和原有回调顺序保持不变。
- `index` 连续分为 transaction_enter、delete、aggregate_and_fts_write、commit_return。
  前者含连接排队及 BEGIN，后者含提交及回到 Dart 的调度；均不是 SQLite 内部 CPU 或锁等待探针。
- `scan` 分为已有元数据快照、backend、merge_and_prepare、batch_commit_return、backup_enqueue、completion_callback。
  `scan.batch_commit` 包含排队、实际 SQL 和提交；只用与索引事务的重叠提供竞争证据，不声称已经测得纯锁等待。
- `query` 分为 queued、candidates、verify_sort、publish_callback；过期请求只封存数值 discarded 记录，
  不触碰结果缓存、onMeasured 或 onAccepted。候选再分 index_ready、SQL、映射。
- 结果发布回调只是同步 setState/计数调度；随后 tester.pump 返回及 FrameTiming 另列，不能把回调结束称为像素已经显示。
- 分位数采用 nearest rank。父子区间嵌套不能相加；P99 在 N=10/20 的小组中等于最大值，不能外推罕见尾部。
- 本轮首搜/扫描搜索使用不存在的基准词，候选 SQL 返回空集；映射近零不代表命中大量结果时的映射成本。
  最终校验/排序统计混有清空关键字的全库结果；后续需以非空命中和高命中率查询单独分组。

## SQL 对照实验

命令：`dart run tool/benchmark_library_search_index.dart <隔离 profile> <输出 JSON> --decompose`。
10 对交替生产 `INSERT ... SELECT` 与临时表物化方式；每次比较全部 FTS 字段和行数，20 次全部一致。
这是 Dart JIT 下的反事实 SQL 实验，临时物化改变执行计划和缓存，不可相减宣称得到原语句内部精确分量。
原始数据：`.local/qa/index-sql-decomposition-20260905.json`，无丢弃记录。

| 方法/阶段 | N | P50 ms | P95 ms |
| --- | ---: | ---: | ---: |
| 生产：事务进入 | 10 | 0.213 | 1.047 |
| 生产：清空 FTS | 10 | 223.138 | 393.046 |
| 生产：聚合及 FTS 写入 | 10 | 336.376 | 406.944 |
| 生产：提交返回 | 10 | 110.151 | 118.052 |
| 临时表：聚合物化 | 10 | 38.789 | 60.691 |
| 临时表：FTS 写入 | 10 | 324.666 | 661.758 |

聚合文本不是当前最强热点证据；旧 FTS 清空、写入及提交应优先研究。分步方式本身不作为优化上线。

## 失败轮次保留

首轮 traced Profile 扫描在第 12 次扫描后的搜索清空超时；此前 6 次扫描期间搜索都成功。
这次清空当时未纳入 measure；追踪未看到它对应的新 query 请求，不能归因为旧候选污染或 SQL 慢查询。
现场封存在 `.local/qa/tail-scan-failed1-20260905/`，包含本轮 summary、trace、driver.log。
原 evidence 目录的 failure-state.json 属于前一任务，未作为本轮证据使用。

现将 `scan_search_reset` 独立计时；action 与等待异常均捕获，并为失败状态添加 startedAt。
这补齐了 harness 证据缺口，没有更改生产搜索监听。失败根因仍未确证，后续成功重复不能抹除该失败。

第二轮计划 40 次，实际在第 32 次扫描后的复位再次超时，整轮 `completed=false`。
16 次纯扫描、16 次带输入扫描和 16 次扫描期间搜索完成，31 次复位成功、1 次复位失败。
本轮 failure-state 的 startedAt 与 summary 一致：input/requested/accepted 长度均为 12，
request 67→67、data revision 32→32、inputObserved=true、queuedInput=false、refreshing=false、epochCurrent=true。
截图显示输入框仍是原词。证据将问题定位到“清空未进入新查询”，不足以区分测试输入连接、原生 IME 干扰或页面输入链路。
不得用直接写 controller、忽略失败或自动重试方式让基线变绿。
原始现场 `.local/qa/tail-scan-failed2-20260905/`；成功操作统计与失败窗口严格分开，以下只是诊断数据，不是门禁通过证明。

## 扫描与发布测量

同机 Windows Profile、11,454 条隔离库；后台活动未独占，未同时运行本任务编译/单元测试。
环境沿用 `phase_frames_and_upgrade_acceptance_20260905.md`（Ryzen 9 7900X、64 GB、RTX 4070 SUPER、Flutter 3.44.4）。
第二轮追踪 dropped=0；32 次零视频差量提交均推进数据 revision，出现 33 次索引重建。
这里的零差量只表示 changedVideos 为空，不能据此证明所有标签/层级等派生内容都未改变。

| 阶段 | N | P50 ms | P95 ms | P99/max ms |
| --- | ---: | ---: | ---: | ---: |
| 索引事务进入 | 33 | 0.161 | 43.128 | 50.357 |
| 索引清空 | 33 | 242.205 | 318.106 | 350.322 |
| 聚合及 FTS 写入返回 | 33 | 348.723 | 3396.202 | 3433.084 |
| 索引提交返回 | 33 | 125.894 | 2655.887 | 2697.236 |
| 扫描合并与 batch 准备 | 32 | 35.930 | 45.989 | 48.102 |
| 扫描 batch 提交返回 | 32 | 5.164 | 231.139 | 248.420 |
| 候选 SQL | 33 | 0.418 | 39.358 | 56.010 |
| 最终校验/排序 | 54 | 0.012 | 86.903 | 98.241 |
| 结果同步发布回调 | 54 | 0.006 | 0.022 | 0.025 |
| 操作确认后额外 pump 返回 | 49 | 13.287 | 35.064 | 44.090 |
| 旧请求候选等待后丢弃 | 12 | 924.200 | 3910.814 | 3910.814 |
| 扫描期间搜索至结果加一帧 | 16 | 1647.779 | 1769.468 | 1769.468 |

扫描 batch 与索引事务重叠 10 次；最大 batch 为 248.420 ms，其中 246.298 ms 与索引事务区间重叠。
另 22 次无索引重叠，P50 4.696/P95 28.058/P99 31.840 ms。强烈提示连接串行竞争值得优先消除，
但当前探针不能把重叠时间全部判为锁等待。索引写入/提交的秒级长尾同样包含线程调度与恢复到 Dart 的成本，
不能凭 await 墙钟直接断言 SQLite 执行了数秒。

搜索阶段帧 N=2659，build P95 1.933、raster P95 1.878、total P95 16.166 ms；
>33.3 ms 为 38/2659=1.43%，最大 128.911 ms。纯扫描帧 N=1590，total P95 7.581 ms，
慢帧 27/1590=1.70%。扫描活动内事件循环间隙 P95 29.095/34.827 ms，P99 118.934/121.083 ms。
搜索延迟及慢帧比例仍超过现有标准，且复位超时属于硬失败；不能据此宣称性能达标。

## 独立进程首次索引

10 对新/复用 profile，20 次全部成功，各轮 trace 独立封存，dropped=0；每进程首次搜索各重建一次。
冷态仅指新进程、新 profile 缩略图缓存；未清 OS 缓存，新 profile 通过 SQLite backup 保留原库的派生 FTS。
因此测试的是已有库启动后的首次索引准备，不是从完全空 FTS 建库。复用 profile 也始终是新进程。
不与前轮直接计算性能改善百分比：本轮增加观测、运行时段和主机负载不同，且生产算法没有优化变化。

| 指标 | 新 profile P50/P95 ms | 复用 profile P50/P95 ms | 每组 N |
| --- | ---: | ---: | ---: |
| 外部进程至可操作 | 957.790 / 1000.139 | 988.108 / 1016.567 | 10 |
| Dart 入口至可操作 | 715.637 / 741.868 | 724.125 / 761.600 | 10 |
| 首次搜索至结果加一帧 | 869.694 / 910.709 | 1009.730 / 1087.740 | 10 |
| 候选索引就绪等待 | 798.986 / 849.898 | 952.010 / 1024.307 | 10 |
| 清空 FTS | 295.782 / 329.004 | 334.540 / 367.082 | 10 |
| 聚合及 FTS 写入返回 | 348.888 / 369.174 | 441.037 / 493.083 | 10 |
| 提交返回 | 125.817 / 137.628 | 153.777 / 178.206 | 10 |

每组 P99/max 等于 P95，完整数值见同名 JSON。原始副本及逐轮 JSON/trace 位于
`.local/qa/tail-startup-20260905/`。首次搜索 P95 仍超过 500 ms；启动符合初始预算。

## 验证与独立只读审查

- `flutter analyze`：最终无问题（13.6 s）。第一次最终检查遇到并行页面测试的 unused import，
  该任务移除 import 后重跑通过；本任务未改它的功能测试。
- `flutter test`：最终工作树 726 项通过、4 项既有跳过（24 s），包含并行 pending 页面任务的新增测试。
  本轮新增 3 项 trace 测试覆盖关闭透传、同一异常实例、容量、跨 await 关联和旧会话隔离；
  既有 query controller 的过期候选/epoch/dispose/诊断测试在 trace 开启时通过。真实 SQLite 等价测试也实际执行。
- `flutter build windows --debug`：成功（17.0 s）。Profile 已实际启动生产页；20 次启动成功，
  两轮扫描诊断均有复位硬失败，不能写成完整运行时通过。第二轮失败截图已目视核对输入框与空结果状态。
- `python tool/agent_eval.py validate`（含 QA manifest）：通过；`dart format` 完成，`git diff --check` 无错误。
- 停止业务代码编辑后独立只读审查：对照 HEAD 核对候选返回后的身份检查、发布前检查、
  scan batch/备份/markDataChanged 顺序及生产 SELECT 文本；所有原有分支保留。
  本轮没有删除 Widget、ValueKey、Route、菜单、callback 或播放来源入口。
- `AGENTS.md` 第 186 行要求“真实验证失败……不得提交”；由于两次复位硬失败尚未查清，
  本轮保留未提交工作树与证据，没有 stage、commit 或 push，也没有新提交 CI 通过声明。

```text
schema: unchanged；分步实验仅使用隔离连接 TEMP 表
FilterQuery / TagQueryService: unchanged；请求与 epoch 检查保留
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved；真实媒体只读，QA 数据库隔离
prompt impact: satisfies first principles；观测已测尾部，不扩大优化范围
protected behaviors: preserved；本轮无删除或替换 UI 子树
unauthorized feature removal: none
mount and reachability: 生产 Profile 页面有 Finder/截图证据；输入复位失败保留
validation: analyze/tests/Debug 通过；扫描运行时失败，安装及原生验收仍阻塞
```

## 后续改动顺序

1. 先为输入复位增加即时投递断言及 TextInput 连接/焦点诊断，在无输入冲突时复现并区分 harness 与生产问题。
   确认生产问题时先补失败页面测试再修，保留本轮两次失败；不能将未投递输入算作 SQL 或发布长尾。
2. 为“零视频差量但标签/层级变化”和“确实没有任何可搜索数据变化”建立对照测试，再设计独立的索引内容 revision。
   查询/页面 epoch 继续推进及拒绝旧结果；只允许已证明文本未变的情况复用索引。新增、改名、别名变化、删除均需与完整查询 stable-ID 集合等价。
3. 在同机配对实验中测重建数、旧请求浪费和 batch 重叠是否下降；有稳定收益才改变失效范围。
   秒级 SQL await 尾部需结合 SQLite worker/线程调度 trace 继续拆解，不能把所有等待当作 FTS CPU。
4. 首次启动索引复用另设版本/内容有效性证据及安全回退；不直接持久化当前进程 revision 作为跨进程正确性保证。
   再按原标准复测首次搜索、标签动画和结果帧，当前不直接引入增量 FTS。
5. 安装升级与原生路径保持以下环境前置条件；搜索历史、保存筛选、标签导出继续后置。

## 安装与原生验收

**仍待可丢弃 Windows 环境及无输入冲突时段就绪。** 当前未获得可用临时账户/VM，
此前原生输入存在持续用户冲突及截图目标不一致；不在日用账户试装、不把 Flutter Finder 当作原生验收。
条件就绪后按 `phase_frames_and_upgrade_acceptance_20260905.md` 执行旧版本安装升级、备份恢复、
目录选择取消、设置页、关键菜单与播放返回，核对 stable ID、manual 标签、收藏和进度并保存原生截图。
