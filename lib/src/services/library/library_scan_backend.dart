import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/tag_rules.dart';
import '../../models/library_scan_models.dart';
import 'library_scan_service.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 一代目录扫描产生的不可变文件系统差量。
 *
 * 后端只陈述磁盘事实，不携带 manual 标签、收藏、播放记录等用户数据，也不写 SQLite。
 * stable identity、relink 唯一性和事务提交始终由 Dart Application 层决定。
 */
class LibraryScanDelta {
  LibraryScanDelta({
    required this.generationId,
    required Iterable<LibraryScannedVideo> added,
    required Iterable<LibraryScannedVideo> modified,
    required Iterable<String> seenPathKeys,
    required Iterable<String> scannedRootKeys,
    required this.unchangedCount,
    this.cancelled = false,
  })  : added = List<LibraryScannedVideo>.unmodifiable(added),
        modified = List<LibraryScannedVideo>.unmodifiable(modified),
        seenPathKeys = Set<String>.unmodifiable(seenPathKeys),
        scannedRootKeys = Set<String>.unmodifiable(scannedRootKeys);

  /** 调用方分配的扫描代次。 */
  final int generationId;

  /** 磁盘存在但已知索引中没有当前路径的条目。 */
  final List<LibraryScannedVideo> added;

  /** 当前路径已知，但文件元数据、路径上下文或 missing 状态发生变化的条目。 */
  final List<LibraryScannedVideo> modified;

  /** 本轮实际枚举到的全部视频路径 key。 */
  final Set<String> seenPathKeys;

  /** 本轮确认可访问并完成枚举的 root key。 */
  final Set<String> scannedRootKeys;

  /** 元数据未变化、无需提交数据库的条目数量。 */
  final int unchangedCount;

  /** 扫描是否因 generation 取消而提前结束。 */
  final bool cancelled;

  /** 需要 Application 层校验并提交的新增与修改条目。 */
  Iterable<LibraryScannedVideo> get changedEntries sync* {
    yield* added;
    yield* modified;
  }
}

/**
 * 文件系统扫描平台边界。
 *
 * 实现可以是 Dart 或 Rust，但只能读取目录、stat 和轻量 fingerprint；禁止直接访问 SQLite。
 */
abstract interface class LibraryScanBackend {
  /** 扫描 roots 并返回指定 [generationId] 的不可变差量。 */
  Future<LibraryScanDelta> scan({
    required int generationId,
    required List<String> roots,
    required Map<String, LibraryScanKnownMetadata> knownMetadata,
    LibraryScanProgressCallback? onProgress,
  });

  /** 取消尚未提交的指定代次；已返回的旧差量仍由 Application 层做二次代次校验。 */
  void cancelGeneration(int generationId);

  /** 暂停或恢复当前只读扫描；暂停不得丢弃已经发现的候选或重新开始扫描。 */
  Future<void> setPaused(bool paused);
}

/**
 * 现有 Dart 目录扫描器的契约适配器。
 *
 * 它是 Rust 后端接入前的行为基线，也是在原生组件不可用时的可回滚 fallback。
 */
class DartLibraryScanBackend implements LibraryScanBackend {
  DartLibraryScanBackend(
      {LibraryScanService service = const LibraryScanService()})
      : _service = service;

  /** 只读文件系统扫描服务。 */
  final LibraryScanService _service;

  /** 已取消且尚未结束的扫描代次。 */
  final Set<int> _cancelledGenerations = <int>{};

  /** 播放器占用磁盘期间阻止 Dart fallback 继续枚举或读取 fingerprint。 */
  bool _paused = false;

  /** 恢复扫描时唤醒全部等待中的代次。 */
  Completer<void>? _resumeCompleter;

  /** 每个 Dart 代次独立排除暂停时长，避免恢复后的 ETA 被播放时间污染。 */
  final Map<int, _LibraryScanRateEstimator> _progressEstimators =
      <int, _LibraryScanRateEstimator>{};

