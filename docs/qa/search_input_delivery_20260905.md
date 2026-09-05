# 2026-09-05 · 扫描后输入投递诊断

## 问题与边界

上一轮扫描复位超时中 input/requested/accepted 均保持旧长度、request revision 未变。
该证据无法区分输入未到达与生产输入回调问题，不能据此归因 SQL。

新增 checked_search_input 经原 tester.enterText 协议执行，不直接写生产 controller、
不重试、不重新注册输入连接。投递后立即核对目标 controller 的文本；未匹配时以
input_delivery_not_observed 失败，而不是继续等查询超时。错误目标 controller 在投递前失败。
记录注册/客户端/焦点、editable 数量、controller 身份、目标是否匹配和长度，不输出搜索词。
平台 editingState 只作为回显长度，不能单独证明投递成功。该分类不直接证明是 harness
缺陷，因为应用同步回写旧值也会得到相同失败；后续仍需结合连接与回调证据。

## 验证

- 三项 focused 通过：正常输入及清空、同步回写旧值、错误目标 controller。
  记录不含测试秘密搜索词；`.local/checked_search_input_test.log`。
- analyze 无问题，`.local/checked_search_input_analyze.log`；格式化完成。
- 独立隔离 profile 从带标记的现有 QA 库经 SQLite backup 创建，不复制用户媒体。
  `.local/qa/input-delivery-20260905`；真实 Profile Finder 运行日志
  `.local/checked_input_profile.log`，本次运行结果待收集。
- 生产输入、查询实现和门槛未修改；新增 helper 测试加入 core-regression。

## 首轮真实 Profile

20 次扫描、20 次扫描后清空均完成，summary.completed=true；32 次输入记录均 delivered。
上述原始标签是初版口径；按 before.targetMatches 重分类后，22次实际从非目标文本变为
目标文本，10次本来已经匹配。不能把32次全部解释为有效文本变更。
其中21次投递前没有活动客户端，但 enterText 正常建立连接并完成投递；不能把 before.hasClient=false
单独作为故障判据。所有投递前输入协议 handler 均已注册。
这轮未复现旧故障，不证明旧故障已修复；旧失败在第32次扫描后出现，因此第二个独立快照
`.local/qa/input-delivery40-20260905` 正在跑40次，日志 `.local/checked_input_profile40.log`。

## 独立审查修正

同值输入现在单列 already_matched，focused追加同值空串边界。每条输入记录增加所属
phase；measure失败只关联本阶段新增的输入，非输入阶段不会附带旧搜索记录。
三项focused再次通过。这些元数据修正发生在第二轮已编译运行后，因此两轮原始记录按
before字段重分类，不冒称第二轮已验证新phase字段。第二轮期间有一次focused执行，
其帧/时延数据不能作为独占环境性能验收；本轮只用于输入可靠性诊断。
停止编辑后的独立复核通过，两项意见关闭；新元数据版本的真实运行仍待执行，最新修正
后的analyze将在当前运行结束后补做。

## 第二轮真实 Profile

40次扫描和40次复位完成，completed=true；62条记录按旧版本before字段重分类为
42次实际文本变更、20次同值，零input_delivery_not_observed。两轮共60扫描、64次
文本变更、30次同值，均未复现旧故障；不宣告旧故障修复，不把帧/耗时当性能达标。
修正后的analyze已通过。第三个独立快照 input-delivery-v2-20260905 运行2次扫描，
仅验证最新phase与already_matched元数据，结果待收集。

第三轮2次扫描完成，completed=true；新phase均属于当前搜索/扫描复位阶段，原始outcome
直接区分delivered和already_matched。日志 `.local/checked_input_profile_v2.log`。
这轮验证成功路径元数据；非输入阶段失败不附旧记录仍为源码审查证据，未人工制造
真实Profile失败。首轮最终Flutter渲染截图已检查：搜索为空、媒体网格及扫描完成反馈可见；
截图只留隔离目录，不提交包含媒体文本/缩略图的原始图像，不声称原生输入已验收。

schema、FilterQuery/TagQueryService、filtered queue、thumbnail/media queue未修改；
用户媒体未写入，只有隔离数据库可写。旧故障未复现但未证明修复，性能目标仍未达标。

## 后续

按同轮 startedAt 核对 summary、failure-state 和 inputAttempts，区分 input delivery
与后续 query acceptance；不覆盖旧失败，不将该运行当作原生 IME/鼠标验收。
