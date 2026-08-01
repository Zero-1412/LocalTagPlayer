# Chat 4：播放器与筛选结果队列

## 所有权

- `PlaybackSession`、PlayerPage 和来源 filtered queue；
- `PlayerService` / `PlayerBackend` 及可选平台扩展；
- 播放切换、seek、全屏、控制显隐、队列和只读诊断；
- Windows native 后端的显式 QA 边界。

## 必须保持

- 右侧队列只来自来源筛选结果，不回退全局媒体库；
- 二级标签切换留在来源语境，返回媒体库保留筛选；
- generation/cancellation 防止旧 open/seek 覆盖新请求；
- 长按方向键期间累计逻辑目标并使用 keyframe 预览，KeyUp 只精确收敛最后目标一次；
- 连续预览使用约 64ms 刷新预算和受限重复步长；反馈合并到同一节奏，禁止每个
  KeyRepeat 都重建完整播放器页面；
- 单次方向键仍精确前进/后退 5 秒，进度条释放后仍只提交最终目标；
- MediaKit Texture 是正式默认，native mpv/child HWND 只显式 QA；
- 用户播放/暂停意图、current index 和进度不因诊断/反馈重建；
- 控制、隐藏进度、设置和队列入口有页面级挂载与真实可达证据。

## 非目标

不把 NVIDIA/NVOFA 实验宣传或自动晋级为生产能力，不优先专业播放器功能。

历史：`docs/history/chat/CHAT_4_PLAYER_THROUGH_2026-07-30.md`。
