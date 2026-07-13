import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

// ignore_for_file: slash_for_doc_comments

/** 验证未变化文件复用数据库 fingerprint，不重新读取首尾内容。 */
void main() {
  test('untracked count snapshots roots before asynchronous enumeration',
      () async {
    final first = await Directory.systemTemp.createTemp('ltp_count_first_');
    final second = await Directory.systemTemp.createTemp('ltp_count_second_');
    addTearDown(() async {
      await first.delete(recursive: true);
      await second.delete(recursive: true);
    });
    await File('${first.path}${Platform.pathSeparator}first.mp4')
        .writeAsBytes([1]);
    await File('${second.path}${Platform.pathSeparator}second.mp4')
        .writeAsBytes([2]);
    final roots = <String>[first.path, second.path];

    final pending = const LibraryScanService().countUntrackedVideos(
      roots,
      const <String>{},
    );
    roots.clear();

    expect(await pending, 2);
  });

  test('scan reuses fingerprint when indexed size and modified time match',
      () async {
    final root = await Directory.systemTemp.createTemp('ltp_scan_reuse_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}${Platform.pathSeparator}clip.mp4');
    await file.writeAsBytes(List<int>.generate(16384, (index) => index % 251));
    final stat = await file.stat();
    const cachedFingerprint = 'v2:16384:cached-fingerprint';

    final result = await const LibraryScanService().scanRoots(
      [root.path],
      knownMetadata: {
        TagRules.pathKey(file.path): LibraryScanKnownMetadata(
          fileSize: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
          mediaFingerprint: cachedFingerprint,
        ),
      },
    );

    expect(result.entries.single.mediaFingerprint, cachedFingerprint);
  });

  test('Dart scan backend emits immutable delta and honors cancellation',
      () async {
    final root = await Directory.systemTemp.createTemp('ltp_scan_delta_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}${Platform.pathSeparator}clip.mp4');
    await file.writeAsBytes(List<int>.generate(8192, (index) => index % 251));
    final stat = await file.stat();
    final backend = DartLibraryScanBackend();
    final known = <String, LibraryScanKnownMetadata>{
      TagRules.pathKey(file.path): LibraryScanKnownMetadata(
        fileSize: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
        mediaFingerprint: 'v2:8192:cached',
        rootPath: root.path,
        relativePath: 'clip.mp4',
      ),
    };

    final unchanged = await backend.scan(
      generationId: 10,
      roots: [root.path],
      knownMetadata: known,
    );
    expect(unchanged.unchangedCount, 1);
    expect(unchanged.added, isEmpty);
    expect(unchanged.modified, isEmpty);
    expect(() => unchanged.seenPathKeys.add('mutate'), throwsUnsupportedError);

    backend.cancelGeneration(11);
    final cancelled = await backend.scan(
      generationId: 11,
      roots: [root.path],
      knownMetadata: known,
    );
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.changedEntries, isEmpty);
  });

  test('Rust sidecar matches Dart fingerprint and unchanged classification',
      () async {
    final executable = File(
      'build/windows/x64/runner/Debug/ltp_rust_library_scan.exe',
    ).absolute;
    if (!Platform.isWindows || !executable.existsSync()) {
      return;
    }
    final root = await Directory.systemTemp.createTemp('ltp_rust_scan_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}${Platform.pathSeparator}sample.mp4');
    await file.writeAsBytes(List<int>.generate(16384, (index) => index % 251));
    final dartBackend = DartLibraryScanBackend();
    final rustBackend = RustProcessLibraryScanBackend(executable: executable);

    final dartDelta = await dartBackend.scan(
      generationId: 20,
      roots: [root.path],
      knownMetadata: const <String, LibraryScanKnownMetadata>{},
    );
    final rustDelta = await rustBackend.scan(
      generationId: 21,
      roots: [root.path],
      knownMetadata: const <String, LibraryScanKnownMetadata>{},
    );
    expect(rustDelta.added.single.mediaFingerprint,
        dartDelta.added.single.mediaFingerprint);

    final scanned = rustDelta.added.single;
    final known = <String, LibraryScanKnownMetadata>{
      TagRules.pathKey(scanned.path): LibraryScanKnownMetadata(
        fileSize: scanned.fileSize,
        modifiedMs: scanned.modifiedMs,
        mediaFingerprint: scanned.mediaFingerprint,
        rootPath: scanned.rootPath,
        relativePath: scanned.relativePath,
      ),
    };
    final unchanged = await rustBackend.scan(
      generationId: 22,
      roots: [root.path],
      knownMetadata: known,
    );
    expect(unchanged.unchangedCount, 1);
    expect(unchanged.changedEntries, isEmpty);
  });
}
