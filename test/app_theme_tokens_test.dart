// ignore_for_file: slash_for_doc_comments

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

/** 使用指定系统媒体偏好承载共享交互表面。 */
Widget _surfaceHarness({
  required MediaQueryData mediaQuery,
  required Widget child,
}) {
  final accessibility = AppAccessibilityData.fromMediaQuery(mediaQuery);
  return MediaQuery(
    data: mediaQuery,
    child: MaterialApp(
      theme: buildLocalTagPlayerTheme(
        highContrast: accessibility.highContrast,
      ),
      home: AppAccessibilityScope(
        data: accessibility,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  test('Apple Phase 0 tokens keep semantic hierarchy stable', () {
    expect(AppRadius.control, lessThan(AppRadius.card));
    expect(AppRadius.card, lessThan(AppRadius.panel));
    expect(AppSpacing.md, 16);
    expect(AppMotion.press, lessThan(AppMotion.hover));

    final regular = buildLocalTagPlayerTheme();
    final highContrast = buildLocalTagPlayerTheme(highContrast: true);

    expect(regular.colorScheme.outline, appBorder);
    expect(highContrast.colorScheme.outline, appBorderHighContrast);
    expect(
      highContrast.dialogTheme.surfaceTintColor,
      Colors.transparent,
    );
  });

  test('system accessibility flags produce deterministic motion policy', () {
    final regular = AppAccessibilityData.fromMediaQuery(
      const MediaQueryData(),
    );
    final reduced = AppAccessibilityData.fromMediaQuery(
      const MediaQueryData(
        disableAnimations: true,
        accessibleNavigation: true,
        highContrast: true,
        textScaler: TextScaler.linear(1.5),
      ),
    );

    expect(regular.reduceMotion, isFalse);
    expect(regular.motionDuration(AppMotion.panel), AppMotion.panel);
    expect(reduced.reduceMotion, isTrue);
    expect(reduced.highContrast, isTrue);
    expect(reduced.motionDuration(AppMotion.panel), Duration.zero);
    expect(reduced.fadeDuration(AppMotion.hover), AppMotion.reducedFade);
    expect(reduced.textScaler.scale(20), 30);
  });

  testWidgets('text scaling remains available to application content',
      (tester) async {
    await tester.pumpWidget(
      _surfaceHarness(
        mediaQuery: const MediaQueryData(
          textScaler: TextScaler.linear(1.5),
        ),
        child: const Text(
          '缩放文字',
          key: ValueKey<String>('scaled-text'),
          style: TextStyle(fontSize: 20),
        ),
      ),
    );

    final text = tester.widget<Text>(
      find.byKey(const ValueKey<String>('scaled-text')),
    );
    final mediaQuery = tester.widget<MediaQuery>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('scaled-text')),
            matching: find.byType(MediaQuery),
          )
          .first,
    );

    expect(text.style?.fontSize, 20);
    expect(mediaQuery.data.textScaler.scale(20), 30);
    expect(tester.getSize(find.text('缩放文字')).height, greaterThan(20));
  });

  testWidgets(
      'reduced motion removes press scale and high contrast keeps solid surface',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _surfaceHarness(
        mediaQuery: const MediaQueryData(
          disableAnimations: true,
          highContrast: true,
        ),
        child: AppInteractionSurface(
          semanticLabel: '测试动作',
          material: AppSurfaceMaterial.translucent,
          onTap: () => taps++,
          child: const Text('执行'),
        ),
      ),
    );

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('执行')));
    await tester.pump();

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(scale.scale, 1);
    expect(scale.duration, Duration.zero);
    expect(decoration.color?.a, 1);

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });
}
