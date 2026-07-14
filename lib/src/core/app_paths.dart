import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 应用私有文件路径提供器。
 *
 * 路径策略由组合根创建并注入，业务服务不得再读取静态路径或进程级测试覆盖状态。
 */
class AppPaths {
  AppPaths({
    Directory? dataDirectoryOverride,
    Map<String, String>? environment,
    Future<Directory> Function()? applicationSupportDirectory,
  })  : _dataDirectoryOverride = dataDirectoryOverride,
        _environment = environment ?? Platform.environment,
        _applicationSupportDirectory =
            applicationSupportDirectory ?? getApplicationSupportDirectory;

  /** 测试或临时 profile 显式指定的数据目录。 */
  final Directory? _dataDirectoryOverride;

  /** 由组合根捕获的进程环境，只用于解析临时数据目录。 */
  final Map<String, String> _environment;

  /** 系统应用支持目录查询函数，允许 contract test 注入 fake。 */
  final Future<Directory> Function() _applicationSupportDirectory;

  /** 返回应用私有数据目录，并确保目录已经存在。 */
  Future<Directory> dataDirectory() async {
    final explicitDirectory = _dataDirectoryOverride;
    if (explicitDirectory != null) {
      await explicitDirectory.create(recursive: true);
      return explicitDirectory;
    }
    final overridePath = _environment['LOCAL_TAG_PLAYER_DATA_DIR'];
    if (overridePath != null && overridePath.trim().isNotEmpty) {
      final directory = Directory(overridePath.trim());
      await directory.create(recursive: true);
      return directory;
    }
    final appDirectory = await _applicationSupportDirectory();
    final directory = Directory(p.join(appDirectory.path, 'LocalTagPlayer'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> settingsFile() => _file('settings.json');

  /** 媒体库排序偏好独立于播放设置保存。 */
  Future<File> librarySortPreferencesFile() => _file('library_sort.json');

  Future<File> legacyLibraryFile() => _file('library.json');

  Future<File> libraryDatabaseFile() => _file('library.db');

  /** 桌面窗口布局独立保存，避免覆盖其它设置。 */
  Future<File> windowLayoutFile() => _file('window_layout.json');

  /** 返回缩略图缓存目录，并确保目录已经存在。 */
  Future<Directory> thumbnailDirectory() async {
    final directory = Directory(
      p.join((await dataDirectory()).path, 'thumbnails'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  /** 在应用数据目录下解析单个文件。 */
  Future<File> _file(String name) async {
    return File(p.join((await dataDirectory()).path, name));
  }
}
