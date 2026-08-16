import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/tag_rules.dart';
import '../../features/library/application/library_file_command_executor.dart';
import '../../features/library/application/library_manual_tag_command_executor.dart';
import '../../models/platform_models.dart';
import '../../models/video_item.dart';
import '../../widgets/library/library_tag_editor_dialog.dart';
import '../player/player_delete_dialog.dart';

import 'library_page_state_host.dart';

// ignore_for_file: slash_for_doc_comments

/** LibraryPageCommandsMixin 按既有一致性边界承载页面协调逻辑，不复制业务状态 owner。 */
mixin LibraryPageCommandsMixin<T extends StatefulWidget>
    on LibraryPageStateHost<T> {
  @override
  Future<void> deleteVideoFromPlayer(VideoItem item) async {
    await deleteConfirmedLibraryVideo(item);
    // 播放器路由仍在前台时不重建媒体库；返回后统一刷新可见结果和标签计数。
    runtime.playerScopedLibraryDataChanged = true;
    runtime.playerScopedNeedsCountRefresh = true;
    runtime.playerScopedTagDefinitionsChanged = true;
    runtime.playerScopedRemovedVideoIds.add(item.videoId);
  }

  /** 相似候选页先合并收藏/manual 标签，再复用统一确认/回收站/记录清理边界。 */
  @override
  Future<bool> deleteVideoFromSimilarity(
    VideoItem item,
    VideoItem mergeInto,
  ) {
    return _deleteVideoWithConfirmation(
      item,
      mergeInto: mergeInto,
      onDeleted: () => markLibraryDataChanged(
        tagDefinitionsChanged: true,
        removedVideoIds: <String>[item.videoId],
      ),
    );
  }

  /**
   * 处理媒体卡片删除动作；所有用户视频文件都先移入系统回收站。
   *
   * 数据库事务会一并删除标签关系、收藏、播放进度、媒体详情和稳定身份记录；缺失/不可读
   * 自动清理是独立的数据库记录清理，不会删除磁盘文件。
   */
  Future<void> requestDeleteVideo(VideoItem item) async {
    await _deleteVideoWithConfirmation(
      item,
      onDeleted: () => markLibraryDataChanged(
        tagDefinitionsChanged: true,
        removedVideoIds: <String>[item.videoId],
      ),
    );
  }

  Future<bool> _deleteVideoWithConfirmation(
    VideoItem item, {
    VideoItem? mergeInto,
    required VoidCallback onDeleted,
  }) async {
    final decision = await resolveSingleVideoDeleteDecision(
      item,
      mergeInto: mergeInto,
    );
    if (decision == null || !mounted) {
      return false;
    }
    try {
      await deleteConfirmedLibraryVideo(item, mergeInto: mergeInto);
      if (mounted) {
        onDeleted();
      }
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      final message =
          error is FileSystemException ? error.message : '当前平台暂不支持移入回收站';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除失败：$message；媒体库记录未删除')),
      );
      return false;
    }
  }

  /**
   * 执行已经由用户确认的单条媒体库删除。
   *
   * 该方法不刷新页面，便于批量删除在全部条目处理完后只触发一次筛选和计数更新。
   */
  Future<void> deleteConfirmedLibraryVideo(
    VideoItem item, {
    VideoItem? mergeInto,
  }) async {
    await runtime.fileCommandExecutor.deleteById(
      DeleteVideoCommand(item: item),
      moveFileToTrash: fileSystem.moveFileToTrash,
      deleteRecordById: (videoId) async {
        final store = runtime.store;
        if (store == null) {
          return;
        }
        if (mergeInto == null) {
          await store.deleteVideoById(videoId);
        } else {
          await store.deleteVideoAndMergeUserDataById(
            sourceVideoId: videoId,
            targetVideoId: mergeInto.videoId,
          );
        }
      },
      deleteThumbnail: (target) async {
        await runtime.thumbnailService?.deleteThumbnailFor(target);
      },
    );
  }

  /**
   * 删除当前完整筛选结果中已选择的视频。
   *
   * 每条记录继续走与单条删除一致的平台边界；成功项立即从选择集移除，失败项保留选择，
   * 最后只刷新一次筛选和标签计数，避免大媒体库中每删一条都全量重算。
   */
  Future<void> requestDeleteSelectedVideos(
    List<VideoItem> currentVideos,
  ) async {
    final targets = [
      for (final item in currentVideos)
        if (runtime.selectedLibraryVideoIds.contains(item.videoId)) item,
    ];
    if (targets.isEmpty) {
      return;
    }
    final decision = await resolveBatchVideoDeleteDecision(targets.length);
    if (decision == null || !mounted) {
      return;
    }

    final result = await runtime.fileCommandExecutor.deleteAllById(
      targets.map(
        (item) => DeleteVideoCommand(
          item: item,
        ),
      ),
      moveFileToTrash: fileSystem.moveFileToTrash,
      deleteRecordById: (videoId) async {
        await runtime.store?.deleteVideoById(videoId);
      },
      deleteThumbnail: (target) async {
        await runtime.thumbnailService?.deleteThumbnailFor(target);
      },
    );
    if (!mounted) {
      return;
    }
    setState(
      () => runtime.librarySelection.removeAll(result.deletedVideoIds),
    );
    if (result.deletedVideoIds.isNotEmpty) {
      markLibraryDataChanged(
        tagDefinitionsChanged: true,
        removedVideoIds: result.deletedVideoIds,
      );
    }
    if (result.failedItems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已删除 ${result.deletedVideoIds.length} 个，'
            '${result.failedItems.length} 个失败；失败项仍保持选中',
          ),
        ),
      );
    }
  }

  /** 单条删除按确认偏好决定是否显示提示；文件动作始终进入系统回收站。 */
  Future<VideoDeleteDecision?> resolveSingleVideoDeleteDecision(
    VideoItem item, {
    VideoItem? mergeInto,
  }) async {
    final settings = runtime.playbackSettings;
    final immediate = videoDeleteDecisionWithoutPrompt(settings);
    if (immediate != null) {
      return immediate;
    }
    final decision = await showPlayerDeleteConfirmationDialog(
      context,
      item,
      mergeInto: mergeInto,
    );
    return rememberDeleteDecision(decision);
  }

  /** 批量删除与单条删除共享确认显示，并始终把文件移入系统回收站。 */
  Future<VideoDeleteDecision?> resolveBatchVideoDeleteDecision(
    int count,
  ) async {
    final settings = runtime.playbackSettings;
    final immediate = videoDeleteDecisionWithoutPrompt(settings);
    if (immediate != null) {
      return immediate;
    }
    final decision = await showBatchVideoDeleteConfirmationDialog(
      context,
      count: count,
    );
    return rememberDeleteDecision(decision);
  }

  /**
   * 只在用户确认删除后保存弹窗选择；设置写入失败时中止删除，避免界面记忆与
   * 后续真实文件动作分叉。
   */
  Future<VideoDeleteDecision?> rememberDeleteDecision(
    VideoDeleteDecision? decision,
  ) async {
    if (decision == null || !mounted) {
      return null;
    }
    final next = runtime.playbackSettings.copyWith(
      confirmBeforeDeletingVideo: !decision.dontAskAgain,
    );
    try {
      await applicationService.savePlaybackSettings(next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存删除偏好失败：$error；本次未执行删除')),
        );
      }
      return null;
    }
    if (mounted) {
      setState(() => runtime.playbackSettings = next);
    }
    return decision;
  }

  /**
   * 使用统一弹窗编辑视频独立的顶层 manual 标签。
   *
   * 文件夹筛选可以处于二级上下文，但用户主动维护的标签不继承该父级；
   * 这样同一个 manual 标签可以跨文件夹复用，并由 manual 分组统一筛选。
   * [deferLibraryRefresh] 仅供播放器前台路由使用，保存后延迟到返回媒体库再刷新结果，
   * 避免隐藏页面在播放期间执行标签计数重算。
   */
  Future<void> editTags(
    VideoItem item, {
    bool deferLibraryRefresh = false,
  }) async {
    final lockedTags = folderTagsForItem(item);
    final tagItems = runtime.store?.allTagItems ?? const <TagItem>[];
    final initialManualTags = manualTagsForItem(item);
    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (_) => TagEditorDialog(
        title: item.title,
        helperText: '只修改独立 manual 标签；文件夹标签由目录结构维护。',
        existingTags: tagEditorCandidates(tagItems),
        favoriteTags: {
          for (final tag in tagItems)
            if (tag.source == TagSource.manual && tag.isFavorite) tag.name,
        },
        mostUsedTags: mostUsedManualTags(),
        initialManualTags: initialManualTags,
        lockedTags: lockedTags,
      ),
    );
    if (updated == null) {
      return;
    }
    final replacement = runtime.manualTagCommandExecutor.replace(
      ReplaceVideoManualTagsCommand(
        item: item,
        selectedTags: updated,
        lockedFolderTags: lockedTags,
      ),
      commit: (target, parentTag, manualTags) async {
        await runtime.store?.replaceManualTags(
          target,
          parentTag: parentTag,
          manualTags: manualTags,
        );
      },
    );
    if (mounted) {
      setState(() {});
    }
    try {
      await replacement;
    } catch (_) {
      if (mounted) {
        // command 已恢复一级/二级模型；同步重建当前卡片，避免继续展示未持久化选择。
        setState(() {});
      }
      rethrow;
    }
    if (mounted && deferLibraryRefresh) {
      runtime.playerScopedLibraryDataChanged = true;
      runtime.playerScopedTagDefinitionsChanged = true;
    } else if (mounted) {
      markLibraryDataChanged(tagDefinitionsChanged: true);
    }
  }

  /**
   * 播放器继续复用媒体库页面的统一标签编辑入口。
   *
   * 当前一级标签、folder 锁定项、manual 候选集合和保存语义全部由 [editTags] 统一决定，
   * 防止播放器与批量维护入口随时间演化成不同的数据视图。
   */
  @override
  Future<void> editManualTagsFromPlayer(VideoItem item) =>
      editTags(item, deferLibraryRefresh: true);

  Set<String> folderTagsForItem(VideoItem item) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.parentTagsFor(rootPath, item.path);
  }

  /** 从 source 明确的关系索引读取当前视频的独立 manual 标签。 */
  Set<String> manualTagsForItem(VideoItem item) {
    final store = runtime.store;
    if (store == null) {
      final folderTags = folderTagsForItem(item);
      return {
        for (final tag in item.tags)
          if (!folderTags.any((folderTag) => TagRules.sameTag(folderTag, tag)))
            tag,
      };
    }
    final tagIds = store.videoTagIdsByPathKey[TagRules.pathKey(item.path)] ??
        const <String>{};
    return {
      for (final tagId in tagIds)
        if (store.tagsById[tagId]?.source == TagSource.manual)
          store.tagsById[tagId]!.name,
    };
  }

  /** 按真实 video-tag 关联次数为编辑器候选排序，不依赖可变展示计数。 */
  List<String> mostUsedManualTags() {
    final store = runtime.store;
    if (store == null) {
      return const <String>[];
    }
    final usageByNormalizedName = <String, int>{};
    final displayNameByNormalizedName = <String, String>{};
    for (final tagIds in store.videoTagIdsByPathKey.values) {
      for (final tagId in tagIds) {
        final tag = store.tagsById[tagId];
        if (tag == null || tag.source != TagSource.manual || tag.isHidden) {
          continue;
        }
        final normalizedName = TagRules.normalizeTag(tag.name).toLowerCase();
        if (normalizedName.isEmpty) {
          continue;
        }
        displayNameByNormalizedName.putIfAbsent(normalizedName, () => tag.name);
        usageByNormalizedName.update(
          normalizedName,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final names = displayNameByNormalizedName.keys.toList(growable: false)
      ..sort((left, right) {
        final byUsage = usageByNormalizedName[right]!
            .compareTo(usageByNormalizedName[left]!);
        return byUsage != 0 ? byUsage : left.compareTo(right);
      });
    return [for (final name in names) displayNameByNormalizedName[name]!];
  }

  Set<String> folderChildTagsForItem(VideoItem item, String parentTag) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.childTagsFor(rootPath, item.path)[parentTag] ??
        const <String>{};
  }
}
