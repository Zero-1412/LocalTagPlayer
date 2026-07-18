// ignore_for_file: slash_for_doc_comments

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

/** 为媒体库顶部组件提供稳定桌面尺寸，避免测试受默认窄视口影响。 */
void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 240);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('Phase 1 search surface follows real TextField focus',
      (tester) async {
    _useDesktopViewport(tester);
    final controller = TextEditingController(text: '雷神');
    final focusNode = FocusNode(debugLabel: 'phase1-search-focus');
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var clearCount = 0;

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        searchFocusNode: focusNode,
        keyword: controller.text,
        onSearchChanged: (_) {},
        onClearKeyword: () => clearCount += 1,
      ),
    );

    AnimatedContainer searchSurface() => tester.widget<AnimatedContainer>(
          find.byKey(LibrarySmokeKeys.searchSurface),
        );

    final initialDecoration = searchSurface().decoration! as BoxDecoration;
    expect(
        initialDecoration.borderRadius, BorderRadius.circular(AppRadius.card));
    expect((initialDecoration.border! as Border).top.width, 1);

    await tester.tap(find.byKey(LibrarySmokeKeys.searchField));
    await tester.pump(AppMotion.hover);

    final focusedDecoration = searchSurface().decoration! as BoxDecoration;
    expect(focusNode.hasFocus, isTrue);
    expect((focusedDecoration.border! as Border).top.color, appAccentViolet);
    expect((focusedDecoration.border! as Border).top.width, 1.5);

    final clearSearch = find.byTooltip('清除搜索关键词');
    expect(tester.getSize(clearSearch), const Size.square(40));
    await tester.tap(clearSearch);
    expect(clearCount, 1);
  });

  testWidgets('Phase 1 filter state keeps context and accessible actions',
      (tester) async {
    _useDesktopViewport(tester);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var clearCount = 0;

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        videoCount: 171,
        selectedTags: const <String>['原神', '雷神'],
        onSearchChanged: (_) {},
        onClearAll: () => clearCount += 1,
      ),
    );

    expect(
      find.bySemanticsLabel(RegExp(r'当前筛选状态.*171 个视频')),
      findsOneWidget,
    );
    final chips = find.byType(InputChip);
    expect(chips, findsNWidgets(2));
    final firstChip = tester.widget<InputChip>(chips.first);
    expect(
      (firstChip.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppRadius.control),
    );
    expect(firstChip.deleteButtonTooltipMessage, '移除该筛选');

    final clearAll = find.byTooltip('清空全部筛选');
    expect(tester.getSize(clearAll), const Size.square(40));
    await tester.tap(clearAll);
    expect(clearCount, 1);
  });

  testWidgets('Phase 1 status exposes all-library context and reduced motion',
      (tester) async {
    _useDesktopViewport(tester);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const accessibility = AppAccessibilityData(
      disableAnimations: true,
      accessibleNavigation: false,
      highContrast: true,
      textScaler: TextScaler.noScaling,
    );

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        videoCount: 11163,
        accessibility: accessibility,
        onSearchChanged: (_) {},
      ),
    );

    expect(find.text('全部视频'), findsOneWidget);
    final searchSurface = tester.widget<AnimatedContainer>(
      find.byKey(LibrarySmokeKeys.searchSurface),
    );
    expect(searchSurface.duration, AppMotion.reducedFade);
    final decoration = searchSurface.decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, appAccentViolet);
    expect((decoration.border! as Border).top.width, 1.5);
  });

  testWidgets('Phase 1 search and filter state remain usable at 150% text',
      (tester) async {
    _useDesktopViewport(tester);
    final controller = TextEditingController(text: '雷神');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: referenceTopBarSearchSmokeHarness(
          controller: controller,
          keyword: controller.text,
          videoCount: 171,
          selectedTags: const <String>['原神', '雷神'],
          onSearchChanged: (_) {},
          onClearAll: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(LibrarySmokeKeys.searchField), findsOneWidget);
    expect(find.byTooltip('清空全部筛选'), findsOneWidget);
    expect(find.text('171 个视频'), findsOneWidget);
  });

  testWidgets('150% desktop keeps the complete five-digit result count',
      (tester) async {
    tester.view.physicalSize = const Size(980, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const accessibility = AppAccessibilityData(
      disableAnimations: false,
      accessibleNavigation: false,
      highContrast: false,
      textScaler: TextScaler.linear(1.5),
    );

    await tester.pumpWidget(
      referenceTopBarSearchSmokeHarness(
        controller: controller,
        videoCount: 11163,
        accessibility: accessibility,
        onSearchChanged: (_) {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('11163 个视频'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(LibrarySmokeKeys.filterStatusArea)).width,
      198,
    );
  });
}
