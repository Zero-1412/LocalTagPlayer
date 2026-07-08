part of '../app.dart';

abstract interface class FileSystemAdapter {
  Future<List<String>> pickDirectories();

  Future<bool> directoryExists(String path);

  Future<bool> fileExists(String path);

  Future<List<FileSystemEntitySnapshot>> listFiles(
    String rootPath, {
    required bool recursive,
  });

  Future<FileSystemEntitySnapshot?> statFile(String path);

  String normalizePath(String path);

  String joinPath(List<String> parts);

  String relativePath({required String rootPath, required String path});

  Future<void> revealInFileManager(String path);
}

abstract interface class PlayerBackend {
  Future<void> open(PlaybackSession session);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> dispose();

  Stream<PlaybackSession> get sessionChanges;

  Stream<DiagnoseStatus> get diagnoseChanges;
}

abstract interface class FFmpegBackend {
  Future<ExternalMediaToolsState> locateTools();

  Future<bool> isAvailable();

  Future<String?> version();

  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback,
  });

  Future<MediaDetails?> probe(VideoItem item);
}

abstract interface class DatabaseProvider {
  Future<File> databaseFile();

  Future<void> open();

  Future<void> close();

  Future<int> get schemaVersion;

  Future<void> migrate({required int fromVersion, required int toVersion});
}

class FileSystemEntitySnapshot {
  const FileSystemEntitySnapshot({
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
  });

  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;
}
