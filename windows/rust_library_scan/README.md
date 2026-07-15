# Rust LibraryScanBackend

该 sidecar 只读取媒体库 root、文件 stat 与首尾 fingerprint 样本，不连接或写入 SQLite。

扫描先收集视频候选，再对已知总量执行 stat/fingerprint。stdout 保持 `LTPS` 二进制快照；stderr 只输出 `LTP_SCAN_PROGRESS|阶段|已处理|总数`，不包含路径、标题或标签。Dart 可传入暂停标记文件，sidecar 在安全文件边界等待，删除标记后从原候选位置继续。

构建系统检测到 `cargo` 时生成 `ltp_rust_library_scan.exe` 并随 Windows 应用安装；工具链不存在时 Windows 构建继续使用 Dart `LibraryScanBackend`。运行时 Rust 进程缺失、启动失败或协议异常也会回退 Dart，Application 层仍负责 stable identity、relink 校验与单事务写库。

协议仅传递路径和文件元数据，不传 manual 标签、收藏、播放记录或媒体详情。
