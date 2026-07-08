part of '../app.dart';

class MediaDetails {
  const MediaDetails({
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
  });

  factory MediaDetails.fromJson(Map<String, Object?> json) {
    return MediaDetails(
      videoCodec: json['videoCodec'] as String?,
      audioCodec: json['audioCodec'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }

  final String? videoCodec;
  final String? audioCodec;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {
        'videoCodec': videoCodec,
        'audioCodec': audioCodec,
        'width': width,
        'height': height,
      };

  String get resolution {
    if (width == null || height == null) {
      return '\u5206\u8fa8\u7387\u8bfb\u53d6\u4e2d';
    }
    return '${width}x$height';
  }

  String get videoLabel {
    final codec = _codecLabel(videoCodec);
    return codec == null ? resolution : '$codec, $resolution';
  }

  String get audioLabel {
    final codec = _codecLabel(audioCodec);
    return codec ?? '\u97f3\u9891\u8bfb\u53d6\u4e2d';
  }

  static String? _codecLabel(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty || value == 'auto' || value == 'no') {
      return null;
    }
    return value.toUpperCase();
  }
}


