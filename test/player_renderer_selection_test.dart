import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/playback_settings.dart';
import 'package:local_tag_player/src/features/settings/presentation/playback_backend_dropdowns.dart';
import 'package:local_tag_player/src/services/player/player_backend_selection.dart';

void main() {
  test('macOS 与 Linux 复用 MediaKit NativePlayer 增强配置', () {
    for (final platform in <String>['macOS', 'Linux']) {
      final selection = resolvePlayerBackendSelection(
        isWindows: false,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
        environmentOverride: 'windows-native-hwnd',
      );
      expect(
        selection,
        PlayerBackendSelection.mediaKitLibmpvEnhanced,
        reason: '$platform 不创建第二个原生后端，只复用 media_kit 的 libmpv 实例',
      );
    }
  });

  test('生产配置复用 MediaKit Texture 且 Windows 保留显式 QA 覆盖', () {
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.automatic,
      ),
      PlayerBackendSelection.mediaKitLibmpvEnhanced,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
      ),
      PlayerBackendSelection.mediaKitLibmpvEnhanced,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: false,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
      ),
      PlayerBackendSelection.mediaKitLibmpvEnhanced,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.mediaKit,
      ),
      PlayerBackendSelection.mediaKit,
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
        environmentOverride: 'windows-native-hwnd',
      ),
      PlayerBackendSelection.windowsNativeHwnd,
      reason: 'child HWND 只保留给显式 NVIDIA/airspace 隔离门禁',
    );
    expect(
      resolvePlayerBackendSelection(
        isWindows: false,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.windowsLibmpv,
        environmentOverride: 'windows-native-hwnd',
      ),
      PlayerBackendSelection.mediaKitLibmpvEnhanced,
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

  test('旧自动设置迁移为 MPV 且两个用户选项可往返', () {
    final legacy = PlaybackSettings.fromJson(<String, Object?>{
      'hwdec': 'auto-safe',
    });
    expect(
      legacy.rendererPreference,
      PlayerRendererPreference.windowsLibmpv,
    );

    final windows = legacy.copyWith(
      rendererPreference: PlayerRendererPreference.windowsLibmpv,
    );
    expect(
      PlaybackSettings.fromJson(windows.toJson()).rendererPreference,
      PlayerRendererPreference.windowsLibmpv,
    );
  });

  testWidgets('MediaKit 兼容与同实例增强切换必须确认且保存后可撤销', (tester) async {
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

    Future<void> chooseRenderer(PlayerRendererPreference value) async {
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
                value,
              ),
            )
            .last,
      );
      await tester.pumpAndSettle();
    }

    await chooseRenderer(PlayerRendererPreference.mediaKit);
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
      PlayerRendererPreference.windowsLibmpv,
    );

    rebuildPage(() => showRendererSettings = true);
    await tester.pump();
    await chooseRenderer(PlayerRendererPreference.mediaKit);
    await tester.tap(find.text('确认切换'));
    await tester.pumpAndSettle();
    expect(
      saved.single.rendererPreference,
      PlayerRendererPreference.mediaKit,
    );
    expect(find.textContaining('跨平台兼容'), findsWidgets);
    expect(find.textContaining('压缩画质增强'), findsOneWidget);
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
      PlayerRendererPreference.windowsLibmpv,
    );

    // 再次保存后不操作撤销，提示应在短暂窗口结束后自行消失。
    rebuildPage(() => showRendererSettings = true);
    await tester.pump();
    await chooseRenderer(PlayerRendererPreference.mediaKit);
    await tester.tap(find.text('确认切换'));
    await tester.pumpAndSettle();
    expect(find.text('渲染器已保存，将在下次进入播放器时生效'), findsOneWidget);
    // 入场动画完成后才开始计时，额外留出退场动画窗口。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('渲染器已保存，将在下次进入播放器时生效'), findsNothing);
  });
}
