import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/library/presentation/library_empty_recovery.dart';
import 'package:local_tag_player/src/widgets/library/library_smoke_keys.dart';

void main() {
  testWidgets('首次使用优先添加目录并保留单文件入口', (tester) async {
    var folders = 0;
    var files = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibraryEmptyRecovery(
          hasLibrary: false,
          hasActiveFilters: false,
          message: null,
          onAddFolder: () => folders += 1,
          onAddFiles: () => files += 1,
          onClearFilters: () {},
          onOpenFilters: () {},
        ),
      ),
    ));

    expect(find.text('添加媒体目录，自动建立标签视图'), findsOneWidget);
    expect(find.textContaining('前两级文件夹生成可筛选标签'), findsOneWidget);
    await tester.tap(find.byKey(LibrarySmokeKeys.emptyAddFolder));
    await tester.tap(find.byKey(LibrarySmokeKeys.emptyAddFiles));
    expect(folders, 1);
    expect(files, 1);
  });

  testWidgets('筛选零结果可清空或打开条件且支持 150% 文字', (tester) async {
    var clears = 0;
    var opens = 0;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Scaffold(
          body: LibraryEmptyRecovery(
            hasLibrary: true,
            hasActiveFilters: true,
            message: null,
            onAddFolder: () {},
            onAddFiles: () {},
            onClearFilters: () => clears += 1,
            onOpenFilters: () => opens += 1,
          ),
        ),
      ),
    ));

    expect(find.text('没有匹配的视频'), findsOneWidget);
    await tester.tap(find.byKey(LibrarySmokeKeys.emptyClearFilters));
    await tester.tap(find.byKey(LibrarySmokeKeys.emptyOpenFilters));
    expect(clears, 1);
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });
}
