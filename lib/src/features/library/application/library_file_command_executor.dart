import 'dart:collection';

import 'package:path/path.dart' as p;

import '../../../core/tag_rules.dart';
import '../../../models/video_item.dart';

// ignore_for_file: slash_for_doc_comments

/** 文件菜单“打开位置”的显式只读命令。 */
class RevealVideoLocationCommand {
  const RevealVideoLocationCommand(this.item);

  /** 需要在平台文件管理器中定位的稳定视频对象。 */
  final VideoItem item;
}

/** 同目录重命名的显式命令；扩展名始终从原路径保留。 */
class RenameVideoFileCommand {
  const RenameVideoFileCommand({
    required this.item,
    required this.newBaseName,
  });

  /** 需要保留 stable videoId 的视频对象。 */
  final VideoItem item;

  /** 已由 presentation 校验过的、不含扩展名的新文件名。 */
  final String newBaseName;
}

/** 删除媒体库记录及本地视频文件的显式命令。 */
class DeleteVideoCommand {
  const DeleteVideoCommand({required this.item});

  /** 需要删除的稳定视频对象。 */
  final VideoItem item;
}

/** 批量删除完成后的不可变结果；失败项保留原对象供页面继续选中。 */
class LibraryBatchDeleteResult {
  LibraryBatchDeleteResult({
    required Iterable<String> deletedVideoIds,
    required Iterable<VideoItem> failedItems,
  })  : deletedVideoIds =
            UnmodifiableSetView<String>(Set<String>.of(deletedVideoIds)),
        failedItems =
            List<VideoItem>.unmodifiable(List<VideoItem>.of(failedItems));

  /** 已完成 Repository 删除的 stable videoId。 */
  final Set<String> deletedVideoIds;

  /** 任一文件系统或 Repository 步骤失败的条目。 */
  final List<VideoItem> failedItems;
}

/**
 * 媒体库文件菜单命令执行器。
 *
 * 本类只编排调用方注入的平台与 Repository 命令，不持有 Store、BuildContext、Route、
 * Widget、缓存服务或平台实现。页面仍拥有确认、偏好保存、SnackBar 与刷新时机。
 */
class LibraryFileCommandExecutor {
  const LibraryFileCommandExecutor();

