# CHANGELOG.md

本文件只保存当前发布候选和版本索引。完整历史位于
`docs/history/changelog/`，不要把旧条目复制回根文件。

## Unreleased

- `file_picker` 升至 12.2.0，并将目录、多文件、单文件和保存入口迁移到新的静态/联邦 API；保存合同改为由平台适配器直接接收真实 bytes，取消时不创建 0-byte 文件。
- `file_picker 12` 新增固定 Flutter 3.47 revision 的独立三平台探针门禁；在该探针先通过后，`package_info_plus` 才从新基线单独升至 10.2.1，全程未使用 dependency override。
- 新增单依赖 Flutter 3.47 隔离门禁：`desktop_drop` 0.8.4 全项通过并升级；早期 `package_info_plus` 10.2.1 在 `file_picker` 11.0.3 基线上因 `win32` 冲突被正确阻断，未使用 override。
- 新增四条媒体库恢复状态的 Windows Flutter surface 截图门禁；启动加载/失败页统一为媒体库深色画布，清理确认内容由设置页与门禁复用同一生产组件。
- 11,000 项侧栏统计回归扩展为 120 次普通 rebuild/resize 模拟，同一 revision 仍只遍历一次。
- 缺失或暂时不可读的视频不再因启动、扫描或点击播放被自动移除；稳定身份、标签、收藏、播放记录和进度默认保留，可在恢复路径后重新关联。
- 无效记录清理改为设置页中的显式维护动作，并在执行前说明数据库记录、用户数据与备份快照的影响；该动作不删除磁盘文件。
- 媒体库启动失败不再永久显示加载环，改为不修改媒体文件的可重试错误页；收藏保存失败会回滚并提示。
- 首次使用优先引导选择媒体目录并说明 folder 标签来源；筛选无结果时可直接清空或查看筛选条件。
- 侧栏收藏/missing 统计按媒体库 revision 复用，11,000 项基准只构建一次；最近播放与收藏列表只在当前来源需要时生成。
- 在 Flutter 3.47 基线上定向更新 `file_picker` 11.0.2 → 11.0.3 与 `sqflite_common_ffi` 2.4.2 → 2.4.2+1；主版本升级继续等待独立兼容门禁。
- 新增 Flutter 3.47 Windows 隔离兼容门禁：在排除用户未跟踪文件的短路径副本中，固定 SDK revision，验证全量测试、analyze、Debug/Release 构建和启动，并以正式 MediaKit Texture 运行真实 seek 矩阵。
- 新增 12 样本 seek 可重放基线：运行前复核 codec、分辨率、GOP 与文件身份，摘要不输出本机媒体路径；矩阵支持 preflight、断点续跑、冷却及有限瞬态重试。
- 本轮只增强 QA/构建证据，不改变播放器默认后端、来源 filtered playback queue、seek 运行时策略、schema 或用户数据。

## 0.2.10

- 播放器媒体控制面板继续保留音轨、字幕、音画同步和章节入口，并按当前后端能力显示逐帧、A-B loop 与外挂字幕操作。
- 播放器精确控制与进度定位继续沿用当前会话边界；操作只作用于当前媒体，不重建来源 filtered playback queue，也不写入媒体库。
- 播放器稳定性诊断补充输入链、Texture 呈现和资源释放的分层证据，失败状态保持可见，不把自动化缺证写成通过。
- 版本治理与发布说明收敛为可审查的当前索引，完整历史保留在 dated history。

详细用户发布说明见 `docs/RELEASE_NOTES_0.2.10.md`。

## 已发布版本

- 0.2.10+12：当前正式版本，详细发布说明见 `docs/RELEASE_NOTES_0.2.10.md`。
- 0.2.9+11：详细发布说明见 `docs/RELEASE_NOTES_0.2.9.md`。
- 0.2.8+10：详细发布说明见 `docs/RELEASE_NOTES_0.2.8.md`。
- 更早版本和逐项变更见 `docs/history/changelog/`。
