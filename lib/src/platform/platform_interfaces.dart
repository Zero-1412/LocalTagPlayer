import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/external_media_tools_state.dart';
import '../models/media_details.dart';
import '../models/platform_models.dart';
import '../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

abstract interface class PlayerBackend {
  /** 当前后端的只读播放状态；UI 不得据此取得原生 Player。 */
  PlayerBackendState get state;

  /** 播放位置变化流。 */
  Stream<Duration> get positionChanges;

  /** 播放/暂停状态变化流。 */
  Stream<bool> get playingChanges;

  /** 媒体播放完成事件流。 */
  Stream<bool> get completedChanges;

  /** 原生播放错误流，内容不得包含本地媒体路径。 */
  Stream<String> get errorChanges;

  /** 纹理标识变化通知；原生后端可据此报告纹理挂载与解绑。 */
  ValueListenable<int?> get textureId;

  /** 打开一个媒体路径；filtered queue 的选择仍由页面层负责。 */
  Future<void> openPath(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  Future<void> setVolume(double volume);

  Future<void> playOrPause();

  /** 设置后端专有属性；不存在的属性允许被实现安全忽略。 */
  Future<void> setProperty(String property, String value);

  /** 查询后端诊断属性；不可用时返回统一占位文本。 */
  Future<String> getProperty(String property);

  /** 截取当前视频帧，编码格式由调用方指定。 */
  Future<Uint8List?> screenshot({String format = 'image/jpeg'});

  /** 构建视频纹理表面；具体 Player/纹理控制器不得泄漏给页面。 */
  Widget buildVideoSurface({required Widget controls});

  Future<void> dispose();

  /** 等待后端拥有的 Player、纹理与原生资源全部释放。 */
  Future<void> get released;
}

/**
 * 根据用户硬解设置创建独占播放会话后端。
 *
 * 默认工厂返回 media_kit 适配器；后续 Windows C++ 实现可在组合根切换，
 * PlayerPage 不需要感知具体后端类型。
 */
typedef PlayerBackendFactory = PlayerBackend Function({
  required String hwdec,
  required bool enableHardwareAcceleration,
});

/**
 * PlayerBackend 暴露给 Flutter UI 的不可变状态快照。
 *
 * 仅保留渲染与交互需要的轻量字段，避免未来原生后端高频跨边界传递复杂对象。
 */
class PlayerBackendState {
  const PlayerBackendState({
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
    required this.volume,
    required this.videoTrackCount,
    required this.audioTrackCount,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final double volume;
  final int videoTrackCount;
  final int audioTrackCount;
}

abstract interface class FFmpegBackend {
  Future<ExternalMediaToolsState> locateTools();

  Future<bool> isAvailable();

  Future<String?> version();

  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback,
  });

  Future<MediaDetails?> probe(VideoItem item);
}

/**
 * 媒体信息批处理平台边界。
 *
 * 原生实现只负责读取文件与生成紧凑结果；SQLite 写入仍由 Dart Repository 串行完成，
 * 避免双端数据库连接引入锁与迁移风险。
 */
abstract interface class MediaProbeBackend {
  /** 批量探测同一代请求；实现必须限制并发并保留输入顺序。 */
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  });

  /** 取消指定代的排队与执行中任务，旧结果不得继续写回。 */
  Future<void> cancelGeneration(int generationId);
}

/** 创建独立媒体探测会话后端的组合根工厂。 */
typedef MediaProbeBackendFactory = MediaProbeBackend Function();
