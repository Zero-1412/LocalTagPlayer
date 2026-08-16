# ADR-003：stable videoId 主身份与 path 可变唯一字段

状态：已接受
日期：2026-08-16
对应路线：Phase 1、Phase 2

## 背景

`VideoItem` 已经携带稳定 `videoId`，但旧 schema 仍使用 `videos.path PRIMARY KEY`，
内存媒体索引和部分命令也把 mutable path 当作身份。这样会让文件重命名、跨目录 relink、
扫描恢复和后台迟到写入面临“同一视频生成第二条记录”或“旧路径写错对象”的风险。

## 决策

### 1. 身份模型

```text
videoId       = 永不因路径变化而改变的数据库主身份
path          = 当前文件位置，必须唯一但允许更新
mediaFingerprint = 文件内容/媒体身份，用于有证据的 relink
isMissing     = 当前路径不可用，记录和用户数据继续保留
```

内存使用 `VideoIdentityIndex`：

- `byVideoId` 是主索引，稳定命令和后台结果首先按它解析；
- `pathKey -> VideoItem` 是同步辅助视图，保留既有查询/页面迁移期兼容性；
- 同一 Map 写入、删除、清空和 path 变化必须同步两侧索引；
- 生产代码不得以 path 重新生成新的 `videoId`，也不得用 path 覆盖另一条 ID 记录。

标签关系同样以 `video_id` 为主查询索引；`video_path` 只保留为当前路径的冗余兼容字段，
路径更新只更新该字段，不改变 `(video_id, tag_id, source)` 关系身份。

### 2. schema 目标

Phase 2 完成后：

```sql
videos(
  video_id TEXT PRIMARY KEY NOT NULL,
  path TEXT NOT NULL UNIQUE,
  ...
)

video_tags(
  video_id TEXT NOT NULL,
  video_path TEXT NOT NULL,
  tag_id TEXT NOT NULL,
  source TEXT NOT NULL,
  PRIMARY KEY(video_id, tag_id, source)
)
```

Windows 额外维护 `path COLLATE NOCASE` 唯一索引，与现有 `TagRules.pathKey` 一致；
其它平台使用当前路径大小写语义。

### 3. migration 策略

- 数据库版本从 1 升至 2，由 `DatabaseProvider` 的 `onUpgrade` 回调触发；启动维护阶段
  仍会检查表形状，以覆盖版本号已更新但进程在换表中断的异常状态；
- 旧表不会尝试直接修改主键，而是在同一 SQLite transaction 中读取、创建 `__phase2`
  新表、写入、删除旧表并 rename 新表；
- 缺失或重复的旧 `video_id` 生成新的 `vid_...`，但同一路径和已有稳定 ID 优先保留；
- 旧 tag relation 先按 stable ID 解析，无法解析时按旧 path 回填；孤立关系使迁移失败，
  不静默丢数据；重复关系合并 locked/时间字段；
- 迁移必须幂等，重启不会重新生成 ID、复制标签或改变用户字段；
- 迁移前失败由 SQLite transaction 回滚，保留旧表形状供恢复或安全停止。

### 4. 命令 API

文件删除、同目录重命名和 missing relink 的生产页面入口通过 stable-ID callback：

```text
deleteVideoById(videoId)
renameVideoPathById(videoId, newPath)
relinkMissingVideoById(videoId, newPath)
deleteVideoAndMergeUserDataById(sourceVideoId, targetVideoId)
```

物理文件动作仍使用命令快照中的当前 path；数据库提交身份只能使用 `videoId`。旧 path
方法暂保留作为迁移兼容端口，但不再由页面命令主路径调用。

## 不变事项

- `FilterQuery` / `TagQueryService` 的 AND/OR/NOT 和关键词语义不变；
- source filtered queue、播放器 current index、PlayerBackend 和缓存队列不改行为；
- tags、favorites、play records、progress 与 stable ID 绑定；
- missing 记录不因 schema 迁移或路径失效立即删除。

## 验证证据

- `test/library_stable_identity_phase2_test.dart` 覆盖双索引、stable tag lookup、旧库换表
  和二次迁移幂等；
- `test/library_store_test.dart` 的旧库启动、同目录改名、fingerprint relink 和 missing
  relink focused 用例覆盖真实 Store 链路；
- `test/architecture_contract_test.dart` 门禁页面命令不回退 path-only Repository API。

## 对抗式审查

```text
schema: changed from path primary key to videoId primary key with path unique migration
FilterQuery / TagQueryService: semantics unchanged; stable relation index added
filtered queue: unchanged
thumbnail/media queue: unchanged
user data: preserved by videoId and migration transaction
protected behaviors: delete/rename/relink semantics preserved and stronger stale-ID guard added
unauthorized feature removal: none
mount and reachability: page commands remain mounted; no route removed
validation: phase2 focused + existing architecture/store focused tests and flutter analyze
```
