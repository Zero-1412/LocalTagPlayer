/**
 * 主界面真实窗口语义优先压测脚本。
 *
 * 脚本只执行非破坏性交互：标签、排序、本地媒体库路径、视频播放入口和返回。
 * 一旦检测到应用退出、窗口丢失、连续找不到语义目标或重复命中同一目标，就停止并返回原因。
 */

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const sortModes = [
  { name: 'recent', label: '日期' },
  { name: 'name', label: '名称' },
  { name: 'type', label: '类型' },
  { name: 'size', label: '大小' },
  { name: 'folder', label: '目录' },
  { name: 'added', label: '添加时间' },
];

const preferredLocalRoots = ['video', '原神', '崩铁', '绝区零'];

function parseIndexedLines(tree) {
  return tree
    .split('\n')
    .map((line) => {
      const match = line.match(/^\s*(\d+)\s+([^\s]+)\s+(.*)$/);
      if (!match) return null;
      return {
        index: Number(match[1]),
        role: match[2],
        text: match[3].trim().replace(/\s+/g, ' '),
        raw: line,
      };
    })
    .filter(Boolean);
}

function shuffled(items) {
  return [...items].sort(() => Math.random() - 0.5);
}

function findBySemantic(lines, label) {
  return lines.find((line) => line.text.includes(label));
}

function findUniqueBySemantic(lines, label) {
  const matches = lines.filter((line) => line.text.includes(label));
  return matches.length === 1 ? matches[0] : null;
}

function semanticTokenFromText(text) {
  const patterns = [
    /qa\.sort\.field\.button/,
    /qa\.sort\.direction\.button/,
    /qa\.sort\.field\.[^\s]+/,
    /qa\.local\.root\.[^\s]+/,
    /qa\.local\.folder\.[^\s]+/,
    /qa\.tag\.primary\.[^\s]+/,
    /qa\.tag\.child\.[^\s]+\.[^\s]+/,
    /qa\.video\.play\.[^\s]+/,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) return match[0];
  }
  return null;
}

function isDangerousChromeElement(element) {
  return /关闭|Close|最小化|最大化|Minimize|Maximize/i.test(element.text);
}

async function resolveStableElement(label, { attempts = 3 } = {}) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const firstTree = await snapshotText();
    const first = findUniqueBySemantic(parseIndexedLines(firstTree), label);
    if (!first || isDangerousChromeElement(first)) {
      await sleep(120);
      continue;
    }

    await sleep(90);
    const secondTree = await snapshotText();
    const second = findUniqueBySemantic(parseIndexedLines(secondTree), label);
    if (
      second &&
      second.index === first.index &&
      second.text === first.text &&
      !isDangerousChromeElement(second)
    ) {
      return second;
    }
  }
  return null;
}

function findByVisibleText(lines, label) {
  return lines.find((line) => line.text === label || line.text.includes(label));
}

function primaryTagCandidates(lines) {
  return lines
    .filter((line) => line.text.includes('qa.tag.primary.'))
    .map((line) => {
      const label = line.text.match(/qa\.tag\.primary\.([^\s]+)/)?.[1];
      return label ? { ...line, label } : null;
    })
    .filter(Boolean);
}

function childTagCandidates(lines, primaryLabel) {
  const prefix = `qa.tag.child.${primaryLabel}.`;
  return lines
    .filter((line) => line.text.includes(prefix))
    .map((line) => {
      const rest = line.text.slice(line.text.indexOf(prefix) + prefix.length);
      const label = rest.split(/\s/)[0];
      return label ? { ...line, label } : null;
    })
    .filter(Boolean);
}

async function currentAppWithWindow() {
  const apps = await sky.list_apps();
  return apps.find((candidate) =>
    /local_tag_player/i.test(`${candidate.id} ${candidate.displayName ?? ''}`) &&
    candidate.windows?.length,
  );
}

async function bindTargetWindow() {
  const app = await currentAppWithWindow();
  if (!app) {
    throw new Error('local_tag_player exited or window disappeared');
  }
  globalThis.targetWindow = app.windows[0];
  await sky.activate_window({ window: globalThis.targetWindow });
  return globalThis.targetWindow;
}

async function snapshotText() {
  try {
    await bindTargetWindow();
    const state = await sky.get_window_state({
      window: globalThis.targetWindow,
      include_screenshot: true,
      include_text: true,
    });
    globalThis.targetWindow = state.window;
    return state.accessibility?.tree ?? '';
  } catch (error) {
    const message = String(error?.message ?? error);
    if (/minimized|stale|not found/i.test(message)) {
      await sleep(250);
      await bindTargetWindow();
      const state = await sky.get_window_state({
        window: globalThis.targetWindow,
        include_screenshot: true,
        include_text: true,
      });
      globalThis.targetWindow = state.window;
      return state.accessibility?.tree ?? '';
    }
    throw error;
  }
}

