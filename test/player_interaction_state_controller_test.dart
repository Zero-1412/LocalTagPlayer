import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/player/application/player_interaction_state_controller.dart';

void main() {
  testWidgets('控制条只执行最新自动隐藏 Timer', (tester) async {
    var changes = 0;
    final controller = PlayerInteractionStateController<String>(
      initialFeedbackIcon: 'idle',
      onChanged: () => changes++,
    );
    addTearDown(controller.dispose);

    controller.showControls(hideAfter: const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    controller.showControls(hideAfter: const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.controlsVisible, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(controller.controlsVisible, isFalse);
    expect(changes, 1);
  });

  testWidgets('控制条悬停和设置浮层会暂停自动隐藏', (tester) async {
    final controller = PlayerInteractionStateController<String>(
      initialFeedbackIcon: 'idle',
      onChanged: () {},
    );
    addTearDown(controller.dispose);

    controller.setPointerInControlBar(true);
    controller.showControls(hideAfter: const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller.controlsVisible, isTrue);

    controller.setPointerInControlBar(
      false,
      hideAfter: const Duration(milliseconds: 10),
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(controller.controlsVisible, isFalse);

    controller.openSettings();
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller.settingsOpen, isTrue);
    expect(controller.controlsVisible, isTrue);

    controller.closeSettings(hideAfter: const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    expect(controller.settingsOpen, isFalse);
    expect(controller.controlsVisible, isFalse);
  });

  testWidgets('新快捷键反馈覆盖旧 Timer 且保留最新图标和水印类型', (tester) async {
    final controller = PlayerInteractionStateController<String>(
      initialFeedbackIcon: 'idle',
      onChanged: () {},
    );
    addTearDown(controller.dispose);

    controller.showFeedback(
      label: '播放',
      icon: 'play',
      visibleFor: const Duration(milliseconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 10));
    controller.showFeedback(
      label: '前进 5 秒',
      icon: 'forward',
      isSeekWatermark: true,
      visibleFor: const Duration(milliseconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 10));

    expect(controller.feedbackVisible, isTrue);
    expect(controller.feedbackLabel, '前进 5 秒');
    expect(controller.feedbackIcon, 'forward');
    expect(controller.feedbackIsSeekWatermark, isTrue);

    await tester.pump(const Duration(milliseconds: 10));
    expect(controller.feedbackVisible, isFalse);
  });

  testWidgets('dispose 取消两类 Timer 并拒绝后续发布', (tester) async {
    var changes = 0;
    final controller = PlayerInteractionStateController<String>(
      initialFeedbackIcon: 'idle',
      onChanged: () => changes++,
    );
    controller.showControls(hideAfter: const Duration(milliseconds: 10));
    controller.showFeedback(
      label: '播放',
      icon: 'play',
      visibleFor: const Duration(milliseconds: 10),
    );
    final changesBeforeDispose = changes;

    controller.dispose();
    controller.showFeedback(label: '迟到事件', icon: 'late');
    await tester.pump(const Duration(milliseconds: 20));

    expect(changes, changesBeforeDispose);
    expect(controller.feedbackLabel, '播放');
  });
}
