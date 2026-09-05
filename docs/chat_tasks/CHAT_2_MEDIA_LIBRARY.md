# Chat 2：标签数据、媒体库与稳定身份

## 所有权

- SQLite tag/video/relation 模型与 migration；
- `FilterQuery` / `TagQueryService`；
- 扫描、root、stable identity、missing/relink 和批量路径替换；
- favorites、play records、progress 的稳定身份绑定。

## 必须保持

- 候选索引与完整查询保持 stable-ID 集合一致：短 Unicode 词按码点判断，别名先解码 JSON。
- 异步候选返回后先验证请求身份，再触碰缓存/诊断；同 revision 索引重建合并，新 revision 等待旧事务收尾。
- 零差量扫描推进 repository epoch 后接续最新输入，旧 Future 晚到不可污染结果；同条件空差量不刷新标签计数。
- FTS 聚合通过事务内 INSERT SELECT 写入，JSON 解码、stable-ID 等价、失败回滚与重试不变。
- 回归证据与分批验收见 `../qa/query_correctness_and_baseline_20260905.md`。

- 同组 OR、跨组 AND、排除 NOT；
- folder 来源可重算，manual/locked 数据保留；
- 一级/二级 folder 标签服从当前 root 父子层级；
- 路径变化不创建第二个用户身份；
- 启动、扫描和播放预检只标记 missing，不自动删除稳定身份或其用户数据；
- 缺失/不可读记录仅可在说明标签、收藏、播放记录、进度和备份影响后手动确认清理；
- 收藏切换写入失败恢复原值并反馈，不能保留未持久化的乐观状态；
- 空库优先从 root 目录建立 folder 标签；零筛选结果保留清空与查看条件入口；
- 全库侧栏统计按数据 revision 复用，普通 rebuild 不重复扫描全部视频；
- 恢复状态在 Windows runner 上保留可重复 surface 截图门禁；Finder 点击不得冒充
  SendInput/UIA，系统目录选择器仍需单独原生证据；
- `file_picker 12` 取消目录选择时保持媒体库与用户数据不变；保存动作由平台 adapter 接收
  真实 bytes，不能用 0-byte 文件模拟旧的“只选路径”合同；
- 扫描器只产出候选，Repository 拥有数据库写入。

## 非目标

不拥有播放器 UI、视觉风格、缓存后端或未经验证的物理文件移动。

历史：`docs/history/chat/CHAT_2_MEDIA_LIBRARY_THROUGH_2026-07-30.md`。
