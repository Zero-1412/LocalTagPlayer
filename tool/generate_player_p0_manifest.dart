import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _codecs = <String>['h264', 'hevc', 'av1'];
const _resolutions = <String>['1080p', '4k'];
const _gops = <String>['short-gop', 'long-gop'];
const _actions = <String>[
  'startup',
  'shortForward',
  'shortBackward',
  'drag',
  'longForward',
  'longBackward',
  'fullscreen',
];

/// 从用户本机只读资料库和 ffprobe 生成未跟踪的 P0 manifest。
///
/// 该工具只把真实路径写入调用方指定的本机输出文件，不打印路径、文件名、videoId
/// 或媒体标题。不能满足的 case 会保留空 path，并以退出码 3 表示 unknown，禁止把
/// 不完整的本机素材集冒充为完整 12-case manifest。
Future<void> main(List<String> arguments) async {
  final parser = _Arguments(arguments);
  final output = parser.value('--output');
  if (output == null || output.trim().isEmpty) {
    stderr.writeln('缺少 --output；manifest 必须写入未跟踪的本机 QA 目录。');
    exitCode = 64;
    return;
  }

  final ffprobe = parser.value('--ffprobe') ??
      <String>[
        Directory.current.path,
        'windows',
        'tools',
        'ffmpeg',
        'bin',
        'ffprobe.exe',
      ].join(Platform.pathSeparator);
  if (!File(ffprobe).existsSync()) {
    stderr.writeln('找不到 ffprobe；manifest 未生成。');
    exitCode = 2;
    return;
  }

  final databasePath = _findLibraryDatabase(parser.value('--database'));
  if (databasePath == null) {
    stderr.writeln('未找到 LocalTagPlayer library.db；manifest 未生成。');
    exitCode = 2;
    return;
  }
  final executablePath = parser.value('--executable') ??
      <String>[
        Directory.current.path,
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
        'local_tag_player.exe',
      ].join(Platform.pathSeparator);
  final executableSha256 = await _sha256Of(executablePath);

  final maxCandidates =
      int.tryParse(parser.value('--max-candidates') ?? '') ?? 24;
  if (maxCandidates < 1 || maxCandidates > 100) {
    stderr.writeln('--max-candidates 必须在 1 到 100 之间。');
    exitCode = 64;
    return;
  }
  final probeTimeoutSeconds =
      int.tryParse(parser.value('--probe-timeout-seconds') ?? '') ?? 15;
  if (probeTimeoutSeconds < 1 || probeTimeoutSeconds > 120) {
    stderr.writeln('--probe-timeout-seconds 必须在 1 到 120 之间。');
    exitCode = 64;
    return;
  }
  final maxProbes = int.tryParse(parser.value('--max-probes') ?? '') ?? 24;
  if (maxProbes < 1 || maxProbes > 200) {
    stderr.writeln('--max-probes 必须在 1 到 200 之间。');
    exitCode = 64;
    return;
  }

  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );

  try {
    final candidates = await _readCandidates(database);
    final selected = <String, _ProbedCandidate>{};
    var probeCount = 0;
    for (final resolution in _resolutions) {
      if (probeCount >= maxProbes) break;
      for (final codec in _codecs) {
        if (probeCount >= maxProbes) break;
        final bucket = candidates['$resolution-$codec'] ?? <_Candidate>[];
        final bestByGop = <String, _ProbedCandidate>{};
        for (final candidate in bucket.take(maxCandidates)) {
          if (probeCount >= maxProbes) break;
          final probed = await _probeCandidate(
            candidate,
            ffprobe,
            timeout: Duration(seconds: probeTimeoutSeconds),
          );
          probeCount++;
          if (probed == null || !bestByGop.containsKey(probed.gop)) {
            if (probed != null) bestByGop[probed.gop] = probed;
          } else if (_bitrateOf(probed) > _bitrateOf(bestByGop[probed.gop]!)) {
            bestByGop[probed.gop] = probed;
          }
          if (bestByGop.length == _gops.length) break;
        }
        for (final gop in _gops) {
          final probed = bestByGop[gop];
          if (probed != null) selected['$resolution-$codec-$gop'] = probed;
        }
      }
    }

    final cases = <Map<String, Object?>>[];
    var missing = 0;
    for (final resolution in _resolutions) {
      for (final codec in _codecs) {
        for (final gop in _gops) {
          final id = '$resolution-$codec-$gop';
          final probed = selected[id];
          if (probed == null) missing++;
          cases.add(<String, Object?>{
            'id': id,
            'path': probed?.candidate.path ?? '',
            'codec': codec,
            'width': probed?.candidate.width ?? _defaultWidth(resolution),
            'height': probed?.candidate.height ?? _defaultHeight(resolution),
            'gop': gop,
            'p95BudgetMs': _budget(resolution, gop),
            'selectionStatus': probed == null
                ? 'missing-candidate'
                : 'selected-and-ffprobe-verified',
            if (probed != null) ...<String, Object?>{
              'maxKeyframeIntervalSeconds': probed.maxGopSeconds,
              'bitrateKbps': probed.bitrateKbps,
              'durationSeconds': probed.durationSeconds,
            },
          });
        }
      }
    }

    final destination = File(output);
    await destination.parent.create(recursive: true);
    final manifest = <String, Object?>{
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'source': 'readonly-library-db-plus-ffprobe',
      'status': missing == 0 ? 'complete' : 'partial',
      'build': <String, Object?>{
        'configuration': 'Debug',
        'surface': 'mediaKit-texture',
        'executableSha256': executableSha256 ?? '',
        'evidenceKind': 'desktop-composited-pixel-change',
      },
      'actions': _actions,
      'cases': cases,
      'selection': <String, Object?>{
        'databaseReadOnly': true,
        'maxCandidatesPerBucket': maxCandidates,
        'probeTimeoutSeconds': probeTimeoutSeconds,
        'maxProbes': maxProbes,
        'probedCandidates': probeCount,
        'selectedCases': cases
            .where((item) =>
                item['selectionStatus'] == 'selected-and-ffprobe-verified')
            .length,
        'missingCases': missing,
        'shortGopMaxSeconds': 1.1,
        'longGopMinSeconds': 4.0,
      },
    };
    await destination.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );

    final selectedCount = cases.length - missing;
    final status = manifest['status'].toString();
    stdout.writeln(
      'P0_MANIFEST_GENERATED status=$status '
      'selected=$selectedCount missing=$missing probed=$probeCount '
      'database=readonly',
    );
    if (missing > 0) exitCode = 3;
  } finally {
    await database.close();
  }
}

