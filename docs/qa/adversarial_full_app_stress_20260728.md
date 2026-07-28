# 2026-07-28 全应用对抗式暴力压测

## 目标与边界

本轮以“不破坏标签发现与 filtered playback queue 闭环”为前提，对当前可达的主要功能、
动画和 Windows 双播放器后端执行高频重复操作。压测只修改可重复证明的问题，不改
SQLite schema、标签过滤语义、用户数据或缓存失效策略。

“所有功能”按当前测试环境中的安全可达范围解释：搜索、排序、标签发现、网格/列表、
设置子页、播放器切换、队列、seek、全屏和长播均覆盖；因为没有隔离的临时媒体库，
删除文件、移除来源目录和重扫真实用户目录等破坏性操作没有执行。单显示器也不能替代
125% / 150% / 200% 的真实跨物理 DPI 测试。

## 自动化覆盖

### 完整静态与回归

- `flutter analyze`：通过，无问题。
- `flutter test --reporter expanded`：307 项通过，3 项真实媒体库 benchmark 按设计跳过。
- `flutter build windows --debug`：通过。
- `node --check scripts/qa/main_window_stress_semantic.mjs`：通过。
- `git diff --check`：通过，仅有工作区既有行尾提示。

### MediaKit / MPV 双后端矩阵

命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_player_backend_stability_matrix.ps1 `
  -LongPlaySeconds 120 `
  -RapidSwitchCount 100 `
  -MaxDroppedFrames 5 `
  -Output ".local\qa\adversarial-full-final2-player-matrix-data"
```

结果：

| 后端 | 全屏往返 | 快速切换 | 长播 | 队列开合 P95 | 设置开合 P95 | seek P95 | 停滞 | 最大掉帧 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| MediaKit | 6 次 | 100 次 | 120 秒 | 14.981ms | 22.135ms | 9.440ms | 0 | 0 |
| MPV | 6 次 | 100 次 | 120 秒 | 15.007ms | 22.176ms | 12.662ms | 0 | 2 |

两后端都保持 `d3d11va-copy`，全屏队列可见且可命中，快速切换后的来源队列、顺序、
当前 index 和最终打开项一致。自动矩阵门禁通过；发布状态仍保留
`pending-physical-cross-dpi`。

汇总：

```text
.local/qa/adversarial-full-final2-player-matrix-data/
  player-backend-stability-matrix.json
```

### 主窗口语义压力

主窗口脚本执行 4 轮搜索、六种排序、标签父子选择、标签面板开合和网格/列表切换。
正式门禁通过，没有崩溃、路由丢失或排序错误。脚本仍记录两类软失败：

- 标签选择后的自动折叠会让旧语义节点短暂失效；
- 滚动后的卡片可能离开当前语义视口。

两者都属于自动化可见性和节点代次抖动，不是产品状态错误。脚本已改为每次点击前重新
解析语义目标，并在选择子标签前按产品既有折叠规则重新展开父标签；不会以固定索引点击
过期节点。

## 真实窗口压力

- 网格/列表连续切换 12 轮：单轮最大 158ms、平均 151ms；无残留布局、重叠或列数漂移。
- 设置的播放与解码、画质、交互、备份、缩略图缓存共 30 次子页往返：
  单轮最大 604ms、平均 555ms，数值包含两次 Route 切换和稳定等待；无黑框、溢出或旧层残留。
- 播放器实测队列开合、设置弹层、全屏、全屏队列和实时视频合成。
- 最终 MPV Debug 实窗确认：进入全屏和展开全屏队列 1.5 秒后的稳定帧中，
  顶部文件/序号摘要均未残留；视频、控制层和队列继续实时更新。

## 压测发现并修复的问题

### 网格卡片缺少稳定播放语义

列表视图已有稳定播放入口，网格视图只能依赖容易失效的节点位置。网格与列表现在共享
`LibrarySmokeSemantics.videoPlay(item)`；多选模式仍使用独立选择语义和 selected 状态，
没有改变点击行为或 filtered queue。

### 标签压力脚本误用旧语义索引

标签选择会按既有产品规则自动折叠面板，原脚本继续复用旧节点索引会误报失败。脚本现在
重新解析目标、有限重试 stale index，并在同一父标签的子项之间恢复展开状态。

### MPV 全屏残留顶部摘要像素

真实全屏稳定帧发现：Flutter 状态虽已卸载非全屏顶栏，但 Windows child HWND 可能先完成
全屏尺寸切换，把上一帧摘要像素留在视频顶部。全屏命令现在先设置过渡门禁并等待
`WidgetsBinding.instance.endOfFrame`，确认“顶栏已卸载”帧提交后才调用原生
`setFullScreen`。失败时仍恢复过渡状态，退出全屏、队列和会话记忆语义不变。

## 尚需人工完成的发布门禁

- 在真实 125% / 150% / 200% 显示器之间拖动窗口并往返全屏；模拟 DPI 已通过，
  但不能替代物理显示器。
- 如需覆盖删除、移除目录和重扫，应先建立与用户资料库完全隔离的临时媒体根，再运行
  破坏性压力矩阵。
- 可再执行一次每后端 30 分钟正式长播；本轮 120 秒暴力矩阵用于快速发现交互与动画回归，
  不替代已有的 30 分钟发布证据。
