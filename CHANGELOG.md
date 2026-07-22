# CHANGELOG.md

## 2026-07-22 · 播放器 GPU 画质超分

- 播放器进度条齿轮的一级设置新增“GPU 画质超分”，默认关闭、整行可点，并明确提示只放大低分辨率画面；开关通过现有播放设置串行持久化，旧 `settings.json` 缺字段时保持安全默认值。
- 新增 `PlayerVideoSuperResolution`，开启时向 `PlayerBackend` 应用 `ewa_lanczossharp`、Lanczos chroma、sigmoid upscaling 与 resize-only；关闭时恢复 Lanczos 低开销基线。每次媒体 open 前后重放完整配置，避免后端状态重建后只剩 UI 选中态。
- 当前发布依赖的 libmpv `v0.36.0-403` 未包含新版 Intel/NVIDIA `d3d11vpp scaling-mode`，因此本轮是本地 GPU 高质量上采样，不宣称厂商 AI 超分；Flutter UI 不读取或处理视频帧，也不触发 filtered queue、媒体详情或缩略图重算。
- 同一 `PlayerBackend` 的超分属性应用按请求串行化，避免媒体 open 前后重放与用户点击交错后留下半套旧配置；播放诊断新增超分设置、实际 GPU 缩放器与 resize-only 状态。
- focused 5 项及全量 237 项测试通过，3 项显式 benchmark 跳过，`flutter analyze` 与 Windows Debug 构建通过。
- 显式启动 Debug 路径时，Windows 应用激活实际路由到已安装 Release 进程；准备点击时自动化又检测到用户输入并按安全规则中止。尚未完成新构建的“进入播放器 → 齿轮 → 开关 → 诊断”真实点击截图，已在 `CURRENT_TASK.md` 保留准确复测路径。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、硬解设置、稳定身份或用户标签/收藏数据。

## 2026-07-21 · GitHub 首次公开发布与隐私收口

- README 从内部进度索引重写为面向首次访问者的产品说明，完整交代创建目的、标签发现闭环、特色功能、技术栈、架构边界、下载方式、平台限制和本地数据策略。
- 正式包工作流支持 `vX.Y.Z` 标签发布；只有 Windows x64 安装器与 macOS DMG 都构建成功，才创建 GitHub Release，并同时上传两端 SHA-256 校验文件。
- 对当前文件和 Git 历史执行隐私审计，删除公开历史中的个人邮箱、本机用户名/盘符路径和 `.codex/config.toml`；提交者元数据改为 GitHub noreply 身份并安全强制更新远程 `master`。
- `.gitignore` 增加本地数据库、日志、媒体样本、环境变量、证书、签名文件、安装包、`.local/` 与 Codex 本地配置过滤；这些本地信息继续保留，不进入后续提交。
- 定向扫描未发现已跟踪的媒体、数据库、日志、私钥、签名证书、环境变量或 API token。仓库中的 FFmpeg/FFprobe 为公开第三方运行时依赖，README 已明确当前尚无项目级许可证，后续需单独收口再分发说明。
- `v0.1.0` 的版本解析、Windows、macOS 与公开发布 job 全部成功；Release 含 Windows/macOS 安装包和两份 SHA-256 校验文件，远程 README 的核心章节与脱敏状态已复验。
- GitHub 服务端仍可按已知旧哈希命中重写前的无引用提交对象；普通 clone 与公开 refs 已清理，彻底删除该平台缓存仍需 GitHub Support 执行服务端 purge。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放器/缓存后端、标签语义或用户数据。

## 2026-07-21 · 媒体卡片文件菜单收口

- 媒体库网格卡片、紧凑列表和本地目录视图的“更多”菜单移除“编辑标签 / 重命名文件”，只保留“打开文件 / 删除文件”；播放器详情中的标签编辑与重命名入口不变。
- “打开文件”通过页面层把当前 `VideoItem.path` 交给 `FileSystemAdapter.revealInFileManager`，Windows 使用 Explorer `/select` 定位具体文件，不打开媒体库 root 或资源目录。
- 双项菜单限制为 136–156px 宽、40px 条目最小高度和 4px 垂直留白，统一网格/列表表面、图标间距和删除警示色。
- 页面级回归锁定当前卡片路径、双项文案、已移除动作和紧凑几何；完整 235 项测试通过，3 项显式 benchmark 跳过，`flutter analyze` 与 Windows debug build 通过。
- 1248×714 隔离 Debug 实窗确认菜单无遮挡、错位或溢出；点击 `40712-1080p` 的“打开文件”后，资源管理器打开到对应目录并选中 `40712-1080p.mp4`，未执行改名或删除。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放器/缓存后端、标签来源语义或用户数据。

## 2026-07-21 · Windows / macOS 正式版打包链路

- 新增 Inno Setup Windows x64 安装器定义，使用当前用户目录安装，并明确保证卸载不删除用户数据库、标签、收藏或播放记录。
- 新增 Windows 与 macOS Release 打包流水线：Windows 生成 `.exe` 安装器，macOS 在真实 runner 启动检查后生成带 Applications 入口的 `.dmg`，两端同时附带 SHA-256。
- macOS 发布元数据移除 `com.example` 占位符，bundle identifier 改为 `com.zero1412.localtagplayer`，Finder 展示名统一为 `Local Tag Player`。
- 当前仓库未配置 Windows Authenticode、Apple Developer ID 与 notarization 凭据，因此产物明确按未签名/未公证交付；配置证书前不得宣称系统信任链通过。
- Windows 安装器完成隔离安装、关键运行时检查、Release 进程 10 秒存活与卸载冒烟；最终 108,571,720 字节，SHA-256 为 `0ad9b542bed463d9036111c1a2a7acc2e1e0fe4ff4d4261339665890a506fe36`。
- Actions 运行 `29815594317` 的 Windows / macOS job 均成功；macOS 通过 Release 进程 10 秒启动检查，DMG 为 42,757,735 字节，SHA-256 为 `536c53e804e2267ccecc3d6991da66561e25bc6676cf94119e5d3222b03a5094`。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放器/缓存后端、标签语义或用户数据。

## 2026-07-21 · 卡片改名页面刷新回归

- 新增真实 `LibraryPage` 页面级回归，以隔离临时文件完成“卡片更多 → 重命名文件 → 确认”的完整交互，不访问用户媒体。
- 回归锁定名称升序下 `charlie → alpha` 后卡片立即移动到 `bravo` 前，并验证旧关键字不再命中、新关键字立即命中。
- 记录改名前后的 Repository `resultCounts` 调用次数，确认改名与后续关键字输入只刷新可见结果，不启动无关的全库标签计数。
- 完整 236 项测试通过，3 项显式 benchmark 跳过；`flutter analyze` 与 Windows debug build 通过。未修改生产代码、SQLite schema、过滤语义、filtered queue、缓存队列或用户数据。

## 2026-07-21 · 播放器定位语义与卡片重命名收口

- 播放队列移除顶部重复“回到选中”图标，只在选中项离开视口时保留底部定位入口；“回到播放”改为只滚动到实际播放项，不再覆盖用户正在浏览的 `selectedIndex`。
- 媒体库网格卡片、紧凑列表和本地目录卡片的“更多”菜单新增“重命名文件”，复用播放器既有弹窗、平台文件系统边界、同一 `videoId` 路径事务与失败回滚。
- 卡片改名只失效文件名、路径、搜索和排序相关缓存，保留稳定标签计数，避免 11,170 条媒体库为不改变标签的动作执行全库计数刷新。
- 新增隔离临时文件完整冒烟，确认文件占用时按 pause/stop/rename/open/seek/play 恢复播放，原文件消失、新文件存在，手动标签、收藏和稳定身份保持。
- 完整 235 项测试通过，3 项显式 benchmark 跳过；focused 冒烟、`flutter analyze`、Windows debug build 与 1249×714 实窗点击截图通过。真实媒体只打开重命名弹窗后取消，没有改名或删除。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容/顺序、`PlayerBackend` contract、缓存队列或标签来源语义。

## 2026-07-21 · 播放器文件重命名与标签入口解耦

- 播放器详情的文件名铅笔改为“重命名文件”，下方“添加标签 / 继续添加”继续只维护 manual 标签，两个入口不再触发同一动作。
- 重命名弹窗只编辑 basename、只读保留扩展名，并校验空值、路径字符、系统保留名和尾部点/空格；非法输入、同名占用和失败状态都有直接中文反馈。
- `FileSystemAdapter` 增加拒绝覆盖的重命名边界；媒体库以 SQLite batch 把同一 `videoId` 更新到新 mutable path，提交失败尝试恢复原文件名。文件句柄占用时播放器会受控停止、重试并恢复原位置和播放状态。
- 测试覆盖平台重命名/拒绝覆盖、稳定身份与手动标签/收藏/进度持久化、两个 UI 入口职责和 DialogRoute 输入生命周期。完整 233 项测试通过，3 项显式 benchmark 跳过；`flutter analyze` 与 Windows debug build 通过。1249×714 最新 Debug 实窗确认弹窗无错位、遮挡或溢出，取消后原文件名、播放和 11,170 条媒体库结果保持。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容/顺序、`PlayerBackend` contract、缓存队列或标签来源语义。

## 2026-07-21 · 播放器 Route、转场与反馈收口

- 媒体库在播放器 Route 压入前先提交语义排除，播放器根节点声明独立 route scope；Windows UIA 在播放期间不再残留媒体库控件，返回后立即恢复媒体库语义。
- 正常返回先暂停并保留最后一帧，原生 stop/dispose 延后到反向 Route 启动后串行执行；pause 失败时仍提前 stop 兜底，修复返回中间帧黑屏和 `0:00 / 0:00` 重置态闪现。
- 列表/详情和设置页层级统一为“旧内容退出、新内容进入”的分段转场；播放、暂停、seek、上下条、倍速、音量和全屏快捷键增加短时 HUD，并同步恢复底部控制条。
- 队列搜索改用“查找并播放下一条”文案，固定状态行明确成功、无匹配和空查询结果；详情路径提高对比度和字号，非收藏项隐藏空心心形，保留无障碍收藏状态。
- 229 项测试通过，3 项显式 benchmark 跳过；`flutter analyze`、Windows debug build 和 1249×714 最新 Debug 实窗连续点击通过。70ms 返回中间帧保留真实视频画面与时间，未见黑帧、重置态、层级重叠、遮挡或溢出。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容/顺序、`PlayerBackend`、缩略图/media 队列、稳定身份或用户数据。

## 2026-07-19 · Apple UI Phase 3 维护页缩放与键盘收口

- 备份、缓存维护动作新增 125%/150% 键盘遍历回归；标签详情使用显式视觉顺序，标签组菜单限制高度并保持字段锚点，维护主题补齐深色弹层画布与紫色交互态。
- 标签详情卡片改用真实 `Material` 表面；开关固定浅色滑块、深色轨道及单层 hover/focus 反馈，不再出现黑色孔洞、整轨覆盖或双重光圈；合并和删除入口改为只读“检查影响”，反馈层明确未执行并默认聚焦安全返回。
- 标签编辑器添加未保存状态与精确移除 tooltip，取消仍不写入标签关系。
- 125%/150% 真实窗口连续完成标签详情下拉、开关 hover、高风险反馈取消和标签编辑器未保存取消；150% 下拉展开前会把锚点移入可视区，末项不再被窗口裁切，高风险反馈也固定使用深色维护表面。临时标签修改已取消，没有写入用户数据。
- 完整 226 项测试、`flutter analyze` 和 Windows debug build 通过；未改 schema、过滤/队列、备份/缓存后端或用户数据。

## 2026-07-19 · 删除偏好、全局返回与快捷键录制

- 删除弹窗记忆回收站选择并增加“不再提示”；单条、批量和播放器队列共享设置，跳过提示时严格按已保存最终状态执行，持久化失败不继续删除。
- 设置“数据与维护”增加“删除文件”二级页，分别控制是否提示和是否移入回收站；删除浮层统一为深色维护主题，100%/150% 文字缩放下保持可读。
- 所有非主路由支持鼠标返回侧键与可配置“返回上一页”；快捷键改为直接录制键盘单键/组合键，冲突原位红字提示且不交换绑定，录制结束后的页面返回焦点保持稳定。
- 完整 221 项测试、`flutter analyze`、Windows debug build 与真实窗口连续点击通过；未执行媒体删除，验收偏好已恢复。SQLite schema、标签过滤、filtered queue、播放器/缓存后端和用户数据语义不变。

## 2026-07-19 · Apple UI 播放设置浮层与播放器控制条

- 设置页下拉路由改用深色次级表面与紫色交互反馈，继续观看和播放解码的展开选项恢复清晰对比度；选项含义、确认门禁与保存行为不变。
- 播放器普通控制键移除常驻半透明黑底，只在 hover、press 和 focus 时显示反馈；紫色主播放按钮保持视觉主次。
- 猫咪进度焦点从 26px 调整为真实 28px 绘制，端点映射随尺寸校准，不改轨道布局、seek 或预览链路。
- focused tests、完整 214 项测试、`flutter analyze`、Windows debug build 和 1249×714 真实窗口点击截图通过；验收视频恢复 0:00 暂停状态。
- 未修改 schema、标签/过滤语义、filtered queue、`PlayerBackend`、缓存队列、解码值或用户标签/收藏数据。

## 2026-07-19 播放器猫咪进度焦点与当前文件定位

- 恢复主进度条历史矢量猫耳史莱姆焦点，保留当前 Apple 主题轨道、悬停/reduced-motion 时序及全屏 1–1.25 倍有限缩放；音量条继续使用紧凑圆点。
- 文件按钮改用“在文件管理器中显示当前视频”明确文案，并通过播放/选择索引分离测试锁定 `currentItem.path`，避免定位队列选中项或媒体库目录。
- focused tests、完整 213 项测试、`flutter analyze` 与 Windows debug build 通过；真实 Windows 窗口确认资源管理器选中当前播放的 `7月12日(4).mp4`。
- 未修改 schema、标签过滤语义、filtered queue、`PlayerBackend`、缓存队列或用户数据。

## 2026-07-18 · Apple UI 播放队列操作层与顶栏联动

- 左滑操作层在完全收起时卸载，队列项成为当前播放项时清除旧滑动进度，修复收藏/删除动作与播放徽标重叠；主动左滑能力及收藏、删除回调不变。
- 非全屏宽屏队列折叠时标题栏同步收起，顶部 64px 热区悬停临时显示、移开收回，队列展开后标题栏常驻；全屏覆盖队列保持原行为，辅助导航继续可达返回入口。
- focused tests、完整 212 项测试、`flutter analyze` 和 Windows debug build 通过，3 项 benchmark 跳过；1249×714 实窗完成播放项、队列/顶栏三态及 Phase 3 连续截图。
- 注入滚轮下 140ms 顶部恢复没有闪回，暂不调整；真实 Precision Touchpad 惯性仍需人工复核。filtered queue、播放索引、播放器后端、缓存队列和用户数据未改变。

## 2026-07-18 · Apple UI 排序入口与菜单几何统一

- expanded 媒体库排序字段收敛为 168px，六项下拉菜单强制继承同宽和同左边缘，修复触发按钮偏宽而菜单按内容收缩的割裂感。
- 方向按钮继续保留 48px 命中区；动作带微调为 380px，少量余量只用于排序与低频动作分组，普通/多选切换不推动搜索框。
- 新增入口/菜单几何回归并复验 150% 文字缩放；完整 211 项测试通过，3 项 benchmark 跳过，`flutter analyze` 和 Windows debug build 通过。
- 未修改 SQLite schema、过滤与排序语义、filtered queue、播放器/缓存队列或用户数据；真实触控板与 Phase 3 连续截图待用户回复“已空闲”后补验。

## 2026-07-18 · Apple UI 媒体库顶部边界与 Phase 3 维护页补齐

- expanded 媒体库顶部信息区改为只在结果绝对顶部显示；离开顶部后即使中途停止或反向滚动也保持收起，回到 offset 0 并稳定 140ms 后才恢复。
- 回顶入口保留越过首次视口的显示条件和距离型平滑回顶，视觉改为 44px 深色无亮环表面与紫色 `chevron.up`，继续支持 tooltip、键盘、Semantics 和 reduced motion。
- 视频数据备份页重排为保护范围、响应式同步状态和维护动作；标签编辑器统一维护页深色材质、标题上下文、搜索清除与当前/候选标签分区。所有备份、导出、标签来源和保存回调保持。
- focused tests 与完整 210 项测试通过，3 项 benchmark 跳过；`flutter analyze`、Windows debug build 通过。1249×714 实窗补齐“日期”六项菜单终态，后续滚动和 Phase 3 点击因检测到用户输入而停止并保留精确复测路径。
- 未修改 SQLite schema、过滤语义、filtered queue、播放器/缓存队列、备份后端、标签来源或用户数据。

## 2026-07-18 · Apple UI Phase 1 排序动作带补齐

- expanded 媒体库把固定动作带中的大块无语义留白改为弹性当前排序字段，形成“字段、方向、多选、视图”的连续操作序列；多选切换时搜索宽度仍保持稳定。
- 当前字段显示真实排序状态并复用原菜单与回调，medium/compact 图标形态不变；没有新增排序计算、列表 rebuild 或装饰动画。
- 完整 205 项测试、`flutter analyze`、Windows debug build 和 1248×714 真实窗口截图通过，3 项 benchmark 跳过；自动展开菜单因检测到用户输入而停止，菜单行为由 widget 回归覆盖。
- 未修改 SQLite schema、过滤语义、filtered queue、播放器/缓存队列或用户数据。

## 2026-07-18 · Apple UI Phase 1 媒体库顶部信息区复修

- expanded 媒体库移除搜索与动作外层的大圆角工具容器，收紧标题排版和垂直留白，让首排视频成为更明确的视觉中心。
- 搜索与排序间距收敛为 12px；排序、多选、视图切换按语义分组，标签入口改为中性次级动作，活动状态仍使用紫色。
- 保持真实 `TextField`、筛选/排序回调、固定 360px 动作带和 48px 命中区，多选切换不改变搜索宽度。
- 新增桌面间距与 150% 文字缩放测试；完整 205 项测试、`flutter analyze`、Windows debug build 和 1248×714 真实窗口截图通过，3 项 benchmark 跳过。
- 未修改 SQLite schema、过滤语义、filtered queue、播放器/缓存队列或用户数据。

## 2026-07-18 · Apple UI Phase 3 目录管理与 Missing/Relink

- 目录管理由通用弹窗改为完整深色维护工作区，统一状态摘要、目录卡片、添加、扫描和解除管理入口；解除管理明确说明只隐藏内容并保留本地文件与全部稳定身份数据。
- Missing/Relink 统一为状态摘要、数据保留提示和响应式待处理列表；批量路径替换重排为路径映射、只读摘要、搜索、状态列表和动作区，保留原 fingerprint 校验、二次确认、重试与审计流程。
- 维护主题新增深色弹窗包装和高对比度按钮 token，修复页面局部主题之外弹出的浅色确认层；危险动作仍使用明确红色，不以动效弱化风险。
- 新增 150% 文字缩放、数据策略、弹窗材质和按钮配色回归；完整 204 项测试、`flutter analyze`、Windows debug build 与 1248×714 真实窗口连续截图通过，3 项 benchmark 跳过。
- 未修改 SQLite schema、过滤语义、filtered queue、播放器/缓存后端、relink 服务、稳定身份或用户数据。

## 2026-07-18 · Apple UI 主界面信息架构复修

- 媒体库主界面从后台工具条式布局改为页面标题、主搜索操作和按需筛选状态三层结构；保留现有视频卡片及全部搜索、排序、多选、视图和扫描功能。
- 左栏按浏览与资料库重组，使用克制选中胶囊和真实资料库统计；移除没有实际容量语义的固定进度装饰，不删除任何导航或目录动作。
- 右侧竖排标签恢复条退出真实布局，改由标题区横向“标签”按钮展开/收起原标签发现侧栏；收起后结果区完整回收宽度。
- 完整 202 项测试通过，3 项 benchmark 跳过，`flutter analyze` 与 Windows debug build 通过；1248×714 真实窗口完成标签开合及 100%/125%/150% 文字缩放截图验收。
- 未修改 SQLite schema、过滤语义、filtered queue、播放器/缓存后端、稳定身份或用户数据。

## 2026-07-18 · Apple UI Phase 3 缓存诊断

- 缩略图缓存设置页改为响应式诊断面板，统一展示服务状态、有效缓存覆盖、四项关键指标、后台任务、失败语义与失败处理；加载态与终态保持相同结构锚点。
- `CacheStats`、失败属于缺失子集、失败详情上限、队列忙碌禁用、重试与清除失败标记回调全部保持；没有新增磁盘读取、缓存任务或 FFmpeg 调用。
- 新增 150% 文字缩放和失败动作 focused tests；完整 202 项测试通过，3 项显式 benchmark 跳过，`flutter analyze` 与 Windows debug build 通过。
- 1248×714 真实 Debug 窗口完成缓存加载、终态和返回截图；标签中心搜索/清除/详情、设置四入口与二级返回也已补齐，无明显遮挡、错位或横向溢出。
- 未修改 SQLite schema、缓存有效性、`ThumbnailService` 调度、FFmpeg/FFprobe 边界、filtered queue、稳定身份或用户数据。

## 2026-07-18 · Apple UI Phase 3 标签中心与设置入口

- 标签中心改为圆角双栏维护工作区，搜索使用稳定 `TextField` 链路；详情按使用情况、标签属性、批量 manual 与高风险操作分组，folder/manual、引用检查和全部原回调保持。
- 设置首页以实色分组面板承载四个共享交互表面，统一图标层级、状态摘要与 hover/focus/press 反馈；设置二级内容卡片使用共享 14px 圆角并遵守 reduced motion/high contrast。
- 人工完成播放器队列“左滑展开 → 回拖一半 → 快速反向 → 展开终态”并取得真实截图，收藏/删除动作完整露出，面板等高且无回弹、错位、遮挡或溢出。
- 完整 200 项测试通过，3 项显式 benchmark 跳过；`flutter analyze` 和 Windows debug build 通过。Phase 3 最新 EXE 的窗口捕获被用户前台游戏占用，已停止抢占，页面真实点击待窗口空闲后补验。
- 未修改 SQLite schema、标签删除/合并语义、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存队列、稳定身份或用户数据。

## 2026-07-18 · Apple UI Phase 1 媒体库主工作区

