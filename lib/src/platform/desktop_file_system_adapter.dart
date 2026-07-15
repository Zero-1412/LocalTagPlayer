// ignore_for_file: slash_for_doc_comments

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'file_system_adapter.dart';

/**
 * Windows、macOS 与 Linux 桌面文件系统实现。
 *
 * 所有 `dart:io`、FilePicker 与平台文件管理器命令都收口在该类中；Flutter 页面
 * 只依赖 [FileSystemAdapter]，不会感知 `explorer.exe`、`open` 或 `xdg-open`。
 */
class DesktopFileSystemAdapter implements FileSystemAdapter {
  const DesktopFileSystemAdapter();

  @override
  Future<List<String>> pickDirectories({String? dialogTitle}) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
    );
    return path == null ? const <String>[] : <String>[normalizePath(path)];
  }

  @override
  Future<List<String>> pickFiles({
    String? dialogTitle,
    List<String> allowedExtensions = const <String>[],
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      allowMultiple: true,
    );
    return <String>[
      for (final file in result?.files ?? const <PlatformFile>[])
        if (file.path != null) normalizePath(file.path!),
    ];
  }

  @override
  Future<String?> pickFile({
    String? dialogTitle,
    List<String> allowedExtensions = const <String>[],
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    return path == null ? null : normalizePath(path);
  }

  @override
  Future<String?> pickSavePath({
    required String suggestedName,
    String? dialogTitle,
    List<String> allowedExtensions = const <String>[],
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: suggestedName,
      type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
    );
    return path == null ? null : normalizePath(path);
  }

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<List<FileSystemEntitySnapshot>> listFiles(
    String rootPath, {
    required bool recursive,
  }) async {
    final directory = Directory(rootPath);
    if (!await directory.exists()) {
      return const <FileSystemEntitySnapshot>[];
    }
    final snapshots = <FileSystemEntitySnapshot>[];
    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final stat = await entity.stat();
      final isDirectory = stat.type == FileSystemEntityType.directory;
      snapshots.add(FileSystemEntitySnapshot(
        path: normalizePath(entity.path),
        isDirectory: isDirectory,
        size: isDirectory ? null : stat.size,
        modifiedAt: stat.modified,
      ));
    }
    return snapshots;
  }

  @override
  Future<FileSystemEntitySnapshot?> statFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final stat = await file.stat();
    return FileSystemEntitySnapshot(
      path: normalizePath(file.absolute.path),
      isDirectory: false,
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    bool flush = false,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: flush);
  }

  @override
  String normalizePath(String path) => p.normalize(p.absolute(path));

  @override
  String joinPath(List<String> parts) => p.joinAll(parts);

  @override
  String relativePath({required String rootPath, required String path}) =>
      p.relative(path, from: rootPath);

  @override
  Future<void> revealInFileManager(String path) async {
    final file = File(path).absolute;
    if (!await file.exists()) {
      throw FileSystemException('文件不存在，无法打开所在位置', file.path);
    }
    if (Platform.isWindows) {
      await Process.start('explorer.exe', <String>['/select,${file.path}']);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', <String>['-R', file.path]);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', <String>[file.parent.path]);
      return;
    }
    throw UnsupportedError('当前平台不支持打开文件位置');
  }
}

/** macOS 文件选择、枚举与 Finder reveal 的显式适配器类型。 */
class MacOsFileSystemAdapter extends DesktopFileSystemAdapter {
  const MacOsFileSystemAdapter();
}

/** Linux 文件选择、枚举与 xdg-open reveal 的显式适配器类型。 */
class LinuxFileSystemAdapter extends DesktopFileSystemAdapter {
  const LinuxFileSystemAdapter();
}
