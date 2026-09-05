import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../integration_test/support/checked_search_input.dart';

void main() {
  testWidgets('协议投递并清空输入，诊断不携带搜索文本', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final records = <Map<String, Object?>>[];
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TextField(controller: controller))));
    for (final text in ['private-media-name', '', '']) {
      await enterCheckedSearchText(
          tester, find.byType(TextField), controller, text,
          onRecord: records.add);
      expect(controller.text, text);
    }
    expect(records.map((record) => record['outcome']),
        ['delivered', 'delivered', 'already_matched']);
    expect(records.toString(), isNot(contains('private-media-name')));
  });

  testWidgets('输入被接收后回写旧值立即失败，不冒充查询超时', (tester) async {
    final controller = TextEditingController(text: 'old');
    addTearDown(controller.dispose);
    final records = <Map<String, Object?>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TextField(
                controller: controller,
                onChanged: (_) => controller.text = 'old'))));
    Object? failure;
    try {
      await enterCheckedSearchText(
          tester, find.byType(TextField), controller, '',
          onRecord: records.add);
    } catch (error) {
      failure = error;
    }
    expect(failure, isStateError);
    expect(records.single['outcome'], 'input_delivery_not_observed');
    expect(controller.text, 'old');
  });

  testWidgets('错误目标 controller 在投递前失败', (tester) async {
    final actual = TextEditingController(text: 'old');
    final wrong = TextEditingController();
    addTearDown(actual.dispose);
    addTearDown(wrong.dispose);
    final records = <Map<String, Object?>>[];
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TextField(controller: actual))));
    await expectLater(
        enterCheckedSearchText(tester, find.byType(TextField), wrong, '',
            onRecord: records.add),
        throwsStateError);
    expect(records.single['outcome'], 'target_controller_mismatch');
    expect(actual.text, 'old');
  });
}