- 左侧主导航、顶部搜索/筛选工具栏、右侧标签发现和视频结果卡片统一为 Apple 式实色结构层级，移除旧式强边线、双重投影和分散控件外观；所有现有入口、筛选语义和 filtered queue 保留。
- 视频卡片增加 14px 圆角内容表面，以及克制的 hover、焦点、多选、按压反馈；reduced motion 停用结构缩放和侧栏位移，高对比度继续使用清晰描边。
- 125%/150% 文字缩放动态增加两行标题槽位，并对高 DPI 亚像素舍入留出安全余量；150% 实体卡片测试确认长中文标题无 RenderFlex 溢出。
- 100% 真实窗口完成搜索/清除、标签展开/父子选择/清空、打开视频/返回连续验收；返回媒体库后窗口与进程保持，11,163 条结果恢复。125%/150% 复验推动结果状态按文字倍率增加桌面宽度预算，两档均完整显示五位数结果数量，卡片标题和左右侧栏无裁切、重叠或溢出。
- 完整 198 项测试通过，3 项显式 benchmark 跳过；`flutter analyze` 和 Windows debug build 通过。
- 未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存队列、稳定身份或用户数据。

## 2026-07-18 · 播放器返回复验与三档文字缩放

- 受控 `flutter run -d windows` 中复现“媒体库 → 播放器 → 左上返回”，11,163 条来源 filtered queue 正常回到媒体库，窗口、进程与筛选状态保持；此前进程消失归因于调试会话/窗口句柄丢失，不修改正确的导航语义。
- 新增仅 Debug 生效的 `LOCAL_TAG_PLAYER_QA_TEXT_SCALE`，只接受 1.0/1.25/1.5，供真实窗口验收复用 `MediaQuery.textScaler`，Release 与 Windows 全局设置不受影响。
- 1248×714 的 125% 截图发现底部时间文本挤压三段式控制条；现在按文字倍率提高时间显示门槛，空间不足时仅隐藏辅助时间，中央传输控制与全部入口保留。125%/150% 复验无 RenderFlex 溢出。
- 150% 媒体库卡片标题裁切已由后续主工作区响应式改造修复；播放器左滑快速反向现已由人工手势与真实终态截图闭环。
- 完整 196 项测试、`flutter analyze` 和 Windows debug build 通过，3 项显式 benchmark 跳过；未修改 SQLite schema、过滤语义、filtered queue、`PlayerBackend`、缓存队列、稳定身份或用户数据。

## 2026-07-18 · Apple UI Phase 2 播放器真实窗口验收

- 在 1248×714 真实窗口完成播放/暂停、seek、列表/详情往返连续截图；控制状态、时间与进度反馈同步，切换侧栏无残影、遮挡、错位、溢出或视频区域抖动。
- 在 2560×1440 全屏完成右侧覆盖队列唤出、离开自动收起与 Esc 返回窗口模式截图；队列显示期间视频纹理未被横向压缩，顶栏语境与中央传输控制保持稳定。
- Windows 自动化无法保持左滑隐藏动作层后，人工配合完成快速反向，定时截图确认展开终态稳定；单键 `F` 被中文输入法候选截获，UI 全屏按钮路径通过。
- 初次点击返回后的进程消失后来在受控 `flutter run` 会话中无法复现；复验确认返回媒体库、窗口与筛选状态均正常，原记录已纠正为调试会话/窗口句柄丢失。
- 本轮仅补验收记录，未修改 SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体详情队列、稳定身份、业务代码或用户数据。

## 2026-07-18 · Apple UI Phase 2 播放器空间与动效精修

- 顶栏标题改为对称居中布局；底部控制改为左右信息/工具与中央传输三段结构，46px 主播放动作使用短淡入缩放，控制层显示结合淡入与克制短位移。
- 全屏队列从逐帧压缩视频宽度改为根 Stack 内的固定覆盖层；右侧滑入/淡入期间视频纹理尺寸保持不变，原右缘热区、隐藏计时、队列滚动和功能入口全部保留。
- 列表/详情增加方向连续过渡并在结束后卸载旧列表；队列左滑按剩余距离 ease-out 吸附且可被下一次拖动中断，不增加整列 stagger 或后台媒体读取。
- 共享交互表面支持可选无描边 chrome，普通态更克制，键盘焦点与高对比度轮廓不降级；reduced motion 移除位移/缩放并保留短淡入。
- focused widget 126 项、完整 194 项测试、`flutter analyze` 和 Windows debug build 通过，3 项显式 benchmark 跳过；50,000 条队列搜索约 29ms。
- 最新 Debug EXE 已启动且唯一定位，但窗口激活时检测到用户正在目标窗口输入，自动 QA 按规则停止，真实点击与截图路径记录在 `CURRENT_TASK.md`。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体详情队列、稳定身份和用户数据均未改变。

## 2026-07-18 · Apple UI Phase 2 播放器全布局

- 新增播放器共享深色 token 与 `playerWorkspaceTheme`，统一画布、结构/抬升表面、描边、文字、状态、阴影、弹窗、菜单和输入，删除页面私有主题分支。
- 顶栏使用 40px 共享交互表面，并同时展示当前文件名、filtered queue 序号与筛选摘要；视频容器升级为内容优先的大圆角结构表面，底部控制改为小范围实色浮动 chrome，无大面积毛玻璃。
- 右侧列表/详情、队列搜索、二级标签、卡片状态、左滑动作和离屏定位统一为克制实色层级；队列宽度收敛到 360–460px，所有既有功能入口和 ValueKey 保留。
- 设置一/二/三级浮层、失败恢复与删除确认统一材质并支持 reduced motion；主进度条从装饰性猫耳焦点收敛为简洁圆点和单色紫色轨道，seek、帧预览、音量与全屏行为不变。
- 播放器 30 项 focused widget tests、完整 193 项测试、`flutter analyze` 和 Windows debug build 通过，3 项显式 benchmark 跳过；50,000 条队列搜索约 25–34ms。
- Windows 自动化成功启动并唯一定位 Debug 窗口，但连续两次激活均失败并返回 `failed to activate captured window`，因此没有复用旧句柄执行点击或截图；人工复测路径已记录在 `CURRENT_TASK.md`。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体详情队列、稳定身份和用户数据均未改变。

## 2026-07-18 · Agent Eval 成本门槛与 Apple UI Phase 1 搜索状态

- Agent Eval 增加 suite 默认工具调用、输入 token 和输出 token 预算；超限成为确定性硬失败，报告保存生效门槛与实际 usage。同一 Codex 工具调用的 started/completed 事件按 `item.id` 去重。
- 来源 filtered queue 与播放器队列回退明确升级为 Level 3；`reg-player-source-queue` 在 12 次工具、600,000 输入和 8,000 输出 token 单轮门槛内重新执行 N=5，5/5、平均 100 分、`stable=true`，累计输入较旧基线下降约 63%。
- Apple UI Phase 1 首个组件族迁移媒体库搜索与筛选状态：保留唯一真实 `TextField` 输入链路，搜索表面改用真实 hover/focus 反馈，筛选状态建立低对比度实色层级并显式展示“全部视频”上下文。
- 关键词清除和清空筛选使用 40px 共享交互表面；活动 chip 保持中性、结果数以强调点和主要文字表达，状态区增加 live-region 语义并遵守 reduced motion、high contrast 与 150% 文字缩放。
- 4 项 focused tests、完整 193 项测试通过，3 项 benchmark 跳过；58 个 Eval 用例目录验证、11 项 scorer tests、`flutter analyze` 和 Windows debug build 通过。
- 真实 1249×714、11,163 条媒体窗口确认顶部控件对齐、焦点轮廓和结果首屏无溢出；后续连续输入/标签点击因检测到用户正在操作窗口而停止抢占，精确人工复测路径已记录。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存队列、稳定身份和用户数据均未改变。

## 2026-07-18 · 完成关键 Agent 回归与 Apple UI Phase 0

- Codex CLI 从 `0.121.0` 升级到 `0.144.5`，登记官方 `openaiDeveloperDocs` MCP；Agent Eval 兼容新版输出 Schema，并改用 `codex exec -` 的 stdin 输入链路，修复 Windows 下任务提示未传入的问题。
- `router-pos-1` 以 100 分通过；过滤、播放队列、缓存、稳定身份四组回归均达到 5/5、`stable=true` 且无基础设施错误，平均分依次为 100 / 80 / 100 / 100。
- 播放队列五轮都保持正确 Skill、零文件改动和业务约束，但稳定误判为 Level 2 并过度读取上下文；记录为后续 router 分级和 token 预算回归项，不修改现行 scorer 阈值掩盖问题。
- Apple UI Phase 0 建立共享颜色、材质、圆角、间距、排版、阴影和语义动效 token；全局接入文字缩放、reduced motion 与 high contrast 策略。
- 新增保留 `InkWell`、键盘、焦点和 Semantics 的 `AppInteractionSurface`；可选透明材质默认关闭，高对比度下回退实色，未引入全窗口 blur。
- 4 项 focused tests、完整 189 项测试、`dart format`、`flutter analyze` 和 Windows debug build 通过；真实最大化窗口完成“媒体库 → 设置 → 返回媒体库”点击与截图，11,163 条媒体库状态保持。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体详情队列、稳定身份和用户数据均未改变。

## 2026-07-18 · 建立 Agent / Skill 自动化 Eval 基线

- 新增隔离 Agent Eval 运行器，捕获 Codex 原始 JSONL、规范化 Trace、结构化结果、实际 Git 变化、确定性评分、Rubric judge、延迟、token 和 N 次稳定性；CLI、网络和模型兼容错误独立标记为基础设施故障，不污染 Agent 分数。
- 建立 58 个逻辑用例：11 个 Skill 各两个正触发和两个负触发，另含 capability 与 regression；关键数据、过滤、队列和缓存回归默认执行 N=5 并要求全部通过。
- 移除 `AGENTS.md` 中易漂移的当前验证和阶段优先级，补充 Apple UI Skill 注册及 Skill 组合规则；Bootstrap 收敛为单一入口，Agent Harness 增加自动化 Eval 门禁。
- 收窄 `$ltp-apple-ui-design`：只在明确视觉、动效、交互或无障碍任务中作为设计覆盖层，纯 SQLite、过滤、队列、缓存后端和稳定身份任务不得触发。
- 本地目录验证、7 项评分器单元测试、全部 11 个 Skill 结构校验、`flutter analyze` 和 Windows debug build 通过。真实隔离 smoke 因当前 Codex CLI 不支持默认 `gpt-5.6-sol` 被标记为 `infrastructure_error`，升级 CLI 后需要重跑运行时基线。

## 2026-07-18 · 建立 Apple 式全应用 UI skill 与迁移蓝图

- 新增 `.agents/skills/ltp-apple-ui-design`，将上游 `emilkowalski/skills` 的设计基础、动效审查、动效机会筛选和术语能力收敛为一个 Local Tag Player 专用 skill。
- 将 Web/CSS 专属建议替换为 Flutter/Windows 实现边界：保护真实 `TextField`、标签层级、筛选性能、filtered queue、播放器与缓存队列；限制大面积 blur，并要求 reduced motion、high contrast、键盘和 Semantics 验证。
- 新增 `docs/design/APPLE_UI_MIGRATION.md`，按共享 token、媒体库、播放器、维护页、全局细节组件和跨平台 polish 六阶段规划全应用迁移，禁止一次性机械换皮或混入业务重构。
- 本轮未修改业务代码、SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体详情队列或用户数据。

## 2026-07-17 · 统一维护页面与浏览偏好

- 标签中心、设置、缩略图缓存和缺失重关联页面统一为媒体库深色维护主题；标签分组 chip 增加明确选中勾选、强调色和列表筛选反馈。
- `FileSystemAdapter` 的目录/文件选择支持初始目录和父目录解析；添加目录/视频优先当前媒体位置，单条 Relink 优先原文件父目录并安全回退到原 root 或媒体 root。
- 缓存统计明确失败属于缺失子集，列出失败文件与原因，并提供受活动队列保护的失败重试和失败标记清除；后者不删除视频文件或有效 JPEG。
- 设置首页直接展示当前继续观看策略，策略下拉移到播放设置首项；网格/列表选择写入既有偏好 JSON，重启保持用户选择。
- 超宽列表复用内存中的标签、媒体详情和文件大小组成独立信息列，提升横向信息密度且不增加磁盘探测或全列表重算。
- 完整 185 项测试、静态分析和 Windows debug build 通过；真实最大化窗口确认深色维护页、选择器起点、标签反馈、缓存语义、继续策略、列表偏好重启恢复及超宽布局。

## 2026-07-17 · 修复用户数据安全与关键异步状态

- “继续观看”清除单条/多条进度前保存稳定 videoId 对应的完整播放快照，操作后提供 10 秒撤销；撤销只恢复仍处于空状态的记录，不覆盖用户随后重播形成的新进度。清空全部增加二次确认，并明确不删除视频文件、标签或收藏。
- `LibraryRepository` 增加批量 `upsertPlaybackStates` 与 `cancelActiveScan` 契约。扫描取消会终止当前 backend generation、解除暂停并阻止旧结果提交；Relink 文件选择取消前不再进入 busy 状态。
- 播放器快捷键统一门禁覆盖 `EditableText`、PopupRoute、弹窗、菜单、其它路由和原生文件对话框；队列搜索关闭后恢复播放器焦点，Esc 优先退出全屏。全屏队列根表面持续判断右侧热区，离开后按用户配置延时自动隐藏。
- 媒体库窄宽度优先展示活动筛选 chip 和清除入口；扫描状态补齐阶段、进度、ETA 与取消；本地目录统计区分文件夹和视频并获得完整文案宽度；卡片“更多”新增“打开位置”，继续复用 `FileSystemAdapter` 平台边界。
- 备份完整性忽略全局派生的标签 `usage_count`，并把当前数据差异与 fingerprint 歧义分开解释；空标签提交保留弹窗并显示中文字段错误，不再暴露原始英文异常。
- 新增 focused tests 覆盖精确撤销与重播保护、删除竞态保护、清空确认、扫描取消、Relink 取消、备份语义、快捷键门禁、全屏热区、活动筛选、打开位置、空标签和本地混合统计。完整 180 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过。
- 1268×714 隔离媒体库真实点击确认“1 个文件夹 · 0 个视频”完整显示、活动筛选与菜单入口可见、空标签错误留在弹窗；播放器逐键输入 `chamosan` 未触发截图，关闭搜索后 PageUp 恢复队列快捷键，全屏队列离开热区后自动隐藏且 Esc 正常退出全屏。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容与顺序、`PlayerBackend`、缩略图/媒体详情队列均未改变；用户播放进度通过稳定身份精确保留。

## 2026-07-17 · 增强主界面侧栏开合动画

- 左右侧栏结构动画从 260ms 调整为 320ms，宽度变化继续使用双向平滑曲线，内容过渡统一增加更明显的横向位移、淡入和 0.965→1 轻微缩放。
- 左右移动边缘增加随开合状态连续过渡的描边与低透明阴影；折叠轨道使用强调色边缘，展开面板恢复工作区边框。
- 复用现有 `AnimatedContainer` / `AnimatedSwitcher`，没有新增动画 Controller、筛选计算或列表重建路径；新增 focused widget 验证组合动画与实际切换链路。
- 完整 166 项测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。最新 Debug 窗口完成左右栏往返开合及左栏动画中快速反向截图，三列稳定且无裁切、闪白、溢出或状态跳变。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-17 · 设置按功能分组并进入二级页

- 设置首页重组为“播放设置”和“数据与维护”两组，只保留播放与解码、播放器交互、视频数据备份、缩略图缓存四个列表入口。
- 解码策略与继续观看归入“播放与解码”；全屏播放列表与快捷键归入“播放器交互”；备份开关、状态和维护动作归入“视频数据备份”；缓存统计与刷新归入“缩略图缓存”。
- 每个功能类型使用独立标题和返回入口，系统返回键在二级页先回设置首页；首页不再渲染开关、滑杆、下拉框或统计信息。
- 新增 focused widget；完整 165 项测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。最新 Debug 窗口已完成“媒体库 → 设置 → 依次打开四个二级页 → 返回列表”真实点击与截图，首页无实际控件，二级页长内容滚动、缓存加载态、对齐和返回状态均正常。
- SQLite schema、设置存储、解码切换确认、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缓存队列和用户数据均未改变。

## 2026-07-17 · 统一卡片与播放器标签编辑

- 视频卡片和播放器详情改为调用同一个标签编辑方法，同一筛选上下文下的父级范围、选中标签、锁定 folder 标签、候选内容和保存语义保持一致。
- 候选不再只汇总视频兼容字段，而是从规范化 `TagItem` 索引读取当前层级全部未隐藏标签名称，因此未关联视频或 `usageCount=0` 的标签也可选择；其它父级仍被隔离。
- 候选名称可以来自 folder 等既有来源，但用户选中后仍由 `replaceManualTags` 建立独立 manual 关系，不修改或删除原来源；候选标题改为“全部可用标签”。
- 移除“全部可用标签”前 24 项截断，滚动区域展示完整集合；新增 2 项 focused tests，完整 164 项测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。
- 中间构建真实窗口确认旧数据源在“原神”下只显示 24 项并据此完成修正；最新构建复测因前台窗口处于用户全屏播放且持续输入而停止，人工路径为“卡片更多 → 编辑标签 → 滚到候选末尾 → 取消 → 播放同视频 → 详情 → 编辑标签 → 对比标题、数量和末尾标签”。
- SQLite schema、folder/manual 来源记录、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、`PlayerBackend`、缓存队列和用户数据均未改变。

## 2026-07-17 · 播放器顶部显示当前文件名

- 删除播放器顶部重复的队列搜索栏，标题由固定 `local_tag_player` 改为当前实际播放视频的完整文件名，并随播放项切换即时更新。
- 文件名使用跨平台路径 basename，保持单行省略并提供完整 tooltip；返回按钮、播放标识和紧凑窗口队列入口保持原位置与行为。
- 移除只服务顶部搜索的 controller、FocusNode 和 `Ctrl+K` 聚焦分支；右侧队列按需搜索及其 filtered queue 定位逻辑继续保留。
- 新增 focused widget；完整 162 项测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。最新 Debug 窗口确认首个视频标题正确，双击第二项后标题同步更新，未见遮挡、错位或溢出。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容与顺序、播放索引、`PlayerBackend`、缓存队列和用户数据均未改变。

## 2026-07-17 · 精简播放器详情底部操作

- 移除播放器右侧详情面板底部“编辑标签 / 打开位置 / 更多操作”操作区，详情内容现在以文件路径卡片结束。
- 同步收窄 `PlayerSidePanel` 与详情组件参数，删除只为上述入口存在的收藏、打开位置和完整信息回调；播放器控制条、队列卡片及其它页面的同类动作不受影响。
- 保留标签卡片内“继续添加”和文件名右侧编辑入口，避免删除底部重复动作时切断详情页的基础标签维护能力。
- focused widget、完整 161 项测试、`dart format`、`flutter analyze` 和 Windows debug build 通过；最新 Debug 窗口真实点击详情并截图，底部留白、卡片对齐和滚动区域均正常。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、`PlayerBackend`、缓存队列和用户数据均未改变。

## 2026-07-17 · 播放器静音与键鼠音量控制

- 音量图标改为可点击按钮：非零音量点击后静音，再次点击恢复静音前最后一次非零音量；0 音量时显示静音图标和“恢复音量”tooltip。
- 页面统一维护即时音量，按钮、滑条、上下方向键和视频区域滚轮都经过同一条 0..100 钳制链路，每次按键或滚轮变化 5。
- 队列搜索获得焦点时不消费上下键或视频滚轮；滚轮监听只包裹视频画面，右侧 filtered queue 保留原列表滚动行为。
- 新增 2 项 focused tests；完整 161 项测试、`flutter analyze` 和 Windows debug build 通过。真实窗口完成静音/恢复、方向键、视频滚轮及队列滚轮截图验证。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 内容和顺序、播放索引、缓存队列和用户数据均未改变。

## 2026-07-17 · 播放控制条打开文件位置入口

- 在播放器底部控制条的音量图标前新增弹出式 `eject` 图标按钮，tooltip 为“打开文件位置”。
- 点击入口复用播放器已有的文件定位回调和 `FileSystemAdapter.revealInFileManager` 平台边界；路径失效时继续显示原有稳定失败提示。
- 新增 focused widget 覆盖图标、tooltip 与点击回调；真实 Debug 窗口确认按钮位置、对齐和间距正常，点击后 Windows 文件资源管理器打开当前目录并选中正在播放的视频。
- 完整 159 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放/音量逻辑、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-17 · 队列左滑操作区等高与红心去阴影

- 队列左滑操作区显式占满条目 Stack 的完整高度，并只保留横向间距，使操作面板与前景列表卡片上下边缘统一。
- 去除操作面板投影和已收藏红心背后的半透明粉色底，红心状态、点击命中、收藏回调和删除入口保持不变。
- 新增 focused widget，断言操作面板与卡片实际像素高度一致且收藏按钮表面透明；真实 Debug 窗口已进入播放器并选中收藏队列项，基础布局无遮挡、错位或溢出。自动化拖拽未能让隐藏层保持展开，仍需人工左滑一次确认最终展开视觉。
- 完整 158 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-17 · 标签面板标题统一折叠入口

- 移除右侧标签筛选面板标题栏末端的独立向上箭头，改为点击“筛选图标 + 标签筛选”标题区域收起面板；折叠后的竖向窄条继续作为展开入口。
- 标题入口保留 48px 命中高度、hover/focus 水波反馈、tooltip 和明确按钮语义；dense 弹层未传收起回调时仍为纯标题，不产生无效点击。
- 新增 focused widget，覆盖标题点击回调、tooltip 与独立箭头不存在；1249×714 真实窗口完成展开、标题收起和再次展开截图，未见错位、遮挡或溢出。
- 完整 157 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-17 · 侧栏开合保持媒体网格列数

- 网格列数不再由左右侧栏开合后的结果区宽度决定，改为使用窗口宽度扣除默认侧栏占位后的稳定基准；同一窗口尺寸下只改变卡片大小，不增加或减少列数。
- 保留窗口缩放的响应式行为：只有窗口基准宽度变化并稳定后才允许跨越列数断点；筛选结果、滚动控制器、卡片稳定身份和缩略图 Future 均保持不变。
- focused widget 覆盖侧栏动画结束后仍保持三列；1268×714 真实窗口点击验证左右侧栏四种展开/折叠组合均保持三列，未见横向溢出、遮挡或状态反馈异常。
- 完整 156 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 侧栏动画与媒体网格连续重排

- 修正第一轮“锁定旧网格宽度并裁切”的过渡缺陷：侧栏收起不再留下临时空白，展开时也不会逐步裁掉右侧卡片。
- 动画期间锁定网格列数、卡片稳定身份、滚动控制器和缩略图 Future，但使用当前结果区宽度连续计算卡片尺寸；跨越响应式断点后只在宽度稳定时单次换列。
- 左侧功能栏取消按中间宽度阈值突然替换整棵内容；展开栏和 76px 图标轨道各自保留目标几何，通过淡入淡出与轻微位移切换，旧内容不会在退场期间被压缩溢出。
- focused widget 覆盖三列动画期间保持、稳定后单次切换四列，以及左栏折叠入口和中间帧无 overflow。
- 完整 156 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过，新 Debug EXE 已启动且进程响应正常。
- 当前任务仍未暴露 `computer-use` Windows 控制入口，无法合规执行真实点击与截图；人工复测路径为“连续折叠/展开左栏两次 → 展开/收起右栏两次 → 检查卡片无裁切、无空白、仅最终单次换列”。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 媒体卡片对齐与侧栏平滑重排