Future<Map<String, List<_Candidate>>> _readCandidates(Database database) async {
  final rows = await database.rawQuery(
    '''
SELECT path, media_details_json
FROM videos
WHERE is_missing = 0
  AND media_details_json IS NOT NULL
ORDER BY last_played_at DESC, added_at DESC
''',
  );
  final buckets = <String, List<_Candidate>>{};
  for (final row in rows) {
    final path = row['path'] as String?;
    final detailsText = row['media_details_json'] as String?;
    if (path == null || detailsText == null || !File(path).existsSync()) {
      continue;
    }
    final details = _readDetails(detailsText);
    if (details == null) continue;
    final resolution = _resolutionOf(details.width, details.height);
    if (resolution == null) continue;
    final codec = details.codec;
    final key = '$resolution-$codec';
    buckets.putIfAbsent(key, () => <_Candidate>[]).add(
          _Candidate(
            path: path,
            codec: details.codec,
            width: details.width,
            height: details.height,
          ),
        );
  }
  return buckets;
}

Future<_ProbedCandidate?> _probeCandidate(
  _Candidate candidate,
  String ffprobe, {
  required Duration timeout,
}) async {
  final probeResult = await _runFfprobe(
    ffprobe,
    <String>[
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-skip_frame',
      'nokey',
      '-show_entries',
      'stream=codec_name,width,height,bit_rate,duration:format=bit_rate,duration:frame=best_effort_timestamp_time',
      '-of',
      'json',
      '--',
      candidate.path,
    ],
    timeout: timeout,
  );
  if (probeResult == null || probeResult.exitCode != 0) return null;

  try {
    final streamJson = jsonDecode(probeResult.stdout);
    final streams = streamJson['streams'];
    if (streams is! List<dynamic> || streams.isEmpty) return null;
    final stream = streams.first;
    if (stream is! Map<String, dynamic>) return null;
    final codec = _normalizeCodec(stream['codec_name']?.toString());
    if (codec != candidate.codec ||
        stream['width'] != candidate.width ||
        stream['height'] != candidate.height) {
      return null;
    }
    final frames = streamJson['frames'];
    if (frames is! List<dynamic>) return null;
    final keyframes = <double>[];
    for (final frame in frames) {
      if (frame is! Map<String, dynamic>) continue;
      final time = _number(frame['best_effort_timestamp_time']);
      if (time != null) keyframes.add(time);
    }
    if (keyframes.length < 2) return null;
    var maxGopSeconds = 0.0;
    for (var index = 1; index < keyframes.length; index++) {
      final interval = keyframes[index] - keyframes[index - 1];
      if (interval > maxGopSeconds) maxGopSeconds = interval;
    }
    final gop = maxGopSeconds <= 1.1
        ? 'short-gop'
        : maxGopSeconds >= 4.0
            ? 'long-gop'
            : null;
    if (gop == null) return null;
    final bitrate = _number(stream['bit_rate']) ?? 0;
    final duration = _number(stream['duration']) ?? 0;
    return _ProbedCandidate(
      candidate: candidate,
      gop: gop,
      maxGopSeconds: double.parse(maxGopSeconds.toStringAsFixed(3)),
      bitrateKbps: double.parse((bitrate / 1000).toStringAsFixed(1)),
      durationSeconds: double.parse(duration.toStringAsFixed(3)),
    );
  } on Object {
    return null;
  }
}

