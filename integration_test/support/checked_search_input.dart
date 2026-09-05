import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 经 Flutter 输入协议投递搜索，并把输入未到达与后续查询超时分开。
 * 只记录长度、身份匹配和连接状态，不记录搜索词或平台通道原始参数；不重试或直接写 controller。
 */
Future<void> enterCheckedSearchText(
  WidgetTester tester,
  Finder field,
  TextEditingController controller,
  String text, {
  required void Function(Map<String, Object?> record) onRecord,
}) async {
  Map<String, Object?> snapshot() {
    final editable =
        find.descendant(of: field, matching: find.byType(EditableText));
    final elements = editable.evaluate().toList();
    final widget =
        elements.length == 1 ? elements.single.widget as EditableText : null;
    final registered = tester.testTextInput.isRegistered;
    return {
      'registered': registered,
      'hasClient': registered ? tester.testTextInput.hasAnyClients : null,
      'editableCount': elements.length,
      'controllerMatches':
          widget == null ? false : identical(widget.controller, controller),
      'focused': widget?.focusNode.hasFocus,
      'inputLength': controller.text.length,
      'targetMatches': controller.text == text,
      // editingState 是框架发给测试输入端的回显，不能单独作为投递成功证据。
      'echoLength':
          (tester.testTextInput.editingState?['text'] as String?)?.length,
    };
  }

  final before = snapshot();
  String outcome = 'action_error';
  try {
    if (before['controllerMatches'] != true) {
      outcome = 'target_controller_mismatch';
      throw StateError(outcome);
    }
    await tester.enterText(field, text);
    if (controller.text != text) {
      outcome = 'input_delivery_not_observed';
      throw StateError(outcome);
    }
    // 同值调用不证明发生了输入变更，也不能作为新查询接续的样本。
    outcome = before['targetMatches'] == true ? 'already_matched' : 'delivered';
  } finally {
    onRecord({
      'targetLength': text.length,
      'before': before,
      'after': snapshot(),
      'outcome': outcome
    });
  }
}
