part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/** Windows 原生 FFmpeg 媒体探测方法通道。 */
const _windowsMediaProbeChannel = MethodChannel('local_tag_player/media_probe');

/**
 * Windows C++ `libavformat/libavcodec` 批处理适配器。
 *
 * 跨边界只传不可变请求和紧凑结果；本类不访问 SQLite，也不持有页面回调。
 */
class WindowsNativeMediaProbeBackend implements MediaProbeBackend {
  const WindowsNativeMediaProbeBackend();

  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async {
    if (requests.isEmpty) {
      return const <MediaProbeResult>[];
    }
    final raw = await _windowsMediaProbeChannel.invokeListMethod<Object?>(
          'probeBatch',
          <String, Object?>{
            'generationId': generationId,
            'requests': requests
                .map((request) => <String, Object?>{
                      'videoId': request.videoId,
                      'path': request.path,
                      if (request.knownSize != null)
                        'knownSize': request.knownSize,
                      if (request.knownModifiedAt != null)
                        'knownModifiedAt': request.knownModifiedAt,
                    })
                .toList(growable: false),
          },
        ) ??
        const <Object?>[];
    return raw.whereType<Map<Object?, Object?>>().map((value) {
      final map = value.cast<String, Object?>();
      final cancelled = map['cancelled'] as bool? ?? false;
      final error = map['error'] as String?;
      final width = map['width'] as int?;
      final height = map['height'] as int?;
      return MediaProbeResult(
        videoId: map['videoId'] as String? ?? '',
        cancelled: cancelled,
        error: error,
        details: cancelled || error != null
            ? null
            : MediaDetails(
                videoCodec: map['videoCodec'] as String?,
                audioCodec: map['audioCodec'] as String?,
                width: width,
                height: height,
              ),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> cancelGeneration(int generationId) =>
      _windowsMediaProbeChannel.invokeMethod<void>(
        'cancelGeneration',
        <String, Object?>{'generationId': generationId},
      );
}

/**
 * 非 Windows 与原生桥不可用时的兼容实现。
 *
 * 该实现仍经过现有 `FFmpegBackend`，保证平台路径解析与失败语义不散落到业务层。
 */
class CompatibleMediaProbeBackend implements MediaProbeBackend {
  CompatibleMediaProbeBackend();

  /** 当前兼容实例内已取消的 generation；实例随页面释放，不跨会话累积。 */
  final Set<int> _cancelledGenerations = <int>{};

  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async {
    final results = <MediaProbeResult>[];
    for (final request in requests) {
      if (_cancelledGenerations.contains(generationId)) {
        results.add(MediaProbeResult(
          videoId: request.videoId,
          cancelled: true,
        ));
        continue;
      }
      final item = VideoItem(
        videoId: request.videoId,
        path: request.path,
        title: p.basenameWithoutExtension(request.path),
        folder: p.dirname(request.path),
        tags: const <String>{},
        fileSize: request.knownSize,
        modifiedMs: request.knownModifiedAt,
        addedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      try {
        final details = await ExternalMediaTools.probe(item);
        results.add(MediaProbeResult(
          videoId: request.videoId,
          details: details,
          error: details == null ? 'media probe unavailable' : null,
        ));
      } catch (error) {
        results.add(MediaProbeResult(
          videoId: request.videoId,
          error: error.runtimeType.toString(),
        ));
      }
    }
    return results;
  }

  @override
  Future<void> cancelGeneration(int generationId) async {
    _cancelledGenerations.add(generationId);
  }
}

/** 根据当前平台选择原生批处理或兼容探测实现。 */
MediaProbeBackend createMediaProbeBackend() => Platform.isWindows
    ? const WindowsNativeMediaProbeBackend()
    : CompatibleMediaProbeBackend();