  @override
  Future<LibraryScanDelta> scan({
    required int generationId,
    required List<String> roots,
    required Map<String, LibraryScanKnownMetadata> knownMetadata,
    LibraryScanProgressCallback? onProgress,
  }) async {
    bool isCancelled() => _cancelledGenerations.contains(generationId);
    final progressEstimator = _LibraryScanRateEstimator();
    progressEstimator.setPaused(_paused);
    _progressEstimators[generationId] = progressEstimator;
    try {
      if (isCancelled()) {
        return LibraryScanDelta(
          generationId: generationId,
          added: const <LibraryScannedVideo>[],
          modified: const <LibraryScannedVideo>[],
          seenPathKeys: const <String>{},
          scannedRootKeys: const <String>{},
          unchangedCount: 0,
          cancelled: true,
        );
      }
      final snapshot = await _service.scanRoots(
        roots,
        generationId: generationId,
        knownMetadata: knownMetadata,
        isCancelled: isCancelled,
        waitIfPaused: _waitIfPaused,
        onProgress: onProgress == null
            ? null
            : (progress) => onProgress(progressEstimator.enrich(progress)),
      );
      if (snapshot.cancelled || isCancelled()) {
        return LibraryScanDelta(
          generationId: generationId,
          added: const <LibraryScannedVideo>[],
          modified: const <LibraryScannedVideo>[],
          seenPathKeys: snapshot.seenPathKeys,
          scannedRootKeys: snapshot.scannedRootKeys,
          unchangedCount: 0,
          cancelled: true,
        );
      }
      final added = <LibraryScannedVideo>[];
      final modified = <LibraryScannedVideo>[];
      var unchangedCount = 0;
      for (final item in snapshot.entries) {
        final known = knownMetadata[TagRules.pathKey(item.path)];
        if (known == null) {
          added.add(item);
        } else if (_hasChanged(known, item)) {
          modified.add(item);
        } else {
          unchangedCount++;
        }
      }
      return LibraryScanDelta(
        generationId: generationId,
        added: added,
        modified: modified,
        seenPathKeys: snapshot.seenPathKeys,
        scannedRootKeys: snapshot.scannedRootKeys,
        unchangedCount: unchangedCount,
      );
    } finally {
      _cancelledGenerations.remove(generationId);
      _progressEstimators.remove(generationId);
    }
  }

