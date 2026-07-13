import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// ignore_for_file: slash_for_doc_comments

/** 验证 Windows 原生 FFmpeg 批处理、紧凑结果和 generation 取消。 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local_tag_player/media_probe');

  testWidgets('native media probe batches and cancels without SQLite access',
      (tester) async {
    final path = Platform.environment['LOCAL_TAG_PLAYER_PROBE_MEDIA_PATH'];
    expect(path, isNotNull);
    expect(await File(path!).exists(), isTrue);

    final result = await channel.invokeListMethod<Object?>('probeBatch', {
          'generationId': 101,
          'requests': [
            {
              'videoId': 'probe-smoke',
              'path': path,
              'knownSize': await File(path).length(),
              'knownModifiedAt': 0,
            },
          ],
        }) ??
        const <Object?>[];
    final first =
        (result.single as Map<Object?, Object?>).cast<String, Object?>();
    expect(first['videoId'], 'probe-smoke');
    expect(first['cancelled'], isFalse);
    expect(first['error'], isNull, reason: '${first['error']}');
    expect(first['videoCodec'], isNotEmpty);
    expect(first['audioCodec'], isNotEmpty);
    expect(first['width'], 320);
    expect(first['height'], 180);

    final pending = channel.invokeListMethod<Object?>('probeBatch', {
      'generationId': 102,
      'requests': List.generate(
        200,
        (index) => {
          'videoId': 'cancel-$index',
          'path': path,
          'knownSize': 1,
          'knownModifiedAt': 0,
        },
      ),
    });
    await channel.invokeMethod<void>(
      'cancelGeneration',
      {'generationId': 102},
    );
    final cancelled = await pending ?? const <Object?>[];
    expect(
      cancelled.whereType<Map<Object?, Object?>>().any(
            (value) => value['cancelled'] == true,
          ),
      isTrue,
    );
  });
}
