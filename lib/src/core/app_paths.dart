part of '../../main.dart';

class AppPaths {
  const AppPaths._();

  // Centralize app-owned paths before platform-specific storage implementations diverge.
  static Future<Directory> dataDirectory() async {
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
    final directory = Directory(p.join((await dataDirectory()).path, 'thumbnails'));
    await directory.create(recursive: true);
    return directory;
  }
}

