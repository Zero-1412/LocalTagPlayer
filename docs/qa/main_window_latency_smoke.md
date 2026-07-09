# 主界面标签切换耗时 smoke

本文档记录真实窗口 QA 的耗时采样方式。它用于媒体库、标签筛选、排序和搜索相关改动后的非破坏性复测，目标是把“是否卡顿”落到可比较的点击耗时记录。

## 适用范围

- 右侧一级标签展开 / 收起。
- 一级标签下二级标签 chip 点击。
- 搜索框 `Ctrl+K -> 输入 -> 结果数变化`。
- 本地媒体库路径进入 / 返回。

## 采样原则

- 先确认 debug exe 已启动到主界面，并且媒体库数据已加载完成。
- 每轮记录 `primary`、`childClickCount`、`elapsedMs`、`resultText`。
- 标签复测至少选择不同一级标签，随机点击其下二级标签两次，连续执行十轮。
- 只记录点击和结果响应耗时，不执行删除、扫描、标签改名等破坏性操作。
- 如果自动化输入丢字符，以真实键盘逐键输入结果为准；批量 `type_text` 只作为辅助，不作为失败依据。

## Computer Use 采样脚本模板

在 Computer Use 已连接目标窗口后，按当前窗口实际坐标调整 `primaryRows` 和二级 chip 的 `x` 偏移。脚本输出 JSON，可直接复制到 `CURRENT_TASK.md` 或对应 Chat 文档。

```js
const results = [];
const primaryRows = [
  { name: "一级A", y: 320 },
  { name: "一级B", y: 384 },
  { name: "一级C", y: 448 },
  { name: "一级D", y: 512 },
  { name: "一级E", y: 576 },
  { name: "一级F", y: 640 },
  { name: "一级G", y: 704 },
  { name: "一级H", y: 320 },
  { name: "一级I", y: 384 },
  { name: "一级J", y: 448 },
];

for (let index = 0; index < primaryRows.length; index += 1) {
  const item = primaryRows[index];
  const started = Date.now();
  await sky.click({ window: targetWindow, x: 2012, y: item.y });
  await new Promise((resolve) => setTimeout(resolve, 160));
  await sky.click({ window: targetWindow, x: 2135, y: item.y + 56 });
  await new Promise((resolve) => setTimeout(resolve, 240));
  await sky.click({ window: targetWindow, x: 2230, y: item.y + 56 });
  await new Promise((resolve) => setTimeout(resolve, 240));
  const state = await sky.get_window_state({
    window: targetWindow,
    include_screenshot: false,
    include_text: true,
  });
  targetWindow = state.window;
  const header = state.accessibility.tree
    .split("\n")
    .find((line) => /当前筛选|共 .* 视频/.test(line));
  results.push({
    round: index + 1,
    primary: item.name,
    childClickCount: 2,
    elapsedMs: Date.now() - started,
    resultText: header ?? "",
  });
  await sky.click({ window: targetWindow, x: 2012, y: item.y });
  await new Promise((resolve) => setTimeout(resolve, 120));
}

nodeRepl.write(JSON.stringify(results, null, 2));
```

## 通过标准

- 十轮点击中不出现全页空白、窗口无响应或筛选状态明显错乱。
- 单轮耗时应主要由脚本等待时间构成；如果同类操作出现明显高于其它轮次的耗时，需要记录当轮一级标签、结果数量和可见异常。
- 标签计数刷新不得阻塞可见视频结果更新；如果结果列表已更新但右侧计数稍后变化，属于预期行为。
