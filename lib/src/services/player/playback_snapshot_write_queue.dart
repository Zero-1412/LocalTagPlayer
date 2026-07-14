import 'dart:async';
import 'dart:collection';

import '../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 一次不可变的稳定视频播放快照。 */
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.item,
    required this.position,
    required this.duration,
    required this.completed,
    required this.updatedAt,
  });

  /** 持有稳定 videoId 的内存条目；mutable path 不参与队列键。 */
  final VideoItem item;
  final Duration position;
  final Duration duration;
  final bool completed;
  final DateTime updatedAt;

  String get videoId => item.videoId;
}

/**
 * 按 videoId 合并并串行写入播放快照。
 *
 * 同一视频在上一笔写入期间产生的多次位置更新只保留最新快照；不同视频仍按入队顺序逐笔执行，
 * 避免高频回调并发 upsert 覆盖收藏、标签兼容字段或更新顺序。
 */
class PlaybackSnapshotWriteQueue {
  PlaybackSnapshotWriteQueue({required this.writer});

  /** 实际单条持久化函数，由 LibraryPage 注入当前 store 边界。 */
  final Future<void> Function(PlaybackSnapshot snapshot) writer;

  final LinkedHashMap<String, PlaybackSnapshot> _pending =
      LinkedHashMap<String, PlaybackSnapshot>();
  final List<Completer<void>> _flushWaiters = <Completer<void>>[];
  var _running = false;
  var _disposed = false;
  Object? _lastError;

  int get pendingCount => _pending.length;

  /** 读取并清除最近一次写入错误，供页面提供稳定提示。 */
  Object? takeLastError() {
    final error = _lastError;
    _lastError = null;
    return error;
  }

  /** 合并同一 videoId 的待写状态，并在需要时启动唯一 worker。 */
  void enqueue(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    _pending[snapshot.videoId] = snapshot;
    if (!_running) {
      _running = true;
      scheduleMicrotask(_drain);
    }
  }

  /** 等待当前正在写入和已经合并的快照全部完成。 */
  Future<void> flush() {
    if (!_running && _pending.isEmpty) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _flushWaiters.add(completer);
    return completer.future;
  }

  /** 停止接收新快照，并等待已接受状态安全落库。 */
  Future<void> dispose() async {
    _disposed = true;
    await flush();
  }

  /** 唯一串行 worker；失败会结束对应 flush，但不会阻塞后续快照。 */
  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final entry = _pending.entries.first;
      _pending.remove(entry.key);
      try {
        await writer(entry.value);
      } catch (error) {
        // 记录安全错误信号并继续消费其它 videoId，避免一条失败阻塞整个队列。
        _lastError = error;
      }
    }
    _running = false;
    for (final waiter in _flushWaiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _flushWaiters.clear();
    // worker 结束瞬间可能有新快照入队；再次启动以避免竞态遗留。
    if (_pending.isNotEmpty && !_running) {
      _running = true;
      scheduleMicrotask(_drain);
    }
  }
}
