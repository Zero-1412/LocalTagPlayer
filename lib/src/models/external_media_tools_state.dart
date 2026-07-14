// ignore_for_file: slash_for_doc_comments

/** 桌面媒体工具定位结果，不包含任何进程级可变状态。 */
class ExternalMediaToolsState {
  const ExternalMediaToolsState({
    this.ffmpegPath,
    this.ffprobePath,
    this.ffmpegVersion,
    this.ffprobeVersion,
  });

  final String? ffmpegPath;
  final String? ffprobePath;
  final String? ffmpegVersion;
  final String? ffprobeVersion;

  bool get hasFfmpeg => ffmpegPath != null;
  bool get hasFfprobe => ffprobePath != null;
}
