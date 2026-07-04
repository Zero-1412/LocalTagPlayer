part of '../../main.dart';

class VideoItem {
  VideoItem({
    required this.path,
    required this.title,
    required this.folder,
    required this.tags,
    required this.addedAt,
    Map<String, Set<String>>? childTags,
    this.rootPath,
    this.relativePath,
    this.fileSize,
    this.modifiedMs,
    this.isFavorite = false,
    this.mediaDetails,
    this.mediaFingerprint,
    this.thumbnailError,
    this.mediaDetailsError,
    this.lastPlayedAt,
  }) : childTags = childTags ?? <String, Set<String>>{};

  final String path;
  final String title;
  final String folder;
  final Set<String> tags;
  final Map<String, Set<String>> childTags;
  final DateTime addedAt;
  String? rootPath;
  String? relativePath;
  int? fileSize;
  int? modifiedMs;
  bool isFavorite;
  MediaDetails? mediaDetails;
  String? mediaFingerprint;
  String? thumbnailError;
  String? mediaDetailsError;
  DateTime? lastPlayedAt;

  Map<String, Object?> toJson() => {
        'path': path,
        'title': title,
        'folder': folder,
        'tags': tags.toList()..sort(),
        'childTags': childTags.map((key, value) => MapEntry(key, value.toList()..sort())),
        'rootPath': rootPath,
        'relativePath': relativePath,
        'fileSize': fileSize,
        'modifiedMs': modifiedMs,
        'isFavorite': isFavorite,
        'mediaDetails': mediaDetails?.toJson(),
        'mediaFingerprint': mediaFingerprint,
        'thumbnailError': thumbnailError,
        'mediaDetailsError': mediaDetailsError,
        'addedAt': addedAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
      };

  static VideoItem fromJson(Map<String, Object?> json) {
    return VideoItem(
      path: json['path']! as String,
      title: json['title']! as String,
      folder: json['folder']! as String,
      tags: ((json['tags'] as List?) ?? const []).cast<String>().toSet(),
      childTags: ((json['childTags'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(key as String, ((value as List?) ?? const []).cast<String>().toSet()),
      ),
      rootPath: json['rootPath'] as String?,
      relativePath: json['relativePath'] as String?,
      fileSize: json['fileSize'] as int?,
      modifiedMs: json['modifiedMs'] as int?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      mediaDetails: json['mediaDetails'] is Map
          ? MediaDetails.fromJson((json['mediaDetails'] as Map).cast<String, Object?>())
          : null,
      mediaFingerprint: json['mediaFingerprint'] as String?,
      thumbnailError: json['thumbnailError'] as String?,
      mediaDetailsError: json['mediaDetailsError'] as String?,
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.now(),
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
    );
  }
}


