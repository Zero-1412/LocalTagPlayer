import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放器画面双击和回车全屏保持页面级可达', () {
    final view =
        File('lib/src/pages/player/player_state_view.dart').readAsStringSync();
    final helpers = File('lib/src/pages/player/player_state_helpers.dart')
        .readAsStringSync();
    final queue = File('lib/src/pages/player/player_queue_sidebar.dart')
        .readAsStringSync();

    expect(
      view,
      matches(RegExp(r'onDoubleTap:\s+togglePlaybackWithFeedback')),
    );
    expect(
      helpers,
      contains('void togglePlaybackWithFeedback()'),
    );
    expect(helpers, contains('playerService.playOrPause()'));

    final enterCase = helpers.indexOf('case LogicalKeyboardKey.enter:');
    final numpadEnterCase =
        helpers.indexOf('case LogicalKeyboardKey.numpadEnter:');
    final enterFullscreen = helpers.indexOf(
      'toggleFullscreenWithFeedback();',
      numpadEnterCase,
    );
    expect(enterCase, greaterThanOrEqualTo(0));
    expect(numpadEnterCase, greaterThan(enterCase));
    expect(enterFullscreen, greaterThan(numpadEnterCase));
    final repeatGuard =
        helpers.indexOf('if (event is KeyRepeatEvent)', numpadEnterCase);
    expect(
      repeatGuard,
      greaterThan(numpadEnterCase),
    );
    expect(
      repeatGuard,
      lessThan(enterFullscreen),
    );
    expect(
      helpers.indexOf('final pressedKey = playerShortcutIdFromEvent(event);'),
      lessThan(enterCase),
    );

    // 队列条目原有双击播放入口属于受保护行为，不能被画面手势替换。
    expect(queue, contains('onDoubleTap: () => onPlay(index)'));
  });

  test('播放器所有短时反馈只挂载一个左上角组件', () {
    final view =
        File('lib/src/pages/player/player_state_view.dart').readAsStringSync();
    final chrome = File('lib/src/pages/player/player_chrome_widgets.dart')
        .readAsStringSync();
    final page =
        File('lib/src/pages/player/player_page.dart').readAsStringSync();

    expect(
      RegExp(r'PlayerShortcutFeedback\(').allMatches(view),
      hasLength(1),
    );
    expect(
      view,
      matches(
        RegExp(
          r'if \(shortcutFeedbackLabel != null\)\s+'
          r'Positioned\.fill\(\s+child: PlayerShortcutFeedback',
        ),
      ),
    );
    expect(view, isNot(contains('PlayerSeekFeedbackWatermark')));
    expect(chrome, isNot(contains('class PlayerSeekFeedbackWatermark')));
    expect(page, isNot(contains('shortcutFeedbackIsSeekWatermark')));
  });
}
