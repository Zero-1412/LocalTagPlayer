import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/core/playback_settings.dart';
import 'package:local_tag_player/src/models/player_gpu_capabilities.dart';
import 'package:local_tag_player/src/pages/library/library_page.dart';
import 'package:local_tag_player/src/platform/platform_interfaces.dart';
import 'package:local_tag_player/src/services/player/player_smooth_motion.dart';

// ignore_for_file: slash_for_doc_comments

/** 记录显示同步属性顺序的最小运行时边界，不依赖 MediaKit 或 Windows runner。 */
class _SmoothMotionRuntime implements PlayerRuntimeAccess {
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final Map<String, String> properties = <String, String>{};
  final List<String> writes = <String>[];

  /** 指定一个属性在写入后返回错误值，用于验证读回失败回滚。 */
  String? mismatchedProperty;

  @override
  PlayerBackendState get state => const PlayerBackendState(
        position: Duration.zero,
        duration: Duration.zero,
        playing: false,
        buffering: false,
        volume: 100,
        videoTrackCount: 0,
        audioTrackCount: 0,
      );

  @override
  ValueListenable<int?> get textureId => _textureId;

  @override
  Future<void> setProperty(String property, String value) async {
    writes.add('$property=$value');
    properties[property] = value;
  }

  @override
  Future<String> getProperty(String property) async {
    if (property == mismatchedProperty) return 'unavailable';
    return properties[property] ?? 'unavailable';
  }

  @override
  Future<PlayerGpuCapabilityMatrix> queryGpuCapabilities() async =>
      const PlayerGpuCapabilityMatrix.unsupported();
}

void main() {
  test('旧设置安全迁移为关闭且新档位可往返持久化', () {
    final legacy = PlaybackSettings.fromJson(const <String, Object?>{});
    expect(legacy.smoothMotionMode, PlayerSmoothMotionMode.off);

    final enabled = legacy.copyWith(
      smoothMotionMode: PlayerSmoothMotionMode.displayInterpolation,
    );
    final restored = PlaybackSettings.fromJson(enabled.toJson());
    expect(
      restored.smoothMotionMode,
      PlayerSmoothMotionMode.displayInterpolation,
    );
  });

  test('显示同步插值按稳定顺序写入并以属性读回确认', () async {
    final runtime = _SmoothMotionRuntime();
    final result = await PlayerSmoothMotion.apply(
      backend: runtime,
      mode: PlayerSmoothMotionMode.displayInterpolation,
    );

    expect(
      runtime.writes,
      const <String>[
        'video-sync=display-resample',
        'tscale=oversample',
        'interpolation=yes',
      ],
    );
    expect(result.active, isTrue);
    expect(result.verified, isTrue);
  });

  test('任一属性读回不一致时关闭插值且不宣称能力已启用', () async {
    final runtime = _SmoothMotionRuntime()..mismatchedProperty = 'video-sync';
    final result = await PlayerSmoothMotion.apply(
      backend: runtime,
      mode: PlayerSmoothMotionMode.displayInterpolation,
    );

    expect(result.active, isFalse);
    expect(result.verified, isFalse);
    expect(runtime.properties['interpolation'], 'no');
    expect(
      runtime.writes.sublist(runtime.writes.length - 3),
      const <String>[
        'interpolation=no',
        'tscale=oversample',
        'video-sync=display-resample',
      ],
    );
  });

  testWidgets('启用必须确认，确认后可撤销为原设置', (tester) async {
    var settings = PlaybackSettings.defaults;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlaybackSmoothMotionDropdown(
              settings: settings,
              onChanged: (value) => setState(() => settings = value),
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byType(DropdownButtonFormField<PlayerSmoothMotionMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示同步插值').last);
    await tester.pumpAndSettle();
    expect(find.text('启用显示同步插值？'), findsOneWidget);
    expect(settings.smoothMotionMode, PlayerSmoothMotionMode.off);

    await tester.tap(find.text('启用'));
    await tester.pumpAndSettle();
    expect(
      settings.smoothMotionMode,
      PlayerSmoothMotionMode.displayInterpolation,
    );
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(settings.smoothMotionMode, PlayerSmoothMotionMode.off);
  });

  testWidgets('确认弹窗等待期间移除选择器不会更新已释放 Route', (tester) async {
    var visible = true;
    var changeCount = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return visible
                  ? PlaybackSmoothMotionDropdown(
                      settings: PlaybackSettings.defaults,
                      onChanged: (_) => changeCount++,
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await tester
        .tap(find.byType(DropdownButtonFormField<PlayerSmoothMotionMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示同步插值').last);
    await tester.pumpAndSettle();
    rebuild(() => visible = false);
    await tester.pump();
    Navigator.of(tester.element(find.byType(AlertDialog))).pop(true);
    await tester.pumpAndSettle();

    expect(changeCount, 0);
    expect(tester.takeException(), isNull);
  });
}
