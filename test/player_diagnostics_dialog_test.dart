import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/pages/player/player_diagnostics_dialog.dart';

PlaybackDiagnosticsSnapshot _snapshot() => PlaybackDiagnosticsSnapshot(
      lines: const <String>['匿名诊断行'],
      sampledAt: DateTime(2026, 7, 29, 15),
      wasPlaying: false,
      wasBuffering: false,
      progressMs: 0,
      expectedMs: 0,
      smooth: true,
      avSync: 0,
      mistimedFrames: 0,
      voDelayedFrames: 0,
      voDroppedFrames: 0,
      decoderDroppedFrames: 0,
      totalDroppedFrames: 0,
      cacheDuration: 8,
      cacheBufferingState: 100,
      hwdecCurrent: 'd3d11va-copy',
      videoCodec: 'h264',
      videoWidth: 1920,
      videoHeight: 1080,
      seekLatencyMs: 20,
      detailsQueued: 0,
      frameDurationMs: 16.67,
      videoStalled: false,
      audioStalled: false,
    );

void main() {
  testWidgets('诊断弹窗只消费状态流和采样回调并在卸载后停止响应', (tester) async {
    final playing = StreamController<bool>.broadcast();
    var samples = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackDiagnosticsDialog(
          playingChanges: playing.stream,
          sample: () async {
            samples++;
            return _snapshot();
          },
          title: '播放诊断',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(samples, 1);
    expect(find.byKey(const ValueKey('player.diagnostics.dialog')),
        findsOneWidget);
    expect(find.text('匿名诊断行'), findsOneWidget);

    playing.add(true);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(samples, 2);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    playing.add(true);
    await tester.pump();
    expect(samples, 2);

    await playing.close();
  });
}
