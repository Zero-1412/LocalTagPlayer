# PROJECT.md

## 产品

Local Tag Player 是面向大型本地视频库的 Tag 驱动发现播放器。典型媒体库约
11,000 个视频、8 TB；目标是让用户通过标签、搜索和当前筛选队列快速发现并连续播放，
而不是替代 PotPlayer、VLC 或专业视频工作站。

## 核心用户流程

```text
添加本地目录
-> 递归扫描视频
-> 从 root 第一/第二层派生 folder 标签
-> 用户维护 manual 标签、别名和收藏
-> 分组标签与关键词筛选
-> 当前结果成为播放队列
-> Tag Manager 修正数据
-> 缓存与诊断维持缩略图和媒体信息稳定
```

核心查询语义：

- 同组标签 OR、不同组 AND、排除标签 NOT；
- 关键词匹配文件名、路径、标签名和别名；
- 一级/二级 folder 标签遵守当前媒体 root 的真实父子层级；
- folder 标签可重算，manual 标签和其它用户维护数据必须保留；
- 播放器消费来源页面传入的 filtered queue。

稳定身份方向：

```text
videoId = 数据库稳定身份
fingerprint = 文件/媒体身份
path = 当前可变位置
missing = 路径失效但记录保留
```

## 技术栈

- Flutter / Dart 桌面应用；
- SQLite 与 `sqflite_common_ffi`；
- `media_kit` / `media_kit_video`；
- FFmpeg / FFprobe；
- Windows 原生 C++ 播放边界；
- Windows Rust 媒体库扫描边界。

当前产品和性能基线以 Windows 为主；macOS/Linux 通过平台 adapter 和 CI 验证。
Windows 路径、原生库和系统命令不能泄漏到平台无关业务层。

## 源码运行

```powershell
flutter pub get
flutter run -d windows
```

## 验证

```powershell
flutter test
flutter analyze
flutter build windows --debug
```

## 文档入口

- `AGENTS.md`：所有任务都适用的长期规则；
- `CURRENT_TASK.md`：当前任务、最近三项、稳定基线、阻塞和下一步；
- `ARCHITECTURE.md`：当前模块/数据边界和基线；
- `ROADMAP.md`：当前优先级和未来里程碑；
- `docs/chat_tasks/`：领域阶段合同与历史；
- `docs/qa/`：可重复门禁与 dated 证据；
- `CHANGELOG.md`：版本和历史行为变更。

Agent 执行流程、上下文 Level、注释、真实点击、Git 和安全规则只以 `AGENTS.md`
为准，不在本文件重复。
