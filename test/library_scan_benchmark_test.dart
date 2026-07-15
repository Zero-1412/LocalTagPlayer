import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 真实大库只读扫描基准。
 *
 * 测试只在显式环境开关下运行，并要求调用方先复制真实数据库到隔离 profile；扫描服务
 * 只读取 root、stat 与指纹样本，不调用 `LibraryScanCoordinator`，因此不会写回 SQLite。
 */
void main() {
  final enabled =
      Platform.environment['LOCAL_TAG_PLAYER_SCAN_BENCHMARK'] == '1';
  test(
    'benchmarks indexed load, directory walk, stat and fingerprint throughput',
    () async {
      DynamicLibrary.open(
        File('windows/tools/sqlite/sqlite3.dll').absolute.path,
      );
      sqfliteFfiInit();
      final paths = AppPaths();
      final databaseProvider = SqfliteDatabaseProvider(
        paths: paths,
        factory: databaseFactoryFfi,
      );
      final outputPath =
          Platform.environment['LOCAL_TAG_PLAYER_SCAN_BENCHMARK_OUTPUT'];
      expect(outputPath, isNotNull);
      final rustExecutable = <File>[
        File('build/windows/x64/runner/Debug/ltp_rust_library_scan.exe')
            .absolute,
        File(
          'windows/rust_library_scan/target/release/ltp_rust_library_scan.exe',
        ).absolute,
      ].firstWhere(
        (candidate) => candidate.existsSync(),
        orElse: () => File('ltp_rust_library_scan.exe').absolute,
      );
      final rustBackend = Platform.isWindows && rustExecutable.existsSync()
          ? RustProcessLibraryScanBackend(executable: rustExecutable)
          : null;

      final loadWatch = Stopwatch()..start();
      final store = await LibraryStore.load(
        scanBackend: rustBackend ?? DartLibraryScanBackend(),
        databaseProvider: databaseProvider,
      );
      loadWatch.stop();
      addTearDown(store.close);
      expect(store.videos.length, greaterThanOrEqualTo(11000));

      final service = const LibraryScanService();
      final enumerateWatch = Stopwatch()..start();
      final enumerated = await service.countUntrackedVideos(
        store.roots,
        const <String>{},
      );
      enumerateWatch.stop();

      final timerGaps = <int>[];
      var previousTick = DateTime.now();
      final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final now = DateTime.now();
        timerGaps.add(now.difference(previousTick).inMicroseconds);
        previousTick = now;
      });
      final scanWatch = Stopwatch()..start();
      final result = await service.scanRoots(store.roots);
      scanWatch.stop();

      final knownMetadata = <String, LibraryScanKnownMetadata>{
        for (final item in store.videos.values)
          TagRules.pathKey(item.path): LibraryScanKnownMetadata(
            fileSize: item.fileSize,
            modifiedMs: item.modifiedMs,
            mediaFingerprint: item.mediaFingerprint,
            rootPath: item.rootPath,
            relativePath: item.relativePath,
            isMissing: item.isMissing,
          ),
      };
      final indexedScanWatch = Stopwatch()..start();
      final indexedResult = await service.scanRoots(
        store.roots,
        knownMetadata: knownMetadata,
      );
      indexedScanWatch.stop();

      LibraryScanDelta? rustDelta;
      Duration? rustElapsed;
      Duration? rustDiscoveryElapsed;
      Duration? rustFingerprintElapsed;
      LibraryScanProgress? rustFinalProgress;
      LibraryScanCommitResult? rustInitialCommit;
      Duration? rustInitialCommitElapsed;
      LibraryScanCommitResult? rustSteadyCommit;
      Duration? rustSteadyElapsed;
      if (rustBackend != null) {
        final forceFingerprint = Platform.environment[
                'LOCAL_TAG_PLAYER_SCAN_BENCHMARK_FORCE_FINGERPRINT'] ==
            '1';
        final progressWatch = Stopwatch()..start();
        var phaseStartedAt = Duration.zero;
        LibraryScanPhase? activePhase;
        final rustWatch = Stopwatch()..start();
        rustDelta = await rustBackend.scan(
          generationId: 1,
          roots: store.roots,
          knownMetadata: forceFingerprint
              ? const <String, LibraryScanKnownMetadata>{}
              : knownMetadata,
          onProgress: (progress) {
            if (activePhase != progress.phase) {
              final now = progressWatch.elapsed;
              if (activePhase == LibraryScanPhase.discovering) {
                rustDiscoveryElapsed = now - phaseStartedAt;
              } else if (activePhase == LibraryScanPhase.fingerprinting) {
                rustFingerprintElapsed = now - phaseStartedAt;
              }
              activePhase = progress.phase;
              phaseStartedAt = now;
            }
            rustFinalProgress = progress;
          },
        );
        rustWatch.stop();
        rustElapsed = rustWatch.elapsed;
        final finishedAt = progressWatch.elapsed;
        if (activePhase == LibraryScanPhase.discovering) {
          rustDiscoveryElapsed = finishedAt - phaseStartedAt;
        } else if (activePhase == LibraryScanPhase.fingerprinting) {
          rustFingerprintElapsed = finishedAt - phaseStartedAt;
        }

        // 只写隔离数据库副本：首轮提交统一 root 层级，第二轮测量真正稳定态差量。
        final initialCommitWatch = Stopwatch()..start();
        rustInitialCommit = await store.scanWithChanges();
        initialCommitWatch.stop();
        rustInitialCommitElapsed = initialCommitWatch.elapsed;
        final steadyWatch = Stopwatch()..start();
        rustSteadyCommit = await store.scanWithChanges();
        steadyWatch.stop();
        rustSteadyElapsed = steadyWatch.elapsed;
      }
      timer.cancel();

      final sortedGaps = timerGaps..sort();
      int percentileGap(double percentile) => sortedGaps.isEmpty
          ? 0
          : sortedGaps[math.min(
              sortedGaps.length - 1,
              (sortedGaps.length * percentile).floor(),
            )];
      final sampledBytes = result.entries.fold<int>(
        0,
        (sum, item) => sum + math.min(item.fileSize, 8192),
      );
      final scanSeconds = scanWatch.elapsedMicroseconds / 1000000;
      final summary = <String, Object?>{
        'indexedRecords': store.videos.length,
        'roots': store.roots.length,
        'databaseLoadMs': loadWatch.elapsedMilliseconds,
        'enumeratedVideos': enumerated,
        'directoryWalkMs': enumerateWatch.elapsedMilliseconds,
        'scannedVideos': result.entries.length,
        'fullScanMs': scanWatch.elapsedMilliseconds,
        'indexedScanVideos': indexedResult.entries.length,
        'indexedScanMs': indexedScanWatch.elapsedMilliseconds,
        if (rustDelta != null) ...<String, Object?>{
          'rustScanMs': rustElapsed!.inMilliseconds,
          'rustDiscoveryMs': rustDiscoveryElapsed?.inMilliseconds,
          'rustFingerprintMs': rustFingerprintElapsed?.inMilliseconds,
          'rustFingerprintProcessed': rustFinalProgress?.processed,
          'rustFingerprintTotal': rustFinalProgress?.total,
          'rustForcedFingerprint': Platform.environment[
                  'LOCAL_TAG_PLAYER_SCAN_BENCHMARK_FORCE_FINGERPRINT'] ==
              '1',
          'rustAdded': rustDelta.added.length,
          'rustModified': rustDelta.modified.length,
          'rustUnchanged': rustDelta.unchangedCount,
          'rustInitialCommitMs': rustInitialCommitElapsed!.inMilliseconds,
          'rustInitialModified': rustInitialCommit!.modifiedCount,
          'rustInitialRelinked': rustInitialCommit.relinkedCount,
          'rustInitialMissing': rustInitialCommit.missingCount,
          'rustSteadyEndToEndMs': rustSteadyElapsed!.inMilliseconds,
          'rustSteadyModified': rustSteadyCommit!.modifiedCount,
          'rustSteadyAdded': rustSteadyCommit.addedCount,
          'rustSteadyMissing': rustSteadyCommit.missingCount,
        },
        'entriesPerSecond': scanSeconds == 0
            ? 0
            : double.parse(
                (result.entries.length / scanSeconds).toStringAsFixed(1),
              ),
        'fingerprintSampleMiB':
            double.parse((sampledBytes / 1048576).toStringAsFixed(1)),
        'fingerprintSampleMiBPerSecond': scanSeconds == 0
            ? 0
            : double.parse(
                (sampledBytes / 1048576 / scanSeconds).toStringAsFixed(2),
              ),
        'eventLoopGapP95Ms':
            double.parse((percentileGap(0.95) / 1000).toStringAsFixed(2)),
        'eventLoopGapMaxMs': sortedGaps.isEmpty
            ? 0
            : double.parse((sortedGaps.last / 1000).toStringAsFixed(2)),
      };
      await File(outputPath!).writeAsString(
        const JsonEncoder.withIndent('  ').convert(summary),
      );
      // 输出只包含数量与耗时，不包含媒体路径、标题或标签。
      // ignore: avoid_print
      print('LTP_SCAN_BENCHMARK ${jsonEncode(summary)}');
    },
    skip: enabled ? false : '仅由显式真实媒体库基准命令启用',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
