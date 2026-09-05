# 2026-09-05 分阶段帧时序、重复启动与原生验收

## 范围

从 f6fe98b 继续验证，不修改生产代码、schema、FilterQuery/TagQueryService、来源 filtered queue
或 thumbnail/media queue。隔离 profile 允许写入缓存和播放记录，真实媒体文件只读。
搜索、标签动画、路径进入/返回、播放进入/返回和扫描的操作与帧记录分开。

## 测量方法

- Profile 构建，生产 LibraryPage/PlayerPage，Flutter Finder 输入。
- 使用 fullyLive 帧策略让生产动画自然逐帧运行；上一轮默认测试帧策略的数据不得与本轮混算。
- 用 rasterFinishWallTime 减去 totalSpan 还原 vsync 墙钟时间，按开始时刻归属互斥阶段；
  不按回调到达时刻分类，不假设 Dart 与引擎单调时钟 epoch 相同。
- 每阶段分别保留 build/raster/total 的 N、P50/P95/P99/max，以及 >33.3 ms、>100 ms 和跨界帧数。
- 操作时延在结果发布后再经过一帧停止；其后的 600 ms 动画尾部仍归属本操作阶段。
- 冷启动分为外部进程启动到可操作标记、Dart app.main 到页面可操作两个口径；测试构建有驱动开销。
- 新 profile 没有缩略图缓存；随后热态复用该 profile。OS 磁盘缓存未清理，不称为 OS 冷态。
- 启动原始样本按独立进程保存；低样本路由操作每轮重复 20 次，失败样本保留且不混入成功分位数。

## 环境检查

HypervisorPresent=true，Hyper-V 模块可用，但 vmms 服务停止；Get-VM 无法取得实例。
当前进程没有管理员权限，WindowsSandbox.exe 不存在。尚未获得可丢弃 Windows 用户或 VM。
尝试启动 vmms 返回 Cannot open 'vmms' service，未能启动虚拟机管理服务。
独立 computer-use 的 @oai/sky 已成功初始化并列出原生窗口，原生控制能力可用。

## 安装升级验收约束

本机有历史 0.2.8 安装器，但不得在当前 Windows 用户中运行升级来代替独立环境验收。
Inno Setup 使用固定 AppId 和每用户安装目录；即使更改安装路径，仍可能影响当前用户卸载记录。
必须在可丢弃 Windows 用户/VM 中使用旧安装器，创建合成媒体与 manual 标签/收藏/进度，
保存 stable-ID 清单和应用导出备份，然后运行候选安装器并逐字段对比。
测试目录选择取消、设置页进入/返回、关键菜单及播放器返回，保存系统窗口截图。
安装器退出码和单元测试通过均不能代替安装后的真实窗口验收。

## 执行结果

### 启动重复样本

11,454 条历史 QA 副本，Ryzen 9 7900X / 64 GB / RTX 4070 SUPER / Windows 11，
Flutter 3.44.4 / Dart 3.12.2，3840×2160、150% 缩放，MediaKit Texture 默认后端。
主机已有浏览器/视频客户端后台活动，未做系统冷重启或全机独占；真实媒体根只读。

| 模式与指标 | N | P50 ms | P95 ms | P99/max ms |
| --- | ---: | ---: | ---: | ---: |
| 新 profile：进程到可操作 | 10 | 958.835 | 988.771 | 988.771 |
| 复用 profile：进程到可操作 | 10 | 991.937 | 1019.244 | 1019.244 |
| 新 profile：Dart 入口到可操作 | 10 | 716.603 | 759.001 | 759.001 |
| 复用 profile：Dart 入口到可操作 | 10 | 748.719 | 753.888 | 753.888 |
| 新 profile：首次搜索 | 10 | 1115.891 | 1169.381 | 1169.381 |
| 复用 profile：首次搜索 | 10 | 1074.372 | 1164.741 | 1164.741 |

20 次启动功能全部成功。N=10 的经验 P95/P99 均等于本组最大值，不能据此推断罕见尾部概率。
启动符合初始预算；首次搜索不满足 P95 ≤500 ms、P99 ≤1 s。复用 profile 不消除首次搜索成本。
证据：`.local/qa/startup-repeat-20260905/startup-repeats.json` 与逐次报告/日志。

### 交互与阶段帧

完整成功运行 run2（日志 `ltp_phase_run2.log`）完成每类路由 20 次与 20 次面板展开/收起。
run3 再执行 20 次各类路由，随后在重复扫描阶段失败；该轮此前完成的阶段样本保留为诊断证据，
不能把整轮计为通过。两轮不混合分位数，以下操作表使用完整成功的 run2。