/// 对 ffprobe 设置硬超时，避免一条超长媒体无限占用 P0 manifest 门禁。
Future<_ProbeProcessOutput?> _runFfprobe(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    runInShell: false,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill();
      return -1;
    },
  );
  final stdout = await stdoutFuture.timeout(
    const Duration(seconds: 2),
    onTimeout: () => '',
  );
  await stderrFuture.timeout(
    const Duration(seconds: 2),
    onTimeout: () => '',
  );
  if (timedOut) return null;
  return _ProbeProcessOutput(exitCode: exitCode, stdout: stdout);
}

/// 只把 Debug 可执行文件摘要写入 manifest；路径本身不进入报告或 stdout。
Future<String?> _sha256Of(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  } on Object {
    return null;
  }
}

double _bitrateOf(_ProbedCandidate candidate) => candidate.bitrateKbps;

String? _findLibraryDatabase(String? explicit) {
  if (explicit != null && File(explicit).existsSync()) return explicit;
  final roots = <String?>[
    Platform.environment['APPDATA'],
    Platform.environment['LOCALAPPDATA'],
  ];
  for (final root in roots) {
    if (root == null || root.trim().isEmpty) continue;
    final direct = File(
      <String>[
        root.trim(),
        'com.example',
        'local_tag_player',
        'LocalTagPlayer',
        'library.db',
      ].join(Platform.pathSeparator),
    );
    if (direct.existsSync()) return direct.path;
  }
  for (final root in roots) {
    if (root == null || root.trim().isEmpty) continue;
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    try {
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is File &&
            entity.path
                .replaceAll('\\', '/')
                .endsWith('/LocalTagPlayer/library.db') &&
            entity.existsSync()) {
          return entity.path;
        }
      }
    } on FileSystemException {
      // 其它应用目录无权读取时，继续尝试另一个已知数据根。
    }
  }
  return null;
}

_SampleDetails? _readDetails(String raw) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map<Object?, Object?>) return null;
    final codec = _normalizeCodec((json['videoCodec'] ?? '').toString());
    final width = json['width'];
    final height = json['height'];
    if (codec == null || width is! int || height is! int) return null;
    return _SampleDetails(codec: codec, width: width, height: height);
  } on Object {
    return null;
  }
}

String? _normalizeCodec(String? codec) {
  switch (codec?.trim().toLowerCase()) {
    case 'h264':
    case 'avc':
      return 'h264';
    case 'hevc':
    case 'h265':
    case 'hev1':
      return 'hevc';
    case 'av1':
      return 'av1';
    default:
      return null;
  }
}

String? _resolutionOf(int width, int height) {
  if (width == 1920 && height == 1080) return '1080p';
  if (width >= 3840 && height >= 2160) return '4k';
  return null;
}

int _defaultWidth(String resolution) => resolution == '4k' ? 3840 : 1920;

int _defaultHeight(String resolution) => resolution == '4k' ? 2160 : 1080;

int _budget(String resolution, String gop) {
  if (resolution == '1080p') return gop == 'short-gop' ? 500 : 1200;
  return gop == 'short-gop' ? 800 : 1800;
}

double? _number(Object? value) {
  if (value == null) return null;
  return double.tryParse(value.toString());
}

class _Candidate {
  const _Candidate({
    required this.path,
    required this.codec,
    required this.width,
    required this.height,
  });

  final String path;
  final String codec;
  final int width;
  final int height;
}

class _ProbedCandidate {
  const _ProbedCandidate({
    required this.candidate,
    required this.gop,
    required this.maxGopSeconds,
    required this.bitrateKbps,
    required this.durationSeconds,
  });

  final _Candidate candidate;
  final String gop;
  final double maxGopSeconds;
  final double bitrateKbps;
  final double durationSeconds;
}

class _ProbeProcessOutput {
  const _ProbeProcessOutput({required this.exitCode, required this.stdout});

  final int exitCode;
  final String stdout;
}

class _SampleDetails {
  const _SampleDetails({
    required this.codec,
    required this.width,
    required this.height,
  });

  final String codec;
  final int width;
  final int height;
}

class _Arguments {
  _Arguments(this.values);

  final List<String> values;

  String? value(String name) {
    final index = values.indexOf(name);
    if (index < 0 || index + 1 >= values.length) return null;
    return values[index + 1];
  }
}
