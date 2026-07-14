# 媒体库增删与播放器十轮专项压测（2026-07-14）

## 范围与安全边界

- 使用真实 `X:\test-media` 和真实应用 profile 的隔离副本，磁盘媒体文件只读。
- 每轮添加顶层 root、快速滚动、进入播放器并随机 seek 3 次、退出、移除顶层 root，再对剩余库重复滚动和播放。
- 共 10 轮、20 次播放器会话、60 次 seek；Finder/VM Service 持续驱动 Flutter 帧，不关闭语义树，不使用 Windows UIA。
- 录屏、状态、帧耗时、进程、I/O、GPU 和播放器诊断位于 `artifacts/library_add_remove_stress_10cycles_retry_20260714`，不纳入 Git。

## 结果

- 隔离库基线为 4,827 条；添加顶层 root 后新增 6,308 条，总量 11,135；10 轮添加和移除后 Store/SQLite/UI 数量始终一致。
- 添加端到端中位数 2,010 ms、P95 2,405 ms；提交后 UI 追平中位数 0.03 ms、P95 0.37 ms。
- 移除端到端中位数 562 ms、P95 773 ms；UI 追平中位数 0.02 ms、P95 0.04 ms。
- 每轮快速滚动后媒体探测约完成 234 条，仍排队约 6,000 条；移除 root 会取消旧 generation，队列归零，未再出现旧结果复活已删除记录。
- 像素截图确认滚动停止后的可见卡片已有缩略图，无遮挡、溢出或总量错位。原脚本错误地对不接收点击的 `Image` 使用 `hitTestable`，导致计数为 0；后续脚本已修正，历史十轮数值不用于判定缩略图是否显示。
- 新增库滚动阶段每段 P95 中位数 62.11 ms，486 帧中 52 帧超过 33 ms；移除后滚动阶段 P95 中位数 52.11 ms，347 帧中 45 帧超过 33 ms。数据库差量正确，但快速滚动仍存在明确可感知卡顿。
- 播放器启动阶段 P95 中位数分别约 42.41/21.41 ms；seek 阶段 P95 中位数约 7 ms。20 个诊断样本中视频/音频停滞计数均为 0，AV offset 接近 0。
- 20 个样本中 6 个实际硬解为 `no`，均来自已知 7680×4320 H.264 风险路径；seek 总体 P95 140 ms、最大 154 ms，硬解样本通常为 25–28 ms。
- 进程始终响应，但线程峰值 318、工作集峰值 1,928 MiB、Private 峰值 2,342 MiB、GPU committed 峰值 941 MiB。最终播放器退出 2 秒后 RSS 仍约 971 MiB，明显高于初始媒体库阶段，原生/驱动缓存保留仍是主要风险。
- 录屏 366.4 秒、约 106 MB。严格 `freezedetect` 未发现持续 0.5 秒以上的全窗口冻结；该结论不否定 Flutter 帧采样记录的滚动长帧，因为局部滚动和播放器画面仍会改变全窗口像素。

## 压测中发现并修复的问题

1. 未入库统计异步遍历共享 roots 时，移除 root 会触发 `ConcurrentModificationError`；扫描服务现在先取得不可变快照。
2. root 移除后未提升媒体库数据 revision，过滤状态复用了删除前的 11,135 条缓存；现在移除提交会失效派生缓存并刷新 UI。
3. 媒体探测队列会在 root 移除后继续 `upsertVideo`，把已删记录重新插回 Store/SQLite；现在移除前取消 generation，回写前再次验证 path、videoId 和 fingerprint 仍属于当前 Store。
4. 压测驱动只在点击后 50 ms 检查一次 8K 风险弹窗，会误报播放器启动超时；现在持续等待播放器或已知确认弹窗并模拟用户明确选择。

## 结论

批量增删、SQLite 一致性和 UI 差量追平已达到本轮正确性门槛；快速滚动流畅度、后台队列规模、软件解码样本以及播放器退出后的高位内存仍未达到“无感”目标。下一轮应优先让可见缩略图真正抢占后台预取，并把滚动阶段的构建/布局热点与播放器原生资源保留分别做专项剖析。

## 后续三轮专项复测

- 产物位于 `artifacts/library_scroll_release_8k_guard_final_3cycles_20260714`，不纳入 Git；3 轮添加/移除、6 次播放器、18 次 seek 均完成，进程无无响应。
- 后台缩略图候选文件校验限制为 24 条并发，可见项仍抢占队首；停稳后可见图片为 8–9 张。新增库滚动 build/raster P95 中位为 86.69/3.39 ms，移除后为 51.87/1.86 ms，构建/布局仍是主要峰值。
- 真实 8K H.264 未缓存详情曾绕过矩阵并在纹理创建后把 RSS 推到约 1.30 GiB，随后 `flutter_windows.dll` 以 `0xc0000409` 退出。单项高优先级预检修复后，同一样本两次均在创建纹理前被阻止。
- media_kit 1.2.6 的 Windows NativePlayer 在 dispose 返回后延迟 5 秒调用 `mpv_terminate_destroy`；released 契约和压测等待现已覆盖该宽限期。6 个实际播放样本均为 `d3d11va-copy`，软件解码/音视频停滞为 0，seek P95 28 ms。
- Private/GPU committed 峰值由十轮基线约 2,342/941 MiB 降至约 1,157/712 MiB，主要来自阻止 8K 软件解码和避免相邻会话重叠；返回媒体库后的跨轮高位仍存在，不能宣称原生/驱动缓存已经完全回收。

## 卡片子树与释放长尾专项

- 三轮产物位于 `artifacts/library_card_subtree_release_tail_3cycles_20260714`；三轮添加/移除、六个实际播放器会话和 18 次 seek 完成，未出现崩溃、无响应、软件解码或音视频停滞。干净截图 `cycle-02-added.png` 显示卡片无遮挡、错位或溢出。
- 滚动阶段聚合中，`card_shell` 直接 build 共 300 次、总计 11.07 ms，单阶段 P95 最高 0.10 ms；`actions` 直接 build 共 300 次、总计 0.89 ms。该指标只覆盖传入 builder 的直接执行，不包含框架随后触发的后代 Widget build。
- 包含式 layout 中，`card_shell` 单阶段 P95 最高 11.82 ms，`actions` 最高 8.52 ms；`preview`、`tags`、`metadata` 最高分别为 0.96/0.72/0.52 ms。各子树存在包含和重复布局，不能把总量直接相加；当前证据将下一轮 A/B 收敛到操作按钮的 Material/Semantics/LayoutBuilder 链。
- 首轮添加扫描出现 106.34 秒冷存储异常值，但同阶段卡片探针仅记录 24 次直接 build、总计不足 1 ms；日志无 Flutter 异常或超时，不能把该扫描异常归因为卡片构建。
- 修正 GPU counter 有效位后的单轮对照位于 `artifacts/library_card_subtree_release_tail_validgpu_1cycle_20260714`。最后一次真实 `released` 后 60 秒内，Working Set 563.1→560.1 MiB、Private 643.5→591.7 MiB、线程 128→125、句柄 1026→1020、GPU Dedicated 148.7→108.6 MiB、GPU committed 144.7→104.6 MiB。
- `PlayerMemoryDiagnostics` 的 RSS 在 0/5/15/30/60 秒分别约为 609.7/552.6/554.8/552.0/548.5 MiB；Flutter ImageCache 始终为 19,611,648 bytes。测试未触发 GC、未清理 ImageCache，主要回落发生在前 15–20 秒，剩余约 52 MiB Private 高位继续留给 PlayerBackend/libmpv/驱动边界调查。
