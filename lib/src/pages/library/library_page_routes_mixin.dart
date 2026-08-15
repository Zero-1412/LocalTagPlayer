import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/playback_settings.dart';
import '../../core/tag_rules.dart';
import '../../features/library/application/library_revision_tracker.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../widgets/library/library_add_tag_dialog.dart';
import '../tags/tag_manager_page.dart';
import 'directory_manager_page.dart';
import 'missing_relink_page.dart';
import 'cache_settings_page.dart';
import 'video_similarity_page.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageRoutesMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageRoutesMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  Future<void> openSettings() async {
    final store = runtime.store;
    final thumbnailService = runtime.thumbnailService;
    if (store == null || thumbnailService == null) {
      return;
    }
    await Navigator.of(context).push(
      smoothRoute<void>(
        CacheSettingsPage(
          store: store,
          thumbnailService: thumbnailService,
          playbackSettings: runtime.playbackSettings,
          dataBackupSettings: runtime.dataBackupSettings,
          updateService: updateService,
          onPlaybackSettingsChanged: (settings) async {
            await applicationService.savePlaybackSettings(settings);
            if (mounted) {
              setState(() => runtime.playbackSettings = settings);
            }
          },
          onDataBackupSettingsChanged: (settings) async {
            final previous = runtime.dataBackupSettings;
            await store.setDataBackupEnabled(settings.enabled);
            try {
              await applicationService.saveDataBackupSettings(settings);
            } catch (_) {
              // 设置文件失败时恢复运行态，避免界面、当前服务与下次启动值分叉。
              await store.setDataBackupEnabled(previous.enabled);
              rethrow;
            }
            if (mounted) {
              setState(() => runtime.dataBackupSettings = settings);
            }
          },
          onRunDataBackupNow: store.runDataBackupNow,
          onCheckDataBackupIntegrity: store.checkDataBackupIntegrity,
          onExportDataBackup: () async {
            final now = DateTime.now();
            String two(int value) => value.toString().padLeft(2, '0');
            final suggestedName = 'LocalTagPlayer-视频数据备份-'
                '${now.year}${two(now.month)}${two(now.day)}-'
                '${two(now.hour)}${two(now.minute)}.json';
            final path = await fileSystem.pickSavePath(
              suggestedName: suggestedName,
              dialogTitle: '导出视频依赖备份',
              allowedExtensions: const <String>['json'],
            );
            if (path == null) {
              return null;
            }
            final bytes = await store.createDataBackupExport();
            await fileSystem.writeBytes(path, bytes, flush: true);
            return path;
          },
        ),
        backShortcutProvider: () => runtime
            .playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
    if (mounted) {
      markLibraryDataChanged();
    }
  }

  Future<void> openTagManager(List<VideoItem> currentResults) async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    await Navigator.of(context).push(
      smoothRoute<void>(
        TagManagerPage(
          store: store,
          currentResults: List<VideoItem>.of(currentResults),
        ),
        backShortcutProvider: () => runtime
            .playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
    if (mounted) {
      setState(() {
        runtime.libraryRevisionTracker.record(
          LibraryDataChangeKind.tagDefinitions,
        );
        invalidateDerivedCaches();
        refreshStableTagCountsNow(store);
      });
      scheduleFilterRefresh(refreshCounts: true);
    }
  }

  Future<void> openDirectoryManager() async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      smoothRoute<void>(
        DirectoryManagerPage(
          store: store,
          scanning: runtime.isScanning,
          onAddDirectory: pickFolder,
          onRescan: rescan,
          onRemoveRoot: removeLibraryRootData,
        ),
        backShortcutProvider: () => runtime
            .playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
  }

  /** 打开只读重复候选页；返回后不触发筛选、标签计数或播放队列刷新。 */
  Future<void> openSimilarVideos() async {
    final store = runtime.store;
    final thumbnailService = runtime.thumbnailService;
    if (store == null || thumbnailService == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      smoothRoute<void>(
        VideoSimilarityPage(
          store: store,
          thumbnailService: thumbnailService,
          onRevealLocation: revealVideoLocation,
        ),
        backShortcutProvider: () => runtime
            .playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
  }

  /**
   * 打开缺失视频管理页；返回后只在确有 relink 时刷新派生缓存与标签计数。
   */
  Future<void> openMissingRelink() async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      smoothRoute<bool>(
        MissingRelinkPage(
          store: store,
          fileSystem: fileSystem,
        ),
        backShortcutProvider: () => runtime
            .playbackSettings.shortcuts[PlayerShortcutAction.navigateBack]!,
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        runtime.libraryRevisionTracker.record(
          LibraryDataChangeKind.tagDefinitions,
        );
        invalidateDerivedCaches();
        refreshStableTagCountsNow(store);
      });
      scheduleFilterRefresh(refreshCounts: true);
    }
  }

  // ignore: unused_element
  Future<void> addLibraryTag() async {
    final existingTags =
        runtime.store?.allTagItems.toList() ?? const <TagItem>[];
    final picked = await showLibraryAddTagDialog(
      context,
      tags: existingTags,
    );
    final tag = picked == null ? null : TagRules.normalizeTag(picked);
    if (tag == null || tag.isEmpty || runtime.store == null) {
      return;
    }
    try {
      var tagDefinitionChanged = false;
      if (!runtime.store!.allTagItems.any(
        (existing) =>
            (existing.groupId ?? 'manual') == 'manual' &&
            TagRules.sameTag(existing.name, tag),
      )) {
        await runtime.store!.createManualTag(name: tag, groupId: 'manual');
        tagDefinitionChanged = true;
      }
      var favoriteChanged = false;
      if (!runtime.store!.favoriteTags
          .any((existing) => TagRules.sameTag(existing, tag))) {
        await runtime.store!.addFavoriteTag(tag);
        favoriteChanged = true;
      }
      if ((tagDefinitionChanged || favoriteChanged) && mounted) {
        setState(() {
          runtime.libraryRevisionTracker.record(
            LibraryDataChangeKind.tagDefinitions,
          );
          invalidateDerivedCaches();
          refreshStableTagCountsNow(runtime.store!);
        });
        scheduleFilterRefresh(refreshCounts: true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('\u6dfb\u52a0\u6807\u7b7e\u5931\u8d25\uff1a$error')),
      );
    }
  }

  // ignore: unused_element
  Future<void> removeLibraryTag(String tag) async {
    final store = runtime.store;
    if (store == null) {
      return;
    }
    await store.removeFavoriteTag(tag);
    mutateFilters(() {
      invalidateDerivedCaches();
      runtime.selectedTags.remove(tag);
      runtime.selectedChildTags.clear();
      refreshStableTagCountsNow(store);
    });
  }
}
