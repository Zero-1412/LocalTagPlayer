# Local Tag Player 代码开发标准

> 历史归档：仍有效的强制规则已经收敛到 `AGENTS.md`；此文件仅保存 2026-07-29 的治理背景。

## 目的

本标准把 Dart、Flutter 和 Google 工程实践转化为本项目可执行的开发门禁。外部规范负责
回答“什么是健康的代码变更”，项目本地阈值负责回答“现有超长页面如何持续收敛”。

行数只是复杂度信号，不能替代职责、依赖方向、测试和真实可达性检查。拆成多个互相耦合
的小文件不算完成重构。

## 采用的官方标准

### Effective Dart

来源：[Effective Dart](https://dart.dev/effective-dart)、
[Style](https://dart.dev/effective-dart/style) 和
[Documentation](https://dart.dev/effective-dart/documentation)。

- 使用 `dart format` 保持一致格式，默认遵守 80 字符行宽与标准 import 排序。
- API 和实现保持简洁，删除重复包装、无效状态与不必要依赖。
- 文档应准确、简洁并解释职责。注释语法和语言继续服从本仓库更严格的 `AGENTS.md`：
  结构说明使用中文 `/** ... */`，方法内部意图使用中文 `//`。

### Flutter 应用架构

来源：[Flutter Guide to app architecture](https://docs.flutter.dev/app-architecture/guide)。

- 以职责分离为首要原则，UI、应用状态、数据访问和外部服务不得混成一个所有者。
- View 只负责展示和转发交互；状态与编排进入 controller/view model/application；
  Repository 管理数据语义；Service/平台 adapter 隔离外部系统。
- 依赖只能指向稳定的内层合同。跨 feature 流程通过 Route 输入、应用服务或共享
  domain contract 协作，不直接导入另一 feature 的 Widget 树。
- 不为追求目录形式机械创建层；无状态叶节点可以保持简单，直到它确实拥有状态或业务
  编排职责。

### Google 工程实践

来源：[Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)、
[Code review standard](https://google.github.io/eng-practices/review/reviewer/standard.html) 和
[What to look for](https://google.github.io/eng-practices/review/reviewer/looking-for.html)。

- 每次变更只完成一个自洽目标；相关测试与生产代码放在同一变更中。
- 纯重构不混入新功能或无关清理，降低审查面和回归定位成本。
- 变更必须明确改善整体代码健康度，不用“完美”阻塞可验证的渐进改进。
- 测试覆盖行为和边界，而不只验证被提取的组件能够单独构建。

Google 的行数示例描述的是代码评审变更大小，不是通用的单文件限制；Flutter 和
Effective Dart 也没有规定页面必须小于某个统一行数。下面的 200/500/1000 是本项目
根据当前页面债务制定的本地治理规则。

## 项目本地体积门禁

| 行数 | 级别 | 处理规则 |
| --- | --- | --- |
| `≤200` | 最佳实践 | 新增页面或组件的默认目标；保持一个清晰职责。 |
| `201—500` | 关注区 | 允许存在；评审时检查是否混入状态、数据访问或多个视觉区域。 |
| `501—1000` | 警戒线 | 禁止新增；既有文件必须登记只降不升预算并按一致性边界拆分。 |
| `>1000` | 重构线 | 强制列入重构路线；禁止新增，后续相关修改必须优先降低预算。 |

例外不能只用“拆分不方便”解释。必须同时记录职责边界、保留原因、测试证据和下一次
收敛入口。文件降到 500 行以内后，应从历史预算清单移除。

## 每个变更的执行门禁

1. 先列出受保护行为和获授权改变；没有删除授权的入口、快捷键、状态和返回路径全部保留。
2. 选择一个自洽切片，优先抽取低状态、窄依赖、可独立测试的叶节点。
3. 运行 `dart format`，并确保 `flutter analyze` 零问题。
4. 运行架构合同与相关 focused tests，确认依赖方向、文件预算和页面挂载。
5. 运行完整测试与 `flutter build windows --debug`。
6. 业务或 UI 代码变化后启动真实 Windows 应用；涉及交互时按入口点击并检查截图。
7. 停止编辑后做独立只读审查，逐项确认 schema、筛选、播放队列、缓存队列、用户数据、
   受保护行为和页面可达性。
8. 一次提交只包含本次目标，排除用户已有改动、生成文件和临时产物。

## 本轮落地

- 架构合同扫描全部 presentation 文件，拒绝新的 500 行以上文件。
- 既有 500 行以上文件登记只降不升预算；1000 行以上文件同时进入强制重构清单。
- `RecentPlaybackView` 和 `TagEditorDialog` 已从媒体库聚合 Widget 文件迁为独立叶节点；
  原页面回调、筛选语义、filtered queue 和用户数据保持不变。
- 下一批继续按页面级挂载证据拆分 sidebar 或 top bar，不进行一次性大搬迁。