- 顶栏与首行视频卡片的垂直留白从紧凑间距扩大为 18px，搜索/筛选操作与内容浏览区形成明确层级。
- 网格卡片标题固定使用 42px 两行内容槽位；一行和两行标题不再形成不同的卡片视觉高度，下一行起点保持一致。
- 左右侧栏结构动画统一为 260ms 双向平滑曲线；右侧标签面板增加淡入淡出与轻量横向位移，动画结束后释放旧面板，避免隐藏标签树常驻构建。
- 结果网格在侧栏或窗口宽度连续变化时保持最近稳定宽度，停止后只提交一次换列，并用轻微淡化掩盖最终重排；不会重新筛选、重取缩略图或改变滚动控制器。
- 完整 156 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过，最新 Debug EXE 已启动且响应正常。
- 当前会话未暴露 `computer-use` 要求的 Windows 控制执行入口，无法合规完成真实点击与截图；需人工复测“左栏折叠/展开 → 右栏展开/收起 → 观察首行对齐、顶部间距和卡片仅在动画结束后重排”。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 顶栏视觉权重再平衡

- 宽屏搜索/状态/操作比例从 60/30/10 调整为 50/40/10，搜索区缩短约 17%，新增空间用于标签与媒体库状态。
- 结果数量从标签状态内部拆出并移动到排序字段、排序方向之后，形成“标签 → 排序 → 数量 → 操作”的阅读顺序。
- 多选入口改为透明无边框弱文字按钮，保留 48px 命中高度；hover/focus 才增强文字与浅紫反馈。
- focused widget 覆盖新比例、排序与数量顺序、弱按钮视觉、medium 无溢出及多选切换稳定性。
- 154 项完整测试、`flutter analyze` 和 Windows debug build 通过，最新 Debug EXE 响应正常；真实点击截图因当前会话无 `computer-use` 专用控制入口保留人工复测。

## 2026-07-16 · 搜索与筛选状态分区

- 单层顶栏改为独立搜索框、透明筛选状态区和末端操作区；宽屏按 60/30/10 分配视觉权重，标签与数量不再进入搜索输入容器。
- 筛选 Chip 常态改为灰底白字、无紫色描边；hover、focus、press 才显示浅紫反馈，紫色继续主要用于结果数量与选中状态。
- 多选只替换搜索框右侧区域，搜索框位置和宽度保持稳定；排序使用紧凑控件，末端保留多选和网格/列表连续滑块。
- 新增 focused widget 覆盖区域比例、搜索/状态物理分离、Chip 状态色和多选切换时搜索宽度稳定。
- 154 项完整测试、`flutter analyze` 和 Windows debug build 通过，最新 Debug EXE 响应正常；真实点击截图因当前会话缺少 `computer-use` 专用控制入口保留精确人工复测路径。

## 2026-07-16 · 顶栏输入保护与连续视图滑块

- 搜索表面按可用宽度为 chips 分配独立预算，expanded 输入区至少保留 236px；两个常用标签同时可见，标签更多时优先折叠为数量，不再继续挤压真实 `TextField`。
- 多选入口改用与排序和视图切换一致的 48px 工具栏表面、10px 圆角、深色底和描边，移除默认 `OutlinedButton` 带来的视觉高度和风格差异。
- 网格/列表滑块使用单一 `AnimationController` 同步底块位置与图标颜色；结果区网格/列表重布局延后到滑块稳定后提交，快速重复点击从当前进度反向，父级无关重建不会中断动画。
- 新增双标签输入宽度、按钮高度、动画延后提交、快速反向和父级重建稳定性测试。完整 154 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过，新 Debug EXE 已启动且响应正常。
- 当前运行时未暴露已安装 `computer-use` 所需的 Windows 控制调用通道，因此无法执行合规真实点击与截图；保留“选择原神/雷神 → 比较多选高度 → 快速连续切换网格/列表”的人工复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 单层搜索筛选工具栏

- 删除媒体库视频区上方独立筛选栏，将 folder、manual、收藏和排除条件以可移除 chip 融入真实 `TextField` 搜索表面；关键词继续使用同一 controller / `onChanged` 链路，不复制 `FilterQuery` 语义。
- 搜索区域宽屏最大约 650px，筛选结果数量固定显示在其右侧；排序、多选和视图切换保留在同一行。medium 极窄结果区改用紧凑排序图标并收紧外边距，新增 452px 宽度无 overflow 测试。
- “标签中心”从顶部移入左侧功能栏，展开和折叠侧栏均可访问；compact 因没有常驻侧栏而保留图标入口。
- 多选模式替换整条顶部区域，只显示圆形全选状态、“已选择 N 项”、删除和取消；退出后恢复搜索、chips、数量、排序与视图状态。
- 完整 153 项测试通过，3 项显式 benchmark 跳过；`dart format`、`flutter analyze` 和 Windows debug build 通过，新 Debug EXE 已启动且响应正常。当前会话未暴露可调用的 Windows 点击/截图通道，保留“选择标签 → 检查 chip 与数量 → 进入多选 → 选择/全选 → 删除确认取消 → 退出恢复”的人工截图复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 网格与列表单体滑块

- 顶部结果视图切换从两个独立点击按钮改为一个统一滑块；点击控件任意位置都会切换到另一种布局，不再要求分别命中左侧网格或右侧列表按钮。
- 紫色选中底块使用既有 180ms 动效在两个图标之间平滑移动；图标仅展示当前状态，不再创建各自的鼠标命中区域。
- tooltip 和语义标签根据当前布局提示下一次切换目标，键盘焦点也只落在整个滑块上。
- 完整 95 项 widget、`flutter analyze` 和 Windows debug build 通过；新 Debug EXE 已启动且响应正常。当前会话缺少可调用的 Windows UI 控制接口，保留连续点击与动画截图的人工复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、结果排序、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 筛选与批量操作双状态工具栏

- 媒体库结果工具栏压缩为 64px 单行布局。普通状态只展示“筛选”、最多三个筛选标签、折叠数量、按需出现的“清空”、简化视频数量和轻量“多选”入口，不再显示“当前筛选（AND）”或重复查询摘要。
- 进入多选后整条工具栏切换为“全选 / 已选择 N 个 / 共 M 个 / 删除 / 取消”；选择数字使用主题紫色，零选择时删除禁用，退出后恢复原筛选工具栏。
- 网格卡片和列表行在多选状态使用圆形复选框替换收藏入口，点击卡片只切换稳定 `videoId` 选择，不打开播放器；悬停预览和更多菜单同步停用，避免选择与播放动作冲突。
- 批量删除复用既有确认弹窗和平台文件边界，可选择仅移出媒体库或移入系统回收站；成功项从选择集移除，失败项保留选择并集中提示。
- 完整 95 项 widget、`flutter analyze` 和 Windows debug build 通过；新 Debug EXE 已启动且响应正常。当前会话未暴露可调用的 Windows UI 控制接口，保留多选、全选、删除确认和退出恢复的人工截图复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据持久化结构均未改变。

## 2026-07-16 · 侧栏品牌折叠入口与无滚动条视觉

- 左侧主功能栏隐藏桌面端自动绘制的纵向滚动条；展开侧栏、折叠图标轨道和本地 root 子列表仍保留滚轮、触控板及鼠标拖拽滚动。
- 移除展开态双左箭头和折叠态双右箭头，紫色品牌图标成为唯一折叠入口；展开态三角向右，折叠态使用同一图标旋转 90° 向下。
- 品牌入口继续提供“折叠功能栏 / 展开功能栏”tooltip 和按钮语义，原折叠宽度动画、导航入口及媒体库状态不变。
- 完整 93 项 widget、`flutter analyze` 和 Windows debug build 通过；新 Debug EXE 已启动且响应正常。当前会话缺少 Windows 自动点击接口，保留品牌图标折叠/展开、方向和滚轮的人工截图复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 媒体卡片悬停更多菜单

- 网格视频卡片标题右侧新增竖向更多按钮，仅在卡片 hover、键盘焦点或菜单展开期间以 120ms 淡入；失去焦点并移开后淡出，同时排除隐藏状态的鼠标、语义和键盘命中。
- 标题为按钮使用固定 28px 槽位，按钮显隐不会触发标题重新换行；没有编辑/删除文件语义的复用卡片不创建槽位，避免无故降低信息密度。
- 菜单提供“编辑标签”和“删除文件”。编辑继续调用统一标签编辑器，删除继续调用原有确认流程，可显式选择仅移出媒体库或移入系统回收站；点击更多不会误触卡片播放。
- 完整 93 项 widget、`flutter analyze` 和 Windows debug build 通过；Debug EXE 启动后进程响应正常。当前会话缺少 Windows 自动点击接口，保留“悬停标题 → 打开菜单 → 检查两个动作 → 移开”的人工截图复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、删除业务语义和用户数据均未改变。

## 2026-07-16 · 动态预览时长与透明收藏叠层

- 动态预览首帧显示后，右下角视频时长使用与预览相同的 180ms 过渡淡出；鼠标移开时随静态缩略图恢复，仅悬停或加载阶段仍保留时长。
- 收藏按钮常态、hover、focus 和按压背景全部设为透明；红心尺寸、点击区域、收藏状态颜色、阴影和持久化回调均保持不变。
- 完整 92 项 widget、`flutter analyze` 和 Windows debug build 通过。当前会话未暴露 Windows 自动化执行入口，保留“停留启动预览 → 时长隐藏 → 移开恢复 → 红心无底色”的人工截图复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、动态预览播放器和用户收藏数据均未改变。

## 2026-07-16 · 缩略图动态放大与默认布局扩容

- 卡片 hover 取消 3px 上浮与外部阴影，改为固定圆角裁剪框内 `1.06x` 画面缩放；收藏、时长、标题和网格布局均不参与缩放。
- 缩放进入/退出分别使用 220ms/170ms，同一个控制器从当前进度正向或反向运行，快速跨卡片移动不会重置动画端点。
- 标签筛选折叠条总横向占用从约 92px 降至 64px；桌面结果区水平内边距和列间距同步收紧，卡片最大宽度阈值提高到 310/340/430/500px，使 1600px、2000px 结果区保持四列，2200px 才进入五列。
- 完整 92 项 widget、`flutter analyze` 和 Windows debug build 通过。当前会话未暴露 Windows 自动化执行入口，真实窗口仍需按“快速横扫首行 → 单卡停留 → 移出 → 展开标签筛选”路径补充截图复测。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、动态预览播放器语义和用户数据均未改变。

## 2026-07-16 · 动态预览延迟与退出淡出

- 动态预览使用可取消的 650ms 停留意图，替代原固定 900ms 计时；鼠标在多张卡片间快速移动时不会创建播放器或显示加载状态，稳定停留的启动反馈更及时。
- 鼠标离开后动态画面以 180ms 淡回静态缩略图，动画结束才释放原生播放器；淡出期间重新进入会取消释放并复用已有预览。
- 新增快速掠过与淡出参数 widget 测试，完整 92 项 widget、`flutter analyze` 和 Windows debug build 通过；1268px 真实窗口覆盖快速横扫、稳定停留、离开复位和淡出期间重新移入。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、用户数据和正式播放器行为均未改变。

## 2026-07-16 · 深色缩略图占位与局部悬停浮动

- 缩略图加载中、生成失败和无缩略图统一使用 `#243145 → #182332` 深色渐变底色，通过进度环、失败图标和空状态图标区分语义；悬停动态预览加载层同步改为深色半透明遮罩。
- 移除卡片悬停时的整卡背景、紫色描边和整卡阴影；仅缩略图上浮 3px 并增加轻量投影，标题及下方信息保持原位。
- 完整 90 项 widget 测试、`flutter analyze` 与 Windows debug build 通过；1268px 真实窗口确认动态预览可启动、缩略图浮动且标题不位移。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列、收藏和用户数据均未改变。

## 2026-07-16 · 收藏与时长缩略图叠层微调

- 收藏按钮按卡片宽度使用 30/32/34px，红心使用 17.5/19/20px，边缘间距使用 6/7/9px；未改变收藏回调、稳定身份或持久化语义。
- 收藏黑底透明度从 60% 降为 46%，未收藏红心使用 94% 白色，已收藏继续使用主题红色；图标增加轻量阴影，避免降低底色后在高亮画面中丢失轮廓。
- 时长角标按卡片宽度使用 10/10.5/11px 字号及分档内边距，底色从 70% 降为 56%，字重降为 600并增加文字阴影；未知时长仍显示 `--:--`。
- 1268px 真实窗口确认亮色/暗色缩略图上的红心和时长均清晰且不遮挡主体；收藏切换反馈明确，用户窗口空闲后已恢复原状态，收藏总数回到 5。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、收藏语义、时长探测和缩略图/媒体详情队列均未改变。

## 2026-07-16 · 响应式卡片标题与网格密度

- 卡片标题按实际卡片宽度使用 13.5/14.5/15.5/16px 分档字号，统一 600 字重、1.28 行高和轻量字距；卡片高度继续由同一列数/间距公式计算，不会因字号变化产生溢出。
- 缩略图、点击水波纹和悬停外框统一为 8px 圆角，减少此前 10px 圆角带来的卡片化外观，更接近内容平台的紧凑缩略图。
- 横向列间距按结果区宽度分为 10/14/18/22px，行间距分为 14/16/18/22px；超宽结果区的单卡上限逐步提高到 430px，使 2200px 结果区从 6 列收敛为 5 列。
- 1268px 真实窗口确认三列标题、角标、圆角和间距无遮挡或溢出。最大化复查时检测到用户正在操作其它窗口后停止桌面输入；宽屏列数、间距、字号和高度由纯函数测试覆盖。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 可折叠功能栏与媒体库深色信息流

- 左侧主功能栏新增展开/折叠按钮；折叠态为 76px 图标轨道，媒体库、继续观看、收藏、目录管理、缺失关联、扫描、添加 root、root 切换和设置入口均保留 tooltip 与原动作。
- 折叠宽度使用轻量动画，并按动画中的真实可用宽度选择完整或图标内容，避免展开导航短暂塞入窄轨道产生溢出；折叠状态不参与筛选或列表重算。
- 媒体库页面使用局部深色主题 token，统一工作区背景、搜索、筛选摘要、排序控件、标签面板、空状态和文字层级；应用其它页面的全局主题不变。
- 网格卡片移除常驻浅色外壳、边框和重阴影，采用 16:9 缩略图加两行标题的信息流布局；收藏/时长角标保持，悬停时才显示次级表面和紫色描边。
- 完整 88 项 widget 测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。真实 11,163 条窗口确认折叠后 3 列自然扩展为 4 列、标签面板深色一致、卡片进入 `1 / 11163` 队列并返回后状态保留。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 媒体库提前预加载与筛选缩略图稳定复用

- 增量滚动在当前批次剩余 4 行时提前追加下一批，仍按 10 行一批且只扩大 Sliver 的 `itemCount`；单一滚动控制器、同帧信号合并和完整 filtered queue 保持不变。
- 网格/列表为已挂载范围缓存 `videoId -> index`，向 Sliver 提供稳定下标回查；标签筛选后仍保留的视频卡片可以移动并复用原 State，不因列表下标变化重复初始化缩略图 Future。
- 缩略图首帧直接使用 `ThumbnailService` 已在当前进程验证的 JPEG，并用 gapless image replacement 承接异步 Future；未缓存的新视频仍显示正常加载反馈，缓存有效性和生成队列没有改变。
- 增加独立的 debug 轻量滚动帧统计开关 `LOCAL_TAG_PLAYER_SCROLL_STATS_OUTPUT`：滚动期间只收集 Flutter `FrameTiming`，静止 300ms 后才写一条 JSONL，包含挂载数量、P50/P95/峰值及 16.7/33.3ms 超预算帧数；发布构建零开销。
- 完整 88 项 widget 测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。真实 11,163 条媒体库连续追加到 450 张卡片（约 150 行），滚动位置连续且无闪白、回顶或卡片错位。首轮与旧重型探针共用开关导致帧样本被诊断开销污染，拆分后的第二轮因检测到用户输入而安全停止，精确复测路径已记录。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列及用户数据均未改变。

## 2026-07-16 · 十行增量滚动与标签筛选自动折叠

- 删除媒体库页码栏和全部翻页按钮；网格按当前响应式列数把 10 行换算为一批条目，列表模式每批 10 条，接近已挂载内容末尾时继续在同一列表尾部追加。
- 增量加载复用单一滚动控制器，同一帧内的重复滚动通知会合并；追加只扩大尾部范围，并用稳定 videoId key 保留已有卡片、缩略图 Future 和滚动偏移，避免回顶、闪白或整页替换抖动。
- 筛选或排序结果变化、网格/列表切换时从首批 10 行和顶部重新开始；窗口列数变化只允许扩大已挂载范围，不让已显示卡片倒退消失。
- 标签筛选默认折叠；选择一级、二级、分组、排除或收藏筛选后自动收起。搜索输入和顶部筛选 chip 清理沿用原状态，不干扰连续操作。
- 完整 87 项 widget 测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。真实 11,163 条媒体库确认分页栏消失、默认折叠和滚动追加无明显抖动；自动标签点击因用户正在操作窗口被安全中止，精确人工复测路径已记录。
- SQLite schema、`FilterQuery` / `TagQueryService`、完整 filtered queue、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 分页文案精简与可见卡片时长补齐

- 分页栏移除“当前条目范围 / 完整结果数”，仅保留“第 X / Y 页”；每页仍固定 100 条，首页、上一页、下一页和末页行为不变。
- 正常启动不触发全量扫描时，真实进入视口且总时长缺失的旧详情会进入现有可见优先媒体探测队列；已有编码/分辨率但缺时长的缓存不再被错误视为完整。
- 每批时长写回后只刷新当前视图，不提升媒体库 revision，不重新执行筛选、排序或标签计数；平台探测仍经过 `MediaProbeBackend`，并发和持久化字段不变。
- 86 项 widget、7 项媒体探测测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。重新构建并启动新 EXE 后，真实 11,163 条媒体库只显示“第 1 / 112 页”，可见卡片已显示多组真实时长且无 `--:--`。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图队列和用户数据均未改变。

## 2026-07-16 · 媒体库每页 100 条分页

- 媒体库网格和列表结果固定每页展示 100 条；多页结果在底部提供首页、上一页、下一页、末页，并显示当前页、总页数、当前条目范围和完整结果数。
- 分页状态只位于结果展示组件，翻页不重新执行 `FilterQuery`、标签计数或排序；页码变化时通过 keyed 滚动视图回到页首，筛选/排序结果边界变化时自动回到第一页。
- 打开任意页的视频仍把未切片的完整筛选结果传给播放器。新增 205 条分页 widget 回归测试，确认第二页打开视频时 filtered queue 仍为完整 205 条。
- 完整 87 项 widget 测试、`dart format`、`flutter analyze` 与 Windows debug build 通过。真实 11,163 条媒体库确认 112 页，首页、第二页和末页范围正确，截图未见分页条遮挡、截断、错位或按钮状态异常。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-16 · 媒体库紧凑视频卡片与时长角标

- 网格视频卡片移除缩略图中央播放按钮、底部播放/收藏/更多操作区、标签和视频路径；收藏改为缩略图左上角红心，时长改为右下角深色角标，卡片整体成为打开当前筛选队列的入口。
- 卡片高度由固定桌面值改为按当前网格实际列宽计算，保留 16:9 缩略图和两行标题余量；1268×714 三列窗口下约 168px，明显减少无意义空白。
- `MediaDetails` 增加可选总时长；Windows 原生批量探测读取 `AVFormatContext::duration`，兼容 FFprobe 追加读取 `format.duration`。旧详情复用现有最多 8 条有限批次补齐并写入 `playback_duration_ms`，不新增 SQLite schema，也不在 UI build 中访问文件。
- 聚焦媒体探测与 widget 91 项测试、`dart format`、`flutter analyze` 和 Windows debug build 通过。真实窗口完成收藏切换/恢复、卡片进入播放器和返回路径；角标、标题、卡片间距未见遮挡、溢出或错位。
- `FilterQuery` / `TagQueryService`、filtered queue、缩略图队列、stable identity 和收藏语义未改变。

## 2026-07-16 · 备份完整性检查、便携导出与启动写入优化

- 设置页“视频数据备份”卡片新增“检查完整性”和“导出备份”。完整性检查只读核对 SQLite、快照 JSON、当前视频缺失/过期快照和重复 fingerprint；未来可恢复快照不作为垃圾删除，发现差异时引导用户显式“立即备份”。
- 便携导出使用版本化 JSON，包含稳定 videoId/fingerprint 和依赖 payload，不包含媒体路径、视频文件、缩略图或媒体详情缓存；保存位置继续经过 `FileSystemAdapter` 平台边界。
- 备份控制新增 clean-session 与 reconcile-required 状态；桌面窗口关闭会先等待 Store 写入 clean marker 再销毁。正常关闭后的下次启动只处理持久化增量队列，首次、未完成、异常退出和关闭后重新开启才全量核对。关闭期间发生的主库变化不会被误判为已同步。
- 全量与增量统一生成稳定排序的规范快照，并通过条件 UPSERT 跳过内容相同记录，手动全量核对也不再刷新未变化快照的 `updated_at` 或重写对应 SQLite 页。
- 新增完整性/导出、正常重启零全量写入、关闭后重新开启补齐测试；完整 139 项测试通过，3 项显式烟测/基准跳过，`flutter analyze` 和 Windows debug build 通过。
- 真实窗口确认三个备份入口无截断、遮挡或溢出；正式备份检查为 11,163/11,163、缺失/过期 0、SQLite 正常。导出 3.53 MB、11,163 条且无 path 字段；连续正常关闭/启动后 `session_open=0`、`full_sync_in_progress=0`，最近全量完成时间保持不变。

## 2026-07-16 · 默认开启的视频依赖独立备份

