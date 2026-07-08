part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

class AppPaths {
  const AppPaths._();

  static Directory? _debugDataDirectoryOverride;

  /**
   * 测试进程内的数据目录覆盖入口。
   *
   * Windows debug exe 的临时 profile 继续使用 `LOCAL_TAG_PLAYER_DATA_DIR`；widget test
   * 无法可靠修改当前进程环境变量，因此通过该入口把数据库、设置和缩略图缓存导向可丢弃目录。
   */
  static void debugUseDataDirectoryForTesting(Directory? directory) {
    assert(() {
      _debugDataDirectoryOverride = directory;
      return true;
    }());
  }

  /**
   * 应用私有数据目录。
   *
   * 默认使用系统应用支持目录；设置 `LOCAL_TAG_PLAYER_DATA_DIR` 时改用指定目录，仅用于临时测试库、
   * 自动化复测或可回滚 profile，避免真实媒体库数据被测试动作污染。
   */
  static Future<Directory> dataDirectory() async {
    final debugDirectory = _debugDataDirectoryOverride;
    if (debugDirectory != null) {
      await debugDirectory.create(recursive: true);
      return debugDirectory;
    }
    final overridePath = Platform.environment['LOCAL_TAG_PLAYER_DATA_DIR'];
    if (overridePath != null && overridePath.trim().isNotEmpty) {
      final directory = Directory(overridePath.trim());
      await directory.create(recursive: true);
      return directory;
    }
    final appDir = await getApplicationSupportDirectory();
    final directory = Directory(p.join(appDir.path, 'LocalTagPlayer'));
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> settingsFile() async {
    final directory = await dataDirectory();
    return File(p.join(directory.path, 'settings.json'));
  }

  static Future<File> legacyLibraryFile() async {
    final directory = await dataDirectory();
    return File(p.join(directory.path, 'library.json'));
  }

  static Future<File> libraryDatabaseFile() async {
    final directory = await dataDirectory();
    return File(p.join(directory.path, 'library.db'));
  }

  static Future<Directory> thumbnailDirectory() async {
    final directory =
        Directory(p.join((await dataDirectory()).path, 'thumbnails'));
    await directory.create(recursive: true);
    return directory;
  }
}
