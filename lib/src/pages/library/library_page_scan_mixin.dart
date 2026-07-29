import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/tag_rules.dart';
import '../../models/library_scan_models.dart';
import '../../models/video_item.dart';
import '../../platform/file_system_adapter.dart';
import '../../services/library/library_application_facade.dart';
import '../../services/library/library_scan_ui_diagnostics.dart';
import '../../services/media/media_details_service.dart';
import '../../services/tags/tag_query_service.dart';
import 'library_page_helpers.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageScanMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageScanMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  @override
  Future<void> pickFolder() async {
    final store = runtime.store;
    final paths = await fileSystem.pickDirectories(
      dialogTitle: '\u9009\u62e9\u89c6\u9891\u76ee\u5f55',
      initialDirectory: preferredLibraryPickerDirectory(
        currentPath: runtime.localLibraryPath,
        roots: store?.roots ?? const <String>[],
      ),
    );
    final path = paths.isEmpty ? null : paths.first;
    if (path == null || runtime.store == null) {
      return;
    }
    await scan(
      (onProgress) => runtime.store!.addRootAndScanWithChanges(
        path,
        onProgress: onProgress,
      ),
    );
  }

  /**
   * 打开系统多文件选择器，并把所选视频的父目录交给统一扫描链路。
   *
   * 选择器只允许视频扩展名；文件不会被复制或移动，应用仅注册其所在目录并建立索引。
   */
  Future<void> pickVideoFiles() async {
    final store = runtime.store;
    final paths = await fileSystem.pickFiles(
      dialogTitle: '选择要添加的视频文件',
      initialDirectory: preferredLibraryPickerDirectory(
        currentPath: runtime.localLibraryPath,
        roots: store?.roots ?? const <String>[],
      ),
      allowedExtensions: TagRules.videoExtensions
          .map((extension) => extension.substring(1))
          .toList(),
    );
    await importLibraryPaths(paths);
  }

  /**
   * 校验选择器或资源管理器拖入的路径，并以最少 root 数量触发一轮扫描。
   *
   * 已受现有 root 管理的文件只触发重新扫描；目录和视频文件之外的项目会被忽略。文件
   * stat 通过 [FileSystemAdapter] 异步执行，不在 build 或拖动悬停阶段访问磁盘。
   */
  Future<void> importLibraryPaths(Iterable<String> rawPaths) async {
    final store = runtime.store;
    if (store == null || runtime.isScanning) {
      return;
    }
    final importRevision =
        runtime.scanLifecycleController.beginPathImportInspection();
    final normalizedPaths = <String>[];
    final pathKeys = <String>{};
    for (final rawPath in rawPaths) {
      final normalized = fileSystem.normalizePath(rawPath);
      if (normalized.trim().isNotEmpty &&
          pathKeys.add(TagRules.pathKey(normalized))) {
        normalizedPaths.add(normalized);
      }
    }
    final inspected = await Future.wait<LibraryImportPath?>(
      normalizedPaths.map((path) async {
        if (await fileSystem.directoryExists(path)) {
          return (path: path, isDirectory: true);
        }
        if (TagRules.isVideoPath(path) && await fileSystem.fileExists(path)) {
          return (path: path, isDirectory: false);
        }
        return null;
      }),
    );
    if (!mounted ||
        runtime.store != store ||
        !runtime.scanLifecycleController.isCurrentPathImport(importRevision)) {
      return;
    }
    final imports = inspected.whereType<LibraryImportPath>().toList();
    if (imports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未发现可添加的视频文件或目录')),
      );
      return;
    }
    final newRoots = libraryImportRoots(
      imports: imports,
      existingRoots: store.roots,
    );
    await scan(
      newRoots.isEmpty
          ? (onProgress) => store.scanWithChanges(onProgress: onProgress)
          : (onProgress) => store.addRootsAndScanWithChanges(
                newRoots,
                onProgress: onProgress,
              ),
    );
  }

  @override
  Future<void> rescan() async {
    if (runtime.store == null) {
      return;
    }
    await scan(
      (onProgress) => runtime.store!.scanWithChanges(onProgress: onProgress),
    );
  }

  @override
  Future<void> scan(
    Future<LibraryScanCommitResult> Function(
      LibraryScanProgressCallback onProgress,
    ) action,
  ) async {
    if (runtime.isScanning) {
      return;
    }
    // 新扫描优先使用磁盘；取消上一轮后台媒体探测，避免两类顺序读取互相争抢。
    runtime.libraryMediaDetailsService?.dispose();
    runtime.libraryMediaDetailsService = null;
    runtime.activeScanUiDiagnostics?.abort();
    final diagnostics = kDebugMode ? LibraryScanUiDiagnostics() : null;
    diagnostics?.start();
    runtime.activeScanUiDiagnostics = diagnostics;
    var diagnosticsWillFinish = false;
    final started = await runtime.scanLifecycleController.run(
      action: (onProgress) async {
        final actionWatch = Stopwatch()..start();
        final result = await action(onProgress);
        actionWatch.stop();
        diagnostics?.markScanComplete();
        diagnostics?.recordStage(
          'scan.backend_and_commit',
          actionWatch.elapsed,
          itemCount: result.changedVideos.length,
        );
        return result;
      },
      onAccepted: (result) {
        if (!mounted) {
          return;
        }
        // 只为新增或内容变化项目进入缓存队列，避免每次扫描重新排队整个媒体库。
        runtime.thumbnailService?.prefetchAll(result.probeCandidates);
        startLibraryMediaProbes(result);
        diagnostics?.markPostApply();
        final applyWatch = Stopwatch()..start();
        applyLibraryScanDelta(result);
        final store = runtime.store;
        if (store != null &&
            runtime.playbackSettings.autoRemoveMissingOrUnreadableVideos) {
          // 先反馈扫描完成，再异步串行清理；不可读探测不得阻塞 UI。
          unawaited(cleanupMissingOrUnreadableVideos(store));
        }
        applyWatch.stop();
        diagnostics?.recordStage(
          'ui.delta_schedule',
          applyWatch.elapsed,
          itemCount: result.changedVideos.length,
        );
        if (diagnostics != null) {
          diagnosticsWillFinish = true;
          unawaited(diagnostics.finish(result).whenComplete(() {
            if (identical(runtime.activeScanUiDiagnostics, diagnostics)) {
              runtime.activeScanUiDiagnostics = null;
            }
          }));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '扫描完成：新增 ${result.addedCount}，修改 ${result.modifiedCount}，'
                  '移动 ${result.relinkedCount}，缺失 ${result.missingCount}')),
        );
      },
      onFailure: (error, _) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u626b\u63cf\u5931\u8d25\uff1a$error')),
        );
      },
      onChanged: (state) {
        if (!mounted) {
          return;
        }
        final progress = state.scanProgress;
        if (state.isScanning && progress != null) {
          diagnostics?.recordProgress(progress);
        }
        setState(() {});
      },
    );
    if (!started || !diagnosticsWillFinish) {
      diagnostics?.abort();
      if (identical(runtime.activeScanUiDiagnostics, diagnostics)) {
        runtime.activeScanUiDiagnostics = null;
      }
    }
  }

  /** 用户显式暂停/继续扫描；活动 sidecar 从当前候选位置恢复，不重新遍历目录。 */
  Future<void> toggleScanPaused() async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    await runtime.scanLifecycleController.toggleScanPaused(
      setPaused: store.setScanPaused,
      onChanged: (_) {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  /**
   * 请求取消当前扫描，并保留取消前已经存在的媒体库数据。
   *
   * UI 保持“正在取消”直到扫描 Future 真正退出，避免用户重复启动并发扫描。
   */
  Future<void> cancelScan() async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    try {
      await runtime.scanLifecycleController.cancelScan(
        cancel: store.cancelActiveScan,
        onChanged: (_) {
          if (mounted) {
            setState(() {});
          }
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消扫描失败：$error')),
      );
    }
  }

  /**
   * 仅把本轮新增或内容变化项目送入串行媒体探测队列。
   *
   * 新扫描会先 dispose 旧服务并取消其 generation；回调还会校验 store 与 fingerprint，
   * 防止旧文件结果覆盖新内容。SQLite 写入继续由 Dart Repository 完成。
   */
  void startLibraryMediaProbes(LibraryScanCommitResult result) {
    runtime.libraryMediaDetailsService?.dispose();
    runtime.libraryMediaDetailsService = null;
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final probeCandidatesById = <String, VideoItem>{
      for (final item in result.probeCandidates) item.videoId: item,
    };
    // 旧版媒体详情没有保存总时长。扫描完成后只把仍缺少可靠时长的活动视频
    // 合并进既有有限批次队列，卡片 build 不访问磁盘，完成后复用现有播放时长列。
    for (final item in store.videos.values) {
      if (!item.isMissing &&
          item.playbackDuration <= Duration.zero &&
          item.mediaDetails != null &&
          item.mediaDetailsError == null) {
        probeCandidatesById[item.videoId] = item;
      }
    }
    final probeCandidates = probeCandidatesById.values.toList(growable: false);
    if (probeCandidates.isEmpty) {
      return;
    }
    final mediaImportGeneration =
        runtime.scanLifecycleController.beginMediaImport(
      onChanged: (_) {
        if (mounted) {
          setState(() {});
        }
      },
    );
    final service = _createLibraryMediaDetailsService(
      store,
      mediaImportGeneration: mediaImportGeneration,
    );
    runtime.libraryMediaDetailsService = service;
    // 新增项和旧版缺时长项统一登记为有限批次；真实进入视口仍可提升同一路径任务，
    // 服务通过 videoId/路径去重，不扩大并发。
    service.prefetchAll(probeCandidates);
  }

  /** 创建媒体库详情会话；所有写回继续校验当前 Store、videoId 与 fingerprint。 */
  MediaDetailsService _createLibraryMediaDetailsService(
    LibraryApplicationFacade store, {
    int? mediaImportGeneration,
  }) {
    return applicationService.createMediaDetailsService(
      onBatchUpdated: (updates) async {
        final validUpdates = <VideoItem>[];
        for (final update in updates) {
          final item = update.item;
          final current = store.videos[TagRules.pathKey(item.path)];
          if (runtime.store != store ||
              current == null ||
              current.videoId != item.videoId ||
              current.mediaFingerprint != update.fingerprint) {
            continue;
          }
          // 探测完成可能晚于 root 移除或下一轮扫描；只更新 Store 中仍然有效的当前对象，
          // 禁止旧回调通过 upsert 把已删除记录重新插回 SQLite 和内存索引。
          current.mediaDetails = update.details;
          current.mediaDetailsError = item.mediaDetailsError;
          final duration = update.details.duration;
          if (duration != null && duration > Duration.zero) {
            // 总时长复用稳定 videoId 上已有的持久化列，不新增 schema 或路径绑定。
            current.playbackDuration = duration;
          }
          validUpdates.add(current);
        }
        await store.upsertVideos(validUpdates);
        if (mediaImportGeneration == null &&
            validUpdates.isNotEmpty &&
            mounted &&
            runtime.store == store) {
          // 可见项补齐总时长后只刷新现有视图，不提升媒体库 revision，也不重算筛选或标签计数。
          setState(() {});
        }
      },
      onProgress: mediaImportGeneration != null
          ? (progress) {
              if (!mounted || runtime.store != store) {
                return;
              }
              runtime.scanLifecycleController.publishMediaImportProgress(
                generation: mediaImportGeneration,
                progress: progress,
                isComplete: progress.isComplete,
                onChanged: (_) {
                  if (mounted) {
                    setState(() {});
                  }
                },
              );
            }
          : null,
    );
  }

  /** 在不影响已显示列表的前提下暂停或继续当前后台媒体解析队列。 */
  void toggleMediaImportPaused() {
    final service = runtime.libraryMediaDetailsService;
    final progress = runtime.mediaImportProgress;
    if (service == null || progress == null) {
      return;
    }
    if (progress.isPaused) {
      service.resume();
    } else {
      service.pause();
    }
  }

  /**
   * 把媒体库当前可视卡片的详情提升到扫描后台队列之前。
   *
   * Widget 只报告真实构建项；服务继续串行探测并丢弃过期代次，不在 UI 线程等待。
   */
  void prioritizeVisibleLibraryItem(VideoItem item) {
    if (item.isMissing) {
      return;
    }
    final store = runtime.store;
    if (store == null) {
      return;
    }
    var service = runtime.libraryMediaDetailsService;
    if (service == null || service.isDisposed) {
      service = _createLibraryMediaDetailsService(store);
      runtime.libraryMediaDetailsService = service;
    }
    unawaited(service.detailsFor(
      item,
      // 正常启动不会全量重扫；旧缓存缺时长时只提升真实可见项，继续复用有限批次队列。
      refreshIncomplete: item.playbackDuration <= Duration.zero,
      priority: true,
    ));
  }

  @override
  FilterState buildImmediateFilterState(LibraryApplicationFacade store) {
    final query = currentFilterQuery();
    return FilterState(
      epoch: resultEpoch(query),
      query: query,
      filteredVideos: runtime.sortController.sort(store.videos.values),
      resultCount: store.videos.length,
      totalCount: store.videos.length,
    );
  }

  /** 在低频标签维护完成后同步刷新全库稳定计数快照。 */
}