- 设置页新增“视频数据备份”开关，旧版本无配置时默认开启，并提供状态、进度、等待同步数、最近完成时间与“立即备份”入口。
- 新增独立 `video_dependency_backup.db`：只保存稳定 videoId/fingerprint、收藏、播放状态和非 folder 标签及其分组定义，不复制视频文件，也不与 `library.db` 共表。
- 全量核对按 32 条小批次执行并持久化稳定 videoId 游标；用户修改进入备份库去重队列。应用关闭或异常退出不会清空游标，下次启动继续未完成任务。
- 自动恢复要求扫描侧与备份侧 fingerprint 同时唯一，且主库没有 videoId 冲突；歧义时只建立新身份，不猜测合并。folder 标签继续按当前目录树派生。
- root 移除保留快照；显式单视频删除先让 worker 停在批次边界，再同步删除快照和主库记录，主库删除失败会重新排入备份队列。
- 播放器创建前等待当前备份小批次结束，整个播放会话暂停备份，原生播放器释放后再恢复；备份不读取视频文件。完整 136 项测试通过，3 项显式烟测/基准跳过。
- `flutter analyze` 与 Windows debug build 通过。真实窗口确认默认开关、状态、进度条和按钮无布局问题；正式库 11,163 条快照完成，备份 SQLite `integrity_check=ok` 且没有 path 列。播放期间游标保持不变，返回后从 800/11,163 自动续跑至完成。

## 2026-07-16 · 收藏恢复与 root detached 稳定身份归档

- 使用 SQLite 在线备份 API 在正式库同目录生成恢复前一致性备份；备份包含 11,163 条视频和恢复前 3 条收藏，`integrity_check=ok`。快照中的 3 条收藏逐条以 path 和 `media_fingerprint` 双重匹配，在一个 `BEGIN IMMEDIATE` 事务中恢复；恢复后正式库共 6 条收藏且完整性仍为 `ok`。
- `videos` 幂等新增 `is_detached INTEGER NOT NULL DEFAULT 0` 和索引。旧库所有现有行默认 active，不清空或重建用户数据。
- 移除 root 改为在 metadata 与 detached 状态的同一 batch 中提交；不再删除视频行、标签关系、收藏、播放记录、媒体详情或缩略图。detached 视频退出常规媒体库、筛选和播放队列，标签管理仍保留其引用，避免误删归档数据依赖的标签。
- 重新添加相同 root 时按 path 激活原 videoId；路径变化时 detached 记录加入唯一 fingerprint 候选并复用既有 relink 事务。root 移除前发出的过期单条/批量 upsert 会被拒绝，不能把 detached 静默改回 active。
- focused tests 覆盖旧 schema 迁移、同 root 恢复、跨 root 移动恢复、用户数据重载、归档标签保护和过期回调隔离；133 项完整测试通过，3 项显式烟测/基准跳过。
- `flutter analyze` 与 Windows debug build 通过；最新构建真实窗口确认 root 移除弹窗的主题、对齐、文案和按钮状态正常，取消后媒体库仍为 11,163 条视频和 6 条收藏。正式库只读复核确认 `is_detached` 已迁移、当前 detached 为 0、完整性为 `ok`。

## 2026-07-16 · 收藏数据审计、回收站删除与队列操作区优化

- 只读检查正式 `library.db`、legacy JSON 和隔离基准快照：收藏字段一直写入 SQLite；正式库当前 11,163 条视频中只有 1 条收藏，旧快照的 11,135 条视频中仍有 3 条收藏。正式索引在同一秒整批创建了新 `videoId`，旧收藏与播放状态没有迁移到新身份，说明问题是索引身份重建而非收藏按钮只改内存。
- 本轮不直接改写用户正式库；旧快照中的 3 条收藏仍可作为恢复来源。现有收藏保存/重载与 fingerprint relink 保留用户数据测试继续通过。
- 单视频危险动作改为“同时将本地视频移入回收站”，通过 `FileSystemAdapter.moveFileToTrash` 调用 Windows `SendToRecycleBin`。系统操作失败时抛出异常，上层不会继续删除 SQLite 记录；不再用永久 `File.delete()` 冒充回收站删除。
- 播放器队列左滑操作区使用紧凑深色胶囊、主题描边、内部细分隔线和低强调红心/删除图标；收藏态仅给红心按钮轻量底色，避免大面积红色块破坏当前紫色主题。
- `dart format`、132 项完整测试、`flutter analyze` 和 Windows debug build 通过，3 项显式烟测/基准跳过；另以环境变量单独启用的 3 字节临时文件真实 Windows 回收站烟测通过，常规测试不会持续写入用户回收站。真实窗口已确认最新播放器与常驻收藏状态；自动化拖动未触发展开，随后因检测到用户输入且截图通道无法取得前台进程 ID 而停止，左滑展开态和删除弹窗仍需人工截图复测。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列和标签语义未改变。

## 2026-07-15 · 播放器控制条与队列快捷操作

- 控制条在鼠标不位于底部进度/按钮区域时按 3 秒计时隐藏，暂停态也遵循同一规则；设置浮层打开时锁定显示，关闭后恢复计时。
- 播放状态流每次变化都触发轻量页面重建，确保播放/暂停图标与后端真实状态同步，不启动媒体探测或队列重算。
- “列表 / 详情”分段栏高度从 44px 压缩到 34px，图标、文字和外框同步收紧，保留原连续紫色选中反馈。
- 队列项常驻显示收藏状态；鼠标向左拖动按距离和速度吸附展开 96px 操作区，提供主题内红心和删除按钮，鼠标移出后自动平滑折叠。
- 收藏继续写入当前稳定视频记录；删除可作用于任意队列项，弹窗默认仅移出媒体库并允许显式勾选同步删除本地文件。删除非播放项不切换当前视频，删除播放项才停止后端并打开新的当前项。
- 完整 131 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。真实窗口确认紧凑侧栏、收藏状态与控制条 3 秒隐藏；设置点击后的 Windows 截图通道返回 `no screenshot targets found`，设置保活、左滑按钮和删除弹窗保留人工截图复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源、缩略图/媒体详情队列和标签语义均未改变；用户删除选择由确认弹窗明确决定。

## 2026-07-15 · 播放设置分级精简与全局持久化

- 一级播放设置继续保留镜像画面、单曲循环和列表循环；“更多播放设置”删除重复的完整播放方式、快捷键与播放诊断，只保留“视频比例”“播放速度”两个导航行。
- 视频比例和播放速度分别进入独立三级列表，二级行展示当前生效值；浮层保持 300px 紧凑宽度，未增加全列表重算或媒体 I/O。
- `PlaybackSettings` 向后兼容持久化镜像、队列播放方式、比例和倍速；播放器内修改会同步应用级快照并串行写入 `settings.json`，退出前等待最后一次写入。
- 新播放器会话从全局配置初始化；每次媒体 open 前后重新把比例/panscan 与倍速送入 `PlayerBackend`，防止重启后只恢复数据或选中态而没有真实生效。
- focused tests 覆盖旧配置默认值、JSON 保存/重载、异常值回退、后端参数应用和三级导航；完整 128 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。真实窗口点击一级、二级、比例和倍速列表无位置、遮挡、对齐、溢出或状态反馈问题；设置为“铺满 / 1.5x”后完整重启应用，二级显示值与实际铺满画面均保持，验证后已恢复“自动 / 1.0x”。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、当前索引、缩略图/媒体详情队列和用户视频数据均未改变。

## 2026-07-15 · 冷扫描确定进度与播放让盘

- `LibraryScanBackend` 增加阶段进度和暂停/恢复契约；Rust/Dart 后端先完成目录候选发现，再在已知总数下执行 stat/fingerprint，当前筛选结果区显示处理数/总数、百分比、速度和 ETA。
- Rust sidecar 通过不含路径的 stderr 计数协议上报进度，stdout 快照协议不变；暂停标记只在安全文件边界检查，恢复后从原候选位置继续，不重新遍历目录。
- 播放器进入前自动暂停扫描磁盘读取，退出后恢复；用户已经手动暂停时不自动恢复。大差量 Application 合并每 256 项让出 UI isolate，降低扫描提交撞上播放器路由时的冻结风险。
- 真实 `X:\test-media` 隔离热缓存强制 fingerprint 基准为 11,163 项：目录发现 24ms、fingerprint 1,444ms、初次历史上下文提交 1,995ms、稳定态端到端 754ms。该轮明确作为热态对照；后续真实冷启动由 debug JSONL 的 `scanPhases` 持续记录。
- 完整 126 项测试通过、2 项显式基准跳过，`flutter analyze` 与 Windows debug build 通过。隔离真实窗口在扫描 11,163 条期间点击播放，播放器约 0.5 秒进入并连续响应两秒；返回后扫描原位继续并完成三阶段诊断。进度、播放器和恢复后的媒体库截图均无遮挡、溢出或错位。
- 媒体探测并发未提高；SQLite schema、stable identity、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、标签来源和用户数据均未改变。

## 2026-07-15 · 媒体解析 ETA、暂停控制与磁盘基准

- `MediaDetailsService` 根据已完成批次的有效运行时长计算平滑处理速度，并用剩余条目估算完成时间；暂停期间不累计 ETA，继续时重置短期采样基线，避免等待时间污染速度。
- 暂停不会中断正在执行的最多 8 条原生批次，批次自然完成后停止调度；继续只处理剩余队列，不重复探测或覆盖已持久化结果。
- 当前筛选结果区改为紧凑的“媒体解析 已处理/总数 · 百分比 · 条/秒 · 剩余时间”，右侧提供 28px 暂停/继续按钮；暂停态显示“已暂停”，完成后恢复正常结果摘要。
- 新增受环境变量显式控制的 Windows 原生媒体探测基准。相同 256 文件、6.43 GB 样本首次冷读：D 盘 SATA 机械硬盘 52.78 条/秒，E 盘 NVMe SSD 101.04 条/秒；D 盘后续三轮为 202.16 / 220.32 / 226.04 条/秒，E 盘后两轮为 219.65 / 218.81 条/秒，热态差异收敛到探测计算开销。
- 完整 118 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。隔离 profile 真实导入 `X:\test-media` 的 11,163 条视频，确认进度文案完整、暂停后计数稳定、继续后速度与 ETA 恢复更新；完成摘要已由前一轮全量真实目录验证和最终 widget 回归共同覆盖。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图队列、标签来源与用户数据均未改变。

## 2026-07-15 · 大目录导入进度与媒体详情批处理

- 当前筛选结果区在目录扫描时显示“正在发现并校验视频”；扫描提交后立即开放视频列表，并显示“解析媒体信息 已处理/总数 · 百分比”和细进度条，全部完成后恢复正常结果摘要。
- `MediaDetailsService` 新增一次性后台登记、进度快照和最多 8 条的有限原生批次；可见项继续独立优先，避免一个超大后台批次阻塞当前卡片。
- `LibraryRepository` 新增视频字段批量 upsert，媒体详情每个原生批次只执行一次 SQLite batch；减少大目录数千次平台调用和数据库提交。
- 新扫描开始前取消上一轮媒体探测，避免目录枚举/指纹读取与旧 FFprobe 工作争抢磁盘；失败项计入已处理进度并继续写入诊断状态。
- 新增媒体批次/进度和结果区确定型进度 focused tests。SQLite schema、标签来源与筛选语义、filtered queue、缩略图队列和用户数据均未改变。
- 完整 117 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。隔离 profile 真实导入 `X:\test-media` 的 11,163 条视频，确认列表先显示、进度持续更新、解析期间可切换“原神 / 雷神”171 条结果，完成后恢复“全部视频 · 11163 个结果”；结果区无偏移、遮挡或溢出。

## 2026-07-15 · 媒体库文件选择、拖放导入与目录删除收敛

- 空媒体库中央新增 112×112 方框大“+”、添加视频文案和拖放提示；只有全库确实为空时显示，筛选无结果继续使用原空筛选状态。
- `FileSystemAdapter` 增加多文件选择契约，Windows/macOS/Linux 桌面适配器统一返回规范化路径；`desktop_drop` 为媒体库结果区提供文件/目录释放事件和轻量悬停覆盖反馈。
- 视频文件按所在目录注册 root，目录直接作为 root；已被现有 root 覆盖的路径只触发重扫，同批候选按最上层目录去重，并通过批量 Repository 命令在 metadata 一次落盘后只执行一轮扫描。
- 目录管理弹窗的删除入口改为复用左侧 root 移除协调，统一取消过期媒体探测、失效派生缓存、刷新结果并异步清理缩略图；磁盘视频文件仍不删除。
- 完整 115 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。隔离临时 profile 真实窗口完成空状态、系统多文件选择器、单文件入库、结果/计数/root 刷新、目录删除入口和确认提示截图；自动化 API 不允许拖拽终点越出资源管理器窗口边界，跨窗口释放保留精确人工复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/media 队列语义和用户真实数据均未改变。

## 2026-07-15 · 全屏猫耳焦点分辨率自适应

- 普通窗口继续使用既有猫耳焦点尺寸；只有窗口全屏时，才按视口短边在 900–2160 逻辑像素之间把焦点从 1.0 平滑放大到 1.25 倍。
- 4K 及更高分辨率统一限制为 1.25 倍，避免超宽屏或 8K 画面让焦点过度抢眼；进度轨道、帧预览和音量条尺寸不变。
- 倍率边界与原悬停预览 2 项 focused tests、`flutter analyze`、Windows debug build 通过，未执行全量测试。
- 最新构建在 2560×1440 真实全屏下约使用 1.11 倍焦点；截图确认焦点与轨道居中、预览无遮挡，指针移出后焦点和预览正常隐藏。
- SQLite schema、filtered queue、播放索引、`PlayerBackend`、缓存队列和用户数据均未改变。

## 2026-07-15 · 主进度条猫耳史莱姆焦点

- 主进度条悬停焦点不再使用白色圆点，改为约 22px 的紫蓝猫耳史莱姆矢量图形；浅紫轮廓、渐变主体和轻量外光与现有紫色进度轨道保持同一视觉体系。
- 图形由 Canvas 直接绘制，避免把参考图棋盘背景带入应用，也避免位图缩小后的模糊；小尺寸只保留猫耳、高光、眼睛和短笑线。
- 猫耳焦点只用于主进度条，音量条继续使用原紧凑圆点；150ms 悬停动画、帧预览、点击/拖动和隐藏状态均保持不变。
- 影响范围悬停测试、`flutter analyze` 与 Windows debug build 通过，未执行全量测试；重启最新构建后真实窗口确认焦点可辨识，并与帧预览共存，移出后正常隐藏。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、`PlayerBackend`、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-15 · 优酷式进度条悬停帧预览

- 主进度条未悬停时收窄为 2px 并隐藏圆形焦点；进入轨道后以 150ms 动画加粗到 5px、显示焦点，音量条和控制栏隐藏后的 3px 底边进度线保持原行为。
- 指针停稳 350ms 后显示 220×124 对应时间帧与时间标记；连续移动只更新轻量位置，不连续提交取帧。
- `FFmpegBackend` 新增独立指定时间点预览帧契约，单线程、小尺寸提取且不 seek 主播放器；`ThumbnailService` 同时最多执行 1 项、只保留最新等待项，按秒复用并限制 24 个临时帧。
- 2 项影响范围测试、5 项架构 contract、`flutter analyze` 与 Windows debug build 通过，未执行全量测试。真实窗口确认静止、悬停预览、移出及控制栏隐藏四态无错位、溢出或按钮遮挡，中部预览 `03:59` 与实际位置约 `04:01 / 08:02` 匹配。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、`PlayerBackend`、媒体库缩略图主队列及用户数据均未改变。

## 2026-07-15 · 播放器进度与音量条视觉优化

- 主进度条与音量条复用紧凑滑条组件，使用圆角紫色渐变有效轨道、柔和半透明底轨及带紫色外环的白色滑块；保留原有拖动、滚轮音量和自动化定位键。
- 控制栏淡出后在视频底边保留 3px 只读进度线；进度比例会处理零时长、负数和越界位置，不拦截视频区域点击。
- 2 项影响范围 focused tests、`flutter analyze` 与 Windows debug build 通过，未执行全量测试。
- 真实 Windows 窗口确认新版进度/音量条和控制栏隐藏后的细进度线均无位置、遮挡、溢出或状态反馈问题；全屏自动化复测切换时应用进程意外退出，保留全屏入口人工复核。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、`PlayerBackend`、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-15 · 全屏设置锚定与控制条保活

- 播放设置浮层不再按窗口底部居中，而是读取齿轮按钮实时位置；普通窗口和全屏都在按钮上方显示，并保持浮层右边缘与按钮右边缘对齐。
- 浮层打开增加右下原点缩放淡入；一级/二级页使用相反方向的水平滑动与淡入动画，宽度同步平滑过渡。
- 删除右上角关闭按钮，继续支持点击空白和 Escape 关闭；设置展开期间进度条与控制区锁定可见，关闭后恢复原 3 秒自动隐藏。
- 2 项设置 focused tests、1 项控制条状态测试、`flutter analyze` 与 Windows debug build 通过，未执行全量测试。
- 2560×1440 全屏真实窗口确认浮层与齿轮对齐；保持展开 4 秒后控制条仍可见，切换更多设置正常，点击空白关闭并等待 4 秒后控制条正常隐藏。
- filtered queue、播放索引、PlayerBackend、SQLite schema、标签查询、缓存队列和用户数据均未改变。

## 2026-07-15 · 播放器两级设置与镜像画面

- 齿轮设置改为一级/二级结构：一级只保留镜像画面、单曲循环、列表循环和“更多播放设置”；视频比例、播放速度、完整播放方式、快捷键与播放诊断只在二级页挂载。
- 单曲循环与列表循环使用互斥开关，关闭当前循环会回到顺序播放；不改变 filtered queue 的内容、顺序或当前播放索引。
- `PlayerBackend.buildVideoSurface` 增加可选 `mirror`；MediaKit 和 Windows 原生后端只翻转视频表面，Flutter 控制条与点击坐标保持原方向。
- 2 项设置 focused tests、播放完成边界测试、架构契约、`flutter analyze` 与 Windows debug build 通过，未运行全量测试。
- 真实窗口完成一级面板、镜像切换、进入二级和返回一级截图；一级约 300px、二级约 400px，未见遮挡、溢出、对齐、对比度或状态反馈问题。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/媒体详情队列与用户数据均未改变。

## 2026-07-15 · 播放器画面比例与分组设置浮层

- 对照真实索引确认全屏差异来自视频比例：`1920×1080` 的 16:9 样本可充满全屏，`1728×1080` 的 16:10 样本在默认完整显示下会左右留边，源内上下黑边会进一步形成“被控制条顶起”的观感。
- 齿轮入口改为参考图式紧凑分组浮层，集中展示播放方式、视频比例、播放速度、快捷键和播放诊断；未实现的播放策略、音量均衡不做占位按钮。
- 新增 `自动 / 4:3 / 16:9 / 铺满`：前三项保留完整画面或覆盖显示比例，“铺满”同时通过 mpv panscan 和 media_kit `BoxFit.cover` 等比裁边。
- `PlayerBackend.buildVideoSurface` 向后兼容增加可选 `BoxFit` / `aspectRatio`，默认 `contain` 不变；页面仍不接触具体 Player、VideoController 或纹理对象。
- 3 项播放器 focused tests、`flutter analyze`、Windows debug build 通过，未执行全量测试。真实窗口迭代中发现并修复设置菜单未显示、浮层过宽和仅裁纹理内部仍留边；最终构建自动化复测时进程退出，截图器返回 `no screenshot targets found`，保留精确人工复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-15 · 播放器队列搜索按需展开

- 将队列搜索入口移动到 `当前序号 / 总数` 后，默认只显示搜索图标，点击后才挂载搜索框，再次点击可收起。
- 搜索、定位已选中和删除按钮统一为 32×32 紧凑点击区域，并在按钮之间保留固定间距；搜索展开后自动获取输入焦点。
- 新增搜索展开、提交、收起与图标顺序 focused test，并复跑现有队列内搜索语义测试；`flutter analyze` 和 Windows debug build 通过，未执行全量测试。
- 实际启动 `build\windows\x64\runner\Debug\local_tag_player.exe`，进入播放器后完成默认隐藏、点击展开和再次收起截图检查，未见位置、遮挡、溢出、对齐、对比度或状态反馈问题。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-15 · 精简播放器筛选队列头部

- 删除固定“当前筛选（AND）”、重复总数徽标以及不可操作的“全部视频 / 时长：全部 / 大小：全部”展示条。
- 将 `当前序号 / 总数` 提升到标题行；头部只保留队列名称、定位已选中、删除和下一行队列搜索。
- 真实二级标签切换仍位于来源过滤队列内；filtered queue、搜索定位、返回播放及缓存行为未改变。
- 队列布局与搜索 2 条 focused tests、`flutter analyze`、Windows debug build 通过，未执行全量测试。
- 实际启动最新 Windows debug 程序进入播放器截图，头部层级更紧凑，列表首屏多显示约一条视频卡片，未见遮挡、溢出、对齐或对比度问题。

## 2026-07-15 · 移除重复的定位当前播放入口

- 删除队列标题栏中的“定位当前播放”准星按钮，避免与列表底部的“回到播放”产生重复和交互冲突。
- 顶部继续保留“定位已选中”和删除；底部继续按离屏状态显示“回到播放 / 回到选中”，搜索框定位行为不变。
- 内部回调统一改名为“回到播放”，保留同步选中态和即时返回当前播放项的原有行为。
- 影响范围 focused test、`flutter analyze` 与 Windows debug build 通过，未执行全量测试；真实窗口滚动后点击“回到播放”正确返回第 1 项。
- filtered queue、播放/选择索引、`PlayerBackend`、缓存队列、SQLite schema 与用户数据均未改变。

## 2026-07-15 · 播放器列表与详情分段控件对齐蓝图

- 将右侧“列表 / 详情”从两个分离按钮改为连续等宽分段控件，中央取消间隙并统一深色外框与圆角。
- 选中半区使用紫色渐变、高亮描边和轻量阴影；未选中半区降低图标与文字强调，切换时以 160 ms 动画迁移选中反馈。
- focused test 验证控件高度、默认列表渐变和详情切换后的渐变迁移；`flutter analyze` 与 Windows debug build 通过，未执行无关全量测试。
- 真实 Windows 窗口完成列表/详情点击与截图检查，两种状态均未见遮挡、溢出、对齐或对比度问题。
- filtered queue、播放/选择索引、`PlayerBackend`、缩略图/媒体详情队列、SQLite schema 与用户数据均未改变。

## 2026-07-15 · 修复播放器定位后的队列占位残留

- 队列可视层显式跟踪滚动中与已停稳状态；快速滚动仍显示轻量占位，滚动结束后即使 Flutter 继续建议延后加载，也会恢复完整卡片。
- 为 Windows 滚轮及程序化 `jumpTo` 增加 120 ms 停稳防抖兜底，避免缺失 `ScrollEndNotification` 时可视项永久只显示标题；计时器在组件释放时取消。
- 新增滚动延后判定回归测试；focused 66 项、完整 103 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。
- 真实 Windows 窗口滚动到第 29–31 项后，缩略图、序号、标题与编码信息均完整恢复；定位点击后的截图仍受已知 Flutter Windows 无障碍桥异常阻断。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、播放索引、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-15 · 播放器列表与详情统一侧栏

