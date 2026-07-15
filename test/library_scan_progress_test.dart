import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

// ignore_for_file: slash_for_doc_comments

/** 为扫描进度测试创建少量真实扩展名文件，不依赖 FFmpeg 或用户媒体目录。 */
Future<Directory> _createVideoTree() async {
  final root = await Directory.systemTemp.createTemp('ltp_scan_progress_');
  final nested = await Directory('${root.path}${Platform.pathSeparator}album')
      .create(recursive: true);
  for (var index = 0; index < 40; index += 1) {
    await File('${nested.path}${Platform.pathSeparator}video_$index.mp4')
        .writeAsBytes(List<int>.generate(16384, (offset) => offset % 251));
  }
  return root;
}

/** 验证某个扫描后端会暂停在文件边界，并上报发现与确定型 fingerprint 进度。 */
Future<void> _verifyProgressAndPause(LibraryScanBackend backend) async {
  final root = await _createVideoTree();
  addTearDown(() async {
    await backend.setPaused(false);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });
  final progresses = <LibraryScanProgress>[];
  await backend.setPaused(true);
  var completed = false;
  final scan = backend
      .scan(
        generationId: 77,
        roots: <String>[root.path],
        knownMetadata: const <String, LibraryScanKnownMetadata>{},
        onProgress: progresses.add,
      )
      .whenComplete(() => completed = true);

  await Future<void>.delayed(const Duration(milliseconds: 100));
  expect(completed, isFalse);
  await backend.setPaused(false);
  final result = await scan.timeout(const Duration(seconds: 10));

  expect(result.added, hasLength(40));
  expect(
    progresses.any((item) => item.phase == LibraryScanPhase.discovering),
    isTrue,
  );
  final fingerprint = progresses
      .where((item) => item.phase == LibraryScanPhase.fingerprinting)
      .toList();
  expect(fingerprint, isNotEmpty);
  expect(fingerprint.last.total, 40);
  expect(fingerprint.last.processed, 40);
  expect(fingerprint.last.fraction, 1);
}

void main() {
  test('Dart 扫描后端支持播放让盘和确定型 fingerprint 进度', () async {
    await _verifyProgressAndPause(DartLibraryScanBackend());
  });

  test('Dart 扫描代次在播放让盘期间仍可取消', () async {
    final root = await _createVideoTree();
    final backend = DartLibraryScanBackend();
    addTearDown(() async {
      await backend.setPaused(false);
      await root.delete(recursive: true);
    });
    await backend.setPaused(true);
    final scan = backend.scan(
      generationId: 88,
      roots: <String>[root.path],
      knownMetadata: const <String, LibraryScanKnownMetadata>{},
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    backend.cancelGeneration(88);
    final result = await scan.timeout(const Duration(seconds: 2));
    expect(result.cancelled, isTrue);
  });

  test(
    'Rust sidecar 通过无路径 stderr 协议上报进度并原位恢复',
    () async {
      final executable = File(
        'windows/rust_library_scan/target/release/ltp_rust_library_scan.exe',
      ).absolute;
      await _verifyProgressAndPause(
        RustProcessLibraryScanBackend(executable: executable),
      );
    },
    skip: !Platform.isWindows ||
        !File(
          'windows/rust_library_scan/target/release/ltp_rust_library_scan.exe',
        ).existsSync(),
  );

  test('扫描结果区文案只在总量已知后显示百分比', () {
    expect(
      libraryScanProgressLabel(const LibraryScanProgress(
        generationId: 1,
        phase: LibraryScanPhase.discovering,
        processed: 128,
        discovered: 128,
      )),
      '正在发现视频 · 已找到 128 个',
    );
    expect(
      libraryScanProgressLabel(const LibraryScanProgress(
        generationId: 1,
        phase: LibraryScanPhase.fingerprinting,
        processed: 25,
        discovered: 100,
        total: 100,
        isPaused: true,
      )),
      '校验文件 25/100 · 25% · 播放期间已暂停',
    );
  });
}
