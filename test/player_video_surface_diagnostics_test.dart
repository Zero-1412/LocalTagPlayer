import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/player_video_surface_diagnostics.dart';
import 'package:local_tag_player/src/services/player/player_video_surface_metrics.dart';

void main() {
  test('Texture 物理目标小于原生像素时识别为 Flutter 合成缩小', () {
    final snapshot = PlayerVideoSurfaceDiagnostics(
      supported: true,
      textureWidthPx: 1920,
      textureHeightPx: 1080,
      widgetLogicalWidth: 988,
      widgetLogicalHeight: 556,
      devicePixelRatio: 1,
      widgetPhysicalWidthPx: 988,
      widgetPhysicalHeightPx: 556,
      fittedVideoPhysicalWidthPx: 988,
      fittedVideoPhysicalHeightPx: 555.75,
      horizontalScale: 988 / 1920,
      verticalScale: 555.75 / 1080,
      fit: 'contain',
      filterQuality: 'low',
      sampledAt: DateTime.utc(2026, 7, 30),
    );

    expect(snapshot.isDownscaling, isTrue);
    expect(snapshot.toJson(), containsPair('filterQuality', 'low'));
    expect(snapshot.toJson(), containsPair('isDownscaling', true));
  });

  test('DPR 后物理目标不小于 Texture 时不误报缩小', () {
    final snapshot = PlayerVideoSurfaceDiagnostics(
      supported: true,
      textureWidthPx: 1920,
      textureHeightPx: 1080,
      widgetLogicalWidth: 1280,
      widgetLogicalHeight: 720,
      devicePixelRatio: 1.5,
      widgetPhysicalWidthPx: 1920,
      widgetPhysicalHeightPx: 1080,
      fittedVideoPhysicalWidthPx: 1920,
      fittedVideoPhysicalHeightPx: 1080,
      horizontalScale: 1,
      verticalScale: 1,
      fit: 'contain',
      filterQuality: 'medium',
      sampledAt: DateTime.utc(2026, 7, 30),
    );

    expect(snapshot.isDownscaling, isFalse);
  });

  test('尺寸汇总器按 BoxFit 与 DPR 计算真实物理目标', () {
    final tracker = PlayerVideoSurfaceMetricsTracker(
      filterQuality: FilterQuality.medium,
    );
    tracker.recordTextureSize(const Size(1920, 1080));
    tracker.recordWidgetSurfaceMetrics(
      const Size(1000, 700),
      1.25,
      BoxFit.contain,
      null,
    );

    final snapshot = tracker.snapshot;
    expect(snapshot.widgetPhysicalWidthPx, 1250);
    expect(snapshot.widgetPhysicalHeightPx, 875);
    expect(snapshot.fittedVideoPhysicalWidthPx, 1250);
    expect(snapshot.fittedVideoPhysicalHeightPx, closeTo(703.125, 0.001));
    expect(snapshot.horizontalScale, closeTo(0.651041, 0.000001));
    expect(snapshot.verticalScale, closeTo(0.651041, 0.000001));
    expect(snapshot.filterQuality, 'medium');
    expect(snapshot.isDownscaling, isTrue);
  });

  testWidgets('布局观察器在帧末采集 Widget 逻辑尺寸与 DPR', (tester) async {
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final tracker = PlayerVideoSurfaceMetricsTracker(
      filterQuality: FilterQuality.low,
    )..recordTextureSize(const Size(1920, 1080));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 600,
            height: 400,
            child: PlayerVideoSurfaceMetricsObserver(
              fit: BoxFit.contain,
              aspectRatio: null,
              onMetricsChanged: tracker.recordWidgetSurfaceMetrics,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tracker.snapshot.widgetLogicalWidth, 600);
    expect(tracker.snapshot.widgetLogicalHeight, 400);
    expect(tracker.snapshot.devicePixelRatio, 1.5);
    expect(tracker.snapshot.fittedVideoPhysicalWidthPx, 900);
    expect(tracker.snapshot.fittedVideoPhysicalHeightPx, 506.25);
  });
}
