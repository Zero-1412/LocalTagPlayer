// ignore_for_file: slash_for_doc_comments

/**
 * 播放会话可选择的音频或字幕轨道。
 *
 * 该快照只保存 libmpv/MediaKit 已解析的展示字段，不保存路径，也不承担用户
 * 偏好持久化；切换媒体后必须重新读取，避免把前一文件的轨道 ID 用到新文件。
 */
class PlayerMediaTrack {
  const PlayerMediaTrack({
    required this.id,
    required this.title,
    required this.language,
    required this.codec,
    required this.isDefault,
    required this.selected,
  });

  final String id;
  final String? title;
  final String? language;
  final String? codec;
  final bool isDefault;
  final bool selected;

  /** 不泄露路径的稳定 UI 标签。 */
  String label(String fallback) {
    final name = title?.trim();
    if (name != null && name.isNotEmpty) return name;
    final locale = language?.trim();
    if (locale != null && locale.isNotEmpty) return locale;
    final format = codec?.trim();
    if (format != null && format.isNotEmpty) return format;
    return fallback;
  }
}

/** 当前媒体内的章节；位置仅对当前打开会话有效。 */
class PlayerMediaChapter {
  const PlayerMediaChapter({
    required this.index,
    required this.position,
    required this.title,
  });

  final int index;
  final Duration position;
  final String? title;
}

/**
 * 一次读取完成的媒体控制快照。
 *
 * `supported=false` 代表后端没有该可选能力，而非“当前文件没有音轨/字幕/章节”。
 */
class PlayerMediaControlsSnapshot {
  const PlayerMediaControlsSnapshot({
    required this.supported,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.chapters,
    required this.subtitleDelay,
    required this.audioDelay,
  });

  const PlayerMediaControlsSnapshot.unsupported()
      : supported = false,
        audioTracks = const <PlayerMediaTrack>[],
        subtitleTracks = const <PlayerMediaTrack>[],
        chapters = const <PlayerMediaChapter>[],
        subtitleDelay = Duration.zero,
        audioDelay = Duration.zero;

  final bool supported;
  final List<PlayerMediaTrack> audioTracks;
  final List<PlayerMediaTrack> subtitleTracks;
  final List<PlayerMediaChapter> chapters;
  final Duration subtitleDelay;
  final Duration audioDelay;
}