async function clickElement(element) {
  globalThis.lastSemanticStressClick = {
    at: new Date().toISOString(),
    index: element.index,
    text: element.text,
  };
  await sky.click({
    window: globalThis.targetWindow,
    element_index: element.index,
  });
}

async function safeClickElement(element) {
  try {
    const token = semanticTokenFromText(element.text);
    if (token) {
      const stable = await resolveStableElement(token);
      if (!stable) return false;
      await clickElement(stable);
    } else {
      if (isDangerousChromeElement(element)) return false;
      await clickElement(element);
    }
    return true;
  } catch (error) {
    if (String(error?.message ?? error).includes('outside window bounds')) {
      return false;
    }
    throw error;
  }
}

async function clickSemantic(label) {
  const element = await resolveStableElement(label);
  if (!element) return false;
  return safeClickElement(element);
}

async function scrollMainViewport() {
  await bindTargetWindow();
  const visual = await sky.get_window_state({ window: globalThis.targetWindow });
  globalThis.targetWindow = visual.window;
  const shot = visual.screenshots?.[0] ?? { width: 1268, height: 714 };
  await sky.scroll({
    window: globalThis.targetWindow,
    screenshotId: shot.id,
    x: Math.round(shot.width * 0.56),
    y: Math.round(shot.height * 0.56),
    scrollX: 0,
    scrollY: Math.random() > 0.5 ? 520 : -420,
  });
}

async function exerciseTags(round) {
  const started = Date.now();
  let tree = await snapshotText();
  let lines = parseIndexedLines(tree);
  let primary = null;
  let childPool = [];
  for (const candidate of shuffled(primaryTagCandidates(lines))) {
    if (!(await safeClickElement(candidate))) continue;
    await sleep(180);
    tree = await snapshotText();
    lines = parseIndexedLines(tree);
    childPool = shuffled(childTagCandidates(lines, candidate.label));
    if (childPool.length) {
      primary = candidate;
      break;
    }
  }
  if (!primary) {
    return { ok: false, phase: 'tag.primary', ms: Date.now() - started };
  }

  const clickedChildren = [];
  for (let index = 0; index < 2; index += 1) {
    const remaining = childPool.filter(
      (candidate) => !clickedChildren.includes(candidate.label),
    );
    let child = null;
    for (const candidate of remaining.length ? remaining : childPool) {
      if (await safeClickElement(candidate)) {
        child = candidate;
        break;
      }
    }
    if (!child) {
      return {
        ok: false,
        phase: 'tag.child',
        primary: primary.label,
        clickedChildren,
        ms: Date.now() - started,
      };
    }
    clickedChildren.push(child.label);
    await sleep(220);
    tree = await snapshotText();
    lines = parseIndexedLines(tree);
    childPool = shuffled(childTagCandidates(lines, primary.label));
  }

  if (round % 2 === 0) {
    await scrollMainViewport();
    await sleep(100);
  }
  return {
    ok: true,
    phase: 'tag',
    primary: primary.label,
    clickedChildren,
    ms: Date.now() - started,
  };
}

async function exerciseSort(round) {
  const started = Date.now();
  const mode = sortModes[round % sortModes.length];
  const opened = await clickSemantic('qa.sort.field.button');
  await sleep(120);
  const chosen = opened
    ? await clickSemantic(`qa.sort.field.${mode.name}.${mode.label}`)
    : false;
  await sleep(160);
  const directionA = await clickSemantic('qa.sort.direction.button');
  await sleep(120);
  const directionB = await clickSemantic('qa.sort.direction.button');
  await sleep(160);
  return {
    ok: opened && chosen && directionA && directionB,
    phase: 'sort',
    mode: mode.label,
    opened,
    chosen,
    directionClicks: Number(directionA) + Number(directionB),
    ms: Date.now() - started,
  };
}

async function clickFirstVideoPlay() {
  const tree = await snapshotText();
  const lines = parseIndexedLines(tree);
  const plays = shuffled(
    lines.filter((line) => line.text.includes('qa.video.play.')),
  );
  for (const play of plays) {
    if (await safeClickElement(play)) return true;
  }
  return false;
}

