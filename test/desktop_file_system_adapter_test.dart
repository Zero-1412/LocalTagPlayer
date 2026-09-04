// ignore_for_file: slash_for_doc_comments

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/platform/desktop_file_system_adapter.dart';
import 'package:local_tag_player/src/platform/file_system_adapter.dart';

void main() {
  test('file_picker 12 save contract writes real bytes and preserves cancel',
      () async {
    final root = await Directory.systemTemp.createTemp('ltp_save_adapter_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final originalPlatform = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = originalPlatform);
    final targetPath = '${root.path}${Platform.pathSeparator}export.json';
    final picker = _RecordingFilePickerPlatform(Uri.file(targetPath));
    FilePickerPlatform.instance = picker;
    final bytes = Uint8List.fromList(const <int>[1, 2, 3, 4]);

    final savedPath = await const DesktopFileSystemAdapter().saveBytes(
      bytes: bytes,
      suggestedName: 'export.json',
      dialogTitle: '导出',
      allowedExtensions: const <String>['json'],
    );

    expect(
        savedPath, const DesktopFileSystemAdapter().normalizePath(targetPath));
    expect(picker.receivedBytes, bytes);
    expect(picker.windowsOptions?.lockParentWindow, isTrue);
    expect(picker.linuxOptions?.lockParentWindow, isTrue);
    expect(await File(targetPath).readAsBytes(), bytes);

    final canceledPath = '${root.path}${Platform.pathSeparator}canceled.json';
    FilePickerPlatform.instance = _RecordingFilePickerPlatform(null);
    expect(
      await const DesktopFileSystemAdapter().saveBytes(
        bytes: bytes,
        suggestedName: 'canceled.json',
      ),
      isNull,
    );
    expect(await File(canceledPath).exists(), isFalse);
  });

  test('reveal rejects missing files before launching platform manager',
      () async {
    final missing = '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'ltp_missing_reveal_target.mp4';
    await expectLater(
      const DesktopFileSystemAdapter().revealInFileManager(missing),
      throwsA(isA<FileSystemException>()),
    );
  });

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

  test('desktop adapter renames without overwriting an existing file',
      () async {
    final root = await Directory.systemTemp.createTemp('ltp_rename_adapter_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final adapter = const DesktopFileSystemAdapter();
    final sourcePath = adapter.joinPath(<String>[root.path, 'before.mp4']);
    final targetPath = adapter.joinPath(<String>[root.path, 'after.mp4']);
    await adapter.writeBytes(
      sourcePath,
      Uint8List.fromList(const <int>[1, 2, 3]),
      flush: true,
    );

    final renamedPath = await adapter.renameFile(sourcePath, targetPath);

    expect(renamedPath, adapter.normalizePath(targetPath));
    expect(await adapter.fileExists(sourcePath), isFalse);
    expect(await adapter.fileExists(targetPath), isTrue);
    await adapter.writeBytes(
      sourcePath,
      Uint8List.fromList(const <int>[4, 5, 6]),
      flush: true,
    );
    await expectLater(
      adapter.renameFile(sourcePath, targetPath),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(targetPath).readAsBytes(), const <int>[1, 2, 3]);
  });

  test('desktop adapter routes recoverable deletion through trash boundary',
      () async {
    final root = await Directory.systemTemp.createTemp('ltp_trash_adapter_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final sourcePath = '${root.path}${Platform.pathSeparator}recoverable.mp4';
    await File(sourcePath).writeAsBytes(const <int>[1, 2, 3], flush: true);
    String? routedPath;
    final adapter = DesktopFileSystemAdapter(
      windowsTrashFileOverride: (path) async {
        routedPath = path;
        await File(path).delete();
      },
    );

    await adapter.moveFileToTrash(sourcePath);

    expect(routedPath, adapter.normalizePath(sourcePath));
    expect(await File(sourcePath).exists(), isFalse);
    // 不存在文件保持幂等，且不能再次调用平台回收站边界。
    routedPath = null;
    await adapter.moveFileToTrash(sourcePath);
    expect(routedPath, isNull);
  });

  test(
    'windows adapter moves a temporary file into the real recycle bin',
    () async {
      final root = await Directory.systemTemp.createTemp('ltp_recycle_smoke_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final sourcePath = '${root.path}${Platform.pathSeparator}'
          'ltp-recycle-smoke-delete-me.tmp';
      await File(sourcePath).writeAsBytes(const <int>[1, 2, 3], flush: true);

      await const DesktopFileSystemAdapter().moveFileToTrash(sourcePath);

      expect(await File(sourcePath).exists(), isFalse);
    },
    // 系统回收站是持久外部状态，只在显式烟测中写入一个可识别的 3 字节临时项。
    skip: !Platform.isWindows ||
        Platform.environment['LTP_RUN_RECYCLE_BIN_SMOKE'] != '1',
  );

  for (final entry in <(String, FileSystemAdapter)>[
    ('macOS', const MacOsFileSystemAdapter()),
    ('Linux', const LinuxFileSystemAdapter()),
  ]) {
    test('${entry.$1} adapter preserves the shared file operation contract',
        () async {
      final root = await Directory.systemTemp.createTemp(
        'ltp_${entry.$1.toLowerCase()}_adapter_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final sourcePath = entry.$2.joinPath(<String>[
        root.path,
        'nested',
        'clip.mp4',
      ]);

      await entry.$2.writeBytes(
        sourcePath,
        Uint8List.fromList(const <int>[1, 2, 3]),
        flush: true,
      );

      expect(await entry.$2.fileExists(sourcePath), isTrue);
      expect((await entry.$2.statFile(sourcePath))?.size, 3);
      expect(
        await entry.$2.listFiles(root.path, recursive: true),
        isNotEmpty,
      );
      await entry.$2.deleteFile(sourcePath);
      expect(await entry.$2.fileExists(sourcePath), isFalse);
    });
  }
}

/** 只记录 file_picker 12 保存参数，不打开系统窗口或提前写入测试文件。 */
class _RecordingFilePickerPlatform extends FilePickerPlatform {
  _RecordingFilePickerPlatform(this.result);

  final Uri? result;
  Uint8List? receivedBytes;
  WindowsOptions? windowsOptions;
  LinuxOptions? linuxOptions;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    receivedBytes = bytes;
    this.windowsOptions = windowsOptions;
    this.linuxOptions = linuxOptions;
    return result;
  }
}
