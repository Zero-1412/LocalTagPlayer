import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:media_kit/media_kit.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 使用仓库生成的固定 HDR/SDR 样本做真实 MediaKit 长播基线。
 *
 * 测试直接构建单条来源队列，不读取用户媒体库；外部脚本负责进程 GPU、功耗和像素
 * 截图，本测试只保存匿名播放器诊断与 DXGI 输出矩阵。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('固定画质样本长播基线', (tester) async {
    final samplePath =
        Platform.environment['LOCAL_TAG_PLAYER_QUALITY_SAMPLE_PATH']?.trim();
    final outputPath = Platform
        .environment['LOCAL_TAG_PLAYER_QUALITY_BASELINE_OUTPUT']
        ?.trim();
    final mode =
        Platform.environment['LOCAL_TAG_PLAYER_QUALITY_BASELINE_MODE']?.trim();
    final durationSeconds = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_QUALITY_BASELINE_SECONDS'] ??
              '',
        ) ??
        300;
    if (samplePath == null ||
        samplePath.isEmpty ||
        !File(samplePath).existsSync()) {
      throw StateError('固定画质样本不存在');
    }
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('缺少匿名基线输出路径');
    }
    if (mode != 'hdr' && mode != 'sdr-dark' && mode != 'sdr-dark-enhanced') {
      throw StateError('基线模式必须是 hdr、sdr-dark 或 sdr-dark-enhanced');
    }
    final baselineMode = mode!;

    MediaKit.ensureInitialized();
    final outputDirectory = Directory(outputPath)..createSync(recursive: true);
    // 外部功耗与截图器必须绑定本测试进程，不能只按同名窗口或启动时间猜测。
    File('${outputDirectory.path}\\process.pid')
        .writeAsStringSync(pid.toString(), flush: true);
    final ffmpegBackend = DesktopFFmpegBackend();
    final thumbnailService = ThumbnailService.forDirectory(
      Directory('${outputDirectory.path}\\thumbnail-cache'),
      ffmpegBackend,
    );
    final item = VideoItem(
      videoId: 'fixed-quality-$baselineMode',
      path: samplePath,
      title: baselineMode == 'hdr' ? '固定 HDR10 样本' : '固定 SDR 暗场样本',
      folder: 'isolated-quality-baseline',
      tags: const <String>{'QA'},
      addedAt: DateTime.utc(2026, 7, 22),
    );
    final disposalCompleter = Completer<void>();
    final playerKey = GlobalKey<PlayerPageState>();
    final settings = PlaybackSettings.defaults.copyWith(
      hdrDynamicToneMappingExperimentEnabled: baselineMode == 'hdr',
      darkSceneEnhancementEnabled: baselineMode == 'sdr-dark-enhanced',
      highQualityStreamCacheEnabled: true,
    );

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          key: playerKey,
          initialItem: item,
          playlist: <VideoItem>[item],
          thumbnailService: thumbnailService,
          playbackSettings: settings,
          onPlaybackSettingsChanged: (_) async {},
          activeTags: const <String>['QA'],
          activeChildTag: null,
          queueTitle: '固定匿名画质基线',
          onDeleteVideo: (_, __) async {},
          onToggleFavorite: (_) async {},
          onRenameFile: (_, __) async {},
          onEditManualTags: (_) async {},
          onRelinkMissing: (_) async => false,
          onPlaybackProgressUpdated: (_, __, ___, ____) async {},
          onMediaDetailsUpdated: (_, __, ___) async {},
          disposalCompleter: disposalCompleter,
          fileSystem: const DesktopFileSystemAdapter(),
          playerBackendFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
          }) =>
              MediaKitPlayerBackend(
            hwdec: hwdec,
            enableHardwareAcceleration: enableHardwareAcceleration,
          ),
          mediaProbeBackendFactory: () =>
              createMediaProbeBackend(ffmpegBackend),
          fullscreenSessionController: PlayerFullscreenSessionController(),
        ),
      ),
    );

    await _waitForSessionState(
      tester,
      playerKey,
      mode: baselineMode,
      timeout: const Duration(seconds: 30),
    );
    final samples = <Map<String, Object?>>[];
    final startedAt = DateTime.now();
    var nextSampleAt = startedAt;
    var midpointCaptured = false;
    while (DateTime.now().difference(startedAt).inSeconds < durationSeconds) {
      await tester.pump(const Duration(milliseconds: 50));
      final now = DateTime.now();
      if (!now.isBefore(nextSampleAt)) {
        final snapshot =
            await playerKey.currentState!.buildDiagnosticsSnapshot();
        samples.add(_diagnosticSample(snapshot, now.difference(startedAt)));
        nextSampleAt = now.add(const Duration(seconds: 5));
      }
      if (!midpointCaptured &&
          now.difference(startedAt).inSeconds >= durationSeconds ~/ 2) {
        midpointCaptured = true;
        await _captureBaselineFrame(
          outputDirectory,
          '$baselineMode-midpoint',
          playerKey.currentState!.playerBackend,
        );
      }
    }

    final finalSnapshot =
        await playerKey.currentState!.buildDiagnosticsSnapshot();
    // 结束帧导出可能短暂占用渲染队列；先暂停可确保采证动作不被误计为长播压力。
    await playerKey.currentState!.playerBackend.pause();
    await tester.pump(const Duration(milliseconds: 250));
    await _captureBaselineFrame(
      outputDirectory,
      '$baselineMode-complete',
      playerKey.currentState!.playerBackend,
    );
    final finalLines = finalSnapshot.lines
        .where(
          (line) => <String>[
            'mpv 实际硬解:',
            '源传递函数:',
            'SDR 源信号:',
            '暗部细节增强设置:',
            '暗部细节增强会话:',
            '暗部增强压力保护:',
            '暗部增强自动回滚原因:',
            'mpv 视频滤镜:',
            'HDR 动态映射会话:',
            'HDR 会话压力保护:',
            'HDR 自动回滚原因:',
            'mpv HDR 映射曲线:',
            'mpv HDR 动态峰值:',
            '活动 GPU:',
            '活动 GPU 判定:',
            '显示输出 ',
          ].any(line.startsWith),
        )
        .toList(growable: false);
    final renderBoundary = playerKey.currentState!.playerBackend;
    final gpuBoundary = renderBoundary is PlayerGpuRenderBoundary
        ? renderBoundary as PlayerGpuRenderBoundary
        : null;
    final matrix = await renderBoundary.queryGpuCapabilities();
    final activeAdapter = await gpuBoundary?.queryActiveGpuAdapter();
    final report = <String, Object?>{
      'schemaVersion': 1,
      'mode': baselineMode,
      'requestedDurationSeconds': durationSeconds,
      'actualDurationSeconds': DateTime.now().difference(startedAt).inSeconds,
      'samples': samples,
      'finalDiagnostics': finalLines,
      'gpuMatrix': matrix.toJson(),
      'activeAdapter': activeAdapter?.toJson(),
    };
    await File('${outputDirectory.path}\\$baselineMode-player-baseline.json')
        .writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );

    expect(samples, isNotEmpty);
    expect(finalSnapshot.videoStalled, isFalse);
    expect(finalSnapshot.audioStalled, isFalse);
    if (baselineMode == 'hdr') {
      final experimentStillActive = finalLines.contains('HDR 动态映射会话: 已通过门槛并启用');
      if (experimentStillActive) {
        expect(finalLines, contains('HDR 自动回滚原因: 无'));
        expect(finalLines, contains('mpv HDR 映射曲线: hable'));
      } else {
        // 真实压力可以合法触发本次会话熔断；此时必须恢复自动映射并留下诊断原因。
        expect(finalLines, contains('HDR 动态映射会话: 未启用 / 门槛未通过'));
        expect(
          finalLines.where((line) => line.startsWith('HDR 自动回滚原因: ')),
          isNot(contains('HDR 自动回滚原因: 无')),
        );
        expect(finalLines, contains('mpv HDR 映射曲线: auto'));
        expect(finalLines, contains('mpv HDR 动态峰值: auto'));
      }
    } else if (baselineMode == 'sdr-dark-enhanced') {
      expect(
        finalLines,
        contains('暗部细节增强会话: 已通过 SDR/1080p/硬解门槛并启用'),
      );
      expect(finalLines, contains('暗部增强自动回滚原因: 无'));
      expect(
        finalLines.where((line) => line.startsWith('mpv 视频滤镜: ')).single,
        contains('eq=gamma=1.06:gamma_weight=0.82:brightness=-0.006'),
      );
    } else {
      expect(finalLines, contains('HDR 动态映射会话: 未启用 / 门槛未通过'));
      expect(finalLines, contains('暗部细节增强设置: 关闭'));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await disposalCompleter.future.timeout(const Duration(seconds: 12));
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/** 等待真实媒体可播放，并确认 HDR/SDR 分支已经完成能力门禁。 */
Future<void> _waitForSessionState(
  WidgetTester tester,
  GlobalKey<PlayerPageState> playerKey, {
  required String mode,
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
    final state = playerKey.currentState;
    if (state == null) continue;
    final snapshot = await state.buildDiagnosticsSnapshot();
    if (mode == 'hdr') {
      final active = snapshot.lines.contains('HDR 动态映射会话: 已通过门槛并启用');
      final safelyRolledBack = snapshot.lines.any(
        (line) => line.startsWith('HDR 自动回滚原因: ') && line != 'HDR 自动回滚原因: 无',
      );
      if (active || safelyRolledBack) return;
    } else if (mode == 'sdr-dark-enhanced') {
      if (snapshot.lines.contains(
        '暗部细节增强会话: 已通过 SDR/1080p/硬解门槛并启用',
      )) {
        return;
      }
    } else if (snapshot.lines.contains('SDR 源信号: 已检测')) {
      return;
    }
  }
  throw StateError('固定 $mode 样本未在时限内进入预期播放状态');
}

/** 把可比较的只读诊断字段保存为匿名时间序列。 */
Map<String, Object?> _diagnosticSample(
  PlaybackDiagnosticsSnapshot snapshot,
  Duration elapsed,
) =>
    <String, Object?>{
      'elapsedSeconds': elapsed.inMilliseconds / 1000,
      'progressMs': snapshot.progressMs,
      'avSync': snapshot.avSync,
      'frameDurationMs': snapshot.frameDurationMs,
      'decoderDroppedFrames': snapshot.decoderDroppedFrames,
      'outputDroppedFrames': snapshot.voDroppedFrames,
      'totalDroppedFrames': snapshot.totalDroppedFrames,
      'cacheDuration': snapshot.cacheDuration,
      'videoStalled': snapshot.videoStalled,
      'audioStalled': snapshot.audioStalled,
      'smooth': snapshot.smooth,
    };

/**
 * 直接从播放器渲染后端导出当前视频帧，并通知外部脚本补充窗口级 UI 证据。
 *
 * 后端帧不依赖桌面最前方窗口，避免覆盖层或其它应用污染固定样本的观感证据。
 */
Future<void> _captureBaselineFrame(
  Directory output,
  String name,
  PlayerBackend backend,
) async {
  final bytes = await backend.screenshot(format: 'image/png');
  if (bytes == null || bytes.isEmpty) {
    throw StateError('播放器后端未能导出固定样本帧：$name');
  }
  await File('${output.path}\\$name-video.png').writeAsBytes(
    bytes,
    flush: true,
  );
  File('${output.path}\\$name.ready').writeAsStringSync('ready');
  await Future<void>.delayed(const Duration(seconds: 1));
}
