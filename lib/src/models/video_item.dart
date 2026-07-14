import 'dart:math' as math;

import 'media_details.dart';

// ignore_for_file: slash_for_doc_comments

class VideoItem {
  VideoItem({
    String? videoId,
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
    this.isMissing = false,
    this.playbackPosition = Duration.zero,
    this.playbackDuration = Duration.zero,
    this.playbackCompleted = false,
    this.playbackPositionUpdatedAt,
  })  : videoId = videoId ?? newVideoId(),
        childTags = childTags ?? <String, Set<String>>{};

  /** 不依赖路径的稳定数据库身份。 */
  final String videoId;

  /** 当前文件位置；移动或重命名后允许更新。 */
  String path;
  /** 当前路径对应的显示标题；relink 后随新文件名更新。 */
  String title;
  /** 当前文件所在目录；仅描述位置，不承担稳定身份。 */
  String folder;
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
  /** 当前路径是否已失效；记录和用户数据仍保留。 */
  bool isMissing;
  /** 与稳定 videoId 同行保存的最近播放位置。 */
  Duration playbackPosition;
  /** 最近一次可用的媒体总时长，与稳定 videoId 同行保存。 */
  Duration playbackDuration;
  /** 最近一次播放是否已经进入动态完成阈值。 */
  bool playbackCompleted;
  /** 最近一次写入播放位置的时间。 */
  DateTime? playbackPositionUpdatedAt;

  Map<String, Object?> toJson() => {
        'videoId': videoId,
        'path': path,
        'title': title,
        'folder': folder,
        'tags': tags.toList()..sort(),
        'childTags': childTags
            .map((key, value) => MapEntry(key, value.toList()..sort())),
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
        'isMissing': isMissing,
        'playbackPositionMs': playbackPosition.inMilliseconds,
        'playbackDurationMs': playbackDuration.inMilliseconds,
        'playbackCompleted': playbackCompleted,
        'playbackPositionUpdatedAt':
            playbackPositionUpdatedAt?.toIso8601String(),
      };

  static VideoItem fromJson(Map<String, Object?> json) {
    return VideoItem(
      videoId: json['videoId'] as String?,
      path: json['path']! as String,
      title: json['title']! as String,
      folder: json['folder']! as String,
      tags: ((json['tags'] as List?) ?? const []).cast<String>().toSet(),
      childTags: ((json['childTags'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(key as String,
            ((value as List?) ?? const []).cast<String>().toSet()),
      ),
      rootPath: json['rootPath'] as String?,
      relativePath: json['relativePath'] as String?,
      fileSize: json['fileSize'] as int?,
      modifiedMs: json['modifiedMs'] as int?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      mediaDetails: json['mediaDetails'] is Map
          ? MediaDetails.fromJson(
              (json['mediaDetails'] as Map).cast<String, Object?>())
          : null,
      mediaFingerprint: json['mediaFingerprint'] as String?,
      thumbnailError: json['thumbnailError'] as String?,
      mediaDetailsError: json['mediaDetailsError'] as String?,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
      isMissing: json['isMissing'] as bool? ?? false,
      playbackPosition:
          Duration(milliseconds: json['playbackPositionMs'] as int? ?? 0),
      playbackDuration:
          Duration(milliseconds: json['playbackDurationMs'] as int? ?? 0),
      playbackCompleted: json['playbackCompleted'] as bool? ?? false,
      playbackPositionUpdatedAt:
          DateTime.tryParse(json['playbackPositionUpdatedAt'] as String? ?? ''),
    );
  }

  /** 生成与路径无关、足以在单机媒体库中保持唯一的身份值。 */
  static String newVideoId() {
    final random = math.Random.secure();
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = List<int>.generate(4, (_) => random.nextInt(1 << 32))
        .map((value) => value.toRadixString(36).padLeft(7, '0'))
        .join();
    return 'vid_$time$entropy';
  }
}
