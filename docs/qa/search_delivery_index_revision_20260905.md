# 输入投递、查询接续与扫描索引修订 · 2026-09-05

## 边界与可复现结论

从第一性原理出发，后续修改进行对抗式审查，任务结束后自己给出下一步计划。
延续 `query_tail_decomposition_20260905.md`，仅修复有失败测试的输入合并缺陷并收窄成功空差量扫描的索引失效。
安装升级与原生验收仍待可丢弃 Windows 环境及无输入冲突时段，不在日用账户试装或注入原生输入。

工作区已有 `checked_search_input.dart` 和诊断测试，本轮复用该协议入口，保留其“不重试、不直接写 controller”约束。
相关 20/40 次扫描诊断通过，旧现场未复现；详见 `search_input_delivery_20260905.md`。
旧失败的输入框仍是原词，不能仅因后续运行成功就宣称根因修复。

## 输入链路反例

新增挂载生产 `LibraryPageLifecycleMixin` 和真实 `TextField` 的测试；只记录筛选调度出口。
在同一微任务执行前经测试输入协议发送 alpha→空串或 alpha→beta，先断言 controller 已是目标文本，
再检查筛选调度。旧实现两项均失败：期望 `[最新值]`，实际 `[]`。
原因是 `searchControllerChangeQueued` 为 true 时提前返回，未保存第二次输入；旧微任务发现文本不一致后也退出。
这证明了独立的生产缺陷，但其“文本已到达”与历史故障“仍为旧文本”的表现不同，不冒称二者同根因。

修复始终更新最新观察文本，同一微任务只调度一次；静默更新通过局部 generation 取消旧输入，
旧回调不能清除随后新输入的排队状态。请求身份、结果 epoch 和 dispose 校验均保留。
静默更新后的旧输入不重复调度，紧随其后的新输入仍正常调度。

另建测试输入客户端对照：用公开 TestTextInput API 更换 handler，旧客户端发送过期 client ID，
目标文本不变、无筛选调度，checked helper 报 input_delivery_not_observed；当前客户端发送同一空串则成功。
它证明诊断可以区分测试连接故障与已投递后的生产缺陷，不证明历史现场一定发生过 handler 更换。

## 索引失效反例与实现

真实 SQLite、2,001 条 stable-ID fixture，查询必须实际进入 FTS 候选并经过完整 Dart 过滤校验。
无变化扫描前后比较生产 sourceSelectSql 的全部可搜索字段，三次扫描仍推进 dataRevision 三次；
旧实现重建 4 次，失败测试要求只重建 1 次。修复后满足该要求。

`LibraryRepositoryContext` 新增仅进程内的 searchIndexRevision：

- 所有现有写入默认同时推进查询和索引修订，不批量修改各命令的失效行为。
- 只有成功且 changedVideos 为空的扫描保留索引修订；该提交路径只写 roots/favoriteTags metadata，
  视频/标签/关系写入均由差量条目触发。取消与任何非空差量仍保守失效。
- 扫描不恢复或覆盖旧修订值。扫描期间别名/标签命令仍独立失效；“零视频差量”不能掩盖其它命令的内容变更。
- 页面/查询继续使用 dataRevision；索引复用不等于允许发布旧 epoch 的候选。
- 未引入持久化索引版本或 schema migration；失败回滚与完整 Dart 查询回退不变。

回归覆盖字段完全未变、扫描期间别名变化、新增/改名/manual 标签/删除、扫描文本写入后再空扫描以及取消。
每项执行真实查询，保留 manual 标签和 stable ID，不用源码字符串代替结果集合断言。

## 配对测量口径

在同一台 Windows、同一 11,454 条 SQLite backup 快照上构建两个 Profile 二进制：
baseline 为本轮修改前生产实现，optimized 为输入合并与索引修订修改后实现；两者使用同一 checked-input 基线脚本。
执行顺序 baseline→optimized、optimized→baseline，各轮 20 次扫描（10 次纯扫描、10 次带输入）。
副本、日志和 trace 保留在 `.local/qa/revision-pair-20260905/`，不覆盖旧失败轮次。

脚本在扫描活动期间允许连续输入，优化后可能完成更多输入；报告实际请求数，
搜索时延的主对照只取每次带输入扫描的第一次搜索，N 相同。帧统计另列实际帧数，不称为固定输入数负载。
本任务不在测量期间执行测试或编译；主机其它后台活动并未独占。所有 trace 都是墙钟边界，
scan.batch_commit 与 index 重叠不等同于纯 SQLite 锁等待，累计旧请求等待也不是累计 CPU 时间。

## 配对结果

四轮全部完成、dropped=0；每轮查询请求 43 次、实际变更文本 22 次。
baseline 的扫描期间输入 10 次，另有扫描后清空；optimized 在扫描期间完成 20 次输入，扫描后清空已是同值。
每轮都推进 20 次查询 dataRevision，没有为复用索引跳过 epoch 校验。

