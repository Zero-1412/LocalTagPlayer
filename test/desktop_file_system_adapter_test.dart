import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

void main() {
  test('desktop file system adapter owns list stat write and delete', () async {
    final root = await Directory.systemTemp.createTemp('ltp_fs_adapter_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final child = Directory('${root.path}${Platform.pathSeparator}child');
    await child.create();
    final sourcePath =
        '${root.path}${Platform.pathSeparator}source${Platform.pathSeparator}clip.mp4';
    final adapter = const DesktopFileSystemAdapter();

    await adapter.writeBytes(
      sourcePath,
      Uint8List.fromList(const <int>[1, 2, 3, 4]),
      flush: true,
    );

    expect(await adapter.directoryExists(root.path), isTrue);
    expect(await adapter.fileExists(sourcePath), isTrue);
    final entries = await adapter.listFiles(root.path, recursive: true);
    expect(entries.any((entry) => entry.isDirectory), isTrue);
    expect(
      entries
          .singleWhere(
              (entry) => entry.path == adapter.normalizePath(sourcePath))
          .size,
      4,
    );
    expect((await adapter.statFile(sourcePath))?.size, 4);

    await adapter.deleteFile(sourcePath);
    expect(await adapter.fileExists(sourcePath), isFalse);
    // 删除不存在文件必须保持幂等，避免 UI 重复确认触发竞态异常。
    await adapter.deleteFile(sourcePath);
  });
}
