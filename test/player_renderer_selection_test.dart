import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

void main() {
  test('渲染器解析保留跨平台回退与显式 QA 覆盖', () {
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.automatic,
      ),
      PlayerBackendSelection.mediaKit,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
      ),
      PlayerBackendSelection.windowsNativeHwnd,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: false,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
      ),
      PlayerBackendSelection.mediaKit,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: false,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
        environmentOverride: 'windows-native-hwnd',
      ),
      PlayerBackendSelection.mediaKit,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.mediaKit,
        environmentOverride: 'windows-native-stub',
      ),
      PlayerBackendSelection.windowsNativeStub,
    );
  });

  test('旧播放设置默认迁移为自动渲染且新值可往返', () {
    final legacy = PlaybackSettings.fromJson(<String, Object?>{
      'hwdec': 'auto-safe',
    });
    expect(
      legacy.rendererPreference,
      PlayerRendererPreference.automatic,
    );

    final windows = legacy.copyWith(
      rendererPreference: PlayerRendererPreference.windowsLibmpv,
    );
    expect(
      PlaybackSettings.fromJson(windows.toJson()).rendererPreference,
      PlayerRendererPreference.windowsLibmpv,
    );
  });

  testWidgets('Windows 渲染器切换必须确认且保存后可撤销', (tester) async {
    var current = PlaybackSettings.defaults;
    final saved = <PlaybackSettings>[];
    var showRendererSettings = true;
    late StateSetter rebuildPage;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuildPage = setState;
              if (!showRendererSettings) {
                return const Text('设置页已退出');
              }
              return PlaybackRendererDropdown(
                settings: current,
                windowsNativeRendererAvailable: true,
                onChanged: (settings) async {
                  saved.add(settings);
                  setState(() => current = settings);
                },
              );
            },
          ),
        ),
      ),
    );

    Future<void> chooseWindowsRenderer() async {
      await tester.tap(
        find.byType(
          DropdownButtonFormField<PlayerRendererPreference>,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              PlaybackSettings.rendererLabelFor(
                PlayerRendererPreference.windowsLibmpv,
              ),
            )
            .last,
      );
      await tester.pumpAndSettle();
    }

    await chooseWindowsRenderer();
    expect(find.text('切换播放渲染器'), findsOneWidget);
    // 对话框等待期间退出设置 Route 后，取消结果不能再触发已销毁 State 的 setState。
    rebuildPage(() => showRendererSettings = false);
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(saved, isEmpty);
    expect(
      current.rendererPreference,
      PlayerRendererPreference.automatic,
    );

    rebuildPage(() => showRendererSettings = true);
    await tester.pump();
    await chooseWindowsRenderer();
    await tester.tap(find.text('确认切换'));
    await tester.pumpAndSettle();
    expect(
      saved.single.rendererPreference,
      PlayerRendererPreference.windowsLibmpv,
    );
    expect(find.textContaining('原生 D3D11'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    // 模拟用户保存后立即退出设置 Route；Snackbar 仍由上层 ScaffoldMessenger
    // 承载，撤销操作不得再读取已经 dispose 的下拉控件 State。
    rebuildPage(() => showRendererSettings = false);
    await tester.pump();
    expect(find.text('设置页已退出'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(2));
    expect(
      saved.last.rendererPreference,
      PlayerRendererPreference.automatic,
    );
  });
}
