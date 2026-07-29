import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/platform_models.dart';
import 'package:local_tag_player/src/widgets/library/library_add_tag_dialog.dart';
import 'package:local_tag_player/src/widgets/library/library_confirmation_dialogs.dart';

void main() {
  testWidgets('add tag dialog filters snapshot and returns the chosen label',
      (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              selected = await showLibraryAddTagDialog(
                context,
                tags: const <TagItem>[
                  TagItem(
                    id: 'manual:movie',
                    name: 'movie',
                    displayName: '电影',
                    source: TagSource.manual,
                  ),
                  TagItem(
                    id: 'manual:music',
                    name: 'music',
                    displayName: '音乐',
                    source: TagSource.manual,
                  ),
                ],
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '电');
    await tester.pump();

    expect(find.text('电影'), findsOneWidget);
    expect(find.text('音乐'), findsNothing);
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    expect(selected, '电影');
  });

  testWidgets('remove root confirmation returns intent without deleting data',
      (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              confirmed = await showRemoveLibraryRootConfirmation(
                context,
                root: r'D:\Media',
              );
            },
            child: const Text('移除'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'D:\Media'), findsOneWidget);
    expect(find.textContaining('不会删除本地文件'), findsOneWidget);
    await tester.tap(find.text('解除管理'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
