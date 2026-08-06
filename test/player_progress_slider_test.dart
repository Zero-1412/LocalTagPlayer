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
              onCommitted: (value) => committed = value,
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
}
