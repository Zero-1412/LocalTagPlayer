import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/player_backend_telemetry.dart';
import 'package:local_tag_player/src/services/player/player_backend_telemetry_tracker.dart';

void main() {
  group('PlayerBackendTelemetryTracker', () {
    test('快速切换拒绝过代首帧并记录当前代次解码器', () async {
      final tracker =
          PlayerBackendTelemetryTracker(backendName: 'media-kit-test');
      final events = <PlayerBackendTelemetryEvent>[];
      final subscription = tracker.events.listen(events.add);
      final firstStartedAt = DateTime(2026, 7, 29, 10);
      final firstGeneration = tracker.beginOpen(at: firstStartedAt);
      final secondStartedAt =
          firstStartedAt.add(const Duration(milliseconds: 200));
      final secondGeneration = tracker.beginOpen(at: secondStartedAt);

      expect(
        tracker.recordFirstFrame(
          generation: firstGeneration,
          evidence: 'stale-texture-frame',
          at: firstStartedAt.add(const Duration(milliseconds: 250)),
        ),
        isFalse,
      );
      expect(
        tracker.recordFirstFrame(
          generation: secondGeneration,
          evidence: 'media-kit-texture+mpv-estimated-frame-number',
          at: secondStartedAt.add(const Duration(milliseconds: 75)),
        ),
        isTrue,
      );
      expect(
        tracker.recordDecoder(
          generation: secondGeneration,
          hwdecCurrent: 'd3d11va-copy',
          videoCodec: 'hevc',
          at: secondStartedAt.add(const Duration(milliseconds: 80)),
        ),
        isTrue,
      );

      expect(tracker.snapshot.openGeneration, 2);
      expect(
        tracker.snapshot.firstFrameLatency,
        const Duration(milliseconds: 75),
      );
      expect(
        tracker.snapshot.firstFrameEvidence,
        'media-kit-texture+mpv-estimated-frame-number',
      );
      expect(tracker.snapshot.hwdecCurrent, 'd3d11va-copy');
      expect(tracker.snapshot.videoCodec, 'hevc');
      expect(
        events.map((event) => event.kind),
        containsAllInOrder(<PlayerBackendTelemetryEventKind>[
          PlayerBackendTelemetryEventKind.openStarted,
          PlayerBackendTelemetryEventKind.openStarted,
          PlayerBackendTelemetryEventKind.firstFrame,
          PlayerBackendTelemetryEventKind.decoderResolved,
        ]),
      );

      await subscription.cancel();
      await tracker.close();
    });

    test('同代多个错误只计一次失败并且分类结果不包含路径', () async {
      final tracker =
          PlayerBackendTelemetryTracker(backendName: 'media-kit-test');
      tracker.beginOpen(at: DateTime(2026, 7, 29, 11));
      final firstCode = classifyPlayerBackendError(
        r'Failed to open E:\private\movie.mkv: file not found',
      );
      final secondCode = classifyPlayerBackendError(
        r'Decoder failed for E:\private\movie.mkv',
      );

      tracker.recordError(firstCode);
      tracker.recordError(secondCode);
      tracker.recordError(
        'release_failure',
        affectsCurrentOpen: false,
      );

      expect(firstCode, 'missing_file');
      expect(secondCode, 'decoder_failure');
      expect(firstCode, isNot(contains(r'E:\private')));
      expect(secondCode, isNot(contains(r'E:\private')));
      expect(tracker.snapshot.errorEventCount, 3);
      expect(tracker.snapshot.failedOpenCount, 1);
      expect(tracker.snapshot.openFailureRate, 1);
      expect(tracker.snapshot.lastErrorCode, 'release_failure');

      await tracker.close();
    });

    test('释放快照区分 Player dispose、原生等待和总耗时', () async {
      final tracker =
          PlayerBackendTelemetryTracker(backendName: 'media-kit-test');
      final releaseStartedAt = DateTime(2026, 7, 29, 12);
      tracker.beginRelease(at: releaseStartedAt);
      tracker.completeRelease(
        playerDisposeDuration: const Duration(milliseconds: 40),
        nativeReleaseWait: const Duration(milliseconds: 5200),
        at: releaseStartedAt.add(const Duration(milliseconds: 5260)),
      );

      expect(
        tracker.snapshot.releasePhase,
        PlayerBackendReleasePhase.released,
      );
      expect(
        tracker.snapshot.playerDisposeDuration,
        const Duration(milliseconds: 40),
      );
      expect(
        tracker.snapshot.nativeReleaseWait,
        const Duration(milliseconds: 5200),
      );
      expect(
        tracker.snapshot.totalReleaseDuration,
        const Duration(milliseconds: 5260),
      );

      await tracker.close();
    });
  });
}
