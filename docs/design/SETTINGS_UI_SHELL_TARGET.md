# 设置工作区 UI 外壳重构目标

## 任务范围

本轮只调整设置 Route 的共享标题栏、首页容器和分组入口表面。`CacheSettingsPage` 继续拥有
设置 controller、缓存诊断、备份、删除确认、快捷键冲突与 section 导航；二级页的内容和回调
不在本轮重写。

## Before

- 顶部使用单行通用 `AppBar`，首页与二级页缺少“应用设置 / 维护工作区”的上下文层级。
- 首页被限制在较窄的单列中，首屏先出现一行说明，再进入连续分组，桌面窗口的横向空间没有
  转化为清晰的导航结构。
- 分组容器和入口使用接近的实色，入口之间主要依赖间距区分；设置入口的状态信息和可进入性
  反馈不够集中。

## After

- 顶部使用两级标题：首页显示“维护工作区 / 设置”，二级页显示“设置 / 当前分区”；刷新、
  返回和快捷键命中区保持原 key 与原回调。
- 首页扩展为桌面设置工作区，增加稳定的首页上下文头部，分组标题、分组容器和入口 surface
  形成明确的三层层级。
- 入口保留现有标题、说明、状态 chip 和右侧 chevron，使用低对比度交互表面表达 hover、focus
  和 press；不引入列表 stagger、blur 或全量状态重算。
- 紧凑窗口继续使用可滚动单列；宽窗口只增加可读空间，不改变设置入口顺序或二级页导航。

## 明确不变

- `CacheSettingsPage` 的 section owner、设置持久化、备份/缓存命令、删除确认和快捷键录制不变。
- `settings.category.*`、`settings.section.back`、`settings.refreshCacheStats` 及其它既有 key、
  route、返回路径和回调保持可达。
- schema、`FilterQuery`、`TagQueryService`、filtered queue、PlayerBackend、缩略图/媒体详情队列、
  stable identity 和用户数据不变。