| 指标 | baseline | optimized |
| --- | ---: | ---: |
| 每轮扫描次数 | 20 / 20 | 20 / 20 |
| 每轮 FTS 重建 | 21 / 21 | 1 / 1 |
| 旧候选等待后丢弃 | 9 / 9 | 0 / 0 |
| 旧候选累计等待（两轮） | 61540.048 ms | 0 ms |
| batch 与索引事务重叠次数 | 1 / 2 | 0 / 0 |
| batch 重叠墙钟合计 | 569.441 ms | 0 ms |

| 耗时（合并两轮） | 每组 N | baseline P50/P95/P99 ms | optimized P50/P95/P99 ms |
| --- | ---: | ---: | ---: |
| 每次带输入扫描的首次搜索 | 20 | 1018.911 / 2063.624 / 2437.242 | 149.249 / 166.735 / 186.455 |
| 扫描 batch 返回 | 40 | 12.334 / 126.392 / 302.231 | 2.514 / 5.504 / 23.173 |

结构性收益在两种运行顺序都出现：减少 20 次/轮重复重建，没有将成本转成另一批过期请求。
完整数字位于同名 JSON；关键词为不存在的基准词，不能外推高命中率查询的结果构建成本。

帧门槛仍未关闭：optimized 搜索阶段 >33.3 ms 为 43/1575 与 41/1400，
total P95 为 15.731/17.231 ms；baseline 分别为 35/1659、38/2185。
优化后的清空从 scan_search_reset 移到 search_during_scan，阶段归属发生变化，不能据此直接断言 UI 回归或达标。
合并两种输入阶段的慢帧次数 baseline=94、optimized=84，比例约 1.37%/1.46%，均高于 1% 目标。
优化版首次搜索仍为 789.502/821.818 ms；本轮只减少进程内重复重建，没有解决跨进程首次准备。

## 验证、保护与交付状态

- 新增 9 项 focused（输入 4、真实 SQLite 5）通过；最初的输入合并与索引重建失败日志分别保留于
  `%TEMP%/ltp_input_coalescing_red.log` 与 `%TEMP%/ltp_revision_red3.log`。
  初次测试还暴露了测试自身的异步 expectLater guard 冲突及卸载时序断言问题，均修正测试口径，未以此修改生产卸载行为。
- 最终工作树 `flutter analyze` 无问题（14.0 s），`flutter test` 739 通过、4 项既有跳过（27 s），
  `flutter build windows --debug` 成功（17.5 s）。工作树含其它任务的 pending 页面回归，不能把全部新增用例都归本轮。
- 再从 a0852f2 建立隔离工作树，仅应用本任务暂存补丁，排除另一个任务的 navigation mixin 和卡片测试改动：
  analyze 无问题（8.4 s）、全量 729 通过/5 项跳过（35 s）、Agent/QA manifest validate 通过。
  多出的一项跳过是隔离树未构建 Rust release sidecar；该项目在主工作树全量中已执行。
- 两组 Profile 配对运行共 80 次扫描成功，所有输入变更都经 checked helper 核验。
- 完整生产 Profile Finder smoke 通过：30 次搜索、20 次排序、20 次标签切换、目录进入/返回及播放往返各 4 轮，
  unavailable 为空。展开/收起截图目视检查，结果、计数、输入框和导航可达，无新遮挡/溢出。
  该 smoke 启动时本任务 Debug 构建仍在收尾，仅作为功能验证，不作为独占环境性能结论。
  证据 `.local/qa/revision-full-20260905/1-optimized/evidence/`；不上传含私人媒体文本的截图。
- `python tool/agent_eval.py validate` 通过；格式化及 diff 检查完成。生产源码停止编辑后再核对所有变更分支，
  未移除菜单、Widget、ValueKey、Route 或播放来源回调；旧候选返回后及发布前两处 epoch 检查仍在。

```text
schema: unchanged；只新增进程内索引修订
FilterQuery / TagQueryService: unchanged；索引失效范围有意收窄
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved；manual 标签、stable ID 经真实 SQL/扫描测试验证
prompt impact: satisfies first principles；先失败测试，再最小修复与配对实验
protected behaviors: preserved；无授权删除项
unauthorized feature removal: none
mount and reachability: 生产 lifecycle 挂载测试、生产 Profile Finder 和截图
validation: focused/full/analyze/Debug/Profile 通过；历史输入故障未追溯确诊，原生验收待环境
```

## 下一步

1. 保留输入投递诊断；旧故障再次出现时依据当轮 client/焦点/文本与请求号分类，不把未投递计为慢查询。
2. 对高命中率搜索与全库结果恢复分别测构建成本，统一清空操作阶段后复测慢帧，继续使用原门槛。
3. 跨进程索引复用另建索引格式版本、事务一致性与主库内容有效性证明；不能持久化本轮进程计数冒充长期有效性。
   本轮证据支持保留空扫描复用，但不足以直接启用跨进程复用或增量 FTS。
4. 可丢弃 Windows 环境和无输入冲突时段就绪后，再执行安装升级、恢复、原生设置/目录取消/菜单及返回验收。
