import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/services/library/video_content_similarity_service.dart';
import 'package:local_tag_player/src/widgets/library/video_similarity_status_widgets.dart';

void main() {
  testWidgets('视觉扫描状态显示阶段、计数和线性进度条', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoSimilarityScanningState(
            phase: VideoVisualScanPhase.buildingCandidates,
            progress: 100,
            total: 200,
            elapsed: Duration(seconds: 65),
            estimatedRemaining: Duration(seconds: 120),
            itemsPerSecond: 4.2,
          ),
        ),
      ),
    );

    expect(find.text('正在建立视觉候选（100/200）'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.text('已用时 1分5秒 · 当前阶段预计还需 2分0秒 · 4.2项/秒'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoSimilarityScanningState(
            phase: VideoVisualScanPhase.comparingCandidates,
            progress: 64,
            total: 128,
          ),
        ),
      ),
    );
    expect(find.text('正在用缓存首帧预筛视觉候选（64/128）'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoSimilarityScanningState(
            phase: VideoVisualScanPhase.extractingSignatures,
            progress: 3,
            total: 8,
            estimatedRemaining: Duration(milliseconds: 250),
            itemsPerSecond: 20,
          ),
        ),
      ),
    );
    expect(find.text('正在完成时序画面复核（3/8）'), findsOneWidget);
    expect(
      find.text('已用时 0秒 · 当前阶段预计还需 1秒 · 20.0项/秒'),
      findsOneWidget,
    );
  });
}
