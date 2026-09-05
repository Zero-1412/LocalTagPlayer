import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/pages/library/library_page_lifecycle_mixin.dart';
import 'package:local_tag_player/src/pages/library/library_page_state_host.dart';
import '../integration_test/support/checked_search_input.dart';

// ignore_for_file: slash_for_doc_comments

/** 挂载生产 lifecycle 与真实 TextField，只把筛选调度出口记录下来。 */
class _SearchHost extends StatefulWidget {
  const _SearchHost({super.key});
  @override
  State<_SearchHost> createState() => _SearchState();
}

class _SearchState extends LibraryPageStateHost<_SearchHost>
    with LibraryPageLifecycleMixin<_SearchHost> {
  final requested = <String>[];
  @override
  Future<void> load() async {}
  @override
  void mutateFilters(VoidCallback mutation,
      {bool refreshCounts = false, bool collapseTagPanel = false}) {
    mutation();
    requested.add(runtime.searchController.text);
  }

  @override
  Widget build(BuildContext context) => TextField(
      controller: runtime.searchController, focusNode: runtime.searchFocusNode);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('过期测试客户端未投递清空，与已投递后的生产调度缺陷分开', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: _SearchHost(key: ValueKey('first')))));
    await tester.showKeyboard(find.byType(TextField));
    final replacement = TestTextInput()..register();
    try {
      // 模拟输入协议 handler 更换后旧客户端仍发送旧 client ID；不用私有 API。
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: _SearchHost(key: ValueKey('second')))));
      final state = tester.state<_SearchState>(find.byType(_SearchHost));
      state.setSearchTextSilently('old');
      await tester.showKeyboard(find.byType(TextField));
      final records = <Map<String, Object?>>[];
      Object? failure;
      try {
        await enterCheckedSearchText(
            tester, find.byType(TextField), state.runtime.searchController, '',
            onRecord: records.add);
      } catch (error) {
        failure = error;
      }
      expect(failure, isStateError);
      expect(records.single['outcome'], 'input_delivery_not_observed');
      expect(state.runtime.searchController.text, 'old');
      expect(state.requested, isEmpty);
      // 当前客户端通过同一协议投递则成功；该对照不代表旧真实现场已被确诊。
      replacement.enterText('');
      await tester.pump();
      expect(state.runtime.searchController.text, '');
      expect(state.requested, ['']);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      replacement.unregister();
      tester.testTextInput.register();
    }
  });
  for (final latest in ['', 'beta']) {
    testWidgets('同一微任务前两次已投递输入必须调度最新值 ${latest.isEmpty ? 'clear' : latest}',
        (tester) async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: _SearchHost())));
      final state = tester.state<_SearchState>(find.byType(_SearchHost));
      state.setSearchTextSilently('old');
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.enterText('alpha');
      tester.testTextInput.enterText(latest);
      // 先证明输入已到达；后续失败才可以归因生产监听链，而不是测试连接。
      expect(state.runtime.searchController.text, latest);
      await tester.pump();
      expect(state.requested, [latest]);
      expect(state.runtime.lastObservedSearchText, latest);
    });
  }
  testWidgets('静默清空取消旧输入，后续新输入不受旧回调干扰', (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: _SearchHost())));
    final state = tester.state<_SearchState>(find.byType(_SearchHost));
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.enterText('alpha');
    state.setSearchTextSilently('');
    await tester.pump();
    expect(state.requested, isEmpty);
    tester.testTextInput.enterText('alpha');
    state.setSearchTextSilently('');
    tester.testTextInput.enterText('beta');
    await tester.pump();
    expect(state.requested, ['beta']);
  });
}
