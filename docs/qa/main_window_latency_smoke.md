# 主界面标签切换耗时 smoke

本文档记录真实窗口 QA 的耗时采样方式。它用于媒体库、标签筛选、排序和搜索相关改动后的非破坏性复测，目标是把“是否卡顿”落到可比较的点击耗时记录。

## 适用范围

- 右侧一级标签展开 / 收起。
- 一级标签下二级标签 chip 点击。
- 搜索框 `Ctrl+K -> 输入 -> 结果数变化`。
- 本地媒体库路径进入 / 返回。

## 采样原则

- 先确认 debug exe 已启动到主界面，并且媒体库数据已加载完成。
- 每轮记录 `primary`、`children`、`elapsedMs`、`resultText` 和 `method`。
- 标签复测至少选择不同一级标签，随机点击其下二级标签两次，连续执行十轮。
- 优先使用辅助树里的 `element_index` 命中标签，只有辅助树无法暴露二级 chip 时，才回退到相对坐标。
- 只记录点击和结果响应耗时，不执行删除、扫描、标签改名等破坏性操作。
- 如果自动化输入丢字符，以真实键盘逐键输入结果为准；批量 `type_text` 只作为辅助，不作为失败依据。

## Computer Use 辅助树采样模板

该模板在 Computer Use 已连接目标窗口后执行。它先读取辅助树并按标签文本查找元素索引，避免普通窗口和最大化窗口之间的固定坐标漂移。二级 chip 如果没有独立辅助元素，脚本会使用已展开一级行附近的相对坐标作为最后回退，并在 `method` 中标记。

```js
// 前置条件：globalThis.targetWindow 是 get_window_state 返回过的当前窗口对象。
{
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const visualState = await sky.get_window_state({
  window: globalThis.targetWindow,
});
globalThis.targetWindow = visualState.window;
const windowSize = visualState.screenshots?.[0] ?? { width: 1268, height: 714 };

async function snapshotText() {
  const state = await sky.get_window_state({
    window: globalThis.targetWindow,
    include_screenshot: false,
    include_text: true,
  });
  globalThis.targetWindow = state.window;
  return state.accessibility?.tree ?? "";
}

function parseIndexedLines(tree) {
  return tree
    .split("\n")
    .map((line) => {
      const match = line.match(/^\s*(\d+)\s+([^\s]+)\s+(.*)$/);
      if (!match) return null;
      return {
        index: Number(match[1]),
        role: match[2],
        text: match[3].trim(),
        raw: line,
      };
    })
    .filter(Boolean);
}

function findLabelElement(lines, label, { afterIndex = 0 } = {}) {
  return lines.find((line) => {
    if (line.index <= afterIndex) return false;
    const text = line.text.replace(/\s+/g, " ");
    return text === label || text.startsWith(`${label} `);
  });
}

function findTagPanelStartIndex(lines) {
  const tab = lines.find((line) => line.text.includes("一级标签"));
  return tab?.index ?? 0;
}

function findHeader(tree) {
  return (
    tree
      .split("\n")
      .find((line) => /当前筛选|共 .* 个视频|没有匹配的视频/.test(line)) ?? ""
  )
    .replace(/\s+/g, " ")
    .trim();
}

async function clickElement(element) {
  await sky.click({
    window: globalThis.targetWindow,
    element_index: element.index,
  });
}

async function clickChildByTextOrFallback({
  primary,
  primaryElement,
  childLabels,
  fallbackX,
  fallbackY,
}) {
  const clicked = [];
  let method = "element_index";
  for (const child of childLabels) {
    const tree = await snapshotText();
    const lines = parseIndexedLines(tree);
    const childElement = findLabelElement(lines, child, {
      afterIndex: primaryElement.index,
    });
    if (childElement) {
      await clickElement(childElement);
      clicked.push(child);
      await sleep(180);
      continue;
    }
    method = "fallback_relative_coordinate";
    await sky.click({
      window: globalThis.targetWindow,
      x: fallbackX,
      y: fallbackY,
    });
    clicked.push(`${child}:fallback`);
    await sleep(180);
  }
  return { clicked, method };
}

const plan = [
  { primary: "原神", children: ["默认专辑", "雷神"] },
  { primary: "崩铁", children: ["默认专辑", "流萤"] },
  { primary: "mod", children: ["默认专辑", "ntr"] },
  { primary: "崩坏三", children: ["默认专辑", "芽衣"] },
  { primary: "绝区零", children: ["默认专辑", "艾莲"] },
  { primary: "鸣潮", children: ["默认专辑", "尤诺"] },
  { primary: "虫", children: ["默认专辑", "虫"] },
  { primary: "原神", children: ["默认专辑", "尼可"] },
  { primary: "崩铁", children: ["默认专辑", "知更鸟"] },
  { primary: "绝区零", children: ["默认专辑", "拉米尔"] },
];

const results = [];
for (let round = 0; round < plan.length; round += 1) {
  const item = plan[round];
  const started = Date.now();
  let tree = await snapshotText();
  let lines = parseIndexedLines(tree);
  const panelStartIndex = findTagPanelStartIndex(lines);
  const primaryElement = findLabelElement(lines, item.primary, {
    afterIndex: panelStartIndex,
  });
  if (!primaryElement) {
    results.push({
      round: round + 1,
      primary: item.primary,
      children: item.children,
      elapsedMs: Date.now() - started,
      method: "missing_primary_element",
      resultText: findHeader(tree),
    });
    continue;
  }

  await clickElement(primaryElement);
  await sleep(180);

  const childResult = await clickChildByTextOrFallback({
    primary: item.primary,
    primaryElement,
    childLabels: item.children,
    // 最后回退坐标只依赖当前窗口右侧面板的大致位置，比逐行固定 y 坐标稳定。
    fallbackX: Math.round(windowSize.width * 0.82),
    fallbackY: Math.round(windowSize.height * 0.55),
  });
  await sleep(260);

  tree = await snapshotText();
  results.push({
    round: round + 1,
    primary: item.primary,
    children: childResult.clicked,
    elapsedMs: Date.now() - started,
    method: childResult.method,
    resultText: findHeader(tree),
  });

  lines = parseIndexedLines(tree);
  const primaryAfterClick = findLabelElement(lines, item.primary, {
    afterIndex: findTagPanelStartIndex(lines),
  });
  if (primaryAfterClick) {
    await clickElement(primaryAfterClick);
  }
  await sleep(120);
}

nodeRepl.write(JSON.stringify(results, null, 2));
}
```

## 结果解释

- `method: "element_index"`：一级和二级标签都通过辅助树元素索引命中，可信度最高。
- `method: "fallback_relative_coordinate"`：至少一个二级 chip 未暴露独立辅助元素，脚本使用右侧面板相对坐标回退；该轮需要结合截图或人工复核。
- `method: "missing_primary_element"`：辅助树未找到一级标签，通常是面板不在一级页签、列表滚动位置不对，或应用未加载完成。

## 通过标准

- 十轮点击中不出现全页空白、窗口无响应或筛选状态明显错乱。
- 单轮耗时应主要由脚本等待时间构成；如果同类操作出现明显高于其它轮次的耗时，需要记录当轮一级标签、结果数量和可见异常。
- 标签计数刷新不得阻塞可见视频结果更新；如果结果列表已更新但右侧计数稍后变化，属于预期行为。
- 采样报告中如果 `fallback_relative_coordinate` 超过 3 轮，应优先改进组件语义暴露，而不是继续扩大坐标回退范围。