- 移除播放器底部当前视频信息卡，让视频画面直接占用释放出的垂直空间；文件名、标签、媒体参数、路径及维护入口全部迁入右侧详情页。
- 右侧侧栏将“列表 / 详情”作为同级视图切换：列表继续消费来源 filtered queue，详情绑定实际当前播放项，切回列表不改变选择或播放状态。
- 详情复用编辑标签、继续添加、打开文件位置、收藏和完整视频信息入口；只读取 `VideoItem` 已缓存字段，不因切换详情重新执行文件 stat、FFprobe 或缩略图生成。
- 新增统一侧栏 widget 测试，覆盖默认列表、详情切换、当前项信息、编辑入口回调和切回列表；focused 65 项、完整 102 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。
- 真实 Windows 窗口完成列表/详情切换、详情滚动与操作区截图检查；底部无残留，右侧未见遮挡、溢出或对比度问题。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、`PlayerBackend`、缩略图/媒体详情队列和用户数据均未改变。

## 2026-07-14 · 播放队列可视缓存与选择定位

- 确认播放器不重新获取媒体库：`LibraryPage` 将当前筛选结果复制为会话队列，播放器控制器再复制列表容器，但继续复用同一批 `VideoItem` 及其持久化媒体详情/缩略图缓存。
- 媒体库卡片和播放器队列项按真实可视区域提升缩略图、媒体详情请求；媒体详情保持单任务串行并允许可视任务越过后台队列，播放期间缩略图后台任务继续暂停且最多放行一个可视任务。
- 队列交互恢复为单击选中、双击切换播放；显式“定位当前播放”同步选中态，“定位已选中”不改变播放状态，两者均居中即时跳转并有限重试首帧布局。
- 新增媒体详情抢占、播放暂停期间可视缩略图、选择/播放状态和大索引定位计算测试；focused 67 项、完整 101 项测试、`flutter analyze` 与 Windows debug build 通过，2 项显式基准跳过。
- 真实窗口验证 173 条筛选队列首屏信息/缩略图、单击与双击反馈；自动化定位截图受 Windows Flutter 无障碍桥原生异常阻塞，保留无自动化辅助的人工复测路径。
- SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue 来源、`PlayerBackend`、缓存有效性规则和用户数据均未改变。

## 2026-07-14 · 页面级应用服务与 macOS/Linux runner

- 新增 `LibraryPageApplicationService` 与本地实现，统一加载 facade/缩略图/偏好、创建媒体详情服务并承接 debug 诊断；`LibraryPage` 不再接收完整组合根依赖图。
- 排序偏好拆为独立领域展示模型，实际文件读写由页面应用服务拥有；AppPaths、FFmpeg backend 与 Repository loader 继续只在 bootstrap 组合根选择。
- 生成 macOS/Linux Flutter runner，接入平台 media_kit 库并关闭 macOS App Sandbox 以允许用户选择并读取本地媒体。
- 新增跨平台 GitHub Actions：分别运行 adapter/架构 contract、静态分析、debug build 与启动存活 smoke；SQLite 仍由 Dart Repository 单写。
- 本地 `flutter analyze`、99 项测试和 Windows debug build 通过；真实窗口完成“原神 → 雷神”173 项筛选回归，未发现布局或状态反馈退化。
- GitHub Actions run `29324080724` 中 macOS/Linux 两个 job 均通过 adapter/架构 contract、静态分析、debug build 与 10 秒启动存活 smoke。

## 2026-07-14 · Dart part 全量清零与真实 library 边界

- 按 Store 私有 metadata/tag/scan 协作、播放器/缩略图实现、应用服务、页面/widgets 的顺序迁移剩余 35 个 `part`；项目 57 个 `part` 已全部清零。
- 新增 `LibraryStoreAccess` 私有协作端口、共享集合规则、应用主题 token 和 `LocalTagPlayerDependencies` 组合根 contract；跨文件依赖改为显式 import。
- `LibraryStore` 仍是 SQLite 单写 Repository，`LibraryApplicationFacade` 仍是页面业务入口；标签筛选、stable identity、filtered queue 与缓存队列没有迁往 Rust/C++。
- 架构 contract test 增加零 `part` 守卫；96 项完整测试、`flutter analyze` 与 Windows debug build 通过。
- 真实窗口完成“原神 → 雷神”172 条筛选、本地 root 477 项与“丽莎”9 项目录浏览/返回验证，布局与状态反馈正常。

## 2026-07-14 · DatabaseProvider、只读 Facade 与第二批 library 迁移

- 新增实例化 `AppPaths` 与 `SqfliteDatabaseProvider`；SQLite schema、标签筛选与 stable identity 继续由 Dart 单写拥有。
- facade 改为只读视图与明确命令，Tag/Cache/Playback repository 绑定同一 Store；移除静态媒体工具、窗口单例和旧位置 service。
- 页面不再读取压测环境或直接写启动诊断；该批次完成时 57 个 part 已消除 22 个，后续批次已全部清零。
- 新增 macOS/Linux adapter 类型与 contract/fake tests；analyze、Windows build 和真实窗口筛选通过，非 Windows build 待对应宿主验证。

## 2026-07-14 · 文件系统边界、Repository 门面与组合根

- 新增独立 import 的 `FileSystemAdapter` 与 `DesktopFileSystemAdapter`；目录选择、本地路径异步枚举、文件 stat、截图写入、删除和文件管理器定位不再由页面直接调用 `dart:io` / `FilePicker`。
- `LibraryStore` 实现实际 `LibraryRepository` contract，新增 `LibraryApplicationFacade`；媒体库、标签管理和 Missing/Relink 页面不再依赖 `LibraryStore` 具体类型。
- 播放器、媒体探测、扫描、FFmpeg 与 Repository 具体实现统一在 `bootstrapLocalTagPlayer()` 的 composition root 选择并注入；服务默认构造不再自行选择平台 backend。
- 首批把文件系统模块、`LayoutSize` 与 `MediaDetails` 从单一 `app.dart` part library 迁移为独立 import。SQLite schema、标签筛选、stable identity、filtered queue、缓存与用户数据语义未改变。
- 新增桌面文件系统 adapter focused test；88 项 store/media/widget focused tests、`flutter analyze` 与 Windows debug build 通过。真实窗口完成 root、子目录及一/二级标签切换，异步目录浏览和过滤结果加载正常。

## 2026-07-14 · Windows 原生依赖原子下载

- `native_player/CMakeLists.txt` 不再把网络响应直接写入最终归档；每次下载先写 `.download`，通过固定 SHA256 后再原子改名，失败时删除临时文件并最多重试三次。
- 已校验的 mpv 与 ANGLE 归档复用给 `media_kit_libs_windows_video` 插件，避免同一次 CMake 配置重复访问网络并产生两套不一致缓存。
- 从干净生成目录完成 Windows debug 构建；mpv、ANGLE、media_kit_video 及插件复用文件摘要均验证通过，未修改播放器、过滤、缓存或用户数据语义。

## 2026-07-14 · 模块二级职责目录

- 在现有一级技术模块下增加二级职责目录：页面按 library/player/tags，服务按 library/media/player/relink/tags/window，媒体库组件统一归入 widgets/library。
- `app.dart` 的 part 声明按职责分组，移动文件的 `part of` 相对路径同步更新；测试和外部调用继续只导入 `src/app.dart`，没有新增跨模块耦合。
- 本轮是纯目录与引用重组；SQLite schema、`FilterQuery` / `TagQueryService`、filtered queue、缩略图/media 队列、平台 contract 和用户数据均未改变。

## 2026-07-14 · 压力测试产物自动过期与汇总保留

- 新增统一压力测试产物生命周期脚本；只清理带 `.ltp-stress-artifact` 标记且超过保留期的直接子目录，默认保留 7 天，不触碰人工放入 `artifacts` 的文件。
- 媒体库增删压测与真实播放器压测成功后默认只保留汇总报告和压缩清单，删除隔离 profile、缩略图、临时数据库、录像、截图及逐项原始采样；失败运行保留完整现场。
- 两条 runner 均支持 `-KeepRawArtifacts` 显式保留原始证据，以及 `-ArtifactRetentionDays 0` 禁用自动过期；`artifacts/` 已加入 Git 忽略。
- 本轮只修改测试工具和文档；SQLite schema、标签筛选、filtered queue、缩略图/媒体缓存语义与播放器业务行为均未改变。

## 2026-07-14 · 卡片子树布局与播放器释放长尾诊断

- 增加仅在 debug 压测环境启用的卡片子树探针，分别聚合外壳、预览、元数据、标签和操作区的直接 builder 与包含式 layout 耗时；阶段切换后才写 JSONL，避免逐帧磁盘 I/O 污染结果。
- 三轮真实快速滚动显示直接 builder P95 均低于 0.1 ms；包含式布局热点集中在卡片外壳和操作按钮链。子树存在包含关系，结果不直接求和，也不把后代框架 Widget build 误算进应用 builder。
- 压测在最后一次 `PlayerBackend.released` 后持续驱动 Flutter 帧并采样 60 秒；有效 GPU 样本显示 Private 下降 51.8 MiB、GPU committed 下降 40.1 MiB、线程下降 3，主要回落发生在前 15–20 秒。
- Flutter ImageCache 在释放长尾内固定为 19,611,648 bytes；未触发 GC、未清理 ImageCache，也未在页面层制造表面回落。SQLite schema、标签筛选、filtered queue、缩略图缓存语义和播放器行为均未修改。

## 2026-07-14 · 滚动热点、原生释放屏障与 8K 软件解码门槛

- 后台缩略图预取把最多 500 条候选与实际 cache key/JPEG 校验分层，校验阶段最多并行 24 条；真正可见卡片继续抢占优先队列，过滤刷新不再错误预取结果列表前 36 条。
- 三轮真实 11,135 条媒体库快速滚动中，新增库 build/raster P95 中位数为 86.69/3.39 ms，移除后为 51.87/1.86 ms；可见缩略图停稳后为 8–9 张。瓶颈仍在 Dart 卡片 build/layout，未通过扩大缓存或隐藏内容伪装流畅度。
- 播放器退出严格串行 stop、dispose 与 released；Windows MediaKit 适配器把依赖内部延迟 5 秒执行的 `mpv_terminate_destroy` 纳入 released 契约，压测也等待真实释放后再开始下一会话。
- 修复未解析媒体绕过硬解矩阵：用户点击且 codec/width/height 未缓存时，只对当前项执行一次 5 秒上限的高优先级 `MediaProbeBackend` 预检；播放器队列仍不启动 FFprobe。已确认 8K H.264 默认阻止直接播放并保留代理/转码建议。
- 最终三轮 6 个播放会话均为 `d3d11va-copy`，软件解码、音视频停滞和进程无响应均为 0，seek P95 28 ms；Private/GPU committed 峰值约 1,157/712 MiB。驱动/进程分配池的跨轮高位仍存在，未宣称已经完全释放。

## 2026-07-14 · 媒体库增删与播放器十轮专项压测

- 新增 debug-only 压测控制契约、真实目录十轮 Finder/VM Service 驱动、像素录屏以及 SQLite/队列/帧耗时/进程/I/O/GPU/播放器诊断汇总脚本；真实媒体文件保持只读。
- 修复未入库统计遍历可变 roots 的并发修改、root 移除后过滤缓存未失效，以及旧媒体探测回调把已删记录重新写回 Store/SQLite 三项竞态。
- 10 轮均完成 6,308 条添加和移除，Store/UI 数量一致；添加 P95 2.405 秒、移除 P95 0.773 秒，UI 差量追平小于 1 ms。
- 录屏 366.4 秒；快速滚动 P95 中位数仍约 62/52 ms，20 个播放样本有 6 个实际软件解码，Private/GPU committed 峰值约 2,342/941 MiB，后续继续处理滚动长帧和播放器资源高位保留。

## 2026-07-14 · 4K 硬解矩阵与超规格预检

- 在 RTX 4070 SUPER / 驱动 595.97 / MediaKit `d3d11va-copy` 环境中，分别用真实 3840×2160/60 H.264、HEVC、AV1 样本各执行两轮播放器滚动、seek、全屏与退出；六轮实际硬解均为 `d3d11va-copy`，视频/音频停滞为 0，AV offset 最大约 0.000445 秒，seek 为 25–28 ms。
- 新增只读硬解兼容矩阵，未验证规格保持 unknown，不因“4K”或“AV1”名称笼统告警；已确认软件回退的 7680×4320/60 H.264 在播放器创建前显示明确确认。
- 首次进入播放器和页面内 filtered queue 切换都在新媒体 open 前预检；队列弹窗取消会恢复已打开项，确认后才提交新路径。提示同时提供保留源文件、生成 4K H.264 代理及 4K HEVC 转码的建议与可复制命令；应用不自动转码、不覆盖或删除源文件。
- 预检只读取 hydration 已恢复的 `MediaDetails`，不启动 FFprobe，不修改 SQLite schema、filtered queue、标签语义或缩略图/media 队列。
- 87 项测试、`flutter analyze` 和 Windows debug build 通过；真实窗口点击 8K 样本确认弹窗无遮挡/溢出，取消不创建播放器，明确继续后可进入并正常退出播放器。

## 2026-07-13 · 目录移除、视频删除、缩略图抢占与硬解复核

- 移除 root 现在以单 SQLite batch 提交 metadata、视频行和 `video_tags` 删除；仅删除不再受其它 root 覆盖的记录，磁盘文件保持不动，事务后立即刷新媒体库总量。
- 视频网格、列表、本地目录与继续观看卡片的“更多”菜单新增删除操作；确认弹窗可选同步删除本地文件，并明确清理标签关系、收藏、播放进度、媒体详情和缩略图缓存。
- 可见缩略图任务支持把快速滚动后的目标项重新提升到优先队首；删除会移除等待任务，并抑制活动 FFmpeg/media_kit 任务写回已作废 JPEG。
- 播放器每秒持续采样实际 `hwdec-current`，把平台属性不可用与软件解码分开；高分辨率编码在打开前显式允许 `hwdec-codecs=all`，连续软件解码只记录确认结果，不在当前会话热切换后端。诊断结论补充实际编码与分辨率。
- SQLite schema、`FilterQuery` / `TagQueryService` 语义和 filtered queue 来源未修改；79 项 store/widget tests、`flutter analyze` 与 Windows debug build 通过。真实 11,135 条窗口确认删除弹窗与滚动缩略图，8K H.264 软件回退仍属硬件/编码能力边界，未强行热切换后端。

## 2026-07-13 · 缩略图可见任务与扫描帧耗时诊断

- 修复可见卡片只等待缓存查询、却不等待 FFmpeg 生成任务的链路；同一 cache key 共享单个受限队列 Future，生成完成后卡片立即刷新。
- 卡片信任已完成的异步 JPEG 验证，不再在 build 中同步 `existsSync`；历史 4K fallback JPEG 统一按 384px 解码。
- 真实缓存 11,571 张中发现 555 张超过 1 MiB，合计约 947 MiB；保留有效缓存而不一次性触发重生成。
- debug 扫描新增固定 3 秒 Flutter 帧驱动和 JSONL 诊断。11,133 条大差量中 folder 侧边栏重算约 102 ms、filter 差量替换约 73 ms；零差量不再失效两者。
- 真实 Windows Finder/VM Service 连续点击两轮扫描通过，像素截图确认首屏缩略图已显示，布局无遮挡或溢出。

## 2026-07-13 · SQLite 启动修复与 Rust LibraryScanBackend

- 真实 11,135 条库分阶段确认约 40 秒加载中 `sqlite.open_and_maintenance` 占 38.55 秒（87.64%）：Windows `COLLATE NOCASE` 相关子查询对 20,306 条关系逐条全表扫描 videos，并在每次启动无条件重写 `video_id`。
- 增加 `videos(path COLLATE NOCASE)` 兼容索引，稳定身份和重复关系只在旧库确有缺失/重复时迁移；root 直属视频不再被误判为缺少 folder 标签而每次排入空 batch。真实副本总加载由 43.99 秒降至 0.844 秒，真实窗口首帧约 1.42 秒。
- `TagQueryService.resultCounts` 改为按视频实际标签名反查候选，保持同组 OR/跨组 AND/排除语义不变；全库初始计数由 4.81 秒降至约 205 毫秒，并移到首帧后的可取消空闲任务。
- 新增 `LibraryScanBackend`、不可变 `LibraryScanDelta`、generation 取消与 `LibraryScanCommitResult`；扫描后端只读文件系统，Dart Application 继续校验唯一 fingerprint、stable videoId/relink 并用单 SQLite batch 提交。
- 新增无第三方依赖 Rust Windows 扫描 sidecar；CMake 检测 cargo 后随构建供应可执行文件与 MIT 许可证，缺失/失败时运行时回退 Dart。父子 root 按最上层优先并按 pathKey 去重，保持一级/二级 folder 标签硬规则。
- 真实大库 A/B：去重后 11,133 条，Dart 已缓存扫描 1.751 秒，Rust 1.073 秒；隔离副本首次统一历史 root 上下文并提交 11,061 条修改 1.897 秒，第二轮 Rust 稳定态端到端 240 毫秒且零差量。
- UI 只消费提交成功的变化集合；缩略图和 `MediaProbeBackend` 仅接收新增/内容变化项，旧探测 generation 在新扫描前取消。真实窗口标签切换保持 172 条结果，首次扫描显示修改 11,061，第二轮显示新增/修改/移动/缺失均为 0。
- SQLite 未新增数据列或业务表，manual 标签、收藏、进度和播放记录继续绑定 videoId；未修改 `FilterQuery` 语义、filtered queue 来源或播放器后端。

## 2026-07-13 · 原生媒体探测与大库扫描基准

- D3D11/ANGLE 最终归因确认桥接层、ANGLE 与 Flutter 存在多个设备/上下文，双 1080p BGRA 纹理仅约 15.8 MiB，剩余差额主要来自独立解码池、D3D11VA 表面和驱动缓存；原生 Private/GPU P95 约为 MediaKit 的 114.5%/113.8%，未进入 110% 门槛，停止默认替换路线。
- 新增独立 `MediaProbeBackend` 与 Windows C++ `probeBatch/cancelGeneration`；固定 FFmpeg 8.1 LGPL shared 开发包，首次探测才延迟加载 DLL，原生工作线程限流并通过 interrupt callback 取消执行中 generation。
- `MediaDetailsService` 复用数据库 size/mtime/fingerprint，不再失败后创建临时 media_kit Player；修复完成回调误等待自身 Future 的历史闭环。
- 真实 11,135 条索引、6 个根目录基准中，15,958 个文件纯枚举 84ms，冷盘完整指纹扫描曾为 272.7 秒；复用未变化 fingerprint 后热扫描为 2.72 秒，事件循环 P95 16.95ms，因此不引入 Rust。
- 76 项测试、原生媒体探测集成测试、analyze、Windows debug build和真实窗口两轮播放器回归通过。

## 2026-07-13 · 4K 长视频分阶段 A/B 与原生渲染收敛

- 压测支持匿名锁定同一真实媒体样本，并在进程 CSV 中区分 `player_startup`、`player_stable`、`player_release` 和 `library_idle`；新增可重复生成中位数/P95/峰值的汇总脚本。
- MediaKit、原生基线、原生优化分别完成同一 3840×2160/60fps 长视频 480 秒、18 轮随机滚动、seek、全屏和退出，三组均无音视频停滞、崩溃或无响应。
- 原生渲染增加 `mpv_render_context_update` 帧更新判定、Flutter 请求尺寸量化表面和共享纹理复制计数；原生 demux 预算由 96+32 MiB 收敛到 64+16 MiB。
- 相对原生基线，稳定期工作集/Private 中位数约下降 63/68 MiB，GPU committed P95 下降约 73 MiB，seek P95 从 118 ms 降至 27 ms。
- 优化后原生稳定期 CPU 与工作集低于 MediaKit，但 Private/GPU committed 中位数仍分别高约 196/189 MiB，线程多约 10；继续保留显式实验开关，不切换默认后端。

## 2026-07-13 · Windows 原生 libmpv/ANGLE A/B 后端

- 固定 libmpv、ANGLE 与 media_kit_video Windows 纹理桥接源码的下载地址和 SHA-256，构建时供应运行库并安装第三方许可证与告知文件。
- 原生会话使用单个 `mpv_handle`、单个 `mpv_render_context`、ANGLE 渲染表面和 D3D11 共享纹理；所有控制、事件消费、渲染和释放由一个工作线程串行协调。
- 补齐 EOF、错误、实际硬解、AV 偏移、音频 PTS、帧号、掉帧、缓存、源帧率和显示刷新率的节流采样；页面仍只依赖 `PlayerBackend`。
- 同媒体、同随机种子 20 秒真实 A/B 均为 `d3d11va-copy`，视频/音频停滞均为 0；原生 seek 7 ms、释放约 25 ms，对照分别为 28 ms、约 8 ms。默认后端保持 MediaKit，不据单轮短测宣称整体性能胜出。
- 74 项测试、原生桥接集成测试、`flutter analyze`、Windows debug build 和真实窗口截图通过。

## 2026-07-13 · 播放器分阶段CPU/GPU内存归因

- 播放器生命周期增加不含路径的阶段标记，记录Flutter ImageCache、纹理ID和mpv demux状态。
- Windows压力脚本增加GPU Process Memory的Dedicated、Shared与Committed采样，并按约1秒周期输出。
- 五轮实测确认demux缓存在stop后释放、D3D共享纹理在dispose后约2秒释放，Flutter图片缓存保持稳定。
- 返回媒体库后的主要高位保留来自NVIDIA Dedicated/Committed驱动缓存；它会回落且不单调增长，当前不按活动播放器泄漏处理。

## 2026-07-13 · 压测录屏逐帧分析与 pump 修正

- 使用同步握手确保媒体库加载完成后再计满 180 秒录屏，并为随机操作输出不含路径的时间标记。
- 逐帧分析定位到错误的数秒级 `pumpAndSettle` 步长会让 Flutter 测试绑定长时间只提交一帧，制造画面冻结和点击延迟。
- 所有长等待改为 50 ms 连续 pump；媒体库初始化改为等待真实播放入口，而不是固定延时。
- 修正后进入播放器的预设等待由错误的约 48 秒恢复为 12 秒，重复退出仍完成 pause 和原生 dispose。

## 2026-07-13 · D3D11VA 直连与长驻 Player 评估

- Windows 推荐硬解固定为真实样本已验证的 `d3d11va-copy`，避免 `auto-copy` 枚举无关候选后端。
- 对照中线程峰值由 283 小幅降至 279，Private 峰值约下降 30 MiB；确认候选后端枚举不是约 150 个原生线程的主因。
- 连续退出的原生 dispose 均在约 2–20 ms 完成且线程不累积，因此拒绝会让驱动线程在媒体库常驻的全局 Player 单例方案。
- 后续 PlayerBackend 应负责串行会话所有权和会话结束释放；降低单实例峰值需要继续调查 media_kit/libmpv 视频输出或驱动边界。

