import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 验证Windows runner原生播放器骨架的方法通道、串行命令和纹理释放契约。
 *
 * 该测试不读取媒体库，也不启用UIA；真实媒体播放仍由独立压力测试覆盖。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local_tag_player/native_player');
  final hwndSamplePath =
      Platform.environment['LOCAL_TAG_PLAYER_NATIVE_HWND_SAMPLE']?.trim();
  final mpvTextureSamplePath =
      Platform.environment['LOCAL_TAG_PLAYER_NATIVE_MPV_SAMPLE']?.trim();
  final hwndLifecycleIterations = int.tryParse(
        Platform.environment['LOCAL_TAG_PLAYER_NATIVE_HWND_ITERATIONS'] ?? '',
      ) ??
      8;
  final d3d11vaZeroCopyQa =
      Platform.environment['LOCAL_TAG_PLAYER_D3D11VA_ZERO_COPY_QA'] == '1';

  testWidgets('native player stub serializes lifecycle and releases texture',
      (tester) async {
    final created =
        await channel.invokeMapMethod<String, Object?>('create') ?? const {};
    expect(created['backend'], 'windows-native-stub');
    expect(created['textureId'], isA<int>());
    expect(created['textureId'] as int, greaterThanOrEqualTo(0));

    await channel.invokeMethod<void>('command', {
      'name': 'seek',
      'integer': 4321,
    });
    final seeked =
        await channel.invokeMapMethod<String, Object?>('state') ?? const {};
    expect(seeked['positionMs'], 4321);
    expect(seeked['lifecycle'], 'command_seek');

    await channel.invokeMethod<void>('dispose');
    final disposed =
        await channel.invokeMapMethod<String, Object?>('state') ?? const {};
    expect(disposed['textureId'], -1);
    expect(disposed['lifecycle'], 'disposed');
  });

  testWidgets(
    'native MPV texture advances through observed events without polling',
    (tester) async {
      final created = await channel.invokeMapMethod<String, Object?>(
            'create',
            const <String, Object?>{'mode': 'mpv'},
          ) ??
          const <String, Object?>{};
      expect(created['backend'], 'windows-native-mpv');
      expect(created['native-surface-kind'], 'flutter-texture');

      await channel.invokeMethod<void>('command', {
        'name': 'open',
        'text': mpvTextureSamplePath,
      });
      await channel.invokeMethod<void>('command', {
        'name': 'property',
        'text': 'loop-file=inf',
      });
      await channel.invokeMethod<void>('command', const {'name': 'play'});
      final playing = await _waitForNativeState(
        tester,
        channel,
        (state) =>
            state['hwdec-current'] == 'd3d11va-copy' &&
            state['playing'] == true &&
            (state['positionMs'] as int? ?? 0) >= 1000 &&
            (state['estimated-frame-number'] as int? ?? 0) > 0 &&
            (state['native-rendered-frames'] as int? ?? 0) > 10 &&
            (state['native-mpv-events'] as int? ?? 0) > 0,
        timeout: const Duration(seconds: 20),
      );
      final positionBefore = playing['positionMs'] as int;
      await tester.pump(const Duration(seconds: 1));
      final advanced =
          await channel.invokeMapMethod<String, Object?>('state') ?? const {};
      expect(advanced['positionMs'] as int, greaterThan(positionBefore));
      expect(
        advanced['native-event-batch-yields'],
        isA<int>(),
      );

      await channel.invokeMethod<void>('dispose');
      final disposed =
          await channel.invokeMapMethod<String, Object?>('state') ?? const {};
      expect(disposed['textureId'], -1);
      expect(disposed['lifecycle'], 'mpv_disposed');
    },
    skip: mpvTextureSamplePath == null ||
        mpvTextureSamplePath.isEmpty ||
        !File(mpvTextureSamplePath).existsSync(),
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native child HWND survives repeated in-process sessions',
    (tester) async {
      final samplePath = hwndSamplePath!;
      for (var iteration = 0;
          iteration < hwndLifecycleIterations;
          iteration++) {
        final created = await channel.invokeMapMethod<String, Object?>(
              'create',
              const <String, Object?>{'mode': 'hwnd'},
            ) ??
            const <String, Object?>{};
        expect(created['backend'], 'windows-native-hwnd');
        expect(created['native-surface-kind'], 'child-hwnd');
        expect(created['textureId'], -1);

        // 同一 runner 进程内反复创建真实 wid，直接覆盖页面返回后下一次进入的资源重用。
        await channel.invokeMethod<void>('setSurfaceRect', {
          'left': 32,
          'top': 32,
          'width': 640,
          'height': 360,
          'viewWidth': 800,
          'viewHeight': 600,
          'visible': true,
        });
        await channel.invokeMethod<void>('command', {
          'name': 'open',
          'text': samplePath,
        });
        await channel.invokeMethod<void>('command', {
          'name': 'property',
          'text': 'loop-file=inf',
        });
        final compressionFilterEnabled = d3d11vaZeroCopyQa && iteration.isOdd;
        if (compressionFilterEnabled) {
          // 交替挂载正式“清晰增强”滤镜图，验证零拷贝解码请求不会让软件 vf 拒绝或停播。
          await channel.invokeMethod<void>('command', {
            'name': 'property',
            'text': 'vf=deblock=filter=weak:block=8:alpha=0.06:beta=0.03:'
                'gamma=0.03:delta=0.03,hqdn3d=1.2:0.9:1.8:1.35,'
                'unsharp=5:5:0.35:5:5:0.0',
          });
        }
        final playing = await _waitForNativeState(
          tester,
          channel,
          (state) =>
              state['hwdec-current'] == 'd3d11va' &&
              (!d3d11vaZeroCopyQa || state['d3d11va-zero-copy'] == 'yes') &&
              (!compressionFilterEnabled ||
                  (state['vf'] as String? ?? '').contains('hqdn3d=')) &&
              state['playing'] == true &&
              (state['estimated-frame-number'] as int? ?? 0) > 0,
          timeout: const Duration(seconds: 20),
        );
        expect(playing['native-texture-copies'], 0);
        expect(
          playing['d3d11va-zero-copy'],
          d3d11vaZeroCopyQa ? 'yes' : 'no',
        );
        expect(playing['frame-drop-count'], 0);
        expect(playing['native-surface-visible'], true);

        // airspace 弹层在每轮会话内都必须可隐藏并恢复，不能复用上轮 HWND 状态。
        await channel.invokeMethod<void>(
          'setSurfaceOccluded',
          const <String, Object?>{'occluded': true},
        );
        var state =
            await channel.invokeMapMethod<String, Object?>('state') ?? const {};
        expect(state['native-surface-occluded'], true);
        expect(state['native-surface-visible'], false);
        await channel.invokeMethod<void>(
          'setSurfaceOccluded',
          const <String, Object?>{'occluded': false},
        );
        state =
            await channel.invokeMapMethod<String, Object?>('state') ?? const {};
        expect(state['native-surface-occluded'], false);
        expect(state['native-surface-visible'], true);

        await channel.invokeMethod<void>('dispose');
        final disposed =
            await channel.invokeMapMethod<String, Object?>('state') ?? const {};
        expect(disposed['textureId'], -1);
        expect(disposed['native-surface-visible'], false);
        expect(disposed['native-surface-occluded'], false);
        expect(disposed['lifecycle'], 'mpv_hwnd_disposed');
      }

      // 重复 dispose 是 runner 关闭与页面释放交叠时的合法收尾，必须保持幂等。
      await channel.invokeMethod<void>('dispose');
      final disposed =
          await channel.invokeMapMethod<String, Object?>('state') ?? const {};
      expect(disposed['native-surface-visible'], false);
      expect(disposed['lifecycle'], 'mpv_hwnd_disposed');
    },
    skip: hwndSamplePath == null ||
        hwndSamplePath.isEmpty ||
        !File(hwndSamplePath).existsSync(),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/**
 * 持续驱动 Windows 测试窗口，直到原生快照满足单轮会话的播放条件。
 */
Future<Map<String, Object?>> _waitForNativeState(
  WidgetTester tester,
  MethodChannel channel,
  bool Function(Map<String, Object?> state) predicate, {
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  var latest = <String, Object?>{};
  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 50));
    latest =
        await channel.invokeMapMethod<String, Object?>('state') ?? const {};
    if (predicate(latest)) return latest;
  }
  throw StateError('等待原生会话状态超时：$latest');
}
