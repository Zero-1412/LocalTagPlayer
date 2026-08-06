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
  Future<void> deleteVideoFromPlayer(
    VideoItem item,
    bool moveLocalFileToTrash,
  ) async {
    await deleteConfirmedLibraryVideo(item, moveLocalFileToTrash);
    // 播放器路由仍在前台时不重建媒体库；返回后统一刷新可见结果和标签计数。
    runtime.playerScopedLibraryDataChanged = true;
    runtime.playerScopedNeedsCountRefresh = true;
    runtime.playerScopedTagDefinitionsChanged = true;
  }

  /**
   * 处理媒体卡片删除动作，并把移入系统回收站保持为显式可选项。
   *
   * 数据库事务会一并删除标签关系、收藏、播放进度、媒体详情和稳定身份记录；选择仅移出
   * 媒体库时，仍位于受监控 root 的文件会在下次扫描时作为新条目重新出现。
   */
  Future<void> requestDeleteVideo(VideoItem item) async {
    final decision = await resolveSingleVideoDeleteDecision(item);
    if (decision == null || !mounted) {
      return;
    }
    try {
      await deleteConfirmedLibraryVideo(
        item,
        decision.moveLocalFileToTrash,
      );
      if (mounted) {
        markLibraryDataChanged(tagDefinitionsChanged: true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message =
          error is FileSystemException ? error.message : '当前平台暂不支持移入回收站';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除失败：$message；媒体库记录未删除')),
      );
    }
  }

  /**
   * 执行已经由用户确认的单条媒体库删除。
   *
   * 该方法不刷新页面，便于批量删除在全部条目处理完后只触发一次筛选和计数更新。
   */
  Future<void> deleteConfirmedLibraryVideo(
    VideoItem item,
    bool moveLocalFileToTrash,
  ) async {
    await runtime.fileCommandExecutor.delete(
      DeleteVideoCommand(
        item: item,
        moveLocalFileToTrash: moveLocalFileToTrash,
      ),
      moveFileToTrash: fileSystem.moveFileToTrash,
      deleteRecord: (path) async {
        await runtime.store?.deleteVideo(path);
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

    final result = await runtime.fileCommandExecutor.deleteAll(
      targets.map(
        (item) => DeleteVideoCommand(
          item: item,
          moveLocalFileToTrash: decision.moveLocalFileToTrash,
        ),
      ),
      moveFileToTrash: fileSystem.moveFileToTrash,
      deleteRecord: (path) async {
        await runtime.store?.deleteVideo(path);
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
      markLibraryDataChanged(tagDefinitionsChanged: true);
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

  /** 单条删除按当前偏好决定直接执行或展示统一确认层。 */
  Future<VideoDeleteDecision?> resolveSingleVideoDeleteDecision(
    VideoItem item,
  ) async {
    final settings = runtime.playbackSettings;
    final immediate = videoDeleteDecisionWithoutPrompt(settings);
    if (immediate != null) {
      return immediate;
    }
    final decision = await showPlayerDeleteConfirmationDialog(
      context,
      item,
      initialMoveLocalFileToTrash: settings.moveDeletedFileToTrash,
    );
    return rememberDeleteDecision(decision);
  }

  /** 批量删除与单条删除共享确认显示和回收站默认值。 */
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
      initialMoveLocalFilesToTrash: settings.moveDeletedFileToTrash,
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
      moveDeletedFileToTrash: decision.moveLocalFileToTrash,
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
    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (_) => TagEditorDialog(
        title: item.title,
        helperText: '只修改独立 manual 标签；文件夹标签由目录结构维护。',
        existingTags: tagEditorCandidates(
          runtime.store?.allTagItems ?? const <TagItem>[],
        ),
        initialTags: item.tags,
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
      commit: (target, parentTag) async {
        await runtime.store?.replaceManualTags(target, parentTag: parentTag);
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

  Set<String> folderChildTagsForItem(VideoItem item, String parentTag) {
    final rootPath = item.rootPath;
    if (rootPath == null || rootPath.isEmpty) {
      return const <String>{};
    }
    return TagRules.childTagsFor(rootPath, item.path)[parentTag] ??
        const <String>{};
  }
}