## 2026-07-13 · 播放器资源收敛与独立推进检测

- 将播放器输入与 mpv 前后缓存组合预算从约 512 MiB 收敛到约 192 MiB，并固定 FFmpeg 解码并发为 4。
- 播放诊断只读取缓存详情，不再因打开诊断弹窗创建兜底 media_kit Player。
- 持续独立采样视频帧号与音频 PTS，区分画面冻结、音频停顿和播放器整体停顿。
- 退出链路先确认 pause，再记录 pop 与 dispose 时间；真实媒体循环确认两轮资源均完成释放。
- 对照测试显示工作集峰值下降约 227 MiB，但 D3D11/NVIDIA 视频输出对应的原生线程峰值仍约 283，后续需要在 PlayerBackend 或 media_kit 上游边界继续评估实例复用。

## 2026-07-12 · 全屏队列同级布局与局部重置

- 全屏播放列表改为视频右侧同级栏，展开时挤压视频区域，隐藏后恢复全屏宽度。
- 普通与全屏队列隔离滚动控制器，避免布局切换期双挂载。
- 设置卡新增“恢复默认”，只重置热区宽度和隐藏延迟。

## 2026-07-12 · 全屏队列交互设置

- 设置页可调整全屏播放列表右侧热区宽度和自动隐藏延迟。
- 新字段向后兼容旧设置文件，并对异常数值执行安全范围约束。
- 滑杆松开后持久化，播放器下次进入时使用新参数。

## 2026-07-12 · 全屏队列边缘抽屉

- 全屏播放列表改为非模态右侧抽屉，可由按钮或屏幕右侧边缘悬停唤出。
- 鼠标离开队列范围后自动隐藏，隐藏时不保留后台 ListView。
- 长视频真实点击验证按钮展开、离开隐藏和边缘重新展开。

## 2026-07-12 · 播放器预热、滚轮音量与全屏队列

- 队列缩略图支持路由前预热和首帧同步内存缓存，减少进入播放器时的占位背景闪烁。
- 当前媒体可播放后再延迟预取相邻队列详情，降低大文件首次播放的 I/O 竞争。
- 音量区域支持鼠标滚轮，空闲控制层完全隐藏，全屏播放列表支持右侧展开。
- 长视频真实点击和 DPI-aware 窗口截图覆盖五项改动。

## 2026-07-12 · accessibility bridge 隔离验证与无 UIA 截图

- 增加播放器队列折叠/恢复的无 UIA Windows 桌面集成测试和像素截图脚本。
- 修复队列首次布局时 viewport 尺寸尚未建立导致的空值异常。
- 隔离比较 Flutter stable 3.44.4 与 beta 3.46.0-0.3.pre，因缺少 UIA bridge 修复证据暂不升级生产 SDK。

## 2026-07-12 · 长视频隔离复测与菜单方向纠正

- 生成 600 秒同路径隔离视频，排除 18–24 秒 EOF 对 UI 自动化退出的干扰。
- 真实截图发现 `bottomEnd` 会让菜单向上展开，修正为 `topEnd` 后确认菜单从齿轮下方向下展开。
- 日志确认自动化退出前没有 Dart、media_kit、mpv 或 FFmpeg 异常，唯一错误为 Flutter Windows AXTree 更新失败并进入 `ax_platform_node_win.cc` unreachable code。
- 队列折叠/恢复真实截图仍被该 Flutter Windows 辅助功能桥崩溃阻塞；保活布局由 71 项测试、analyze 和 Windows build 继续覆盖。

## 2026-07-12 · 播放器菜单方向与队列入口收敛

- 播放设置菜单使用 root overlay、底部对齐和向下偏移，固定从齿轮按钮下方展开。
- 全屏按钮后的折叠箭头改为播放队列图标，仍用于宽屏队列展开/折叠。
- 宽屏队列折叠后不再在顶栏显示重复“播放队列”入口；窄屏仍保留底部队列入口。
- `AGENTS.md` 新增强制规则：业务代码修改后自动启动并真实点击；UI 改动触发后必须截图分析。
- 71 项测试、analyze 和 Windows debug build 通过；自动点击受隔离短视频浮层后进程退出阻塞，已记录准确复测路径。

## 2026-07-12 · 播放器二级设置菜单与侧栏保活

- 当前帧截图恢复为控制栏独立相机按钮；播放速度与播放模式改为齿轮菜单中的二级列表。
- 信息卡“更多”菜单固定从按钮下方展开，避免浮层遮挡触发按钮。
- 右侧筛选队列折叠时只压缩为零宽，不销毁列表、缩略图或滚动状态，恢复时不再重新加载。
- 全屏状态优先消费 Escape 并退出全屏；设置页快捷键卡新增只读 `Esc / 退出全屏` 安全入口说明。
- 71 项测试、analyze 和 Windows debug build 通过；隔离窗口截图确认独立截图按钮和二级菜单入口。

## 2026-07-12 · 播放器控制去重与桌面全屏修复

- 倍速、播放模式、快捷键、当前帧截图和播放诊断统一收纳到控制栏齿轮菜单，减少进度条下方重复按钮。
- 全屏按钮改用桌面窗口全屏，进入后隐藏顶栏、信息卡和筛选队列，真实铺满显示器；全屏尺寸不会覆盖普通窗口恢复值。
- 全屏按钮后新增筛选结果队列折叠/展开按钮；队列头部删除重复播放诊断入口。
- 视频信息卡“更多”删除播放模式与播放诊断，只保留收藏和视频信息。
- 71 项测试、analyze 和 Windows debug build 通过；隔离真实窗口截图确认精简控制栏、队列去重和真正全屏。

## 2026-07-12 · 播放器弹窗内部卡片统一

- 标签编辑器统一为“编辑范围 / 标签选择”两级卡片，保留搜索、新建、锁定来源、最近使用、收藏和键盘保存行为。
- 视频信息从纯文本改为文件、媒体、整理状态和按需异常卡片，长路径与指纹保持可选择并可滚动查看。
- 播放诊断新增实时状态、分析结论、详细指标卡片和状态徽标，复制摘要仍不包含本地路径。
- 隔离真实窗口逐一完成标签输入与取消、视频信息打开、诊断打开与复制反馈截图；71 项测试、analyze 和 Windows debug build 通过。

## 2026-07-12 · 窗口恢复、快捷键设置与统一 UI

- 新增桌面窗口状态服务，恢复上次窗口大小与最大化状态；resize 延迟合并写入独立 `window_layout.json`。
- 播放器移除底部快捷键提示；设置页新增十项快捷键编辑和恢复默认，冲突绑定自动交换并写入现有设置 JSON。
- 全局统一弹窗、菜单、BottomSheet 和 SnackBar；播放器使用暗色局部主题，“更多”菜单改为高对比暗底亮字。
- 隔离真实窗口完成设置页、快捷键冲突交换、播放器无提示栏和“更多”菜单截图复测。

## 2026-07-12 · 播放器蓝图信息卡与快捷栏对齐

- 视频信息卡改为蓝图式双层结构：文件名/路径与图标化媒体摘要在上，标签 chips、添加标签和操作按钮在下。
- 标题补齐文件扩展名和编辑入口；分辨率使用独立徽标，收藏迁入“更多”菜单，避免占用主操作区。
- 快捷键栏改为 Space、J/L、T、F、S，并接入编辑标签、全屏和当前帧截图真实动作。
- 隔离真实窗口确认信息卡和快捷栏无溢出；未修改标签来源、filtered queue、PlayerBackend 或缓存队列。

## 2026-07-12 · 播放器蓝图红框控制层精确重排

- 按 1920 宽蓝图重设上一条、播放、下一条、音量滑杆和时间的固定间距，时间统一为 `HH:MM:SS / HH:MM:SS`。
- 右侧补齐真实快捷键提示、当前帧截图和播放模式入口，与既有倍速、诊断、全屏组成完整工具组。
- 截图通过 media_kit 获取 JPEG，并仅在用户确认保存路径后写入；中窄窗口改用底部队列，避免侧栏挤压控制层。
- 未修改 filtered queue、EOF、进度持久化、PlayerBackend、标签语义或缓存队列。

## 2026-07-12 · 播放器蓝图控制区与队列深度对齐

- 使用隔离 profile 与三条真实 H264/AAC 视频截取播放器基线，按蓝图逐区复核进度控制层、信息卡、快捷栏和筛选队列。
- 进度与音量改为蓝紫细轨和小圆点，控制顺序统一为上一条、播放/暂停、下一条、音量、时间、倍速、诊断和全屏。
- 队列补齐只读筛选状态 chips、暗色搜索框、蓝紫播放态和更接近蓝图的缩略图/卡片比例；快捷键栏横向铺满。
- 保留 Windows 原生标题栏；不增加绕过媒体库的“打开文件”或伪装字幕、画中画等未实现能力。

## 2026-07-12 · 播放器蓝图双栏比例修正

- 右侧筛选队列改为随窗口宽度保持约 30% 占比，并限制在 360–500px，宽屏下不再固定挤压为 360px。
- 队列容器顶边与左侧视频画面统一为 18px，恢复蓝图中的双栏视觉基线。
- 新增响应式宽度 focused test；未修改 filtered queue 来源、播放控制、标签语义或缓存队列。

## 2026-07-12 · 播放器蓝图布局对齐

- 新增品牌顶栏、当前队列搜索和已实现快捷键提示，蓝图右上角“打开文件”明确不纳入实现。
- 视频身份卡补充路径与媒体摘要，并以标签、收藏、文件位置和更多操作承接标签播放器差异化。
- 右侧 filtered queue 改为独立圆角容器，增加队列总数徽标并提高播放项的视觉层级。
- 未修改 Schema、filtered queue 来源、EOF 策略、播放进度、PlayerBackend 或缓存队列。

## 2026-07-12 · 播放器控制层与信息层级重排

- 播放、前后项、进度、时间、倍速、音量和全屏统一进入画面底部自动淡化控制条。
- 视频信息卡精简为单行标题、醒目队列序号、短筛选摘要、收藏、标签与更多菜单。
- 文件位置、视频信息、播放诊断和播放模式归入更多菜单；右侧队列顶部去除重复摘要。
- 未修改 filtered queue、EOF 策略、进度持久化、PlayerBackend 或媒体缓存队列。

## 2026-07-12 · 继续观看默认行为与设置页信息增强

- 新增继续观看默认行为设置，默认直接恢复上次位置；从头播放和每次询问仍可选。
- 解码器常用策略收敛为推荐、性能优先和兼容优先，具体技术后端放入高级折叠区并保留切换确认。
- 缩略图缓存逐项展示总数、缓存、缺失、失败、活动/并发、排队和平均耗时；刷新入口增加文字标签。
- 新设置字段使用 JSON 向后兼容默认值，不修改 SQLite schema 或稳定播放进度。

## 2026-07-12 · 搜索计数与播放器筛选上下文一致性

- 当前结果数包含关键词条件并立即更新，摘要直接展示实际标签、关键词与命中数；标签旁统计仍走延迟刷新。
- 补强 `Ctrl+K` 页面级键盘处理，真实窗口页面容器持焦点时可聚焦稳定 `TextField`。
- 播放器右侧复用媒体库筛选摘要并显示队列项数，不再错误回退“全部视频”。
- 提升播放器底部操作及播放模式菜单的暗色对比度，“下一条”改为高辨识度主色按钮。

## 2026-07-12 · 第四阶段隔离播放器 smoke

- 使用两条真实 H264/AAC 测试媒体和独立 profile 点击验证播放模式、随机 EOF、六档倍速、全屏队列上下文与标签入口。
- 修复全屏标签弹窗按 Escape 后底层播放器重复处理同一按键、导致意外返回媒体库的问题。
- 回归确认 Escape 关闭标签弹窗和全屏后仍停留在原 filtered queue 播放页；测试 profile 与媒体已清理。

## 2026-07-11 · 播放模式、倍速与全屏上下文

- 新增顺序、随机、单曲循环和列表循环；默认顺序播放的队尾停止语义保持不变，随机播放不会连续命中当前项。
- 新增六档播放速度和少量桌面高频快捷键，继续保留原有 filtered queue 导航快捷键。
- 全屏画面只展示当前队列序号、筛选标题和编辑标签入口，避免复制完整队列侧栏。
- 本轮未增加字幕、音轨、逐帧或 A-B loop，后续按真实反馈决定是否建设。

## 2026-07-11 · 批量 Relink 审计、原子提交与失败重试

- 预览列表新增本地搜索，支持标题、路径与状态关键词，不触发数据库查询或媒体扫描。
- 新增复制审计摘要，包含分类与执行计数，明确隐藏本地路径和文件标题。
- ready 项执行前统一重验，并在一个 SQLite batch 中原子提交；事务失败恢复视频、标签和关联内存索引。
- 失败 videoId 保留在弹窗中，可恢复目标文件后定向重新预览并重试；成功项不会重复执行。
- 扫描 root 元数据保存失败与视频批事务结果分离，审计摘要和 UI 会单独提示，不误重试已成功视频。

## 2026-07-11 · 跨盘迁移、批量路径预览与快照串行队列

- Missing 管理页新增旧/新路径前缀预览，分类显示可更新、目标不存在、路径冲突和指纹不一致。
- 批量应用前二次确认，只更新 mutable path；每条执行仍复用 fingerprint 校验，不移动或删除文件；旧前缀精确等于媒体 root 时同步迁移扫描 root。
- 新增 `PlaybackSnapshotWriteQueue`，按 videoId 合并待写状态并严格串行 upsert；播放器退出前 flush，错误可见。
- 新增 20 条真实 C:→E: 跨盘 soak，确认重载后稳定身份、manual 标签、收藏和播放进度完整保留。

## 2026-07-11 · Stable Video Identity 播放状态第三阶段

- SQLite `videos` 幂等增加 `playback_duration_ms` 与 `playback_completed`，和既有位置字段一起绑定稳定 videoId。
- 播放器再次打开时提供继续/从头选择；切换、退出、低频进度和 EOF 均写入位置、总时长与完成态。
- 最近播放升级为继续观看，并显示进度；完成项、少于 3 秒和接近结尾项自动排除。
- 短视频使用 1-2 秒尾部阈值，长视频使用 5% 且 5-30 秒范围，避免最后几秒循环恢复。
- 队列 missing 项显示明确状态并停止缩略图/媒体探测；失败面板可直接 Relink，保留标签、收藏和播放状态。

## 2026-07-11 · Missing/Relink 用户闭环与播放器键盘基准

- 标签编辑弹窗新增 autofocus、焦点遍历、Ctrl+Enter 保存和 Escape 取消。
- 当前队列搜索增加 50,000 条性能回归基准，防止误接全库扫描或超线性退化。
- 侧栏新增“缺失与重新关联”；单文件 relink 校验扩展名、路径占用和 fingerprint，失败不改变稳定条目。
- 成功 relink 保留 videoId、manual 标签、收藏、播放记录和进度，并重新派生 folder 标签；未修改 SQLite Schema。

## 2026-07-11

### 标签播放器差异化第二阶段

- 播放器保留可见“编辑标签”入口，编辑器只展示/维护已知 manual 标签；folder 标签锁定显示，不能从播放器误删。
- manual 标签编辑器新增“最近使用 / 收藏标签 / 全部或搜索结果”分区，输入框同时支持即时搜索和新建标签。
- 右侧队列新增轻量搜索定位，匹配当前 filtered queue 的标题、路径、一级/二级标签；搜索只返回队列索引，不重新查询或扫描媒体库。
- 播放页新增“打开文件位置”；系统调用集中在 `DesktopFileLocationService` 平台边界，Windows 选中文件，macOS 使用 reveal，Linux 打开父目录。
- 播放器内收藏与 manual 打标改为单条写库；操作期间不重建队列、不刷新标签计数，返回媒体库后只执行无计数可见结果刷新。
- 新增 focused tests 覆盖队列内搜索、最近/收藏/搜索标签分区、folder 标签锁定和缺失文件定位失败。
- 本轮未修改 SQLite schema、`FilterQuery` / `TagQueryService` 语义、filtered queue 来源或缩略图/media 队列。

### Stable Video Identity 与播放进度迁移

- `videos` 表兼容新增 `video_id`、`is_missing`、`playback_position_ms`、`playback_position_updated_at`；旧库启动时幂等生成稳定 ID，不要求清库。
- `video_tags` 兼容新增 `video_id` 并从旧 `video_path` 关系回填；新增、移除、统计和扫描重建均改按稳定身份操作，`video_path` 暂保留为兼容列。
- `VideoItem.path` 改为 mutable location；扫描发现旧路径失效时不再硬删除记录，而是标记 missing，保留标签、收藏、最近播放、媒体详情与进度。
- fingerprint 升级为 `v2:文件大小:首尾各 4KB 内容哈希`，不依赖路径或修改时间；只有 fingerprint 在旧记录和新扫描结果两侧都唯一时才自动 relink，冲突时拒绝自动合并。
- 播放器按稳定条目低频保存进度并在重新打开时恢复；接近结尾的进度不恢复，播放完成后清零。
- 新增迁移、missing 保留、唯一 fingerprint relink、歧义 fingerprint 防串档、进度持久化和安全恢复 focused tests。
- 迁移向后兼容且幂等；未修改 `FilterQuery` / `TagQueryService` 过滤语义、filtered queue 来源或缩略图队列。

## 2026-07-10

### 真实坏文件 smoke 与播放器内快速编辑 manual 标签

- 播放器打开媒体后增加短时可播放性确认：当时长、视频编码和音频编码均不可用时进入稳定 `unplayable_media` 错误态，避免 0-byte 文件被 `Player.open` 接受后永久停在 `00:00`。
- 使用独立 `LOCAL_TAG_PLAYER_DATA_DIR`、0-byte MP4 和两条真实 H264/AAC 媒体完成隔离窗口 smoke；坏文件的“诊断详情”可见安全错误类型，“跳过此项”会继续播放下一条正常媒体。
- 播放器上下文面板新增“编辑手动标签”入口；编辑器明确锁定 folder 来源标签，只允许维护 manual 标签，并在保存时优先按已有 `tagId` 增删关联。
- 兼容保留其它来源标签与旧视频标签字段；隔离 profile 中新增 manual 标签后播放器立即刷新、filtered queue 不变，重启应用后标签仍存在。
- 新增 focused tests 覆盖无时长且无编码媒体的拒绝逻辑，以及 folder 标签不可删除、manual 标签可编辑的弹窗行为。
- 播放进度记忆本轮不实施，等待 Stable Video Identity 后绑定稳定 `videoId`，避免继续绑定可变路径。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、filtered queue 来源、缩略图/media 队列或播放进度数据。

### 播放器连续播放与错误恢复闭环

- 播放器订阅 `media_kit` 完成事件，在当前 filtered queue 内顺序进入下一条；到达队尾后停止，不默认循环，并持续显示“当前筛选队列已播放完毕”。
- 播放器上下文面板新增显式“上一条 / 下一条”按钮，继续保留 `PageUp / PageDown` 等现有键盘路径。
- 视频打开失败从短暂 SnackBar 改为稳定恢复面板，提供“重试 / 跳过此项 / 诊断详情”；错误摘要只记录安全错误类型，不保存异常正文中的本地路径。
- 播放诊断入口移到播放器顶部，诊断弹窗支持复制不含本地路径的摘要，并在弹窗内显示复制完成态。
- 新增 focused tests 覆盖顺序队列边界、队尾不循环、失败状态重试与成功清理；全量 `flutter test`、`flutter analyze`、Windows debug build 通过。
- 真实窗口验证多条队列 EOF 自动从第 1 条推进到第 2 条；单条筛选队列在 `00:10 / 00:10` 停止并持续显示队尾提示；返回媒体库保留原筛选和结果数量。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、filtered queue 来源、`PlayerBackend` 或缩略图/media 队列。

### 设置页解码切换确认态

- 播放硬件解码下拉抽出为 `PlaybackDecoderDropdown`，解码切换仍必须先经过确认弹窗。
- 修复取消确认后下拉框内部临时选中态残留的问题：取消不会保存设置，也不会继续显示未确认的新解码选项。
- 新增 focused widget test 覆盖取消不保存、确认后才切换的行为。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

## 2026-07-09

### 主界面语义压测稳定化

- 为排序按钮、排序项、本地媒体库 root / 文件夹、一级/二级标签 chip、视频播放/收藏/更多入口补充稳定语义标签，真实窗口 QA 可优先通过辅助树定位，减少普通窗口和最大化窗口之间的坐标漂移。
- 新增 `scripts/qa/main_window_stress_semantic.mjs`：随机执行一级标签、二级标签、排序字段、正倒序、本地媒体库路径、视频打开和返回，并在应用退出、窗口丢失、连续找不到目标或重复命中同一目标时停止。
- 压测脚本点击前会做双快照稳定校验，并过滤关闭、最小化、最大化等窗口 chrome 元素，避免动态 UI 刷新后复用过期 `element_index` 误点到标题栏。
- 压测脚本的残余失败分类从笼统“目标暂时不可见”细分为 `ui_state_wait`、`list_visibility`、`tag_expansion`，同时输出 `failureDetails`，按失败类型、阶段和原因聚合，便于长期 smoke 门禁直接定位误报来源。
- 真实窗口 5 分钟语义压测执行 28 轮，未触发应用退出、窗口丢失或重复点击同一目标；残余失败主要是动态 UI 状态下语义目标暂时不可见，stderr 出现 Flutter Windows `AXTree` 更新错误但进程保持响应。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 标签计数刷新协调与耗时采样

- 新增 `LibraryCountRefreshCoordinator`，统一管理标签计数的空闲延后、取消和过期丢弃，`LibraryPage` 不再内联维护计数刷新 revision。
- 高频标签点击和搜索输入会取消待执行计数任务，低频库结构变化才安排空闲计数刷新，优先保证可见视频结果更新和界面流畅度。
- 新增 focused test 覆盖旧计数任务取消后不会执行 `resultCounts`，只保留最新空闲计数结果。
- 新增 `docs/qa/main_window_latency_smoke.md`，提供真实窗口标签切换、搜索输入和路径切换的耗时采样模板，后续 QA 可记录每轮 `elapsedMs` 与结果摘要。
- 耗时采样模板升级为辅助树优先：脚本先按标签文本解析 `element_index` 并点击，二级 chip 无独立语义时才回退到右侧面板相对坐标，减少普通窗口/最大化窗口坐标漂移造成的误命中。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 搜索输入与标签切换流畅度

