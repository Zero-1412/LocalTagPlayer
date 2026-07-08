# 上下文策略（Token 优化）

## 规则 1：不要默认读取完整项目

默认禁止读取：

- `ROADMAP.md`
- `ARCHITECTURE.md`
- `CHANGELOG.md`
- 全部 `docs/chat_tasks/CHAT_*.md`

除非任务已经明确升级为 Level 3。

## 规则 2：必须声明文件范围

每个任务都要明确：

- 允许读取 / 修改的文件。
- 禁止读取 / 修改的文件。

示例：

```text
只允许：
- lib/src/pages/library_page.dart

禁止：
- 其它全部文件
```

## 规则 3：上下文窗口最小化

Codex 必须使用：

- 最小依赖链。
- 直接 import / caller。
- 精确 `rg` 搜索。

不要默认递归扫描整个项目。

## 规则 4：Skill 用来缩小范围

Skill 是过滤器，不是扩展器。

示例：

```text
$ltp-small-fix -> 只读 1 个错误文件和必要引用
$ltp-tag-filter-data -> 只读 FilterQuery / TagQueryService / tag schema 相关文件
```

## 规则 5：输出小 diff

不要输出：

- 完整文件重写内容。
- 完整日志。
- 完整架构说明。

只输出：

- 已改文件。
- 关键行为变化。
- 验证结果。
- 对抗式审查。
