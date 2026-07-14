import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/external_media_tools_state.dart';
import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

const _ffmpegThumbnailWidth = 384;
const _thumbnailFfmpegTimeout = Duration(seconds: 10);
const _mediaProbeTimeout = Duration(seconds: 6);

class DesktopFFmpegBackend implements FFmpegBackend {
  Future<ExternalMediaToolsState>? _cached;

  Future<ExternalMediaToolsState> _find() async {
    final ffmpeg = await _findExecutable(
      'ffmpeg',
      const [
        'tools\\ffmpeg\\bin\\ffmpeg.exe',
        'tools\\ffmpeg\\ffmpeg.exe',
        'ffmpeg\\bin\\ffmpeg.exe',
        'ffmpeg.exe',
      ],
    );
    final ffprobe = await _findExecutable(
      'ffprobe',
      const [
        'tools\\ffmpeg\\bin\\ffprobe.exe',
        'tools\\ffmpeg\\ffprobe.exe',
        'ffmpeg\\bin\\ffprobe.exe',
        'ffprobe.exe',
      ],
    );
    final ffmpegVersion = ffmpeg == null ? null : await _versionFor(ffmpeg);
    final ffprobeVersion = ffprobe == null ? null : await _versionFor(ffprobe);
    return ExternalMediaToolsState(
      ffmpegPath: ffmpeg,
      ffprobePath: ffprobe,
      ffmpegVersion: ffmpegVersion,
      ffprobeVersion: ffprobeVersion,
    );
  }

  Future<String?> _findExecutable(
      String command, List<String> localCandidates) async {
    final bases = <String>{
      Directory.current.path,
      p.dirname(Platform.resolvedExecutable)
    };
    for (final base in bases) {
      for (final relative in localCandidates) {
        final file = File(p.join(base, relative));
        if (await file.exists()) {
          return file.path;
        }
      }
    }

    try {
      final result = await Process.run('where.exe', [command])
          .timeout(const Duration(seconds: 2));
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          return const LineSplitter().convert(output).first.trim();
        }
      }
    } catch (_) {
      // 外部工具缺失是可接受状态；media_kit 仍作为兜底方案。
    }
    return null;
  }

  Future<String?> _versionFor(String executable) async {
    try {
      final result = await Process.run(executable, ['-version'])
          .timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) {
        return null;
      }
      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return null;
      }
      return const LineSplitter().convert(output).first.trim();
    } catch (_) {
      return null;
    }
  }

  String? _codec(Map<String, Object?>? stream) {
    final value = stream?['codec_name']?.toString().trim();
    return value == null || value.isEmpty ? null : value.toUpperCase();
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  Future<ExternalMediaToolsState> locateTools() {
    return _cached ??= _find();
  }

  @override
  Future<bool> isAvailable() async {
    return (await locateTools()).hasFfmpeg;
  }

  @override
  Future<String?> version() async {
    return (await locateTools()).ffmpegVersion;
  }

  Future<String?> ffprobeVersion() async {
    return (await locateTools()).ffprobeVersion;
  }

  @override
  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback = false,
  }) async {
    final ffmpeg = (await locateTools()).ffmpegPath;
    if (ffmpeg == null) {
      return null;
    }
    await output.parent.create(recursive: true);
    final tempOutput = File('${output.path}.tmp.jpg');
    if (await tempOutput.exists()) {
      await tempOutput.delete();
    }
    ProcessResult result;
    try {
      result = await Process.run(
        ffmpeg,
        [
          '-hide_banner',
          '-nostdin',
          '-loglevel',
          'error',
          '-y',
          '-threads',
          '1',
          '-ss',
          '00:00:02',
          '-noaccurate_seek',
          '-i',
          item.path,
          '-map',
          '0:v:0',
          '-an',
          '-sn',
          '-dn',
          '-frames:v',
          '1',
          '-vf',
          'scale=$_ffmpegThumbnailWidth:-1:force_original_aspect_ratio=decrease',
          '-q:v',
          '4',
          tempOutput.path,
        ],
      ).timeout(_thumbnailFfmpegTimeout);
    } on TimeoutException {
      if (await tempOutput.exists()) {
        await tempOutput.delete();
      }
      throw Exception('ffmpeg timeout ${_thumbnailFfmpegTimeout.inSeconds}s');
    }

    if (result.exitCode == 0 &&
        await tempOutput.exists() &&
        await tempOutput.length() > 0) {
      if (await output.exists()) {
        await output.delete();
      }
      await tempOutput.rename(output.path);
      return output;
    }
    if (await tempOutput.exists()) {
      await tempOutput.delete();
    }
    final message = result.stderr.toString().trim().isNotEmpty
        ? result.stderr.toString().trim()
        : result.stdout.toString().trim();
    throw Exception(
        'ffmpeg exit ${result.exitCode}${message.isEmpty ? '' : ': $message'}');
  }

  @override
  Future<MediaDetails?> probe(VideoItem item) async {
    final ffprobe = (await locateTools()).ffprobePath;
    if (ffprobe == null) {
      return null;
    }
    ProcessResult result;
    try {
      result = await Process.run(
        ffprobe,
        [
          '-v',
          'error',
          '-show_entries',
          'stream=codec_type,codec_name,width,height',
          '-of',
          'json',
          item.path,
        ],
      ).timeout(_mediaProbeTimeout);
    } on TimeoutException {
      throw Exception('ffprobe timeout ${_mediaProbeTimeout.inSeconds}s');
    }

    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim().isNotEmpty
          ? result.stderr.toString().trim()
          : result.stdout.toString().trim();
      throw Exception(
          'ffprobe exit ${result.exitCode}${message.isEmpty ? '' : ': $message'}');
    }

    final decoded = jsonDecode(result.stdout.toString());
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final streams = decoded['streams'];
    if (streams is! List) {
      return null;
    }

    Map<String, Object?>? video;
    Map<String, Object?>? audio;
    for (final stream in streams) {
      if (stream is! Map) {
        continue;
      }
      final map = stream.cast<String, Object?>();
      switch (map['codec_type']) {
        case 'video':
          video ??= map;
        case 'audio':
          audio ??= map;
      }
    }
    if (video == null && audio == null) {
      return null;
    }

    return MediaDetails(
      videoCodec: _codec(video),
      audioCodec: _codec(audio),
      width: _intValue(video?['width']),
      height: _intValue(video?['height']),
    );
  }
}