  /**
   * 通过平台边界定位文件。
   *
   * 返回 false 表示平台动作失败；底层异常不越过 application 边界泄漏本机路径。
   */
  Future<bool> reveal(
    RevealVideoLocationCommand command, {
    required Future<void> Function(String path) revealInFileManager,
  }) async {
    try {
      await revealInFileManager(command.item.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /**
   * 在同一目录完成物理改名并提交 mutable path。
   *
   * Repository 提交失败时立即把文件改回原路径；回滚也失败时返回固定安全错误，要求用户
   * 重新扫描。stable videoId、标签、收藏和播放记录始终由 Repository 原命令保留。
   */
  Future<void> rename(
    RenameVideoFileCommand command, {
    required String Function(String path) normalizePath,
    required String Function(String path) parentPath,
    required String Function(List<String> parts) joinPath,
    required Future<bool> Function(String path) fileExists,
    required Future<String> Function(String oldPath, String newPath) renameFile,
    required Future<void> Function(VideoItem item, String newPath)
        commitRenamedPath,
  }) async {
    final item = command.item;
    final oldPath = item.path;
    final extension = p.extension(oldPath);
    final targetPath = joinPath(<String>[
      parentPath(oldPath),
      '${command.newBaseName}$extension',
    ]);
    if (TagRules.pathKey(oldPath) == TagRules.pathKey(targetPath)) {
      if (normalizePath(oldPath) == normalizePath(targetPath)) {
        return;
      }
      throw StateError('当前暂不支持仅修改文件名大小写，请换一个不同名称');
    }
    if (await fileExists(targetPath)) {
      throw StateError('同名文件已存在，请换一个名称');
    }

    final renamedPath = await renameFile(oldPath, targetPath);
    try {
      await commitRenamedPath(item, renamedPath);
    } catch (_) {
      try {
        await renameFile(renamedPath, oldPath);
      } catch (_) {
        // 物理改名成功但两个方向的恢复都失败时，只能要求重新扫描重新建立 mutable path。
        throw StateError('文件已改名，但媒体库更新失败；请返回媒体库后重新扫描');
      }
      rethrow;
    }
  }

  /**
   * stable-ID 版本的重命名提交入口。
   *
   * 文件系统仍使用命令快照中的 mutable path 执行物理动作，但 Repository 提交只接收
   * videoId，避免路径变化或旧页面引用把写入落到另一条视频记录。
   */
  Future<void> renameById(
    RenameVideoFileCommand command, {
    required String Function(String path) normalizePath,
    required String Function(String path) parentPath,
    required String Function(List<String> parts) joinPath,
    required Future<bool> Function(String path) fileExists,
    required Future<String> Function(String oldPath, String newPath) renameFile,
    required Future<void> Function(String videoId, String newPath)
        commitRenamedPathById,
  }) async {
    final item = command.item;
    final oldPath = item.path;
    final extension = p.extension(oldPath);
    final targetPath = joinPath(<String>[
      parentPath(oldPath),
      '${command.newBaseName}$extension',
    ]);
    if (TagRules.pathKey(oldPath) == TagRules.pathKey(targetPath)) {
      if (normalizePath(oldPath) == normalizePath(targetPath)) {
        return;
      }
      throw StateError('当前暂不支持仅修改文件名大小写，请换一个不同名称');
    }
    if (await fileExists(targetPath)) {
      throw StateError('同名文件已存在，请换一个名称');
    }
    final renamedPath = await renameFile(oldPath, targetPath);
    try {
      await commitRenamedPathById(item.videoId, renamedPath);
    } catch (_) {
      try {
        await renameFile(renamedPath, oldPath);
      } catch (_) {
        throw StateError('文件已改名，但媒体库更新失败；请返回媒体库后重新扫描');
      }
      rethrow;
    }
  }

  /**
   * 执行已确认的删除命令。
   *
   * 所有用户视频删除都必须先通过平台边界移入系统回收站，避免平台拒绝时先丢失
   * 数据库记录；缩略图是可重建缓存，清理失败不能把已经提交的业务删除误报为失败。
   */
  Future<void> delete(
    DeleteVideoCommand command, {
    required Future<void> Function(String path) moveFileToTrash,
    required Future<void> Function(String path) deleteRecord,
    Future<void> Function(VideoItem item)? deleteThumbnail,
  }) async {
    final item = command.item;
    await moveFileToTrash(item.path);
    await deleteRecord(item.path);
    try {
      await deleteThumbnail?.call(item);
    } catch (_) {
      // 缓存可重建，不能覆盖 Repository 已成功提交的删除结果。
    }
  }

  /** 通过 stable videoId 提交数据库删除，path 只承担物理文件动作。 */
  Future<void> deleteById(
    DeleteVideoCommand command, {
    required Future<void> Function(String path) moveFileToTrash,
    required Future<void> Function(String videoId) deleteRecordById,
    Future<void> Function(VideoItem item)? deleteThumbnail,
  }) async {
    await moveFileToTrash(command.item.path);
    await deleteRecordById(command.item.videoId);
    try {
      await deleteThumbnail?.call(command.item);
    } catch (_) {
      // 缓存可重建，不能覆盖已经提交的业务删除。
    }
  }

  /**
   * 串行执行批量删除，返回成功 stable ID 与失败对象。
   *
   * 串行顺序沿用现有实现，避免同时弹起多个平台回收站动作或并发写同一 Repository。
   */
  Future<LibraryBatchDeleteResult> deleteAll(
    Iterable<DeleteVideoCommand> commands, {
    required Future<void> Function(String path) moveFileToTrash,
    required Future<void> Function(String path) deleteRecord,
    Future<void> Function(VideoItem item)? deleteThumbnail,
  }) async {
    final deletedVideoIds = <String>{};
    final failedItems = <VideoItem>[];
    for (final command in commands) {
      try {
        await delete(
          command,
          moveFileToTrash: moveFileToTrash,
          deleteRecord: deleteRecord,
          deleteThumbnail: deleteThumbnail,
        );
        deletedVideoIds.add(command.item.videoId);
      } catch (_) {
        failedItems.add(command.item);
      }
    }
    return LibraryBatchDeleteResult(
      deletedVideoIds: deletedVideoIds,
      failedItems: failedItems,
    );
  }

  /** 批量 stable-ID 删除；失败项仍保留原命令供页面重试。 */
  Future<LibraryBatchDeleteResult> deleteAllById(
    Iterable<DeleteVideoCommand> commands, {
    required Future<void> Function(String path) moveFileToTrash,
    required Future<void> Function(String videoId) deleteRecordById,
    Future<void> Function(VideoItem item)? deleteThumbnail,
  }) async {
    final deletedVideoIds = <String>{};
    final failedItems = <VideoItem>[];
    for (final command in commands) {
      try {
        await deleteById(
          command,
          moveFileToTrash: moveFileToTrash,
          deleteRecordById: deleteRecordById,
          deleteThumbnail: deleteThumbnail,
        );
        deletedVideoIds.add(command.item.videoId);
      } catch (_) {
        failedItems.add(command.item);
      }
    }
    return LibraryBatchDeleteResult(
      deletedVideoIds: deletedVideoIds,
      failedItems: failedItems,
    );
  }
}
