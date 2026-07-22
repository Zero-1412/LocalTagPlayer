import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 统一管理 media_kit 原生库的进程内一次初始化。
 *
 * 应用首帧前不能加载 libmpv，否则 Windows 独立 Debug 进程可能在
 * 窗口服务创建前阻塞；首帧后则应主动预热，避免第一次悬停或
 * 正式播放承担整段冷启动。
 */
class MediaKitInitializer {
  MediaKitInitializer({VoidCallback? initialize})
      : _initialize = initialize ?? MediaKit.ensureInitialized;

  /** 真实初始化回调；测试可注入无原生依赖的替身。 */
  final VoidCallback _initialize;

  /** 只在当前 Dart isolate 成功完成初始化后锁存。 */
  var _initialized = false;

  /** 防止 bootstrap 或重建重复登记首帧预热。 */
  var _warmupScheduled = false;

  bool get initialized => _initialized;
  bool get warmupScheduled => _warmupScheduled;

  /**
   * 幂等初始化 media_kit；失败时不锁存，允许后续用户操作重试。
   */
  void ensureInitialized() {
    if (_initialized) {
      return;
    }
    _initialize();
    _initialized = true;
  }

  /**
   * 在 Flutter 已经提交首帧后预热，保证独立启动仍先显示可用窗口。
   *
   * [onReady] 用于记录预热耗时；[onError] 只用于记录失败诊断。
   * 预热失败不应关闭应用，悬停或播放入口仍可通过
   * [ensureInitialized] 再次尝试。
   */
  void scheduleWarmupAfterFirstFrame({
    VoidCallback? onReady,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (_initialized || _warmupScheduled) {
      return;
    }
    _warmupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 让出首帧收尾的当前事件轮，再于用户 650ms 悬停意图前预热。
      Timer.run(() {
        try {
          ensureInitialized();
          onReady?.call();
        } catch (error, stackTrace) {
          onError?.call(error, stackTrace);
        }
      });
    });
  }
}

/** 正式播放器、媒体卡悬停预览和 bootstrap 共享的单例门禁。 */
final MediaKitInitializer defaultMediaKitInitializer = MediaKitInitializer();

/** 首帧后启动默认预热，失败只写入无路径诊断。 */
void scheduleDefaultMediaKitWarmupAfterFirstFrame() {
  final stopwatch = Stopwatch()..start();
  defaultMediaKitInitializer.scheduleWarmupAfterFirstFrame(
    onReady: () {
      debugPrint(
        'MEDIA_KIT_WARMUP status=ready '
        'duration_ms=${stopwatch.elapsedMilliseconds}',
      );
    },
    onError: (error, stackTrace) {
      debugPrint(
        'MEDIA_KIT_WARMUP status=failed '
        'duration_ms=${stopwatch.elapsedMilliseconds} error=$error',
      );
    },
  );
}
