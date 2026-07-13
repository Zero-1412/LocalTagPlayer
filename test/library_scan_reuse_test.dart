import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

// ignore_for_file: slash_for_doc_comments

/** 验证未变化文件复用数据库 fingerprint，不重新读取首尾内容。 */
void main() {
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
}
