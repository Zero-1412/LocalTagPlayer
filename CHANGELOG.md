# CHANGELOG.md

## 2026-07-04

### Responsive UI + Platform Polish

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






