# CURRENT_TASK.md

> 本文件只保存当前活跃任务、最近稳定基线、已确认阻塞和下一步入口。已完成的详细记录进入 `CHANGELOG.md` 与对应 Chat 文档。

## 活跃任务

### 2026-07-21 Windows / macOS 正式版安装包

- 目标：基于 `pubspec.yaml` 的 `0.1.0+1` 构建 Windows x64 Release 安装器与 macOS Release DMG，不改变业务、数据或播放语义。
- 当前状态：已完成。Windows 本地 Release 安装器、隔离安装/启动/卸载冒烟均通过；独立 macOS runner 已完成 Release 构建、10 秒启动检查、DMG 生成与上传。
- Windows 安装器使用当前用户目录安装，卸载时保留用户数据库、标签、收藏和播放记录。
- macOS bundle identifier 已从模板占位符收敛为 `com.zero1412.localtagplayer`，Finder 展示名为 `Local Tag Player`。
- 仓库当前没有 Windows Authenticode 与 Apple Developer ID / notarization 凭据；生成的安装包必须明确标记为未签名或未公证，不能宣称通过系统信任链。
- Windows 安装器：108,571,720 字节，SHA-256 `0ad9b542bed463d9036111c1a2a7acc2e1e0fe4ff4d4261339665890a506fe36`。
- macOS DMG：42,757,735 字节，SHA-256 `536c53e804e2267ccecc3d6991da66561e25bc6676cf94119e5d3222b03a5094`；Actions 运行 `29815594317` 的 Windows / macOS job 均成功。

### 2026-07-21 播放器队列定位语义与媒体卡片重命名

- 目标：消除重复“回到选中”入口，阻止“回到播放”覆盖浏览选中，并把统一文件重命名能力接入媒体卡片“更多”。
- 当前状态：已完成。
- 队列顶部只保留搜索和删除；“回到选中”只在选中项离开视口时出现在底部，避免同一动作出现两次。
- “回到播放”现在只滚动到真实播放项，不再修改 `selectedIndex`；播放事实与队列浏览焦点保持独立。
- 网格卡片、紧凑列表和本地目录卡片的“更多”菜单复用同一重命名弹窗、物理改名与 SQLite 回滚事务，没有复制校验或稳定身份逻辑。
- 卡片改名只刷新依赖文件名/路径的可见结果、搜索和排序缓存，不触发无关的全库标签计数重算。
- 隔离临时文件冒烟完整覆盖“确认重命名 → Windows 文件占用回退 → 重新打开 → seek 恢复 → 恢复播放”，保持同一 `videoId`、手动标签和收藏。
- 页面级回归通过真实 `LibraryPage` 点击“更多 → 重命名文件”，确认改名后名称升序立即重排、旧关键字立即失效、新关键字立即命中，且 `resultCounts` 调用次数不增加。

## 当前稳定基线

- 产品边界：Tag 驱动的本地视频发现播放器，不扩展字幕、音轨、逐帧或 A-B loop 等专业播放器能力。
- 数据边界：SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容与顺序、标签来源语义均未改变。
- 验证：236 项测试通过，3 项显式 benchmark 跳过；focused 播放恢复冒烟、真实页面改名刷新回归、`flutter analyze`、Windows debug build 均通过。1249×714 最新 Debug 实窗确认“回到播放”后选中项仍保留、顶部无重复入口，并从卡片“更多”打开统一重命名弹窗后取消；未修改真实媒体。
- 架构基线：`Architecture Baseline 0.5.50`。

## 已确认阻塞

- 外部跨平台规划 `<private-planning-document>` 当前不存在；本轮依照仓库内长期规则和现有跨平台边界实施。

## 下一步入口

1. 对外公开分发前配置 Windows Authenticode 证书、Apple Developer ID Application 证书与 notarization 凭据，重新打包并验证 SmartScreen / Gatekeeper。
2. 若继续精修，优先统一“回到播放 / 回到选中”的 tooltip 与无障碍状态描述，继续保持播放事实和浏览焦点分离。
3. 若扩展改名覆盖，优先补紧凑列表与本地目录视图的同一页面级确认回归；继续复用当前事务和轻刷新链路。