- 搜索框新增页面级 `FocusNode` 协调，`Ctrl+K` 会稳定聚焦主搜索框并选中现有文本，真实键盘输入、自动化输入和 controller 文本变化继续统一走 `onChanged` 筛选入口。
- 标签点击和搜索输入默认只刷新当前可见视频结果，不再同步触发全量标签计数刷新；需要刷新计数时使用 revision 保护的延后任务，旧任务完成后不会覆盖新筛选状态。
- 新增 widget smoke 覆盖 `Ctrl+K -> 输入 firefly -> onChanged -> 结果计数/列表更新`，确保搜索结果计数和可见列表同步变化。
- debug exe 真实窗口复测：连续 10 轮随机切换不同一级标签并点击其下二级标签两次，未观察到全页空白或冻结；`Ctrl+K -> 逐键输入` 可触发搜索筛选，结果从全量收敛到匹配列表。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

## 2026-07-08

### 二级标签筛选与交互流畅度

- 修复右侧一级展开卡中点击二级标签可能筛不出视频的问题：`FilterQuery` 现在携带当前媒体库 roots，并按当前文件树重新派生一级/二级层级参与匹配。
- 同时配置 `X:\test-media` 与 `X:\test-media\鸣潮` 这类子 root 时，筛选会以最上层 root 为准，`X:\test-media\鸣潮\尤诺` 正确命中一级 `鸣潮`、二级 `尤诺`。
- 排序 helper 改为预计算标题、目录、扩展名、日期、大小和路径 key，减少大库切换排序或标签后反复拆字符串造成的 UI 卡顿。
- 筛选后的 `FilterState` 排序也复用同一预计算排序入口；标签计数刷新延后到可见结果更新之后，避免点击标签后立即阻塞主界面。
- 项目规则新增：二级标签必须永远从属于一级标签，不能与一级标签同层；标签筛选和排序方式改变时永远以界面流畅度为第一优先级。
- 本次未修改 SQLite schema、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### Windows 风格排序字段

- 顶部排序字段对齐 Windows 文件排序习惯：菜单按“名称 / 日期 / 类型 / 大小 / 目录 / 添加时间”展示。
- “日期”沿用旧的 `recent` 偏好 key 以兼容已保存设置，但排序语义改为优先使用文件修改时间，缺失时回退到应用入库时间。
- “名称”改为大小写不敏感的自然排序，`video2` 会排在 `video10` 前面；“类型”按扩展名排序，“大小”按扫描到的文件大小排序。
- 排序下拉面板增加最小宽度，避免新增长字段后菜单文字溢出或与按钮宽度强绑定。
- 新增 widget tests 覆盖 Windows 风格字段、自然排序、类型/大小/日期/添加时间排序和菜单宽度稳定性。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 文件树层级标签与本地媒体库排序

- 右侧标签发现面板的 folder 一级/二级候选改为从 `store.videos` 的真实路径和 `store.roots` 重新派生，不再信任历史 `tags` 表里的 folder.primary / folder.child 记录。
- 多个 root 同时命中同一视频时优先使用最上层 root，例如 `X:\test-media\崩坏三\李素裳\clip.mp4` 会派生一级 `崩坏三`、二级 `李素裳`，不会把 `李素裳` 当一级。
- folder 组筛选继续通过 `primaryTagId/childTagId` 的路径兼容字段执行，避免历史 tag id 与当前文件树 root 不一致时影响筛选结果。
- 本地媒体库路径浏览里的视频项现在使用与媒体库、标签筛选、本地收藏、最近播放相同的 `sortedLibraryVideos` 排序规则；文件夹仍固定在视频前面。
- 新增 widget test 覆盖 `X:\test-media` 与子 root 并存时的一级/二级派生。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 媒体库排序状态持久化

- 新增媒体库排序偏好持久化到独立 `library_sort.json`，不再每次进入媒体库页面都回到默认排序。
- 媒体库全量结果、标签筛选结果、本地收藏和最近播放统一使用 `sortedLibraryVideos` 排序 helper，避免不同来源各自排序导致选择的排序方式不生效。
- 排序偏好独立于播放硬解 `settings.json`，播放设置保存不会覆盖媒体库排序字段和方向。
- 新增 widget tests 覆盖排序偏好 save/load，以及筛选、收藏、最近播放三类来源使用同一排序规则。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 标签筛选一级列表层级修复

- 右侧标签发现面板增加文件树层级守卫：一级列表只接收 `folder.primary`、`folder` 来源、无父级且 id 形态为 `folder.primary:*` 的标签。
- 二级候选只接收 `folder.child`、`folder` 来源、带父级且 id 形态为 `folder.child:*` 的标签；二级标签继续只在一级展开卡或“全部二级标签”页签展示。
- 补充 widget test，模拟历史污染数据把二级/manual 标签误放进 `folder.primary` 组，确认一级候选不会展示这些污染项。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### 主界面标签与排序性能 QA

- `LibraryStore` focused tests 增加扫描异常路径覆盖：内容变化会清理旧媒体详情/缩略图错误，不可访问 root 不会误删仍存在的视频，非 manual 来源标签不能走批量 manual 添加/移除。
- 右侧标签筛选的“一级标签”页签只展示 `folder.primary` 文件夹一级标签；二级标签统一收敛到“全部二级标签”页签，避免一级页签混入热门二级标签造成层级误解。
- 媒体库排序切换改为直接重排当前 `FilterState`，不再触发完整筛选刷新和 `resultCounts` 重算；标签计数刷新延后执行，降低切换排序或标签时的主线程阻塞感。
- “添加时间”排序只使用 `addedAt`，播放器返回更新 `lastPlayedAt` 不再导致主媒体库默认排序重排。
- 播放器 controller tests 覆盖二级队列切换回退和 open 请求失败后继续保留最新打开请求。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 来源、`PlayerBackend` 或缩略图/media 队列。

### LibraryStore 边界继续拆分

- `LibraryStore` focused tests 继续覆盖 metadata 去重持久化、扫描删除缺失视频并保留剩余 manual 标签、manual child link 删除不破坏 folder child 兼容字段。
- 新增 `LibraryMetadataPersistence`，集中 metadata 表 roots / favoriteTags 的加载、去重和保存。
- 新增 `LibraryScanCoordinator`，承接扫描结果合并、增量视频写入、缺失视频清理、folder 标签索引刷新和 metadata batch 保存。
- 新增 `LibraryTagMaintenance`，承接 manual/folder 标签来源分离策略、批量 manual 标签添加/移除、folder/manual 标签索引同步。
- 播放器侧新增 `PlayerOpenRequestController` 和 `player_delete_dialog.dart`，把 open 请求最新路径/worker/遮罩状态与删除确认弹窗从 `PlayerPage` 拆出。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue、`PlayerBackend` 或缩略图/media 队列。

### Store 测试保护与播放器拆分

- 新增 `test/library_store_test.dart` focused tests，覆盖临时目录扫描、folder 一级/二级标签派生、manual 标签添加/移除不破坏 folder 标签，以及 roots、favoriteTags、收藏和播放时间的 `save/load` 持久化。
- `LibraryStore` 增加 `close()`，用于测试和后续 repository/service 拆分时释放 SQLite 文件句柄。
- 新增 `LibraryScanService`，将文件系统扫描、视频扩展名识别、stat 读取、folder 标签派生和轻量媒体指纹从 `LibraryStore.scan()` 中拆出；`LibraryStore` 仍负责 SQLite 写入、内存状态和标签索引同步。
- `player_page.dart` 拆出 `player_context_panel.dart` 和 `player_queue_sidebar.dart`，保留播放器生命周期、跳转、快捷键和队列语义不变。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面模块继续拆分

- 继续按职责拆分 `library_widgets.dart`：本地媒体库路径浏览迁到 `widgets/library_local_view.dart`，右侧标签筛选面板迁到 `widgets/library_tag_discovery_panel.dart`，视频网格、列表行和卡片迁到 `widgets/library_video_results.dart`。
- `library_page.dart` 中的筛选摘要、显示表达式、播放队列标题、排序比较和排序切换逻辑迁到 `pages/library_page_helpers.dart`，保留页面主体负责状态输入和布局编排。
- 评估 `library_store.dart` 后确认它仍耦合 SQLite 持久化、目录扫描、标签索引同步和手动标签维护；本轮只记录边界，不在缺少专门测试时拆分扫描/标签/持久化层。
- 本次保持 `part of '../app.dart'` 编译边界，不改变私有符号可见性、SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面 UI 模块拆分

- 分析当前代码行数后确认最大耦合点：`library_widgets.dart` 约 5001 行、`player_page.dart` 约 2126 行、`library_page.dart` 约 1943 行、`library_store.dart` 约 1140 行。
- 先按低风险边界拆分 `library_widgets.dart`：测试/自动化 key 移到 `widgets/library_smoke_keys.dart`，顶部排序控件和排序枚举移到 `widgets/library_sort_control.dart`。
- 保持现有 `part of '../app.dart'` 架构，不切换 import/export 边界，避免一次性破坏私有符号访问和业务行为。
- 拆分后 `library_widgets.dart` 降到约 4647 行，排序控件模块约 297 行，smoke key 模块约 68 行。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 排序抽屉展开

- 排序字段列表从 `PopupMenuButton` 浮动菜单改为自定义下拉面板，面板贴合排序字段按钮底部并向下展开。
- 下拉面板使用字段按钮同宽、底部圆角和轻阴影，顶部不再作为独立浮层覆盖或压住按钮。
- 顶部工具栏 smoke 改为验证排序下拉面板与字段按钮底部对齐且宽度一致。
- debug exe 真实窗口复测：点击“添加时间”后，“添加时间 / 名称 / 目录”列表像抽屉一样从按钮下方展开，未再出现按钮与列表重叠。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 本地收藏叠加筛选 QA

- 修复左侧“本地收藏”进入后再点击右侧标签会丢失收藏条件的问题：本地收藏入口现在同步设置 `favoriteOnly`，标签筛选会继续按 AND 关系叠加。
- 当前筛选 chip 中的收藏文案统一为“本地收藏”，不再残留“智能收藏”。
- 排序字段菜单增加垂直偏移，避免弹出列表与顶部排序按钮贴边或视觉重叠。
- 顶部工具栏 smoke 增加排序菜单位置断言，确保菜单项在排序按钮下方展开。
- debug exe 真实窗口复测：本地收藏播放队列标题正确；本地收藏叠加 `mod + ntr` 后结果收敛到 0 条且收藏 chip 保留；网格/列表下排序字段和正倒序切换未发现遮挡。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 顶部工具栏与排序方向

- 顶部工具栏移除“收藏筛选”按钮，收藏视频入口统一到左侧“本地收藏”，避免与侧栏来源视图重复。
- 左侧“智能收藏”改名为“本地收藏”，当前筛选摘要、结果 chips 和播放器队列标题同步更新。
- 排序控件改为工具栏内的分段式控件：左侧选择排序字段，右侧独立切换“正序 / 倒序”。
- 排序方向纳入媒体库筛选状态缓存 key，切换方向时会刷新当前列表顺序，但不改变标签筛选语义。
- 新增顶部工具栏 smoke 断言，覆盖重复收藏按钮移除、排序方向文字和点击回调。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 列表模式操作区对齐

- 列表模式视频行移除内容区 980px 宽度上限，行内信息区使用剩余空间，播放、收藏、更多操作区固定到卡片右侧。
- 操作按钮保持 8px 间距，右侧保留约 8px 内边距，避免按钮贴边或悬在列表中部。
- 新增宽屏列表行 smoke 断言，验证“更多”按钮右边缘贴近列表行右边缘。
- 使用 debug exe 真实窗口复测列表模式：每行播放、收藏、更多按钮已右对齐到列表卡片右侧。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 顶部工具条与播放器返回性能

- expanded 顶部工具条取消搜索框宽屏固定上限，搜索框会填满右侧动作按钮左侧的剩余空间，窗口放大时红框区域同步扩展。
- 播放器返回主界面后，`lastPlayedAt` 更新改为轻量路径：不再触发全库标签计数、完整筛选刷新和缩略图预取，降低大媒体库返回卡顿。
- 保留最近播放、收藏和按播放时间排序场景的必要轻量重建，不改变播放器队列来源或标签筛选语义。
- 新增顶部工具条宽屏填充 helper 测试，避免搜索框重新退回固定宽度。
- 使用 debug exe 真实窗口复测：最大化后顶部搜索工具条已跟随宽度拉伸；从视频进入播放器约 980ms，点击 Back 返回主界面约 698ms。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面布局比例

- 主界面 expanded 状态下，左侧导航和右侧标签筛选面板由固定宽度改为基于窗口总宽度的比例宽度，窗口放大/缩小时三块区域会同步保持相对占比。
- 较窄 expanded 宽度下优先保护中央结果区，避免右侧标签面板把视频结果区域挤压到不可用。
- 新增 `mainLibraryLayoutSlotsForWidth` 纯函数测试，覆盖 1280 / 1600 / 1920 宽度下左右栏增长、中心区增长和总宽度守恒。
- 使用 debug exe 真实窗口复测普通窗口与最大化窗口：三栏区域可见比例随窗口尺寸变化，视频结果区可扩展到更多列，右侧标签筛选未遮挡中心内容。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 搜索输入与 Git 规则

- 新增 Git 远程提交规则：验证通过并完成本地提交后，必须执行 `git push` 到当前分支远程跟踪分支；如果远程不存在、认证失败、网络失败或用户明确要求暂不推送，记录原因并保留本地提交。
- 顶部搜索框从 `SearchBar` 改为稳定 `TextField` 输入链路，保留原搜索图标、`Ctrl + K` 提示、controller 和 `onChanged` 筛选刷新方式。
- 新增顶部搜索框 widget smoke test：输入 `lupa` 后断言 `TextEditingController` 和 `onSearchChanged` 都收到新关键字。
- 真实窗口 QA 继续复测：Computer Use 的 `type_text` / `set_value` 对 Flutter Windows 文本控件仍不稳定；逐键输入可触发搜索筛选，但目录管理、本地媒体库路径和右侧一级/二级筛选因 Windows 自动化前台窗口状态中断，仍需人工复测。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 主界面 smoke test

- 使用 debug exe 对主界面第一轮 smoke test：覆盖媒体库、最近播放、智能收藏、标签中心、设置、排序菜单、右侧标签面板收起/恢复和播放入口。
- 修复右侧标签筛选面板收起后恢复入口缺少按钮语义的问题：收起窄条现在暴露“展开标签筛选”语义、Tooltip 和稳定 smoke key，点击后可恢复右侧标签面板。
- 新增 `collapsedTagDiscoveryRailSmokeHarness` widget smoke test，覆盖收起窄条 key、Tooltip 和点击回调，避免恢复入口再次退化。
- 播放入口复测通过：从主界面底部“播放”进入播放器，右侧队列显示 `1 / 11078`，返回主界面正常。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 语义、播放器队列规则、缩略图/media 队列或用户数据维护规则。

## 2026-07-07

### 媒体库参考顶部布局

- 全仓库自有文档和代码注释完成中文化审查：Dart 注释英文句子已改为中文，`ROADMAP.md`、`docs/chat_tasks`、`.agents/skills`、安装说明和 FFmpeg 工具说明中的英文/乱码正文已改为中文；保留必要技术术语、路径、命令和 API 名称。
- 新增中文优先规则：文档新增/修改、代码注释、任务记录和 Git 提交信息默认使用中文；只有代码、第三方 API、命令、路径、固定术语和外部错误信息保留必要原文。
- 清理右侧标签面板周边残留乱码注释：`_SmartFilterContextCard` 和 `TagDiscoverySmokeHarness` 的维护说明改为中文，不改变筛选逻辑、播放队列或数据库。
- 本轮验证通过：`dart format lib/src/widgets/library_widgets.dart`、`flutter analyze`、`flutter build windows --debug`。
- 修复右侧热门二级标签“更多标签”按钮：从禁用样式改为可点击展开/收起，并显示 `当前/总数`。
- “全部二级标签”页签改为使用完整二级标签列表，不再被热门区默认 12 个标签截断。
- 热门二级标签仅在同名冲突时显示所属一级标签，解决 `ntr/NTR` 等同名标签无法区分的问题。
- 复查媒体库/本地媒体库职责：媒体库仍是全量视频重置入口，本地媒体库仍是路径浏览入口，不改筛选语义、不改扫描或播放逻辑。
- 修复非最大化 debug 窗口下的可视区域溢出：顶部工具条在实际行宽不足时让搜索框弹性收缩，单列视频卡片高度按 16:9 缩略图重新留足空间，列表行动作区在中等宽度下降级为图标按钮。
- 使用 computer-use 复测普通窗口和最大化窗口：顶部工具条、列表行“播放 / 收藏 / 更多”、右侧标签筛选面板、本地媒体库返回入口均可见，未发现遮挡或跑出可视区域。
- 扩展稳定 smoke harness：列表行“播放 / 收藏 / 更多”按钮增加 key 与回调计数断言，本地媒体库 `dense` 列表模式增加文件夹进入/返回验证。
- 右侧标签筛选 smoke 增加结果状态断言：默认专辑 chip 显示当前一级全部示例结果，Child01 chip 会把结果收敛到对应二级标签。
- 列表行播放按钮从 `FilledButton.icon` 改为固定尺寸自定义紫色按钮，避免行内双击识别和按钮内部命中链影响自动化单击验证；视觉尺寸和入口语义保持不变。
- 将本地媒体库返回、鼠标侧键返回、右侧标签筛选展开/收起的 smoke test 方法从截图坐标校准改为稳定 key + harness：测试直接驱动真实 `_LocalLibraryView` 和 `_TagDiscoveryZone`，并断言路径/面板状态。
- 新增 `LibrarySmokeKeys`、`LocalLibrarySmokeHarness`、`TagDiscoverySmokeHarness`，覆盖文件夹进入、返回按钮、鼠标后退侧键、一级标签展开/收起、二级“展开全部/收起”和右侧标签 tab 切换。
- `AppPaths` 增加测试进程内数据目录覆盖入口，服务 widget smoke 的可回滚 profile；debug exe 临时 profile 仍使用 `LOCAL_TAG_PLAYER_DATA_DIR`，真实默认数据目录不变。
- 新增 `LOCAL_TAG_PLAYER_DATA_DIR` 数据目录覆盖，用于临时 profile / 可回滚测试库；不设置时仍使用系统应用支持目录。
- 使用临时 profile 完成最近播放真实鼠标复测：单条删除、全选删除和清空全部都只清理临时库中目标视频的 `last_played_at`。
- 临时 profile 下记录三大入口切换响应：媒体库首次约 213ms，最近播放约 63ms，智能收藏约 59ms，再回媒体库约 51ms；进程均保持响应。
- 热门二级标签区只显示二级标签名，不再显示“所属一级标签”小标签；默认专辑也不会进入热门/全部二级候选列表。
- 一级标签展开卡过滤真实子标签里的“默认专辑”，只保留卡片开头的虚拟默认专辑 chip，避免同一展开卡出现两个默认专辑。
- 本地媒体库文件夹浏览增加返回栈：点击文件夹进入下一级后可用顶部返回按钮回到上一层，鼠标后退侧键也触发同一返回逻辑。
- 最近播放清理增加目标选择测试覆盖：单选删除、全选删除和清空全部都只作用于有播放记录的视频，不影响未播放视频。
- 媒体库、最近播放、智能收藏三大入口改为轻量来源切换：最近播放和智能收藏直接使用内存集合生成结果，媒体库重置时即时清空筛选并重建全量结果，减少入口切换卡顿。
- 最近播放主结果区新增管理工具条：支持单选、全选、删除已选和清空全部；删除语义仅清理 `lastPlayedAt`，不删除视频文件、标签、收藏或播放进度。
- “我的标签库”改为“本地媒体库”：侧栏只管理本地库路径，添加入口复用目录选择，单项移除只更新 root 配置，不再打开标签新增弹窗。
- 本地媒体库路径浏览支持文件夹/视频混合展示：文件夹显示为文件夹项并可进入下一层，已入库视频复用现有卡片/列表行，网格/列表切换继续生效。
- 设置入口从顶部工具条移除并放到左侧功能栏底部；小窗口下使用滚动内容 + 底部固定按钮结构，debug exe 坐标点击确认可进入设置页。
- 最近播放入口从弹窗改为主结果区视图：点击左侧“最近播放”会直接用网格/列表展示最近播放视频，播放时队列也使用该可见列表。
- 左侧“媒体库”入口改为重置入口，点击后清空搜索、标签、分组、排除和收藏筛选，回到全部视频。
- 设置入口补齐到顶部工具条和左侧侧栏，复用已有 `CacheSettingsPage` 展示播放解码设置和缩略图缓存统计。
- “我的标签库”新增标签弹窗支持输入即时过滤已有标签，并在创建/保存失败时用 SnackBar 显示错误。
- 左侧导航继续收敛：删除重复的“播放历史”、低价值的“当前筛选”和“常用标签”，保留“最近播放”并接入最近播放弹窗。
- 目录管理弹窗新增非破坏性移除根目录入口；该操作只更新 root 配置，不删除磁盘文件、不立即清理已索引视频记录。
- “我的标签库”改为可维护快捷标签列表：支持添加已有标签或创建 manual 标签，支持移除快捷项，列表过多时固定高度滚动；移除快捷项不删除真实标签或视频关联。
- 右侧标签数量改为全库稳定计数缓存，点击一级/二级筛选后其它标签数量不会从侧栏消失。
- 顶部工具条修复搜索框在宽屏下占满剩余空间的问题，标签中心、收藏筛选、排序和网格/列表切换在高宽桌面窗口下保持可见。
- 列表行二次修复：限制行内容可读宽度、加宽操作区并放宽行高，列表态播放/收藏/更多按钮在宽屏下可见且不再出现 overflow。
- 列表视图改为真正的密集列表模式：`dense` 结果视图使用 `ListView.builder` 和横向列表行，不再复用卡片网格尺寸。
- 新增列表行专用 UI：左侧缩略图、中部标题/路径/标签、右侧播放/收藏/更多按钮，保持播放入口、收藏和标签编辑回调不变。
- 修复源码乱码清理后暴露的结构缺失：恢复标签发现 helper、右侧标签面板 build、缓存设置页、播放器横向滚动条和缓存统计类，确保主界面可编译可运行。
- 清理 `LibraryPage` / `library_widgets` 触达区域乱码注释和用户可见乱码字符串；触达文件乱码扫描、`flutter analyze`、`flutter build windows --debug`、`flutter test` 均通过。
- 主界面追加点击 smoke 修复：当前筛选条会显示搜索关键字 chip，关键字可通过 chip 的 X 单独清除，避免搜索过滤残留但界面看似“全部视频”。
- 左侧导航补齐“播放历史”和“目录管理”可点击入口；播放历史以只读弹窗展示最近播放条目，目录管理以只读根目录弹窗承载添加目录/重新扫描入口。
- debug exe 复测通过：搜索输入与清除、标签中心打开/返回、播放历史弹窗、目录管理弹窗、卡片更多入口、播放入口与全库队列传递均有可见响应。
- 右侧一级标签列表默认显示 7 个，底部“更多一级标签”改为展开/收起开关。
- 右侧一级标签列表新增“按数量 / 按名称”排序控件；按数量使用当前显示数量排序，按名称使用标签名排序。
- 修复默认专辑和二级标签定位：右侧 folder.child tagId 会反解到 `FilterQuery.childTagId` 的标签名，二级标签 fallback 会把 parentId 反解成一级标签名再匹配视频 childTags。
- 右侧面板滚动列表增加独立 Scrollbar 和内容右侧留白，减少滚动条与一级标签行重合。
- 右侧“标签筛选”补强互斥交互：点击一级折叠行会选择该一级的“默认专辑”并展开，一级之间互斥；当前一级下二级标签互斥，重复点击已选二级会回到默认专辑。
- 所有一级展开卡片新增“默认专辑”虚拟 chip，用当前一级标签过滤表达“该一级下全部视频”，不新增 tag 数据、不改 schema。
- 一级展开标题行改为固定高度整行命中区，“展开全部”保持当前一级本地开关并支持再次点击收起。
- 右侧“标签筛选”面板继续微调一级展开卡片：默认按蓝图展示 9 个二级 chip，“展开全部（总数）⌄”改为可点击轻量文本按钮，并且只影响当前一级标签的本地展开状态。
- “展开全部”点击区域从文字宽度扩大为展开卡片底部整行 32px 高命中区，减少横向点偏时误触下方一级行。
- “更多一级标签”按钮弱化为一级列表底部的浅紫整行文本按钮，高度压到 30px，减少对热门二级标签区的视觉抢占。
- 热门二级标签区按蓝图微调垂直节奏：默认一级列表收回到 5 个，热门 chip 固定 3 列，标题字号略收，底部“更多标签⌄”按钮居中并固定轻量高度。
- 清理右侧标签筛选面板及候选区组件内残留乱码注释/tooltip 说明，避免后续视觉 QA 时被历史编码问题干扰。
- 右侧“标签筛选”面板按蓝图重构视觉：桌面宽度约 440px，增加顶部/左右外边距，使用 20px 圆角、`#E6ECF5` 轻边框和极轻阴影。
- 删除右侧一级区域的“一级标签 40”标题行、绿色竖条和重色强调，一级列表直接使用浅色展开卡片与折叠行。
- 二级标签 chip 改为自定义轻量样式：普通态无 tag 图标，选中态浅紫背景 + check；热门二级标签标题固定为“热门二级标签（可直接选择）”，不再显示数量括号。
- 右侧标签筛选一级列表改为蓝图式手风琴：默认展示更多一级标签，点击折叠一级行展开对应二级标签，避免所有二级标签都被固定到第一个一级标签下。
- 一级展开行新增独立筛选按钮，二级标签 chip 增大命中区域并修复 tooltip 文案，降低右侧面板“点不到”的问题。
- 当前筛选条的“清空全部”按钮移出横向 chips 滚动区域，固定在滚动区外侧，减少点击被滚动容器吞掉的风险。
- 继续按参考图红框微调主界面比例：右侧标签筛选面板改为独立卡片式外观，增加桌面端外边距和固定宽度，视觉上更接近参考图的“工具面板”而不是播放器式贴边栏。
- 顶部搜索框增加最大宽度约束，普通窗口保持弹性，超宽窗口不再横向拉满；顶部工具条左右留白和按钮节奏更接近参考图。
- 右侧标签筛选的分组卡片减少嵌套边框，展开一级标签时用单张组卡承载子标签，降低“列表套列表”的拥挤感。
- expanded 媒体库布局继续按参考图红框修正：顶部工具条现在横跨中间结果区和右侧标签筛选区，右侧标签筛选面板从第二行开始，不再从窗口顶部开始。
- 中间当前筛选条仍限定在视频结果列内，和右侧筛选面板并列，保持“当前筛选 chips + 结果数”和“标签筛选”各自归属清晰。
- 媒体库主界面顶部按参考图选中区域调整：搜索框改为弹性占位，标签中心、收藏筛选、排序和网格/列表切换保持同一行。
- 当前筛选区改为白色工具条，直接展示“当前筛选（AND）”、筛选 chips、清空全部和结果数量；桌面端 chips 横向滚动，避免挤压右侧结果数。
- 本次未修改 SQLite schema、`FilterQuery` / `TagQueryService` 查询语义、播放器 filtered queue 或缩略图/media 队列。

