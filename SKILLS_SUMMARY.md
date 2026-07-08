# 技能摘要

`.agents/skills` 是本项目的 repo-scoped Codex skill 目录。每个技能目录必须包含标准 `SKILL.md`，并使用 `name` / `description` frontmatter。

- `ltp-task-router`：判断 Level 1/2/3、限定上下文和会话边界。
- `ltp-small-fix`：处理 analyzer/build/缺失符号等小修复，限制读取范围。
- `ltp-log-triage`：排查长日志、build/analyze 输出，不吞入完整日志。
- `ltp-session-handoff`：会话过长、compact 后恢复、任务切换时生成短交接。
- `ltp-tag-filter-data`：处理 TagGroup、TagItem、FilterQuery、TagQueryService、schema 与标签来源语义。
- `ltp-media-library-tag-ui`：处理媒体库标签发现 UI、过滤栏、chips、结果数、响应式布局。
- `ltp-player-filter-queue`：处理播放器消费过滤队列、右侧队列、当前 index、PlaybackSession。
- `ltp-cache-diagnostics`：处理缩略图、媒体详情、FFmpeg/FFprobe、诊断和缓存稳定性。
- `ltp-stable-identity-missing-relink`：处理 videoId、fingerprint、mutable path、missing/relink。
- `ltp-tag-manager-batch-tagging`：处理标签管理器、批量 manual tag 操作、删除/合并边界。
