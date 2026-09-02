# Flutter 3.47 Windows 隔离兼容门禁（2026-09-02）

## 结论

候选 1 的 SDK 兼容性通过，候选 3 的本机 seek baseline 可重放。验证使用 Flutter
`3.47.0`、framework revision `4cf24164269a5ebf0c16a028a00727d0e77bbb05`、engine
revision `5f77625673248ee5846fbcaf5d3e1a3878386fd7` 和 Dart `3.13.0`。

门禁在短路径隔离副本运行，排除用户未跟踪文件；本机媒体路径只存在 ignored manifest，
preflight 与结果摘要均不输出路径。隔离副本的最终机器可读证据位于 ignored 目录
`.local/q/f347b/compatibility-summary.json` 与
`.local/q/f347b/08-seek-matrix-debug/summary.json`。

## 最终结果

- `flutter test`：676 通过，5 项按既有条件跳过；
- `flutter analyze`：0 问题；
- Windows Debug：构建通过，隐藏启动 10 秒存活且响应；
- Windows Release：构建通过，隐藏启动 10 秒存活且响应；
- MediaKit Texture Debug seek：12/12 通过，p95 `57–1881 ms`，全部为实际
  `d3d11va-copy`；
- Release Texture 性能：未测，摘要明确为 `not-measured`。

## 失败与校准证据

第一次干净隔离构建在下载固定 mpv 归档时收到 404；第二次使用已验证本地种子后，长隔离
路径触发 MSBuild 260 字符限制。门禁因此增加工作区最大 55 字符保护，并只接受七个固定
SHA-256 全部匹配的依赖种子。

旧 `1800 ms` 建议预算使 4K H.264 长 GOP 在 Flutter 3.47 两次失败，p95 均为
`1861 ms`。独立干净 Flutter 3.44 对照为 `1880 ms`，排除了 3.47 SDK 回归；本机预算
据此显式校准为 `2000 ms`，最终 3.47 门禁为 `1881 ms`。该调整只属于本机回归 baseline，
没有修改播放器运行时 seek、最终帧等待、预览节流或 filtered queue。

矩阵中一次 1080p HEVC short-GOP 会话遇到 Flutter 临时 listener 释放竞态，完整退出后使用
同一 manifest 断点续跑通过。runner 因而要求先做 12-case 全量 preflight，并支持按 case
冷却、最多两次瞬态重试；每次尝试保留独立日志，只有成功日志可在
case/backend/budget 一致时由后续 `-Resume` 复用。

## CI 边界

本轮证明“指定 Flutter 3.47 revision + 摘要匹配的依赖种子”与当前 Windows 工程兼容，
没有证明新 CI runner 能从网络恢复固定 native 依赖。固定 mpv GitHub 资产已返回 404，
SourceForge 直链也未形成可验证恢复源；因此没有修改 CI Flutter pin。下一步应先建立可长期
恢复、许可证齐全且 SHA-256 不变的受控依赖源，再在完全干净的 runner 重放同一门禁。

## 受保护边界

本任务未修改 schema、migration、`FilterQuery`、`TagQueryService`、`PlayerBackend`、
MediaKit 默认后端、thumbnail/media queue、stable identity、来源 filtered playback queue、
用户数据或媒体文件。门禁只复制当前内容到 ignored QA 目录，不在主工作树执行 pub/build。
