import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/pages/player/player_progress_slider.dart';

void main() {
  testWidgets('进度条点击在后端回写前保持目标位置', (tester) async {
    double? committed;

    Widget buildSlider(double value) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 48,
            child: PlayerProgressSlider(
              sliderKey: const ValueKey('progress.test'),
              value: value,
              max: 1000,
              previewIdentity: 'video-1',
              loadPreview: (_) async => null,
              onCommitted: (value) async => committed = value,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildSlider(0));
    final sliderFinder = find.byKey(const ValueKey('progress.test'));
    final sliderRect = tester.getRect(sliderFinder);
    await tester.tapAt(
      Offset(sliderRect.left + sliderRect.width * 0.75, sliderRect.center.dy),
    );
    await tester.pump();

    expect(committed, isNotNull);
    final committedValue = committed!;
    final optimisticValue = tester.widget<Slider>(sliderFinder).value;
    expect(optimisticValue, closeTo(committedValue, 0.001));

    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<Slider>(sliderFinder).value, optimisticValue);

    await tester.pumpWidget(buildSlider(committedValue));
    await tester.pump();
    expect(
      tester.widget<Slider>(sliderFinder).value,
      closeTo(committedValue, 0.001),
    );
  });

  testWidgets('快速连续点击时第一次回写不能清掉第二次目标', (tester) async {
    final committed = <double>[];
    final commitCompleted = Completer<void>();

    Widget buildSlider(double value) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 48,
            child: PlayerProgressSlider(
              sliderKey: const ValueKey('progress.rapid'),
              value: value,
              max: 1000,
              previewIdentity: 'video-1',
              loadPreview: (_) async => null,
              onCommitted: (value) async {
                committed.add(value);
                await commitCompleted.future;
              },
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildSlider(0));
    final sliderFinder = find.byKey(const ValueKey('progress.rapid'));
    final sliderRect = tester.getRect(sliderFinder);
    await tester.tapAt(
      Offset(sliderRect.left + sliderRect.width * 0.50, sliderRect.center.dy),
    );
    await tester.pump();
    await tester.tapAt(
      Offset(sliderRect.left + sliderRect.width * 0.75, sliderRect.center.dy),
    );
    await tester.pump();

    expect(committed, hasLength(2));
    final firstTarget = committed[0];
    final secondTarget = committed[1];

    commitCompleted.complete();
    await tester.pump();

    // 模拟后端先回写第一个点击；第二个目标仍在播放器协调器中等待提交。
    await tester.pumpWidget(buildSlider(firstTarget));
    await tester.pump();

    expect(
      tester.widget<Slider>(sliderFinder).value,
      closeTo(secondTarget, 0.001),
    );
  });
}
