import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// ignore_for_file: slash_for_doc_comments

/** 验证 Windows 原生 FFmpeg 批处理、紧凑结果和 generation 取消。 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local_tag_player/media_probe');
  final smokePath = Platform.environment['LOCAL_TAG_PLAYER_PROBE_MEDIA_PATH'];
  final benchmarkRoot =
      Platform.environment['LOCAL_TAG_PLAYER_PROBE_BENCH_ROOT'];

  testWidgets('native media probe batches and cancels without SQLite access',
      (tester) async {
    final path = smokePath!;
    expect(await File(path).exists(), isTrue);

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
  }, skip: smokePath == null);

  testWidgets('benchmarks native media probe throughput on a real disk root',
      (tester) async {
    final root = Directory(benchmarkRoot!);
    expect(await root.exists(), isTrue);
    final limit = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_PROBE_BENCH_LIMIT'] ?? '',
        ) ??
        256;
    final rounds = int.tryParse(
          Platform.environment['LOCAL_TAG_PLAYER_PROBE_BENCH_ROUNDS'] ?? '',
        ) ??
        3;
    const extensions = <String>{
      '.mp4',
      '.mkv',
      '.webm',
      '.mov',
      '.avi',
      '.m4v',
      '.flv',
      '.wmv',
    };
    final files = root
        .listSync(recursive: true, followLinks: true)
        .whereType<File>()
        .where((file) {
      final name = file.path.toLowerCase();
      return extensions.any(name.endsWith);
    }).toList(growable: false)
      ..sort((left, right) => left.path.compareTo(right.path));
    final selected = files.take(limit).map((file) {
      return (
        path: file.path,
        size: file.lengthSync(),
      );
    }).toList(growable: false);
    expect(selected, isNotEmpty);

    final speeds = <double>[];
    for (var round = 1; round <= rounds; round++) {
      var failures = 0;
      final watch = Stopwatch()..start();
      for (var start = 0; start < selected.length; start += 8) {
        final end = (start + 8).clamp(0, selected.length);
        final batch = selected.sublist(start, end);
        final results = await channel.invokeListMethod<Object?>('probeBatch', {
              'generationId': 2000 + round,
              'requests': [
                for (var index = 0; index < batch.length; index++)
                  {
                    'videoId': 'bench-$round-${start + index}',
                    'path': batch[index].path,
                    'knownSize': batch[index].size,
                    'knownModifiedAt': 0,
                  },
              ],
            }) ??
            const <Object?>[];
        failures += results.whereType<Map<Object?, Object?>>().where((value) {
          return value['cancelled'] == true || value['error'] != null;
        }).length;
      }
      watch.stop();
      final speed = selected.length /
          (watch.elapsedMicroseconds / Duration.microsecondsPerSecond);
      speeds.add(speed);
      // JSONL 便于后续把 HDD/SSD 多轮结果直接追加到诊断记录中。
      // ignore: avoid_print
      print('MEDIA_PROBE_BENCHMARK ${jsonEncode({
            'root': root.path,
            'round': round,
            'items': selected.length,
            'elapsedMs': watch.elapsedMilliseconds,
            'itemsPerSecond': double.parse(speed.toStringAsFixed(2)),
            'failures': failures,
          })}');
    }
    final sortedSpeeds = [...speeds]..sort();
    final median = sortedSpeeds[sortedSpeeds.length ~/ 2];
    // ignore: avoid_print
    print('MEDIA_PROBE_BENCHMARK_SUMMARY ${jsonEncode({
          'root': root.path,
          'rounds': rounds,
          'itemsPerRound': selected.length,
          'medianItemsPerSecond': double.parse(median.toStringAsFixed(2)),
        })}');
  }, skip: benchmarkRoot == null);
}