  @override
  void cancelGeneration(int generationId) {
    _cancelledGenerations.add(generationId);
    // Dart 代次可能正在等待播放让盘；取消必须先唤醒它，才能到达下一次 generation
    // 校验并退出，避免页面关闭或 root 变化后遗留永不完成的 Future。
    _paused = false;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  Future<void> setPaused(bool paused) async {
    if (_paused == paused) {
      return;
    }
    _paused = paused;
    for (final estimator in _progressEstimators.values) {
      estimator.setPaused(paused);
    }
    if (paused) {
      _resumeCompleter ??= Completer<void>();
    } else {
      final completer = _resumeCompleter;
      _resumeCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /** 只在文件边界等待，避免暂停发生在打开文件句柄或半条 fingerprint 中间。 */
  Future<void> _waitIfPaused() async {
    while (_paused) {
      await (_resumeCompleter ??= Completer<void>()).future;
    }
  }

  /** 比较会影响索引、folder 标签或媒体缓存有效性的文件系统字段。 */
  bool _hasChanged(
    LibraryScanKnownMetadata known,
    LibraryScannedVideo scanned,
  ) {
    return known.fileSize != scanned.fileSize ||
        known.modifiedMs != scanned.modifiedMs ||
        known.mediaFingerprint != scanned.mediaFingerprint ||
        known.rootPath != scanned.rootPath ||
        known.relativePath != scanned.relativePath ||
        known.isMissing;
  }
}

/** 创建当前平台的扫描后端；Rust 未就绪或单次失败时明确回退到 Dart 基线。 */
LibraryScanBackend createLibraryScanBackend() {
  final fallback = DartLibraryScanBackend();
  if (!Platform.isWindows) {
    return fallback;
  }
  return FallbackLibraryScanBackend(
    primary: RustProcessLibraryScanBackend(),
    fallback: fallback,
  );
}

/**
 * Windows Rust 扫描 sidecar 的进程适配器。
 *
 * sidecar 只接收 roots 与已知文件元数据，只返回文件系统快照；临时二进制输入文件随代次
 * 删除，Rust 进程不接触 SQLite。取消会终止对应进程，Application 仍会再次校验代次。
 */
class RustProcessLibraryScanBackend implements LibraryScanBackend {
  RustProcessLibraryScanBackend({File? executable})
      : _executableOverride = executable;

  /** 测试或嵌入式构建显式提供的 sidecar；生产默认从应用目录解析。 */
  final File? _executableOverride;

  /** 当前运行中的 generation 与只读扫描进程。 */
  final Map<int, Process> _processes = <int, Process>{};

  /** 每个 sidecar 的暂停标记；进程只在安全文件边界轮询该文件。 */
  final Map<int, File> _controlFiles = <int, File>{};

  /** 当前 sidecar 的进度估算器；暂停时间不计入速度与 ETA。 */
  final Map<int, _LibraryScanProgressEstimator> _progressEstimators =
      <int, _LibraryScanProgressEstimator>{};

  /** 已取消但进程尚未完全退出的 generation。 */
  final Set<int> _cancelledGenerations = <int>{};

  /** 新启动的 sidecar 是否应立即进入播放让盘状态。 */
  bool _paused = false;

  /** sidecar 固定随应用安装在可执行文件同目录。 */
  File get _executable =>
      _executableOverride ??
      File(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'ltp_rust_library_scan.exe',
        ),
      );

  /** 当前构建是否供应了 Rust 扫描 sidecar。 */
  bool get isAvailable => Platform.isWindows && _executable.existsSync();

  @override
  Future<LibraryScanDelta> scan({
    required int generationId,
    required List<String> roots,
    required Map<String, LibraryScanKnownMetadata> knownMetadata,
    LibraryScanProgressCallback? onProgress,
  }) async {
    if (!isAvailable) {
      throw StateError('rust library scan backend unavailable');
    }
    final inputFile = File(p.join(
      Directory.systemTemp.path,
      'ltp-scan-$generationId-${DateTime.now().microsecondsSinceEpoch}.bin',
    ));
    final controlFile = File('${inputFile.path}.pause');
    _controlFiles[generationId] = controlFile;
    await inputFile.writeAsBytes(
      _encodeKnownMetadata(knownMetadata),
      flush: true,
    );
    try {
      if (_cancelledGenerations.contains(generationId)) {
        return _cancelledDelta(generationId);
      }
      if (_paused) {
        await controlFile.writeAsString('', flush: true);
      }
      final orderedRoots = roots.toList()
        ..sort((a, b) => p.split(a).length.compareTo(p.split(b).length));
      final process = await Process.start(
        _executable.path,
        <String>[
          inputFile.path,
          '--control',
          controlFile.path,
          ...orderedRoots,
        ],
        mode: ProcessStartMode.normal,
      );
      _processes[generationId] = process;
      final progressEstimator = _LibraryScanProgressEstimator(generationId);
      progressEstimator.setPaused(_paused);
      _progressEstimators[generationId] = progressEstimator;
      final stdoutFuture = process.stdout.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, bytes) => builder..add(bytes),
      );
      // stderr 只承载不含路径的节流进度；持续排空也避免 sidecar 因管道写满而阻塞。
      final stderrFuture = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        final progress = progressEstimator.parse(line);
        if (progress != null) {
          onProgress?.call(progress);
        }
      });
      final exitCode = await process.exitCode;
      final output = (await stdoutFuture).takeBytes();
      await stderrFuture;
      if (_cancelledGenerations.contains(generationId)) {
        return _cancelledDelta(generationId);
      }
      if (exitCode != 0) {
        throw StateError('rust library scan exited with code $exitCode');
      }
      return _decodeSnapshot(
        generationId: generationId,
        roots: orderedRoots,
        knownMetadata: knownMetadata,
        bytes: output,
      );
    } finally {
      _processes.remove(generationId);
      _controlFiles.remove(generationId);
      _progressEstimators.remove(generationId);
      _cancelledGenerations.remove(generationId);
      try {
        if (await inputFile.exists()) {
          await inputFile.delete();
        }
      } catch (_) {
        // 临时协议文件清理失败不能改变已经完成的扫描事务语义。
      }
      try {
        if (await controlFile.exists()) {
          await controlFile.delete();
        }
      } catch (_) {
        // 暂停标记与输入协议一样属于可丢弃临时文件。
      }
    }
  }

  @override
  void cancelGeneration(int generationId) {
    _cancelledGenerations.add(generationId);
    _processes[generationId]?.kill();
  }

  @override
  Future<void> setPaused(bool paused) async {
    _paused = paused;
    for (final estimator in _progressEstimators.values) {
      estimator.setPaused(paused);
    }
    for (final controlFile in _controlFiles.values.toList()) {
      try {
        if (paused) {
          if (!await controlFile.exists()) {
            await controlFile.writeAsString('', flush: true);
          }
        } else if (await controlFile.exists()) {
          await controlFile.delete();
        }
      } catch (_) {
        // 单个标记写入失败不终止扫描；sidecar 仍保持只读且会正常完成。
      }
    }
  }

  /** 把已知索引编码为无依赖小端二进制协议，避免跨边界传递业务对象。 */
  Uint8List _encodeKnownMetadata(
      Map<String, LibraryScanKnownMetadata> metadata) {
    final output = BytesBuilder(copy: false)
      ..add(<int>[0x4c, 0x54, 0x50, 0x4b]);
    _addUint32(output, 1);
    _addUint32(output, metadata.length);
    for (final entry in metadata.entries) {
      _addString(output, entry.key);
      _addInt64(output, entry.value.fileSize ?? -1);
      _addInt64(output, entry.value.modifiedMs ?? -1);
      _addString(output, entry.value.mediaFingerprint ?? '');
    }
    return output.takeBytes();
  }

  /** 解码 Rust 快照并在 Dart 边界形成与基线实现一致的不可变差量。 */
  LibraryScanDelta _decodeSnapshot({
    required int generationId,
    required List<String> roots,
    required Map<String, LibraryScanKnownMetadata> knownMetadata,
    required Uint8List bytes,
  }) {
    final reader = _LibraryScanBinaryReader(bytes);
    if (reader.readAscii(4) != 'LTPS' || reader.readUint32() != 1) {
      throw const FormatException('invalid rust scan protocol');
    }
    final entries = <LibraryScannedVideo>[];
    final seen = <String>{};
    final scannedRoots = <String>{};
    while (true) {
      final recordType = reader.readUint8();
      if (recordType == 0) {
        break;
      }
      final rootIndex = reader.readUint32();
      if (rootIndex < 0 || rootIndex >= roots.length) {
        throw const FormatException('invalid rust scan root index');
      }
      final root = roots[rootIndex];
      if (recordType == 2) {
        scannedRoots.add(TagRules.pathKey(root));
        continue;
      }
      if (recordType != 1) {
        throw const FormatException('invalid rust scan record');
      }
      final path = reader.readString();
      final fileSize = reader.readInt64();
      final modifiedMs = reader.readInt64();
      final fingerprint = reader.readString();
      // 父子 root 重叠时只采用最上层 root 的第一次记录，避免同一路径重复形成修改差量。
      if (!seen.add(TagRules.pathKey(path))) {
        continue;
      }
      entries.add(LibraryScannedVideo(
        path: path,
        title: p.basenameWithoutExtension(path),
        folder: p.dirname(path),
        rootPath: root,
        relativePath: p.relative(path, from: root),
        tags: TagRules.parentTagsFor(root, path),
        childTags: TagRules.childTagsFor(root, path),
        fileSize: fileSize,
        modifiedMs: modifiedMs,
        mediaFingerprint: fingerprint,
      ));
    }
    return _deltaFromEntries(
      generationId: generationId,
      entries: entries,
      seenPathKeys: seen,
      scannedRootKeys: scannedRoots,
      knownMetadata: knownMetadata,
    );
  }

  /** 按现有索引把完整文件系统快照划分为 added/modified/unchanged。 */
  LibraryScanDelta _deltaFromEntries({
    required int generationId,
    required List<LibraryScannedVideo> entries,
    required Set<String> seenPathKeys,
    required Set<String> scannedRootKeys,
    required Map<String, LibraryScanKnownMetadata> knownMetadata,
  }) {
    final added = <LibraryScannedVideo>[];
    final modified = <LibraryScannedVideo>[];
    var unchangedCount = 0;
    for (final item in entries) {
      final known = knownMetadata[TagRules.pathKey(item.path)];
      if (known == null) {
        added.add(item);
      } else if (known.fileSize != item.fileSize ||
          known.modifiedMs != item.modifiedMs ||
          known.mediaFingerprint != item.mediaFingerprint ||
          known.rootPath != item.rootPath ||
          known.relativePath != item.relativePath ||
          known.isMissing) {
        modified.add(item);
      } else {
        unchangedCount++;
      }
    }
    return LibraryScanDelta(
      generationId: generationId,
      added: added,
      modified: modified,
      seenPathKeys: seenPathKeys,
      scannedRootKeys: scannedRootKeys,
      unchangedCount: unchangedCount,
    );
  }

  /** 创建取消结果，禁止不完整快照进入 Application 提交。 */
  LibraryScanDelta _cancelledDelta(int generationId) => LibraryScanDelta(
        generationId: generationId,
        added: const <LibraryScannedVideo>[],
        modified: const <LibraryScannedVideo>[],
        seenPathKeys: const <String>{},
        scannedRootKeys: const <String>{},
        unchangedCount: 0,
        cancelled: true,
      );

  void _addUint32(BytesBuilder output, int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  void _addInt64(BytesBuilder output, int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  void _addString(BytesBuilder output, String value) {
    final bytes = utf8.encode(value);
    _addUint32(output, bytes.length);
    output.add(bytes);
  }
}

/** 小端扫描协议读取器；所有越界都会转为格式错误，禁止部分结果提交。 */
class _LibraryScanBinaryReader {
  _LibraryScanBinaryReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int readUint8() {
    _require(1);
    return _bytes[_offset++];
  }

  int readUint32() {
    _require(4);
    final value = ByteData.sublistView(_bytes, _offset, _offset + 4)
        .getUint32(0, Endian.little);
    _offset += 4;
    return value;
  }

  int readInt64() {
    _require(8);
    final value = ByteData.sublistView(_bytes, _offset, _offset + 8)
        .getInt64(0, Endian.little);
    _offset += 8;
    return value;
  }

  String readAscii(int length) {
    _require(length);
    final value = ascii.decode(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return value;
  }

  String readString() {
    final length = readUint32();
    _require(length);
    final value = utf8.decode(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return value;
  }

  void _require(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('truncated rust scan protocol');
    }
  }
}

/**
 * Rust 优先、Dart 可回滚的扫描后端。
 *
 * Rust sidecar 缺失或单次失败时自动回退，不允许原生环境问题阻断媒体库差量同步。
 */
class FallbackLibraryScanBackend implements LibraryScanBackend {
  FallbackLibraryScanBackend({
    required this.primary,
    required this.fallback,
  });

  final RustProcessLibraryScanBackend primary;
  final LibraryScanBackend fallback;

  @override
  Future<LibraryScanDelta> scan({
    required int generationId,
    required List<String> roots,
    required Map<String, LibraryScanKnownMetadata> knownMetadata,
    LibraryScanProgressCallback? onProgress,
  }) async {
    if (primary.isAvailable) {
      try {
        return await primary.scan(
          generationId: generationId,
          roots: roots,
          knownMetadata: knownMetadata,
          onProgress: onProgress,
        );
      } catch (_) {
        if (primary._cancelledGenerations.contains(generationId)) {
          return primary._cancelledDelta(generationId);
        }
      }
    }
    return fallback.scan(
      generationId: generationId,
      roots: roots,
      knownMetadata: knownMetadata,
      onProgress: onProgress,
    );
  }

  @override
  void cancelGeneration(int generationId) {
    primary.cancelGeneration(generationId);
    fallback.cancelGeneration(generationId);
  }

  @override
  Future<void> setPaused(bool paused) async {
    await Future.wait(<Future<void>>[
      primary.setPaused(paused),
      fallback.setPaused(paused),
    ]);
  }
}

/** 把 Rust stderr 的无路径计数转换为带速度与 ETA 的进度快照。 */
class _LibraryScanProgressEstimator {
  _LibraryScanProgressEstimator(this.generationId);

  /** 当前扫描代次。 */
  final int generationId;

  Stopwatch? _fingerprintWatch;
  DateTime? _pausedAt;
  Duration _pausedDuration = Duration.zero;

  /** 更新暂停区间；重复调用保持幂等。 */
  void setPaused(bool paused) {
    if (paused) {
      _pausedAt ??= DateTime.now();
      return;
    }
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _pausedDuration += DateTime.now().difference(pausedAt);
      _pausedAt = null;
    }
  }

  /** 解析 `LTP_SCAN_PROGRESS|phase|processed|total` 固定协议。 */
  LibraryScanProgress? parse(String line) {
    final parts = line.split('|');
    if (parts.length != 4 || parts.first != 'LTP_SCAN_PROGRESS') {
      return null;
    }
    final phase = switch (parts[1]) {
      'discovering' => LibraryScanPhase.discovering,
      'fingerprinting' => LibraryScanPhase.fingerprinting,
      _ => null,
    };
    final processed = int.tryParse(parts[2]);
    final parsedTotal = int.tryParse(parts[3]);
    if (phase == null || processed == null || parsedTotal == null) {
      return null;
    }
    final total = parsedTotal < 0 ? null : parsedTotal;
    double? speed;
    Duration? remaining;
    if (phase == LibraryScanPhase.fingerprinting) {
      if (_fingerprintWatch == null) {
        _fingerprintWatch = Stopwatch()..start();
        _pausedDuration = Duration.zero;
        if (_pausedAt != null) {
          _pausedAt = DateTime.now();
        }
      }
      final currentPause = _pausedAt == null
          ? Duration.zero
          : DateTime.now().difference(_pausedAt!);
      final activeElapsed =
          _fingerprintWatch!.elapsed - _pausedDuration - currentPause;
      final seconds = activeElapsed.inMicroseconds / 1000000;
      if (_pausedAt == null && processed > 0 && seconds > 0) {
        speed = processed / seconds;
        if (total != null && speed > 0) {
          remaining = Duration(
            milliseconds:
                (((total - processed).clamp(0, total) / speed) * 1000).round(),
          );
        }
      }
    }
    return LibraryScanProgress(
      generationId: generationId,
      phase: phase,
      processed: processed,
      discovered: phase == LibraryScanPhase.discovering
          ? processed
          : (total ?? processed),
      total: total,
      itemsPerSecond: speed,
      estimatedRemaining: remaining,
      isPaused: _pausedAt != null,
    );
  }
}

/** 为 Dart fallback 进度补充排除播放暂停时间后的速度与 ETA。 */
class _LibraryScanRateEstimator {
  Stopwatch? _watch;
  DateTime? _pausedAt;
  Duration _pausedDuration = Duration.zero;

  /** 更新暂停区间；恢复后的速度只使用实际扫描时间。 */
  void setPaused(bool paused) {
    if (paused) {
      _pausedAt ??= DateTime.now();
      return;
    }
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _pausedDuration += DateTime.now().difference(pausedAt);
      _pausedAt = null;
    }
  }

  /** 保留阶段计数，并以实际运行时长重新计算 fingerprint 速度。 */
  LibraryScanProgress enrich(LibraryScanProgress progress) {
    if (progress.phase != LibraryScanPhase.fingerprinting) {
      return progress.copyWith(isPaused: _pausedAt != null);
    }
    if (_watch == null) {
      _watch = Stopwatch()..start();
      _pausedDuration = Duration.zero;
      if (_pausedAt != null) {
        _pausedAt = DateTime.now();
      }
    }
    final currentPause = _pausedAt == null
        ? Duration.zero
        : DateTime.now().difference(_pausedAt!);
    final activeElapsed = _watch!.elapsed - _pausedDuration - currentPause;
    final seconds = activeElapsed.inMicroseconds / 1000000;
    final speed = _pausedAt == null && progress.processed > 0 && seconds > 0
        ? progress.processed / seconds
        : null;
    final total = progress.total;
    return LibraryScanProgress(
      generationId: progress.generationId,
      phase: progress.phase,
      processed: progress.processed,
      discovered: progress.discovered,
      total: total,
      itemsPerSecond: speed,
      estimatedRemaining: speed == null || total == null || speed <= 0
          ? null
          : Duration(
              milliseconds:
                  ((((total - progress.processed).clamp(0, total)) / speed) *
                          1000)
                      .round(),
            ),
      isPaused: _pausedAt != null,
    );
  }
}
