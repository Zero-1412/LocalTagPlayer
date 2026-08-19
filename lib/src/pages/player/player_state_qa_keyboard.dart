import 'package:flutter/services.dart';

import 'player_input_qa_evidence.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/** Debug-only 观测 Flutter 全局键盘路由；回调返回 false，不参与正式快捷键判定。 */
bool _observePlayerQaGlobalKeyboardEvent(KeyEvent event) {
  final phase = event is KeyRepeatEvent
      ? 'repeat'
      : event is KeyUpEvent
          ? 'up'
          : 'down';
  PlayerInputQaEvidence.playerGlobalKeyboardEventObserved(phase: phase);
  return false;
}

// add/remove 必须复用同一个函数对象，避免页面销毁时留下全局回调。
final KeyEventCallback _playerQaGlobalKeyboardEventHandler =
    _observePlayerQaGlobalKeyboardEvent;

/** 仅在显式 QA 输出可写时挂载全局键盘观测，正式运行不改变输入路由。 */
extension PlayerStateQaKeyboard on PlayerPageState {
  void attachPlayerQaGlobalKeyboardHandler() {
    if (PlayerInputQaEvidence.qaEnabled) {
      HardwareKeyboard.instance.addHandler(_playerQaGlobalKeyboardEventHandler);
    }
  }

  /** 页面销毁时移除同一个顶层回调，避免跨路由残留异步观测。 */
  void detachPlayerQaGlobalKeyboardHandler() {
    HardwareKeyboard.instance
        .removeHandler(_playerQaGlobalKeyboardEventHandler);
  }
}
