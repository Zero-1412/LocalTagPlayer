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

    final playerRegular = playerWorkspaceTheme(regular);
    final playerHighContrast = playerWorkspaceTheme(
      regular,
      highContrast: true,
    );
    expect(playerRegular.scaffoldBackgroundColor, playerCanvas);
    expect(playerRegular.colorScheme.surface, playerSurface);
    expect(playerRegular.colorScheme.outline, playerBorder);
    expect(
      playerHighContrast.colorScheme.outline,
      const Color(0xff727b89),
    );
    expect(playerRegular.dialogTheme.surfaceTintColor, Colors.transparent);
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

  test('maintenance switch hover keeps one readable state layer', () {
    final theme = maintenanceWorkspaceTheme(ThemeData(useMaterial3: true));
    final switchTheme = theme.switchTheme;
    const selected = <WidgetState>{WidgetState.selected};
    const selectedHovered = <WidgetState>{
      WidgetState.selected,
      WidgetState.hovered,
    };
    const hovered = <WidgetState>{WidgetState.hovered};

    expect(
      switchTheme.thumbColor?.resolve(selected),
      const Color(0xfff8f7ff),
    );
    expect(
      switchTheme.thumbColor?.resolve(selectedHovered),
      const Color(0xfff8f7ff),
    );
    expect(switchTheme.trackColor?.resolve(selected), appAccentViolet);
    expect(
      switchTheme.trackColor?.resolve(selectedHovered),
      const Color(0xff7b6cff),
    );
    expect(
      switchTheme.trackColor?.resolve(hovered),
      const Color(0xff27364b),
    );
    expect(
      switchTheme.overlayColor?.resolve(hovered),
      Colors.transparent,
    );
    expect(
      switchTheme.trackOutlineColor?.resolve(selectedHovered),
      Colors.transparent,
    );
    expect(switchTheme.trackOutlineWidth?.resolve(selectedHovered), 0);
  });

  test('maintenance dropdown routes keep the dark workspace surface', () {
    final theme = maintenanceWorkspaceTheme(ThemeData.light());

    // DropdownButtonFormField 的路由从 canvasColor 取背景，不能退回亮色基线。
    expect(theme.canvasColor, librarySurface);
    expect(theme.hoverColor, appAccentViolet.withValues(alpha: 0.10));
    expect(theme.focusColor, appAccentViolet.withValues(alpha: 0.16));
    expect(theme.highlightColor, appAccentViolet.withValues(alpha: 0.20));
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
          showBorder: false,
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
    expect(decoration.border, isNotNull);

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('borderless interaction surface keeps normal chrome clean',
      (tester) async {
    await tester.pumpWidget(
      _surfaceHarness(
        mediaQuery: const MediaQueryData(),
        child: AppInteractionSurface(
          semanticLabel: '无描边动作',
          showBorder: false,
          onTap: () {},
          child: const Text('无描边'),
        ),
      ),
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
  });
}
