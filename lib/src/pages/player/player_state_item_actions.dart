import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'player_rename_file_dialog.dart';
import 'player_page.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 处理手动标签、文件重命名、覆盖层和定位文件动作。
 *
 * 这里只承载 [PlayerPageState] 的实现细节；播放会话、过滤队列与资源生命周期所有权
 * 仍保留在页面状态对象中。
 */
extension PlayerStateItemActions on PlayerPageState {
  Future<void> editManualTags() async {
    shortcutGate.setManualTagEditorOpen(true);
    try {
      await withPlayerOverlaySurfaceOccluded(
        () => pageWidget.onEditManualTags(currentItem),
      );
      if (mounted) {
        rebuild(() {});
      }
    } finally {
      shortcutGate.setManualTagEditorOpen(false);
      restorePlayerShortcutFocus();
    }
  }

  /**
   * 把文件名编辑、平台文件操作和稳定路径提交串成一个播放器内事务。
   *
   * 首次尝试不打断播放；仅当桌面文件句柄拒绝改名时才停止后端、重试并恢复原位置。
   */
  Future<void> renameCurrentFile() async {
    if (renamingFile) {
      return;
    }
    renamingFile = true;
    try {
      await withPlayerShortcutsSuspended(() async {
        final item = currentItem;
        if (item.isMissing) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件缺失，请重新关联后再重命名')),
            );
          }
          return;
        }
        final newBaseName = await withPlayerOverlaySurfaceOccluded(
          () => showPlayerRenameFileDialog(
            context,
            item: item,
          ),
        );
        if (!mounted || newBaseName == null) {
          return;
        }

        final oldPath = item.path;
        final position = playerService.state.position;
        final wasPlaying = playerService.state.playing;
        try {
          await pageWidget.onRenameFile(item, newBaseName);
          if (!mounted) {
            return;
          }
          // 后端仍持有同一文件句柄时无需重新打开，只同步 path 身份供进度和诊断继续解析。
          openedPath = item.path;
          rebuild(() {});
          showRenameResult('文件已重命名');
        } on FileSystemException {
          // Windows 后端可能独占当前媒体句柄；仅在真实文件系统失败后进入一次受控重试。
          openedPath = null;
          await playerService.pause();
          await playerService.stop();
          try {
            await pageWidget.onRenameFile(item, newBaseName);
            await reopenAfterFileRename(
              path: item.path,
              position: position,
              wasPlaying: wasPlaying,
            );
            if (mounted) {
              showRenameResult('文件已重命名，播放状态已恢复');
            }
          } catch (error) {
            // 重试失败时原路径仍应存在；恢复旧媒体，避免一次命名错误终止当前会话。
            try {
              await reopenAfterFileRename(
                path: oldPath,
                position: position,
                wasPlaying: wasPlaying,
              );
            } catch (_) {
              // 下方错误反馈仍保留准确重试入口；这里不以第二个异常覆盖原始失败原因。
            }
            if (mounted) {
              showRenameResult(playerRenameErrorMessage(error));
            }
          }
        } catch (error) {
          if (mounted) {
            showRenameResult(playerRenameErrorMessage(error));
          }
        }
      });
    } finally {
      renamingFile = false;
    }
  }

  /**
   * 隔离冒烟测试入口；仍执行真实弹窗、文件占用回退和播放恢复链路。
   *
   * 生产 UI 不调用该方法，避免测试通过复制私有实现绕过播放器页面状态。
   */
  @visibleForTesting
  Future<void> renameCurrentFileForTesting() => renameCurrentFile();

  /** 在后端因文件占用被停止后重新打开目标路径并恢复用户可见播放状态。 */
  Future<void> reopenAfterFileRename({
    required String path,
    required Duration position,
    required bool wasPlaying,
  }) async {
    openRequests.clearFailure();
    await applyPlaybackEngineProfile();
    await playerService.openPath(path);
    await applyMediaPresentationProfile();
    if (position > Duration.zero) {
      await playerService.seek(position);
    }
    if (wasPlaying) {
      await playerService.play();
    } else {
      await playerService.pause();
    }
    openedPath = path;
    openRequests.clearFailure();
    lastPersistedPosition = position;
    lastProgressWriteAt = DateTime.now();
    if (mounted) {
      rebuild(() {});
    }
  }

  /** 展示不包含本地路径的重命名结果，避免异常正文泄露用户目录。 */
  void showRenameResult(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /** 把领域校验保留为可理解文案，其它异常统一收敛为安全提示。 */
  String playerRenameErrorMessage(Object error) {
    if (error is StateError) {
      return error.message.toString();
    }
    if (error is FileSystemException) {
      return '无法重命名文件，请检查文件是否被其它程序占用或目标名称已存在';
    }
    return '重命名失败，文件名和媒体库记录均未更改';
  }

  /**
   * 在原生文件对话框或其它不参与 Flutter Focus 树的操作期间暂停全部播放器快捷键。
   */
  Future<T> withPlayerShortcutsSuspended<T>(Future<T> Function() action) async {
    shortcutGate.beginSuspension();
    try {
      return await action();
    } finally {
      shortcutGate.endSuspension();
      restorePlayerShortcutFocus();
    }
  }

  /**
   * 在 Flutter 路由弹层显示前让可选原生视频表面退出对应 airspace。
   *
   * PlayerService 会把该意图转发给支持 airspace 的后端；普通 MediaKit/纹理后端
   * 安全忽略。已知弹层矩形时只裁掉被覆盖区域，让其余视频继续实时播放；未知尺寸
   * 的模态弹窗完整让出。嵌套路由使用栈恢复上一层策略，避免中途闪回 child HWND。
   */
  Future<T> withPlayerOverlaySurfaceOccluded<T>(
    Future<T> Function() action, {
    Rect? overlayRect,
  }) async {
    final boundary = playerService;
    final viewSize = MediaQuery.sizeOf(context);
    overlaySurfaceRects.add(overlayRect);
    try {
      await boundary.setFlutterOverlayVisible(
        true,
        overlayRect: overlayRect,
        viewSize: viewSize,
      );
      return await action();
    } finally {
      if (overlaySurfaceRects.isNotEmpty) {
        overlaySurfaceRects.removeLast();
      }
      if (overlaySurfaceRects.isEmpty) {
        await boundary.setFlutterOverlayVisible(false);
      } else {
        await boundary.setFlutterOverlayVisible(
          true,
          overlayRect: overlaySurfaceRects.last,
          viewSize: mounted ? MediaQuery.sizeOf(context) : viewSize,
        );
      }
    }
  }

  /** 弹层真实布局改变时只更新栈顶矩形，不改变嵌套生命周期。 */
  void updateCurrentPlayerOverlaySurfaceRect(Rect rect) {
    if (!mounted || overlaySurfaceRects.isEmpty) return;
    overlaySurfaceRects[overlaySurfaceRects.length - 1] = rect;
    unawaited(
      playerService.setFlutterOverlayVisible(
        true,
        overlayRect: rect,
        viewSize: MediaQuery.sizeOf(context),
      ),
    );
  }

  /** 获取已挂载菜单项的全局矩形，用于把估算裁剪收紧到真实 PopupMenu。 */
  Rect? globalRectForKey(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  /**
   * PopupMenu 的 route 可能晚于调用方首个 post-frame 才挂载。
   *
   * 有限重试直到菜单项存在，再用真实矩形替换首帧估算；旧实现只测量一次，
   * 未挂载时会永久保留错误的 HWND 黑洞。
   */
  void scheduleContextMenuBoundsUpdate(
    List<GlobalKey> itemKeys, {
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || overlaySurfaceRects.isEmpty) return;
      final itemRects = <Rect>[
        for (final key in itemKeys)
          if (globalRectForKey(key) case final rect?) rect,
      ];
      if (itemRects.isEmpty) {
        if (attempt < 5) {
          Future<void>.delayed(const Duration(milliseconds: 16), () {
            if (mounted) {
              scheduleContextMenuBoundsUpdate(
                itemKeys,
                attempt: attempt + 1,
              );
            }
          });
        }
        return;
      }
      final menuRect = itemRects
          .skip(1)
          .fold(itemRects.first, (a, b) => a.expandToInclude(b));
      updateCurrentPlayerOverlaySurfaceRect(menuRect.inflate(10));
    });
  }

  /** 设置路由首帧前的保守矩形；真实面板挂载后会立即回报并收紧。 */
  Rect estimatedSettingsOverlayRect(Rect anchorRect) {
    final size = MediaQuery.sizeOf(context);
    final right = (size.width - anchorRect.right).clamp(12.0, size.width - 220);
    final bottom =
        (size.height - anchorRect.top + 8).clamp(12.0, size.height - 220);
    return Rect.fromLTWH(
      size.width - right - 304,
      size.height - bottom - 264,
      308,
      268,
    ).intersect(Offset.zero & size);
  }

  /** 右键菜单首帧前按点击点与窗口边缘选择展开方向。 */
  Rect estimatedContextMenuOverlayRect(Offset position) {
    final size = MediaQuery.sizeOf(context);
    const menuSize = Size(300, 180);
    final left = position.dx + menuSize.width <= size.width
        ? position.dx
        : position.dx - menuSize.width;
    final top = position.dy + menuSize.height <= size.height
        ? position.dy
        : position.dy - menuSize.height;
    return (Offset(left, top) & menuSize).inflate(8).intersect(
          Offset.zero & size,
        );
  }

  /** 搜索/弹窗收起后在下一帧把 PageDown、Escape 等键盘导航交还播放器。 */
  void restorePlayerShortcutFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primaryFocus = FocusManager.instance.primaryFocus;
      final focusOnDifferentRoute = playerFocusIsOnDifferentRoute(
          playerContext: context, focus: primaryFocus);
      if (!shortcutGate.canRestoreFocus(
        settingsOpen: settingsDialogOpen,
        focusOnDifferentRoute: focusOnDifferentRoute,
      )) {
        // 其它输入上下文仍有效时不得抢回播放器焦点。
        return;
      }
      focusNode.requestFocus();
    });
  }

  /** 队列搜索只在收起时恢复页面焦点，展开时由 EditableText 的 autofocus 接管。 */
  void handleQueueSearchVisibilityChanged(bool visible) {
    if (!visible) {
      restorePlayerShortcutFocus();
    }
  }

  /** 通过平台边界定位当前媒体文件，并稳定展示失败原因。 */
  Future<void> revealCurrentFile() async {
    try {
      await pageWidget.fileSystem.revealInFileManager(
        playerCurrentRevealPath(playback),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开文件位置，请确认文件仍然存在')),
        );
      }
    }
  }
}
