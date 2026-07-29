import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/playback_settings.dart';
import 'package:local_tag_player/src/features/settings/presentation/playback_and_decoding_settings_card.dart';
import 'package:local_tag_player/src/services/player/player_backend_selection.dart';

void main() {
  test('全部平台与历史偏好统一使用 MediaKit Texture', () {
    for (final isWindows in <bool>[false, true]) {
      for (final preference in PlayerRendererPreference.values) {
        expect(
          resolvePlayerBackendSelection(
            isWindows: isWindows,
            hardwareDecodingEnabled: true,
            rendererPreference: preference,
          ),
          PlayerBackendSelection.mediaKit,
        );
      }
    }
  });

  test('Windows 原生后端只允许显式 QA 环境变量进入', () {
    expect(
      resolvePlayerBackendSelection(
        isWindows: true,
        hardwareDecodingEnabled: true,
        rendererPreference: PlayerRendererPreference.mediaKit,
        environmentOverride: 'windows-native-hwnd',
      ),
      PlayerBackendSelection.windowsNativeHwnd,
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
  });

  test('旧渲染器设置全部迁移并保存为 MediaKit', () {
    for (final legacy in <String?>[
      null,
      'automatic',
      'windowsLibmpv',
      'mediaKit',
      'unknown',
    ]) {
      final settings = PlaybackSettings.fromJson(<String, Object?>{
        'hwdec': 'auto-safe',
        if (legacy != null) 'rendererPreference': legacy,
      });
      expect(settings.rendererPreference, PlayerRendererPreference.mediaKit);
      expect(settings.toJson()['rendererPreference'], 'mediaKit');
    }
  });

  testWidgets('播放设置只展示唯一后端且不挂载伪切换入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackAndDecodingSettingsCard(
            settings: PlaybackSettings.defaults,
            onChanged: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('播放后端'), findsOneWidget);
    expect(find.text('MediaKit Texture'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<PlayerRendererPreference>),
      findsNothing,
    );
    expect(find.textContaining('不会自动激活 NVIDIA VSR/HDR'), findsOneWidget);
  });
}