| 操作 | N | P50 ms | P95 ms | P99/max ms |
| --- | ---: | ---: | ---: | ---: |
| 热搜索 | 29 | 155.295 | 186.517 | 194.694 |
| 排序 | 20 | 140.726 | 162.420 | 163.579 |
| 标签筛选 | 20 | 195.690 | 222.751 | 228.929 |
| root 进入 | 20 | 44.414 | 50.713 | 54.504 |
| 子目录进入 | 20 | 55.290 | 60.085 | 69.869 |
| 返回 root | 20 | 40.524 | 50.917 | 58.406 |
| 返回媒体库 | 20 | 148.310 | 166.303 | 221.581 |
| 播放器页面进入 | 20 | 104.972 | 136.800 | 154.022 |
| 播放返回 | 20 | 198.027 | 212.796 | 213.512 |

播放器进入测量页面出现，不冒称视频首帧；playlist stable-ID 列表与来源结果一致，返回保留查询。
run2 帧证据如下，慢帧比例按每阶段实际帧数计算，而非操作次数：

| 阶段 | 帧 N | build P95 ms | raster P95 ms | total P95 ms | >33.3 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 热搜索 | 611 | 17.045 | 2.119 | 21.974 | 21 / 3.44% |
| 标签面板动画 | 885 | 23.872 | 3.132 | 34.985 | 56 / 6.33% |
| 标签筛选 | 820 | 13.924 | 2.668 | 27.607 | 23 / 2.80% |
| 返回 root | 1035 | 0.619 | 1.376 | 16.380 | 3 / 0.29% |
| 播放返回 | 269 | 22.350 | 2.547 | 25.426 | 0 / 0% |

完整 rawFrames 另含 P50/P99/max、跨阶段帧和 >100 ms 数量。
正常动画/交互帧不满足既有 16.7 ms / 1% 门槛；不得因操作时延符合预算就宣布性能通过。
最慢热搜索帧 total=144.833 ms、build=60.313 ms、raster=2.506 ms：成本包含 UI 构建和调度等待，
不能仅凭阶段统计定位具体函数，也不能把所有成本归因于 GPU。run3 的标签面板 build P95=24.105 ms，
与 run2 方向一致。阶段归属表示时间上的重叠，异步媒体释放等相邻任务仍可能参与该窗口的成本。

### 已发现的失败

- run1：首次搜索等待 45 s 超时，输入/请求已更新但结果仍为旧查询；后续 20 次独立启动没有重现，
  原因未关闭。证据 `.local/qa/phase-20260905-failed1`。
- run3：第 10 次带输入扫描期间查询超时。dataRevision 19→20，requestRevision 154→155，
  requestedLength=12、acceptedLength=0，epochCurrent=false；请求更新后没有观察到新结果发布。
  先前 41 次成功的并发搜索 P95=1537.254 ms、P99/max=1543.428 ms，已超过预算。
  该轮纯扫描 10 次、带输入扫描完成 9 次，第 10 次失败，不从分母中删除。
  证据 `.local/qa/phase-20260905-failed3`，`ltp_phase_run3.log`。
- 上述观察与“数据更新淘汰候选后，没有重新调度当前输入”相符；仍需 focused 反例与源码定位确认根因，
  不能通过取消 epoch 检查恢复旧缓存污染。本轮保留生产代码不变。
- run3 的事件循环计时仍含输入后稳定等待，只保留为诊断记录；扫描专项复测收紧到真实扫描活动及结束边界。

### 扫描专项 run4

只执行扫描场景，不先执行播放或路由循环；仍在第 10 次带输入扫描复现失败：
dataRevision 19→20，requestRevision 44→45，requestedLength=12、acceptedLength=0。
两种前置流程均复现，说明该复现不依赖前面的播放流程；尚不能仅据此断言完整根因。

| 指标 | N | P50 ms | P95 ms | P99/max ms |
| --- | ---: | ---: | ---: | ---: |
| 纯扫描，开始到观察到完成 | 10 | 4940.669 | 5146.753 | 5146.753 |
| 带输入扫描，成功完成部分 | 9 | 4380.322 | 4617.104 | 4617.104 |
| 扫描期间搜索，成功部分 | 40 | 235.965 | 1467.300 | 1497.667 |
| 纯扫描事件循环间隙 | 1578 | 36.740 | 56.059 | 65.225 / 209.914 |
| 带输入扫描事件循环间隙 | 1548 | 29.300 | 59.369 | 96.131 / 224.498 |

