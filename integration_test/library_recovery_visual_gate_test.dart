import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/features/library/presentation/library_empty_recovery.dart';
import 'package:local_tag_player/src/features/library/presentation/library_startup_state.dart';
import 'package:local_tag_player/src/features/settings/presentation/missing_cleanup_confirmation_dialog.dart';
import 'package:local_tag_player/src/widgets/app_theme_tokens.dart';
import 'package:local_tag_player/src/widgets/library/library_smoke_keys.dart';
import 'package:path/path.dart' as p;

// ignore_for_file: slash_for_doc_comments

/**
 * 在真实 Windows Flutter surface 上截图四条恢复状态并点击生产组件。
 *
 * Finder 点击不是原生 SendInput；外部 Computer Use 不可用时，这组证据只证明真实桌面
 * runner 的挂载、排版与回调，不冒充系统级鼠标或文件选择器验收。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次空库目录入口可见且可点击', (tester) async {
    var folderRequests = 0;
    await tester.pumpWidget(
      _visualApp(
        LibraryEmptyRecovery(
          hasLibrary: false,
          hasActiveFilters: false,
          message: null,
          onAddFolder: () => folderRequests += 1,
          onAddFiles: () {},
          onClearFilters: () {},
          onOpenFilters: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '01-first-library-directory');

    await tester.tap(find.byKey(LibrarySmokeKeys.emptyAddFolder));
    await tester.pump();
    expect(folderRequests, 1);
  });

  testWidgets('筛选零结果提供就地恢复动作', (tester) async {
    var clearRequests = 0;
    await tester.pumpWidget(
      _visualApp(
        LibraryEmptyRecovery(
          hasLibrary: true,
          hasActiveFilters: true,
          message: null,
          onAddFolder: () {},
          onAddFiles: () {},
          onClearFilters: () => clearRequests += 1,
          onOpenFilters: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, '02-empty-filter-recovery');

    await tester.tap(find.byKey(LibrarySmokeKeys.emptyClearFilters));
    await tester.pump();
    expect(clearRequests, 1);
  });

  testWidgets('清理确认取消不会返回授权', (tester) async {
    bool? result;
    await tester.pumpWidget(
      _visualApp(
        Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('qa.openMissingCleanup'),
            onPressed: () async {
              result = await showMissingCleanupConfirmationDialog(context);
            },
            child: const Text('检查并清理'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('qa.openMissingCleanup')));
    await tester.pumpAndSettle();
    await _capture(tester, '03-missing-cleanup-cancel');

    await tester.tap(
      find.byKey(const ValueKey('settings.fileDeletion.cancelCleanup')),
    );
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('清理缺失或不可读记录？'), findsNothing);
  });

  testWidgets('启动失败页可点击重试并进入加载态', (tester) async {
    await tester.pumpWidget(const _StartupRetryHarness());
    await tester.pumpAndSettle();
    await _capture(tester, '04-startup-failure-retry');

    await tester.tap(find.byKey(const ValueKey('library.startup.retry')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('library.startup.loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('library.startup.failed')), findsNothing);
  });
}

/** 使用生产主题固定恢复状态的真实桌面 surface。 */
Widget _visualApp(Widget child) => RepaintBoundary(
      key: const ValueKey('qa.visualSurface'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLocalTagPlayerTheme(),
        home: Scaffold(
          backgroundColor: libraryBackground,
          body: child,
        ),
      ),
    );

/** 把真实 Windows runner 的 Flutter surface 写入调用方指定的 ignored QA 目录。 */
Future<void> _capture(
  WidgetTester tester,
  String name,
) async {
  final output = Platform.environment['LOCAL_TAG_PLAYER_SCREENSHOT_DIR'];
  if (output == null || output.trim().isEmpty) {
    throw StateError('缺少 LOCAL_TAG_PLAYER_SCREENSHOT_DIR');
  }
  final directory = Directory(output)..createSync(recursive: true);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('qa.visualSurface')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    throw StateError('Flutter surface 无法编码为 PNG');
  }
  await File(p.join(directory.path, '$name.png')).writeAsBytes(
    data.buffer.asUint8List(),
  );
}

/** 启动失败页到 loading 的最小生产组件状态转换。 */
class _StartupRetryHarness extends StatefulWidget {
  const _StartupRetryHarness();

  @override
  State<_StartupRetryHarness> createState() => _StartupRetryHarnessState();
}

class _StartupRetryHarnessState extends State<_StartupRetryHarness> {
  var _retrying = false;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('qa.visualSurface'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLocalTagPlayerTheme(),
        home: _retrying
            ? const LibraryStartupLoadingView()
            : LibraryStartupFailureView(
                onRetry: () => setState(() => _retrying = true),
              ),
      ),
    );
  }
}
