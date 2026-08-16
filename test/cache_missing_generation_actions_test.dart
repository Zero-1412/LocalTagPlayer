import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:local_tag_player/src/features/settings/presentation/cache_failure_actions.dart';
import 'package:local_tag_player/src/services/media/thumbnail_service.dart';

void main() {
  testWidgets('缓存诊断提供生成缺失缓存入口', (tester) async {
    var generateCalls = 0;
    await tester.pumpWidget(
      cacheDiagnosticsSmokeHarness(
        stats: _stats(missing: 3),
        onGenerateMissing: () => generateCalls++,
      ),
    );

    final button = find.byKey(
      const ValueKey('settings.cache.generateMissing'),
    );
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    expect(generateCalls, 1);
  });

  testWidgets('没有缺失项或未注入命令时不允许启动补全', (tester) async {
    await tester.pumpWidget(
      cacheDiagnosticsSmokeHarness(
        stats: _stats(missing: 0),
        onGenerateMissing: () {},
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('settings.cache.generateMissing')),
    );
    expect(button.onPressed, isNull);
  });
}

CacheStats _stats({required int missing}) => CacheStats(
      total: missing,
      cached: 0,
      missing: missing,
      errors: 0,
      queued: 0,
      pendingBackgroundRequests: 0,
      active: 0,
      activeBackground: 0,
      maxConcurrent: 2,
      maxBackground: 1,
      maxBackgroundQueued: 500,
      paused: false,
      completedThisRun: 0,
      failedThisRun: 0,
      ffmpegCompleted: 0,
      fallbackCompleted: 0,
      averageMs: 0,
      failures: const <CacheFailureDetail>[],
    );