### 构建验证

- 本轮 `dart format`、`flutter test`（16 项）、`flutter analyze`、`flutter build windows --debug` 均通过。
- 本轮 `dart format`、`flutter test`、`flutter analyze`、`flutter build windows --debug` 均通过；debug exe 使用临时 profile 启动 3 秒保持运行并可安全关闭。
- `flutter analyze` 通过。
- `flutter build windows --debug` 通过。
- `flutter test` 通过。
- 本轮 debug exe 真实窗口复测：最近播放可打开弹窗，目录管理可见删除根目录按钮，顶部工具条入口在宽屏下可见，列表模式可切入且列表行播放/收藏/更多按钮可见、无 overflow。Win32 坐标脚本仍未稳定点开列表行“更多”弹窗，需人工鼠标或更稳定桌面自动化补测该命中路径。
- `dart format lib/src/pages/library_page.dart lib/src/widgets/library_widgets.dart` 通过。
- 本轮 debug exe 截图验证右侧一级列表默认 7 个、排序控件可见、按数量排序正确、滚动条与列表内容有留白；OS 鼠标坐标在当前 Windows/DPI 环境仍偏移到应用外，真实点击路径需人工补测。
- 本轮 debug exe 验证二级 chip 真实点击：当前筛选能切到“崩铁 + 克拉拉/停云”，结果数量与视频路径跟随当前二级标签；一级标题折叠与展开全部受当前 Windows DPI 坐标自动化影响，建议人工用真实鼠标再补一轮确认。
- 本轮 debug exe 追加验证右侧面板启动可见、标签页切换和一级折叠行点击；“展开全部”按钮已扩大为整行命中区，但坐标自动化受桌面/DPI 环境影响未稳定截到最终展开状态，需人工补一轮该按钮复测。
- 参考宽度截图确认热门二级标签区已进入右侧面板视口，chip 按 3 列排列，“更多标签⌄”按钮居中。
- debug exe 已启动并验证收藏筛选、排序菜单和结果视图切换可点击；搜索框自动输入在 Windows 自动化截图中没有可靠显示，仍需人工复测搜索输入路径。
- 本轮 debug exe 追加验证右侧标签页切换、右侧标签 chip 点击和筛选 chip 关闭；“清空全部”按钮自动化坐标未稳定触发，需后续人工或无障碍树复查命中区域。

## 2026-07-05

### 媒体库标签交互性能

- `TagQueryService.resultCounts` 改为按标签组分批统计候选数量；每个标签组只扫描一次当前视频集合，并优先使用 `videoTagIdsByPathKey` 与候选 tagId 集合求交集，避免每个候选标签都全库扫描。
- `LibraryPage` 不再在 `build()` 中同步执行筛选结果和 `resultCounts` 重计算；当前视频列表与候选数量缓存到页面 State 中，由筛选条件变化后异步刷新。
- 标签点击、清空筛选、搜索、排序和兼容一级/二级标签切换统一走 revision 保护；连续快速点击时旧的视频结果或候选数量结果不会覆盖最新筛选状态。
- 筛选刷新分阶段更新：先更新当前视频结果和播放器可消费的 filtered queue，再刷新左侧候选数量；刷新期间保留旧数量并显示轻量进度提示。
- 缩略图可见区域预取从 `build()` 的 post-frame 回调移到视频结果刷新完成后触发，避免仅因候选数量变化重复触发预取。

### 构建验证

- `flutter analyze` 通过。
- `flutter build windows --debug` 通过。

## 2026-07-04

### 响应式 UI 与平台 polish

- Chat 7 第一阶段完成：统一应用弹窗的浅色 surface、8px 圆角、边框和标题层级。
- 媒体库侧栏目录操作按钮改为可换行按钮组，compact 筛选 BottomSheet 使用统一背景和顶部圆角。
- 媒体库顶部栏在 compact 下压缩搜索提示、排序控件横向滚动、结果数量分行显示，避免搜索框、按钮组和计数溢出。
- 视频卡片网格根据宽度调整 padding、间距、卡片高度和单列布局；卡片底部操作改为弹性播放按钮 + 固定图标按钮。
- 缓存诊断页 compact 下将 AppBar 操作收进菜单，页面 padding 与媒体库统一，避免小窗口横向挤压。
- Tag Manager 从固定左右栏改为 responsive Flex：expanded 常驻 360px 管理侧栏，medium 收窄到 316px，compact 垂直堆叠列表和详情。
- 播放器 compact 下隐藏常驻右侧队列，改为 AppBar 队列入口打开底部队列面板；队列面板宽度不会超过当前窗口。
- 补充 Chat 7 macOS/Linux 适配 notes：FFmpeg bundled tools、sqlite3 动态库、文件管理器 reveal、窗口尺寸和快捷键差异。

### 项目知识库

- 新增 PROJECT.md：项目背景、技术栈、约定、运行方式。
- 新增 ARCHITECTURE.md：当前模块、核心类、数据流、后续拆分建议。
- 新增 CURRENT_TASK.md：当前状态、已知问题、下一步建议、新 Chat 启动提示词。
- 重写 README.md：作为项目入口，避免继续使用历史乱码内容。

### 播放器与标签

- 标签选择统一改为单选。
- 二级标签支持鼠标滚轮和鼠标拖拽横向滑动。
- 从二级标签筛选进入播放器时，播放器使用当前一级标签完整同层列表。
- 播放器右侧顶部显示当前一级标签下的同级二级标签。
- 播放器右侧二级标签支持点击切换列表。
- 默认专辑排序到二级标签第一个。
- 播放器右侧列表改为当前播放位置附近窗口预读，不再对整条播放列表批量读取媒体信息。
- 播放器右侧列表改为固定高度虚拟列表，列表项缓存缩略图和媒体信息 Future，降低滚动与选中刷新时的异步抖动。
- 播放器右侧列表视觉改为更紧凑的专业播放器侧栏样式，强化当前播放项、选中项和媒体信息层级。
- 播放器现在使用进入页面时的 filtered queue 副本作为播放队列；playlist 为空时兜底到 initialItem，initialItem 不在 playlist 时安全从队列首项开始。
- 播放器右侧队列标题显示当前筛选摘要，覆盖 keyword、一级/二级兼容筛选、分组 include/exclude 和收藏筛选，并保持当前序号显示。
- 播放器右侧二级标签切换只在当前 filtered queue 内切换子集，避免从播放器扩展回全量媒体库队列。
- 播放器快速切换视频时串行处理最新 open 请求，降低旧 open 覆盖新 open、dispose 后继续 setState 和 currentIndex 错位风险。
- 验收补漏：无筛选队列标题改为“当前列表”，右侧序号统一为 `1/1661` 格式，并补强 open worker 对结束瞬间 pending 请求的接续处理。

### 缓存与诊断

- 缩略图使用 FFmpeg 优先，media_kit 截图兜底。
- 媒体信息使用 FFprobe 优先，media_kit 兜底。
- 设置页展示 FFmpeg/FFprobe 路径、缩略图缓存状态、媒体信息缓存状态。
- 缩略图队列改为可见区域优先，后台批量任务单独限流，避免后台补缓存占满解码和磁盘资源。
- 后台批量缩略图默认只使用 FFmpeg；media_kit 截图兜底仅用于可见区域优先任务，降低播放卡顿风险。
- FFmpeg 缩略图输出先写临时文件，成功后再替换缓存文件，避免半截 JPEG 被当作有效缓存。
- FFmpeg/FFprobe 增加更明确的超时错误；FFprobe 只读取必要 stream 字段，减少探测输出和解析开销。
- 缓存诊断页新增后台并发统计，补缓存任务完成后按钮自动恢复，并保存缩略图/媒体信息失败原因。
- FFmpeg/FFprobe 调用收敛到 `DesktopFFmpegBackend` 兼容适配层，`ExternalMediaTools` 继续保留原 Windows bundled tools 查找行为。
- 缓存诊断页新增 FFmpeg/FFprobe 版本、缩略图后台排队上限、媒体信息排队/执行中/本轮完成/本轮失败状态。
- 缩略图 media_kit 兜底写入改为临时文件成功后替换，避免半截 JPEG 成为有效缓存。
- 已存在缩略图缓存读取时校验 JPEG 头尾和文件长度，0 字节或半截缓存文件会被丢弃并重新进入缺失状态。
- 缩略图后台批量任务增加排队上限，降低大库补缓存和播放期资源竞争风险。
- 缓存诊断页新增失败重试、清除失败记录和异常文件列表，失败原因继续保存到现有视频表错误字段。
- 缓存诊断页失败重试和清除失败记录按钮在执行中禁用，避免重复触发同一批任务。
- 播放器右键菜单支持视频信息与诊断检查。
- 播放诊断改为弹窗打开期间持续采样，暂停播放时停止采集，关闭弹窗后释放采样任务。
- 播放诊断新增连续采样次数、最近采样时间和异常原因提示，用于观察播放位置推进、掉帧、缓存与 AV 同步问题。

### 媒体库与 SQLite

- 新增 `LibraryStore` 持久化边界 focused tests，覆盖 tag aliases / hidden / favorite / sortOrder 持久化、manual child tag 与 folder child tag 分离、video upsert/delete 后关联清理。
- `LibraryStore` 拆出 `LibraryTagPersistence` 和 `LibraryVideoPersistence`：标签/别名/视频标签关联写入、视频行映射和视频删除写入进入独立 helper，扫描和 folder/manual 业务语义仍留在 store 协调。
- `deleteVideo` 同步移除内存视频索引和 `video_tags` 关联，避免删除后当前 store 与重载 store 状态不一致。
- 右侧标签筛选面板一级排序去除独立标题，选项改为“数量 / 名称 / 常用”；“常用”使用本次会话一级标签点击次数，不新增 schema。
- 右侧一级标签数量排序改为稳定数量基准，避免点击一级标签后因当前筛选结果数变化导致该标签置顶或其它标签重排。
- “全部二级标签”页签改为从标签库展示二级标签，当前筛选下结果数为 0 的标签也保留展示，避免空面板。
- 右侧一级标签行点击改为只展开/收拢，展开卡内的“默认专辑”和二级标签 chip 负责筛选，减少点击冲突和展开延迟感。
- 媒体库结果区取消筛选切换时的网格 AnimatedSwitcher，改用稳定 RepaintBoundary，降低标签筛选时的画面抖动。
- expanded 布局新增右侧标签筛选面板收纳窄条，可收起/恢复标签总列表且保留当前筛选状态。
- 媒体库筛选结果和候选数量移出 `build()` 同步路径，改为页面级缓存 + revision 分阶段刷新；标签点击先反馈选中态，再刷新视频列表和候选数量。
- `TagQueryService.resultCounts` 按标签组批量统计，每个候选组只扫描一次视频集合，并优先使用规范化 tagId 索引，降低大库标签切换时的候选数量计算成本。
- 当前筛选条新增轻量刷新 spinner，提示视频结果或候选数量正在刷新，但不阻塞网格滚动和点击。
- 媒体库顶栏新增标签管理入口，打开后基于当前筛选结果提供批量打标签范围。
- 新增 `TagManagerPage`：支持查看 tag groups、tags、tag aliases、usage count，并按 `folder` / `manual` / `rule` / `filename` / `import` / `auto` 来源展示使用数量。
- 标签管理第一阶段支持创建 manual tag，编辑 displayName、aliases、hidden、favorite、sortOrder，并可移动 tag 到其它 group。
- 当前筛选结果支持批量添加 manual tag、批量移除 manual tag；批量移除只删除 `video_tags.source = manual` 的关系，不会移除 folder 路径派生关系。
- 删除和合并标签当前保留入口和确认弹窗，会先检查 `video_tags` 引用；folder 来源 tag 不允许第一阶段硬删除。
- 分组 tag 匹配在存在规范化索引时优先按 tagId，避免同名 folder 兼容字段误命中 manual tag。
- 验收补漏：Tag Manager 左侧直接展示 tag groups；批量添加/移除只允许 manual 来源标签，避免误把 folder 来源标签作为普通 manual 操作；创建 manual tag 时阻止覆盖同分组同名的非 manual 标签。
- 媒体库首页新增网页式分组 Tag 筛选侧栏，按现有 `tag_groups` 展示标签，并显示候选结果数。
- 媒体库分组筛选支持包含标签和排除标签，排除项在当前筛选条中显示为 `-标签`。
- 媒体库中心顶部新增当前筛选 chips、结果数 / 总数、清空筛选和“保存筛选”入口；Smart List 持久化留到后续阶段。
- 媒体库首页使用 `LayoutSize` / `LayoutBreakpoints` 接入首轮响应式结构：expanded 常驻侧栏，medium 可折叠，compact 使用 BottomSheet。
- 顶部搜索入口文案扩展为文件名 / 路径 / 标签 / 别名，继续复用现有 TagQueryService 搜索能力。
- 保留常用标签、旧一级标签兼容区和二级标签展示，避免一次性删除旧 UI 能力。
- 验收补漏：旧一级/二级兼容筛选与新分组 tag 筛选会清理等价状态，避免同一条件重复叠加。
- 验收补漏：当前筛选条在窄宽度下自动换成上下两行，降低 compact / medium 小窗口溢出风险。
- 新增 `tag_groups`、`tags`、`tag_aliases`、`video_tags` 规范化 Tag 索引表，为分组 Tag、别名、来源和 locked 字段预留数据库基础。
- 扫描目录时同步 `folder` 来源一级/二级 Tag 到 `video_tags`，保留现有文件夹树生成行为。
- 手动编辑标签时同步 `manual` 来源 Tag 到 `video_tags`，为后续 folder/manual/rule/filename/import/auto 来源拆分打基础。
- 新增 `TagQueryContext` 与 `TagQueryService`，支持按 tagId/tagName/alias 匹配、组合筛选和标签结果计数。
- 标签结果计数改为忽略候选标签所在组，避免同组 OR 候选在当前筛选下计数塌缩。
- 旧库加载时会为缺失 `video_tags` 链接的视频回填 folder 来源索引，不会清空已有 manual 链接。
- 手动编辑标签时只刷新当前 manual 编辑范围，并排除路径派生 folder 标签，避免污染 folder 来源。
- SQLite 补充 tag alias 与 video tag source 查询索引。
- 搜索在文件名、路径、文件夹、一级/二级标签之外，新增匹配当前视频关联标签别名。
- 筛选结果进入播放器时作为当前播放队列传入，不再在二级筛选场景自动扩展为整个一级标签队列。
- SQLite 视频表补充根目录、相对路径、文件大小、修改时间字段。
- 旧数据库打开时自动补齐新增列，无需清空媒体库。
- 新增根目录、标题、收藏、修改时间、加入时间索引。
- 打开数据库时启用 WAL、外键、内存临时表和本地缓存配置。
- 目录扫描改为增量写入：新增、删除、标签变化、文件指纹变化时才更新对应视频记录。
- 收藏、播放时间、媒体信息、标签编辑改为单条写库，不再每次重写全部视频。
- 扫描已有视频时按当前目录结构刷新二级标签，避免旧二级标签残留。
- 媒体库路径比较改为 Windows 大小写不敏感稳定 key，避免同一路径因大小写或尾部分隔符差异重复入库。
- 添加根目录时规范化路径并去重，加载旧 metadata 时同步清理重复根目录和常用标签。
- 扫描时对不可访问根目录、不可读取文件、单个文件 stat 失败做容错跳过，避免整次扫描中断。
- 主界面扫描流程增加并发保护和失败恢复，扫描异常不会让按钮永久停留在扫描中。
- 搜索改为多关键词匹配标题、路径、文件夹、一级标签和二级标签。
- 收藏标签和标签编辑增加 trim 与大小写不敏感去重。

### 架构拆分

- 播放页拆出 `PlayerPlaybackController`，集中维护来源播放队列、当前二级标签、正在播放索引和选中索引；`PlayerPage` 继续负责播放器生命周期、mpv 打开和页面交互。
- 播放诊断弹窗迁移到 `player_diagnostics_dialog.dart`，保留持续采样、暂停停止采样和关闭释放 timer/subscription 的行为。
- `lib/main.dart` 按现有类边界拆分为 `src/models`、`src/services`、`src/pages`、`src/widgets`。
- 当前拆分采用 Dart part 机制，保持行为不变，先降低单文件维护成本。
- 明确下一阶段需要抽出平台与数据接口，再从 part 文件演进为真正独立模块。
- 新增 `src/core/TagRules` 和 `src/core/AppPaths`，先集中标签派生规则、视频扩展名判断和应用数据路径。
- PROJECT.md 新增代码注释规则，要求为规则、平台边界、异步流程添加简短必要注释。
- Architecture Baseline 0.4.3 完成：FFmpeg/FFprobe 路径、可用性、版本和调用通过 `FFmpegBackend` 兼容适配层收敛，诊断页补齐缓存失败操作入口。
### 任务规划

- 新增 ROADMAP.md：记录可采纳的跨平台计划、优先级总表、版本规则和新 Chat 读取规则。
- 新增 docs/chat_tasks/CHAT_1_ARCHITECTURE.md 到 CHAT_5_UI.md：为五个 Chat 提供职责边界、版本号、任务范围和可直接粘贴的新对话提示语。

### 构建验证

- `flutter analyze` 通过。
- `flutter build windows --debug` 通过。






# 2026-07-13

- 修复播放器队列快速滚动时同步放大磁盘与媒体探测负载的问题：快速滚动显示轻量占位，空闲后再加载完整队列项，并收窄列表预建范围。
- 播放期间的媒体详情预取限制为当前视频；4K 长视频播放器采用 128 MiB 输入缓冲、受限 30 秒预读和缓存耗尽暂停策略。
- 保持 filtered queue、标签语义、SQLite schema、缩略图缓存有效性与 FFmpegBackend 边界不变。
# 2026-07-13

- 新增Windows C++播放器桥接骨架和显式假后端开关，验证原生外部纹理、串行命令、Flutter控件叠加及退出释放；默认播放后端与用户设置保持不变。
- 记录真实libmpv/D3D11接入的可重复构建要求，禁止从本机Pub Cache或build临时目录链接生产后端。
- 将现有 media_kit/libmpv 播放链路收口到完整 `PlayerBackend` 适配器，播放器页面仅负责 filtered queue 与 UI，不再直接拥有 Player、VideoController 或原生属性入口。
- 增加可注入后端工厂、纹理/状态/诊断/释放契约，为 Windows C++ 播放后端提供不改页面的可回滚 A/B 接入点；默认播放参数与硬解行为保持不变。
- 真实媒体库 90 秒回归完成 4 轮播放、滚动、seek 和退出，实际硬解保持 `d3d11va-copy`，独立视频帧与音频 PTS 均持续推进。
