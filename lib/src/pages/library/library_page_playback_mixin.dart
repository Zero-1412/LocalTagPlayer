import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/tag_rules.dart';
import '../../features/library/application/library_file_command_executor.dart';
import '../../features/library/application/library_playback_queue_controller.dart';
import '../../features/library/application/library_revision_tracker.dart';
import '../../features/library/domain/library_query_snapshot.dart';
import '../../models/media_details.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/library_playback_background_gate.dart';
import '../../services/library/library_scan_playback_gate.dart';
import '../../services/player/playback_snapshot_write_queue.dart';
import '../../services/player/player_hardware_compatibility.dart';
import '../../services/player/player_memory_diagnostics.dart';
import '../player/player_hardware_decode_warning_dialog.dart';
import '../player/player_page.dart';
import 'missing_relink_page.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPagePlaybackMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPagePlaybackMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  /**
   * 从相似候选组建立显式的独立播放来源。
   *
   * 该入口不读取全库或当前媒体库筛选结果；[playlist] 必须来自相似页当前展示的候选组，
   * 再经同一 PlaybackQueueController 固化为 PlayerPage 可消费的快照。
   */
  @override
  Future<void> playSimilarVideo(
    VideoItem item,
    List<VideoItem> playlist, {
    VoidCallback? onRouteReturned,
  }) async {
    final store = runtime.store;
    if (store == null || playlist.isEmpty) {
      return;
    }
    final epoch = LibraryResultEpoch.fromQuery(
      dataRevision: runtime.libraryDataRevision,
      query: const FilterQuery(),
      presentationSort: 'similarity:title:path',
    );
    final result = runtime.playbackQueueController.acceptDisplayedResult(
      source: LibraryResultSource.similarity,
      acceptedLibraryEpoch: epoch,
      displayedVideos: playlist,
      totalCount: playlist.length,
      dataRevision: runtime.libraryDataRevision,
      playbackDataRevision: runtime.playbackDataRevision,
      sortFingerprint: 'similarity:title:path',
    );
    await openVideo(
      item,
      playlist,
      result,
      '相似候选',
      onPlayerRouteReturned: onRouteReturned,
    );
  }

  Future<void> openVideo(
    VideoItem item,
    List<VideoItem> playlist,
    LibraryResultSnapshot acceptedResult,
    String acceptedQueueTitle, {
    VoidCallback? onPlayerRouteReturned,
  }) async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final selection = runtime.playbackQueueController.prepareSelection(
      result: acceptedResult,
      acceptedVideos: playlist,
      selectedVideoId: item.videoId,
    );
    if (selection == null) {
      debugPrint('PLAYER_QUEUE_REJECTED reason=stale_result');
      return;
    }
    final preparedQueue = selection.queue;
    final selectedItem = selection.selectedItem;
    if (runtime.playbackSettings.autoRemoveMissingOrUnreadableVideos &&
        !await fileSystem.fileExists(selectedItem.path)) {
      // 点击与后台清理可能竞态；播放前再次确认路径，失效时只删数据库记录并阻止进入错误页。
      await store.deleteVideo(selectedItem.path);
      if (mounted) {
        markLibraryDataChanged(
          tagDefinitionsChanged: true,
          removedVideoIds: <String>[selectedItem.videoId],
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('路径已失效，已从媒体库移除记录')),
        );
      }
      return;
    }
    final scanWasActive = runtime.isScanning;
    final scanWasAlreadyPaused = runtime.scanProgress?.isPaused ?? false;
    await const LibraryScanPlaybackGate().run<void>(
      scanActive: scanWasActive,
      scanAlreadyPaused: scanWasAlreadyPaused,
      setPaused: store.setScanPaused,
      onPauseChanged: (paused) {
        runtime.scanLifecycleController.publishPlaybackPause(
          paused: paused,
          onChanged: (_) {
            if (mounted) {
              setState(() {});
            }
          },
        );
      },
      // 在预检、缩略图预热和播放器解码开始前先让 sidecar 停在文件边界，避免
      // 机械盘随机 fingerprint 读取与当前视频顺序读取互相拖死。
      action: () => openVideoAfterScanYield(
        selectedItem,
        preparedQueue,
        acceptedQueueTitle,
        onPlayerRouteReturned: onPlayerRouteReturned,
      ),
    );
  }

  /** 在扫描已让出磁盘后执行既有预检、队列预热和 filtered queue 播放链路。 */
  Future<void> openVideoAfterScanYield(
    VideoItem item,
    LibraryPlaybackQueue preparedQueue,
    String queueTitle, {
    VoidCallback? onPlayerRouteReturned,
  }) async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final playlist = preparedQueue.videos;
    var playbackDetails = item.mediaDetails;
    if (Platform.isWindows &&
        runtime.playbackSettings.hardwareDecodingEnabled &&
        (playbackDetails?.videoCodec == null ||
            playbackDetails?.width == null ||
            playbackDetails?.height == null)) {
      playbackDetails = await probeSelectedVideoBeforePlayback(item, store);
      if (!mounted) {
        return;
      }
      if (playbackDetails.videoCodec == null ||
          playbackDetails.width == null ||
          playbackDetails.height == null) {
        // 未知超规格媒体曾绕过兼容矩阵并在创建 8K 纹理时推高内存甚至崩溃。
        // 规格未确认前宁可让用户稍后重试，也不创建不可控的原生播放器会话。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('尚未取得视频编码和分辨率，已暂缓播放；请等待解析完成后重试。'),
          ),
        );
        return;
      }
    }
    final compatibility = PlayerHardwareCompatibility.assess(
      details: playbackDetails,
      settings: runtime.playbackSettings,
    );
    if (compatibility.status == HardwareDecodeCompatibilityStatus.unsupported) {
      // 兼容结论来自 hydration 缓存或当前点击项的单次预检；取消前不创建播放器或预热队列。
      debugPrint(
        'PLAYER_PREFLIGHT_BLOCKED video_id=${item.videoId} '
        'spec=${compatibility.specification}',
      );
      final confirmed = await showPlayerHardwareDecodeWarningDialog(
        context,
        compatibility,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    final thumbnailService = runtime.thumbnailService!;
    final activeChildTag = runtime.selectedChildTags.isEmpty
        ? null
        : runtime.selectedChildTags.first;
    // 在路由切换前把当前项附近已经生成的缩略图提升到同步内存视图，播放器队列
    // 首帧可直接复用，不需要先绘制占位底色再等待异步 Future 完成。
    await runtime.playbackQueueController.warmNearby(
      queue: preparedQueue,
      selectedVideoId: item.videoId,
      load: thumbnailService.thumbnailFor,
    );
    if (!mounted) {
      return;
    }
    final backgroundGate = LibraryPlaybackBackgroundGate(
      thumbnailService: thumbnailService,
      mediaDetailsService: runtime.libraryMediaDetailsService,
      similarityScanController: runtime.similarityScanController,
    )..enter();
    runtime.playerScopedLibraryDataChanged = false;
    runtime.playerScopedNeedsCountRefresh = false;
    runtime.playerScopedTagDefinitionsChanged = false;
    runtime.playerScopedRemovedVideoIds.clear();
    final playerDisposed = Completer<void>();
    runtime.latestPlayerRelease = playerDisposed.future;
    // 备份只做 SQLite 小批次，但播放器仍优先；等待当前批次结束后再创建解码会话。
    await store.pauseDataBackupForPlayback();
    if (!mounted) {
      store.resumeDataBackupAfterPlayback();
      backgroundGate.restore();
      return;
    }
    setState(() => runtime.playerRouteActive = true);
    // 先让媒体库提交 ExcludeSemantics，再压入不透明播放器 Route；否则底层 Route
    // 可能在本次 rebuild 前进入 offstage，让 Windows UIA 继续缓存旧页面节点。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      backgroundGate.restore();
      store.resumeDataBackupAfterPlayback();
      return;
    }
    try {
      await Navigator.of(context).push(
        smoothRoute<void>(
          PlayerPage(
            initialItem: item,
            playlist: playlist,
            queueSnapshot: preparedQueue.snapshot,
            thumbnailService: thumbnailService,
            playbackSettings: runtime.playbackSettings,
            onPlaybackSettingsChanged: (settings) async {
              // 播放器内先更新应用级快照，使下一次进入立即沿用，再写入持久化文件。
              if (mounted) {
                setState(() => runtime.playbackSettings = settings);
              }
              await applicationService.savePlaybackSettings(settings);
            },
            activeTags: runtime.selectedTags.toList()..sort(),
            activeChildTag: activeChildTag,
            queueTitle: queueTitle,
            onDeleteVideo: deleteVideoFromPlayer,
            onToggleFavorite: toggleFavoriteFromPlayer,
            onRenameFile: renameVideoFromPlayer,
            onEditManualTags: editManualTagsFromPlayer,
            onRelinkMissing: relinkMissingFromPlayer,
            onPlaybackProgressUpdated: updatePlaybackProgress,
            onMediaDetailsUpdated: updateMediaDetails,
            disposalCompleter: playerDisposed,
            fileSystem: fileSystem,
            playerServiceFactory: playerServiceFactory,
            mediaProbeBackendFactory: mediaProbeBackendFactory,
            fullscreenSessionController: runtime.playerFullscreenSession,
          ),
        ),
      );
      // 播放器 Route 已返回，调用方可立即恢复动作状态；原生资源释放和进度刷盘仍在 finally 中继续。
      onPlayerRouteReturned?.call();
    } finally {
      if (mounted) {
        // 反向 Route 已完成后立即恢复媒体库语义，不等待原生资源释放尾部。
        setState(() => runtime.playerRouteActive = false);
      }
      // 路由返回不代表 media_kit 原生线程已释放；等待完成信号再恢复后台任务。
      await playerDisposed.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
      unawaited(sampleMemoryAfterPlayerRelease());
      await runtime.playbackSnapshotQueue?.flush();
      final snapshotError = runtime.playbackSnapshotQueue?.takeLastError();
      if (snapshotError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('部分播放进度保存失败，请稍后重试')),
        );
      }
      backgroundGate.restore();
      store.resumeDataBackupAfterPlayback();
    }
    if (mounted && runtime.playerScopedLibraryDataChanged) {
      final removedVideoIds = Set<String>.of(
        runtime.playerScopedRemovedVideoIds,
      );
      runtime.pendingResultDeltaVideoIds.addAll(removedVideoIds);
      runtime.pendingRemovedVideoIds.addAll(removedVideoIds);
      runtime.libraryRevisionTracker.record(
        runtime.playerScopedTagDefinitionsChanged
            ? LibraryDataChangeKind.tagDefinitions
            : LibraryDataChangeKind.content,
      );
      invalidateDerivedCaches();
      scheduleFilterRefresh(
        refreshCounts: runtime.playerScopedNeedsCountRefresh,
        removedVideoIds: removedVideoIds.isEmpty ? null : removedVideoIds,
      );
      runtime.playerScopedLibraryDataChanged = false;
      runtime.playerScopedNeedsCountRefresh = false;
      runtime.playerScopedTagDefinitionsChanged = false;
      runtime.playerScopedRemovedVideoIds.clear();
    }
  }

  /**
   * 为用户刚点击且详情未知的视频执行一次独立高优先级预检。
   *
   * 后台批量探测可能排在数千条记录之后，不能让未知 8K 媒体绕过播放前兼容矩阵。
   * 该服务只处理当前一项并在返回后取消代次；播放器页面和右侧队列仍只读缓存详情。
   */
  Future<MediaDetails> probeSelectedVideoBeforePlayback(
    VideoItem item,
    LibraryApplicationFacade store,
  ) async {
    final service = applicationService.createMediaDetailsService(
      onUpdated: (updated, details, fingerprint) async {
        final current = store.videos[TagRules.pathKey(updated.path)];
        if (runtime.store != store ||
            current == null ||
            current.videoId != updated.videoId ||
            current.mediaFingerprint != fingerprint) {
          return;
        }
        current.mediaDetails = details;
        final duration = details.duration;
        if (duration != null && duration > Duration.zero) {
          current.playbackDuration = duration;
        }
        await store.upsertVideo(current);
      },
    );
    try {
      return await service.detailsFor(item, refreshIncomplete: true).timeout(
            const Duration(seconds: 5),
            onTimeout: () => const MediaDetails(),
          );
    } finally {
      service.dispose();
    }
  }

  /** 返回媒体库后分三次采样，观察原生纹理释放与 Flutter ImageCache 的衰减是否同步。 */
  Future<void> sampleMemoryAfterPlayerRelease() async {
    await PlayerMemoryDiagnostics.logStage('library_after_release_0ms');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await PlayerMemoryDiagnostics.logStage('library_after_release_500ms');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await PlayerMemoryDiagnostics.logStage('library_after_release_2000ms');
  }

  /** 播放器内收藏只写当前视频，返回媒体库后再做一次无计数轻刷新。 */
  Future<void> toggleFavoriteFromPlayer(VideoItem item) async {
    item.isFavorite = !item.isFavorite;
    await runtime.store?.upsertVideo(item);
    runtime.playerScopedLibraryDataChanged = true;
  }

  /** 将播放位置和最近播放时间写入稳定 videoId 对应的视频记录。 */
  Future<void> updatePlaybackProgress(
    VideoItem item,
    Duration position,
    Duration duration,
    bool completed,
  ) async {
    item.playbackPosition = position;
    if (duration > Duration.zero) {
      // 播放内核偶发的临时 0 时长不能覆盖已经持久化的可靠总时长与完成判断。
      item.playbackDuration = duration;
      item.playbackCompleted = completed;
    }
    final updatedAt = DateTime.now();
    item.playbackPositionUpdatedAt = updatedAt;
    item.lastPlayedAt = updatedAt;
    runtime.playbackSnapshotQueue?.enqueue(PlaybackSnapshot(
      item: item,
      position: item.playbackPosition,
      duration: item.playbackDuration,
      completed: item.playbackCompleted,
      updatedAt: updatedAt,
    ));
    if (mounted) {
      markPlaybackTimestampChanged(item);
    }
  }

  /** 播放器错误面板复用 missing 管理页的安全 picker 与 fingerprint 校验。 */
  Future<bool> relinkMissingFromPlayer(VideoItem item) async {
    final store = runtime.store;
    if (store == null) {
      return false;
    }
    final result = await pickAndRelinkMissingVideo(
      context,
      store: store,
      fileSystem: fileSystem,
      item: item,
    );
    if (result?.changed == true) {
      runtime.playerScopedLibraryDataChanged = true;
      runtime.playerScopedNeedsCountRefresh = true;
      runtime.playerScopedTagDefinitionsChanged = true;
    }
    return result?.changed ?? false;
  }

  /** 播放器内改名成功后延迟到 Route 返回再刷新媒体库，避免后台页面重建。 */
  Future<void> renameVideoFromPlayer(
    VideoItem item,
    String newBaseName,
  ) async {
    await renameVideoPath(item, newBaseName);
    runtime.playerScopedLibraryDataChanged = true;
  }

  /**
   * 执行同目录文件重命名，并以同一 videoId 提交新的 mutable path。
   *
   * 文件系统先拒绝覆盖并完成物理改名；SQLite 提交失败时立即尝试恢复原名，避免磁盘与
   * 媒体库索引分叉。调用方只负责选择立即刷新或延迟到播放器 Route 返回后刷新。
   */
  Future<void> renameVideoPath(
    VideoItem item,
    String newBaseName,
  ) async {
    final store = runtime.store;
    if (store == null) {
      throw StateError('媒体库尚未就绪，请稍后重试');
    }
    await runtime.fileCommandExecutor.rename(
      RenameVideoFileCommand(
        item: item,
        newBaseName: newBaseName,
      ),
      normalizePath: fileSystem.normalizePath,
      parentPath: fileSystem.parentPath,
      joinPath: fileSystem.joinPath,
      fileExists: fileSystem.fileExists,
      renameFile: fileSystem.renameFile,
      commitRenamedPath: store.renameVideoPath,
    );
  }

  Future<void> toggleFavorite(VideoItem item) async {
    setState(() => item.isFavorite = !item.isFavorite);
    await runtime.store?.upsertVideo(item);
    if (mounted) {
      markLibraryDataChanged();
    }
  }

  /** 通过共享文件系统平台边界定位视频；页面不拼接 Windows 或其它平台命令。 */
  @override
  Future<void> revealVideoLocation(VideoItem item) async {
    final revealed = await runtime.fileCommandExecutor.reveal(
      RevealVideoLocationCommand(item),
      revealInFileManager: fileSystem.revealInFileManager,
    );
    if (!revealed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开文件位置，请确认文件仍然存在')),
      );
    }
  }

  Future<void> updateMediaDetails(
    VideoItem item,
    MediaDetails details,
    String? fingerprint,
  ) async {
    item.mediaDetails = details;
    final duration = details.duration;
    if (duration != null && duration > Duration.zero) {
      item.playbackDuration = duration;
    }
    item.mediaFingerprint = fingerprint ?? item.mediaFingerprint;
    await runtime.store?.upsertVideo(item);
    if (mounted) {
      markLibraryDataChanged();
    }
  }

  /** 执行播放器弹窗已经确认的删除选择，真实文件删除始终留在平台边界内。 */
}