async function exerciseLocalLibrary(round) {
  const started = Date.now();
  let tree = await snapshotText();
  let lines = parseIndexedLines(tree);
  const mediaLibrary = findByVisibleText(lines, '媒体库');
  if (mediaLibrary) {
    await safeClickElement(mediaLibrary);
    await sleep(180);
  }

  tree = await snapshotText();
  lines = parseIndexedLines(tree);
  let root = null;
  for (const candidate of shuffled(
    preferredLocalRoots
      .map((name) => findBySemantic(lines, `qa.local.root.${name}`))
      .filter(Boolean),
  )) {
    if (await safeClickElement(candidate)) {
      root = candidate;
      break;
    }
  }
  if (!root) {
    return { ok: false, phase: 'local.root', ms: Date.now() - started };
  }
  await sleep(320);

  if (round % 2 === 0) {
    let played = await clickFirstVideoPlay();
    if (!played) {
      await scrollMainViewport();
      await sleep(180);
      played = await clickFirstVideoPlay();
    }
    if (played) {
      await sleep(850);
      await bindTargetWindow();
      await sky.press_key({ window: globalThis.targetWindow, key: 'Alt_L+Left' });
      await sleep(650);
    }
    return {
      ok: played,
      phase: 'local.video',
      root: root.text,
      ms: Date.now() - started,
    };
  }

  tree = await snapshotText();
  lines = parseIndexedLines(tree);
  const folder = lines.find((line) => line.text.includes('qa.local.folder.'));
  if (folder) {
    if (!(await safeClickElement(folder))) {
      await scrollMainViewport();
    }
    await sleep(350);
  } else {
    await scrollMainViewport();
    await sleep(180);
  }
  return {
    ok: true,
    phase: folder ? 'local.folder' : 'local.scroll',
    root: root.text,
    ms: Date.now() - started,
  };
}

export async function runSemanticMainWindowStress({
  minutes = 10,
  maxRounds = Number.POSITIVE_INFINITY,
  stopOnAbnormal = true,
} = {}) {
  await bindTargetWindow();
  const deadline = Date.now() + minutes * 60 * 1000;
  const results = [];
  let round = 0;
  let semanticMissRounds = 0;
  let repeatedClickRounds = 0;
  let repeatedErrorRounds = 0;
  let previousClickText = '';
  let previousErrorText = '';

  while (Date.now() < deadline && round < maxRounds) {
    round += 1;
    const started = Date.now();
    const record = { round, startedAt: new Date().toISOString() };
    try {
      await bindTargetWindow();
      await sky.press_key({ window: globalThis.targetWindow, key: 'Escape' });
      await sleep(80);
      record.tag = await exerciseTags(round);
      record.sort = await exerciseSort(round);
      record.local = await exerciseLocalLibrary(round);
      record.ok = Boolean(record.tag.ok && record.sort.ok && record.local.ok);
      record.lastClick = globalThis.lastSemanticStressClick ?? null;
    } catch (error) {
      record.ok = false;
      record.error = String(error?.message ?? error);
      record.lastClick = globalThis.lastSemanticStressClick ?? null;
      if (stopOnAbnormal && !(await currentAppWithWindow())) {
        record.aborted = true;
        record.stopReason = 'app_exit_or_window_lost';
      }
    }
    record.ms = Date.now() - started;
    results.push(record);

    const lastClickText = record.lastClick?.text ?? '';
    repeatedClickRounds =
      lastClickText && lastClickText === previousClickText
        ? repeatedClickRounds + 1
        : 0;
    previousClickText = lastClickText;

    const errorText = record.error ?? '';
    repeatedErrorRounds =
      errorText && errorText === previousErrorText ? repeatedErrorRounds + 1 : 0;
    previousErrorText = errorText;

    const semanticMiss =
      record.tag?.phase === 'tag.primary' ||
      (record.sort?.phase === 'sort' && !record.sort.opened) ||
      record.local?.phase === 'local.root';
    semanticMissRounds = semanticMiss ? semanticMissRounds + 1 : 0;

    if (stopOnAbnormal && !record.stopReason && semanticMissRounds >= 3) {
      record.aborted = true;
      record.stopReason = 'semantic_targets_missing_three_rounds';
    }
    if (stopOnAbnormal && !record.stopReason && repeatedClickRounds >= 5) {
      record.aborted = true;
      record.stopReason = 'same_semantic_target_repeated';
    }
    if (stopOnAbnormal && !record.stopReason && repeatedErrorRounds >= 3) {
      record.aborted = true;
      record.stopReason = 'same_error_repeated';
    }
    if (record.stopReason) break;
  }

  globalThis.semanticMainWindowStressResults = results;
  const stopped = results.find((item) => item.stopReason || item.aborted);
  return {
    requestedMinutes: minutes,
    rounds: results.length,
    okCount: results.filter((item) => item.ok).length,
    failCount: results.filter((item) => !item.ok).length,
    sortFailures: results.filter((item) => !item.sort?.ok).length,
    tagFailures: results.filter((item) => !item.tag?.ok).length,
    localFailures: results.filter((item) => !item.local?.ok).length,
    stopReason: stopped?.stopReason ?? null,
    stopRound: stopped?.round ?? null,
    maxMs: Math.max(...results.map((item) => item.ms), 0),
    results,
  };
}
