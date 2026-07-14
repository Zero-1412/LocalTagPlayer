// ignore_for_file: slash_for_doc_comments

import 'dart:typed_data';

/**
 * 文件系统实体的不可变快照。
 *
 * 上层只消费路径与轻量元数据，不持有 `dart:io` 的 `File`、`Directory` 或
 * `FileStat`，从而保证页面不会绕过平台边界执行磁盘操作。
 */
class FileSystemEntitySnapshot {
  const FileSystemEntitySnapshot({
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
  });

  /** 当前实体的规范化绝对路径。 */
  final String path;

  /** 当前实体是否为目录；为 false 时表示普通文件。 */
  final bool isDirectory;

  /** 文件大小；目录或无法读取时为 null。 */
  final int? size;

  /** 最后修改时间；无法读取时为 null。 */
  final DateTime? modifiedAt;
}

/**
 * Flutter/Dart 上层访问本地文件系统的唯一平台契约。
 *
 * 页面负责发起用户意图，桌面或移动端实现负责选择器、路径规范化、目录枚举、
 * 文件写入与删除。业务层不得依赖具体平台命令或 `dart:io` 实体。
 */
abstract interface class FileSystemAdapter {
  /** 选择一个或多个目录；用户取消时返回空列表。 */
  Future<List<String>> pickDirectories({String? dialogTitle});

  /** 选择单个文件；[allowedExtensions] 不包含点号。 */
  Future<String?> pickFile({
    String? dialogTitle,
    List<String> allowedExtensions = const <String>[],
  });

  /** 选择保存位置；用户取消时返回 null。 */
  Future<String?> pickSavePath({
    required String suggestedName,
    String? dialogTitle,
    List<String> allowedExtensions = const <String>[],
  });

  /** 判断目录是否存在。 */
  Future<bool> directoryExists(String path);

  /** 判断文件是否存在。 */
  Future<bool> fileExists(String path);

  /**
   * 枚举目录内容。
   *
   * [recursive] 为 false 时只返回直接子项，避免本地路径浏览在 UI 线程全量扫描。
   */
  Future<List<FileSystemEntitySnapshot>> listFiles(
    String rootPath, {
    required bool recursive,
  });

  /** 读取单个文件的轻量元数据；不存在时返回 null。 */
  Future<FileSystemEntitySnapshot?> statFile(String path);

  /** 删除单个文件；文件不存在时安全返回。 */
  Future<void> deleteFile(String path);

  /** 将字节写入用户已选择的文件路径。 */
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    bool flush = false,
  });

  /** 返回当前平台规范化路径。 */
  String normalizePath(String path);

  /** 按当前平台规则拼接路径片段。 */
  String joinPath(List<String> parts);

  /** 计算 [path] 相对 [rootPath] 的路径。 */
  String relativePath({required String rootPath, required String path});

  /** 在当前平台文件管理器中定位文件。 */
  Future<void> revealInFileManager(String path);
}
