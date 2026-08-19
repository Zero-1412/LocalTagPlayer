import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 从当前 Local Tag Player 资料库只读选择一个可用于桌面像素 QA 的本地 4K 样本。
// 工具绝不把媒体路径、标题、videoId 或标签打印到 stdout；仅把调用方明确指定的私有
// `.local` 选择文件写入绝对样本路径，方便后续 PowerShell 直接传给 Debug QA。数据库
// 以 readOnly 模式打开，且不会修改播放进度、缓存或资料库数据。
Future<void> main(List<String> arguments) async {
  final parser = _Arguments(arguments);
  final output = parser.value('--selection-output');
  if (output == null || output.trim().isEmpty) {
    stderr.writeln('缺少 --selection-output；该文件必须位于调用方私有 QA 输出目录。');
    exitCode = 64;
    return;
  }
  final requestedCodec = parser.value('--codec')?.trim().toLowerCase();
  if (requestedCodec != null &&
      requestedCodec.isNotEmpty &&
      !const <String>{'h264', 'hevc', 'av1'}.contains(requestedCodec)) {
    stderr.writeln('--codec 仅接受 h264、hevc 或 av1。');
    exitCode = 64;
    return;
  }

  final explicitDatabase = parser.value('--database')?.trim();
  final databasePath =
      explicitDatabase != null && File(explicitDatabase).existsSync()
          ? explicitDatabase
          : _findLibraryDatabase();
  if (databasePath == null) {
    stderr.writeln('未找到当前用户的 LocalTagPlayer library.db。');
    exitCode = 2;
    return;
  }

  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    final rows = await database.rawQuery(
      '''
SELECT path, media_details_json
FROM videos
WHERE is_missing = 0
  AND media_details_json IS NOT NULL
ORDER BY last_played_at DESC, added_at DESC
''',
    );
    final candidates = <_Candidate>[];
    for (final row in rows) {
      final path = row['path'] as String?;
      final detailsText = row['media_details_json'] as String?;
      if (path == null || detailsText == null || !File(path).existsSync()) {
        continue;
      }
      final details = _readDetails(detailsText);
      if (details == null || details.width < 3840 || details.height < 2160) {
        continue;
      }
      if (requestedCodec != null && details.codec != requestedCodec) {
        continue;
      }
      candidates.add(_Candidate(path: path, details: details));
    }
    if (candidates.isEmpty) {
      stderr.writeln(
        requestedCodec == null
            ? '资料库中没有可读取的 4K H.264/HEVC/AV1 样本。'
            : '资料库中没有可读取的 4K $requestedCodec 样本。',
      );
      exitCode = 3;
      return;
    }
    final selected = candidates.first;
    final destination = File(output);
    await destination.parent.create(recursive: true);
    await destination.writeAsString('${selected.path}\n', flush: true);
    // 不打印路径、文件名、时长或其他可关联用户媒体的标识。
    stdout.writeln(
      'PLAYER_QA_SAMPLE_SELECTED codec=${selected.details.codec} '
      'resolution=${selected.details.width}x${selected.details.height} '
      'candidates=${candidates.length} database=readonly',
    );
  } finally {
    await database.close();
  }
}

String? _findLibraryDatabase() {
  final roots = <String?>[
    Platform.environment['APPDATA'],
    Platform.environment['LOCALAPPDATA'],
  ];
  // Windows path_provider 的 application support 目录通常保留 Flutter package
  // 名称（例如 com.example/local_tag_player），而不是直接位于 AppData 根下。
  // 先检查确定的官方目录，避免为一次只读 QA 样本选择递归遍历整个用户 AppData，
  // 导致探针在真正启动前被无关缓存拖慢。
  for (final root in roots) {
    if (root == null || root.trim().isEmpty) continue;
    final directCandidate = File(
      '${root.trim()}${Platform.pathSeparator}com.example'
      '${Platform.pathSeparator}local_tag_player${Platform.pathSeparator}'
      'LocalTagPlayer${Platform.pathSeparator}library.db',
    );
    if (directCandidate.existsSync()) return directCandidate.path;
  }
  for (final root in roots) {
    if (root == null || root.trim().isEmpty) continue;
    final rootDirectory = Directory(root);
    if (!rootDirectory.existsSync()) continue;
    try {
      for (final entity in rootDirectory.listSync(recursive: true)) {
        if (entity is File &&
            entity.path
                .replaceAll('\\', '/')
                .endsWith('/LocalTagPlayer/library.db') &&
            entity.existsSync()) {
          return entity.path;
        }
      }
    } on FileSystemException {
      // 用户配置目录可能含无权读取的其它应用子树；跳过后继续本机另一个数据根。
    }
  }
  return null;
}

_SampleDetails? _readDetails(String raw) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map<Object?, Object?>) return null;
    final codec = (json['videoCodec'] ?? '').toString().trim().toLowerCase();
    final width = json['width'];
    final height = json['height'];
    final normalizedCodec = switch (codec) {
      'h264' || 'avc' => 'h264',
      'hevc' || 'h265' || 'hev1' => 'hevc',
      'av1' => 'av1',
      _ => '',
    };
    if (normalizedCodec.isEmpty || width is! int || height is! int) return null;
    return _SampleDetails(
      codec: normalizedCodec,
      width: width,
      height: height,
    );
  } catch (_) {
    return null;
  }
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

class _Candidate {
  const _Candidate({required this.path, required this.details});

  final String path;
  final _SampleDetails details;
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