扫描完成时刻由周期观察或页面状态等待确认，含观测粒度，不是原生扫描器内部事务计时。
第 10 次带输入扫描的查询失败不进入成功时延分位数，但保留为 10 次尝试中的 1 次失败。
事件循环 P95 高于 50 ms 目标，未跨越 P95 >100 ms 的硬阈值；查询超时本身已构成硬失败。

失败操作的 45 s 等待窗口不能混入成功操作的帧分母。原始报告保留；
`classified-summary.json` 按最后一个超时操作窗口的时间戳把 1119 帧移到
`search_during_scan_failed`，窗口无删减；新 recorder 已自动区分失败阶段并补 focused test。

| 扫描帧阶段 | N | build P95 ms | raster P95 ms | total P95 ms | >33.3 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 纯扫描 | 1083 | 47.400 | 2.523 | 51.841 | 754 / 69.62% |
| 扫描期间成功搜索 | 1245 | 44.846 | 2.343 | 50.870 | 463 / 37.19% |
| 超时等待窗口，单列 | 1119 | 0.229 | 2.110 | 17.120 | 1 / 0.09% |

扫描帧不能套作正常滚动门槛的通过证明；这些数据用于定位扫描时的 UI 构建与调度成本。
原始与分类修正证据位于 `.local/qa/phase-20260905-scan4`，日志 `ltp_phase_scan4.log`。

### 原生验收与验证边界

已生成三个合成 MP4，位于 `.local/qa/native-20260905/media`；以独立 profile 启动正式 Debug 入口，
保存 `01-empty.png`，确认初始媒体库为 0。未打开用户实际 profile，未运行历史安装器。
Computer Use 的可访问性索引连续失效；坐标输入报告 user input was detected。
按要求重新观察后截图没有显示目标应用，因此停止输入，没有向其它应用发送操作。
仅关闭本任务启动并核验路径的测试进程。目录选择取消、设置页、关键菜单及原生返回均未标记通过。
安装升级还缺可丢弃 Windows 环境，不能把隔离 profile 等同于隔离 Windows 安装状态。

全量 `flutter test` 712 项通过、4 项既有跳过；随后加入的失败窗口分类用例与其余 recorder 用例
单独运行共 3 项通过。最终 `flutter analyze` 0 问题，Windows Debug 正式入口构建通过。
PowerShell 启动入口额外 1 对冷/热实测通过，单列为入口验证，不并入前述 10 对基线。
Agent eval validate 与 29 项工具单测通过；所有 dart format 成功，无超时。

### 对抗式结论与下一步

- schema / FilterQuery / TagQueryService / filtered queue / thumbnail-media queue：unchanged。
- user data：preserved，运行写入仅发生在隔离 profile 与合成媒体目录。
- protected behaviors：没有删除生产 Widget、Route、菜单、快捷键或 callback；无未授权功能删除。
- mount and reachability：生产页面 Finder 路径有证据；原生点击与安装升级仍阻塞，不能冒称通过。
- prompt impact：测量揭示真实失败，不以调整阈值、删除失败样本或修改生产行为使结果变绿。
- 第一优先：用扫描提交跨越 pending 查询的 focused 反例确认根因，再保证当前输入重新调度，保留 epoch 防污染。
- 第二优先：分析扫描、标签面板及结果替换的 UI 构建/同步计算成本，之后按本批原始样本复测。
- 第三优先：降低首次查询的索引准备成本；当前证据不支持仅因热缓存存在就跳过索引正确性检查。
- 获得可丢弃 Windows 用户/VM 和无桌面输入冲突的时段后，执行上述安装升级和原生路径验收。

### 复测命令

```powershell
$env:LOCAL_TAG_PLAYER_DATA_DIR = '<带标记的隔离profile>'
$env:LOCAL_TAG_PLAYER_BASELINE_SCAN = '1'
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/library_query_interaction_baseline_test.dart -d windows
# 仅复测扫描时额外设置 LOCAL_TAG_PLAYER_BASELINE_SCAN_ONLY=1。
./tool/repeat_library_startup_baseline.ps1 -Source <带标记的隔离profile> -Output <全新输出目录> -Binary build/windows/x64/runner/Profile/local_tag_player.exe -Flutter E:/flutter/bin/flutter.bat -Pairs 10
```

原始数据库、媒体路径、截图及日志只留在 `.local/qa`，不提交到远端。
