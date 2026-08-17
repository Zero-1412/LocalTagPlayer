import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/src/pages/player/player_dialog_content.dart';
import 'package:local_tag_player/src/pages/player/player_context_menu_items.dart';

void main() {
  testWidgets('player context menu keeps stable actions and player surface',
      (tester) async {
    final infoItemKey = GlobalKey();
    final diagnosticsItemKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              final popupTheme = playerDialogTheme(context).popupMenuTheme;
              showMenu<String>(
                context: context,
                position: const RelativeRect.fromLTRB(20, 20, 20, 20),
                color: popupTheme.color,
                elevation: popupTheme.elevation,
                shape: popupTheme.shape,
                semanticLabel: '播放器上下文菜单',
                items: buildPlayerContextMenuItems(
                  infoItemKey: infoItemKey,
                  diagnosticsItemKey: diagnosticsItemKey,
                ),
              );
            },
            child: const Text('打开播放器菜单'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开播放器菜单'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('player.contextMenu.info')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player.contextMenu.diagnostics')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '视频信息',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '诊断检查',
      ),
      findsOneWidget,
    );
    expect(
      Theme.of(tester.element(find.byType(PopupMenuItem<String>).first))
          .colorScheme
          .brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('视频信息'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player.contextMenu.info')), findsNothing);
  });
}
