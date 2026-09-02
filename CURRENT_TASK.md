# CURRENT_TASK.md

# 2026-09-02 · Flutter 3.47 隔离门禁与 seek 可重放基线

## 当前

- 目标：先完成候选 1 的 Flutter 3.47 Windows 隔离兼容门禁，以及候选 3 的 12 样本可重放 seek 基线。
- 已完成：固定 Flutter `3.47.0` / framework revision `4cf24164269a5ebf0c16a028a00727d0e77bbb05`，在短路径隔离副本中通过全量测试、analyze、Debug/Release 构建与启动 smoke。
- 已完成：12/12 MediaKit Texture Debug seek 通过；manifest 以 codec、分辨率、GOP、文件大小和 Unix 修改时间复核素材身份，摘要不输出路径。
- 已完成：runner 支持全量 preflight、断点续跑、预算一致性复核、case 冷却和最多两次瞬态重试；4K H.264 长 GOP 预算依据 Flutter 3.44/3.47 同机对照校准为 `2000 ms`。

## 最近三项

- 最终 Flutter 3.47 隔离门禁：676 项通过、5 项既有跳过，analyze 0 问题，Debug/Release Windows 构建与启动均通过。
- 最终 12 样本 p95 为 `57–1881 ms`，全部低于各自预算，实际解码均为 `d3d11va-copy`；Release Texture 性能明确标记为未测。
- v0.2.10 正式发布与媒体控制页面拆分已完成，旧 export、ValueKey、callback、当前会话和来源 filtered playback queue 保持不变。

## 阻塞

- Flutter SDK 兼容性没有阻塞；干净 Windows CMake 仍无法下载固定 mpv 资产，原 GitHub release URL 已返回 404，SourceForge 直链也未形成可验证恢复源。本轮只使用 SHA-256 全量匹配的本地依赖种子，不据此修改 CI Flutter pin。
- 不修改 schema、FilterQuery、TagQueryService、PlayerBackend、缓存/媒体详情队列、stable identity、运行时 seek 策略或用户数据。

## 下一步

- 为固定 mpv/ANGLE/media-kit/FFmpeg 依赖建立可长期恢复且摘要不变的受控来源；在干净 runner 复核后，再把 Windows CI 从浮动 `stable` 固定到已通过的 Flutter 3.47 revision。
- 后续性能比较从同一 ignored manifest 和样本身份出发；只有真实同机结果和原因记录才允许调整预算，不把 Debug 后端帧代理升级为 Release/DWM 性能声明。
