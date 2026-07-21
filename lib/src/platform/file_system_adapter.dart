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
  /**
   * 选择一个或多个目录；用户取消时返回空列表。
   *
   * [initialDirectory] 是当前媒体上下文建议的起点；平台不支持或目录失效时可回退
   * 系统默认位置，页面不得自行拼接平台命令。
   */
  Future<List<String>> pickDirectories({
    String? dialogTitle,
    String? initialDirectory,
  });

  /**
   * 选择一个或多个文件；[allowedExtensions] 不包含点号。
   *
   * 多选能力由平台适配器统一实现，页面不得直接依赖 `FilePicker`，以便 Windows、
   * macOS 与 Linux 共用同一条导入链路。
   */
  Future<List<String>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    List<String> allowedExtensions = const <String>[],
  });

  /** 选择单个文件；[allowedExtensions] 不包含点号。 */
  Future<String?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
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

  /**
   * 把单个文件从 [sourcePath] 重命名为 [targetPath]，并返回规范化后的新路径。
   *
   * 目标已存在时必须拒绝覆盖；上层只负责表达用户意图，不得绕过该边界直接使用
   * `dart:io`。当前播放器用例只允许同目录改名，跨目录移动仍由独立 relink 流程负责。
   */
  Future<String> renameFile(String sourcePath, String targetPath);

  /**
   * 把单个文件移入当前系统的回收站或废纸篓；文件不存在时安全返回。
   *
   * 实现不能静默回退为永久删除；平台不支持时必须抛出明确异常。
   */
  Future<void> moveFileToTrash(String path);

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

  /** 返回文件或目录路径的父目录，不让页面依赖具体平台路径库。 */
  String parentPath(String path);

  /** 计算 [path] 相对 [rootPath] 的路径。 */
  String relativePath({required String rootPath, required String path});

  /** 在当前平台文件管理器中定位文件。 */
  Future<void> revealInFileManager(String path);
}
