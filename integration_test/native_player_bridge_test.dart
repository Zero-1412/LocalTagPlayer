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
}
