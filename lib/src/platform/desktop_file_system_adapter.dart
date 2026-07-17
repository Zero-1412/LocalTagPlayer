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
  const DesktopFileSystemAdapter({
    Future<void> Function(String path)? windowsTrashFileOverride,
  }) : _windowsTrashFileOverride = windowsTrashFileOverride;

  /** 测试注入的回收站边界；生产环境为空并调用 Windows 系统回收站。 */
  final Future<void> Function(String path)? _windowsTrashFileOverride;

  @override
  Future<List<String>> pickDirectories({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );
    return path == null ? const <String>[] : <String>[normalizePath(path)];
  }

  @override
  Future<List<String>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    List<String> allowedExtensions = const <String>[],
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      allowMultiple: true,
      initialDirectory: initialDirectory,
    );
    return <String>[
      for (final file in result?.files ?? const <PlatformFile>[])
        if (file.path != null) normalizePath(file.path!),
    ];
  }

  @override
  Future<String?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    List<String> allowedExtensions = const <String>[],
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      type: allowedExtensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions.isEmpty ? null : allowedExtensions,
      allowMultiple: false,
      initialDirectory: initialDirectory,
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
  Future<void> moveFileToTrash(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return;
    }
    final absolutePath = normalizePath(file.absolute.path);
    final override = _windowsTrashFileOverride;
    if (override != null) {
      await override(absolutePath);
      return;
    }
    if (!Platform.isWindows) {
      // 当前只交付并验证 Windows 回收站；其它桌面端不能用永久删除冒充可恢复删除。
      throw UnsupportedError('当前平台暂不支持移入系统回收站');
    }
    await _moveWindowsFileToTrash(absolutePath);
  }

  /**
   * 使用 Windows 随系统提供的 .NET 文件接口把完整绝对路径移入回收站。
   *
   * 路径通过环境变量传入，避免文件名被 PowerShell 当作脚本执行；命令失败或文件
   * 仍存在时抛出异常，让上层保留数据库记录，不能静默降级为永久删除。
   */
  Future<void> _moveWindowsFileToTrash(String absolutePath) async {
    const script = r'''
Add-Type -AssemblyName Microsoft.VisualBasic
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
  $env:LTP_RECYCLE_TARGET,
  [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
  [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,
  [Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException
)
''';
    final result = await Process.run(
      'powershell.exe',
      const <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ],
      environment: <String, String>{
        ...Platform.environment,
        'LTP_RECYCLE_TARGET': absolutePath,
      },
      runInShell: false,
    );
    if (result.exitCode != 0 || await File(absolutePath).exists()) {
      throw FileSystemException(
        '移入回收站失败，系统退出码 ${result.exitCode}',
        absolutePath,
      );
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
  String parentPath(String path) => p.dirname(normalizePath(path));

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
