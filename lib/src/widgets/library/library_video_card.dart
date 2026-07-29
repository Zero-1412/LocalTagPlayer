import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/library/library_card_ui_diagnostics.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/media_kit_initializer.dart';
import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class InteractiveVideoCard extends StatefulWidget {
  const InteractiveVideoCard({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.onVisible,
    required this.onOpen,
    this.onRevealLocation,
    required this.onToggleFavorite,
    this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
    this.mediaKitInitializer,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 当前卡片进入真实构建范围时的轻量优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;
  final VoidCallback onOpen;
  /** 标题更多菜单的打开文件入口；平台调用仍由页面层负责。 */
  final VoidCallback? onRevealLocation;
  final VoidCallback onToggleFavorite;
  /** 标题更多菜单的删除入口；为空时不显示卡片更多按钮。 */
  final VoidCallback? onDelete;

  /** 多选模式下卡片点击只切换选择，并关闭动态预览和更多菜单。 */
  final bool selectionMode;

  /** 当前卡片是否已选择。 */
  final bool selected;

  /** 切换当前卡片选择状态。 */
  final VoidCallback? onToggleSelected;

  /** 只供回归测试注入初始化失败；生产路径始终使用进程级默认门禁。 */
  @visibleForTesting
  final MediaKitInitializer? mediaKitInitializer;

  @override
  State<InteractiveVideoCard> createState() => InteractiveVideoCardState();
}

class InteractiveVideoCardState extends State<InteractiveVideoCard> {
  /** 当前卡片预览状态；正式播放前用于先停止独立的悬停解码会话。 */
  final _previewKey = GlobalKey<VideoPreviewState>();
  var _hovered = false;
  var _focused = false;
  var _pressed = false;
  var _moreMenuOpen = false;

  /**
   * 进入正式播放器前先关闭悬停预览的媒体与纹理。
   *
   * 媒体库 Route 会保留在播放器下方，不能依赖 widget dispose 释放预览 Player；
   * 否则正式播放器切换分辨率时会与后台预览同时重建 Windows 纹理。
   */
  Future<void> _openAfterReleasingPreview() async {
    await _previewKey.currentState?.releaseForPlayback();
    if (mounted) {
      widget.onOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final accessibility = AppAccessibilityScope.of(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1);
    final supportsMoreActions =
        !widget.selectionMode && widget.onDelete != null;
    // 标题宽度始终为按钮保留固定槽位；显示状态变化不会触发标题重新换行和卡片抖动。
    final showMore =
        supportsMoreActions && (_hovered || _focused || _moreMenuOpen);
    return LibraryCardUiDiagnostics.buildSubtree(
      'card_shell',
      () => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          child: AnimatedScale(
            duration: accessibility.motionDuration(appMotionDuration),
            curve: appMotionCurve,
            scale: _pressed ? 0.992 : 1,
            child: AnimatedContainer(
              duration: accessibility.fadeDuration(appMotionDuration),
              curve: appMotionCurve,
              decoration: BoxDecoration(
                color: librarySurface,
                borderRadius: BorderRadius.circular(libraryVideoCardRadius),
                border: Border.all(
                  color: widget.selected
                      ? appAccentViolet
                      : _focused
                          ? appAccentViolet.withValues(alpha: 0.78)
                          : _hovered
                              ? libraryTextMuted.withValues(alpha: 0.42)
                              : libraryBorder.withValues(alpha: 0.72),
                  width: widget.selected || _focused ? 1.5 : 1,
                ),
                boxShadow: _hovered && !accessibility.highContrast
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x30000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(libraryVideoCardRadius),
                clipBehavior: Clip.antiAlias,
                child: Semantics(
                  button: true,
                  selected: widget.selectionMode ? widget.selected : null,
                  // 网格卡片本身就是播放/选择入口，必须给键盘、辅助技术和语义压测稳定身份。
                  label: widget.selectionMode
                      ? '选择视频 ${item.title}'
                      : LibrarySmokeSemantics.videoPlay(item),
                  child: InkWell(
                    key: LibrarySmokeKeys.cardOpen(item.path),
                    borderRadius: BorderRadius.circular(libraryVideoCardRadius),
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onFocusChange: (focused) =>
                        setState(() => _focused = focused),
                    // 多选期间点击只更新选择；普通状态才打开完整 filtered queue。
                    onTap: widget.selectionMode
                        ? widget.onToggleSelected
                        : () => unawaited(_openAfterReleasingPreview()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeyedSubtree(
                          key: LibrarySmokeKeys.cardThumbnailSurface(item.path),
                          child: VideoPreview(
                            key: _previewKey,
                            item: item,
                            thumbnailService: widget.thumbnailService,
                            playbackSettings: widget.playbackSettings,
                            hovered: _hovered && !widget.selectionMode,
                            hoverPreviewEnabled: !widget.selectionMode,
                            onVisible: widget.onVisible,
                            onToggleFavorite: widget.selectionMode
                                ? null
                                : widget.onToggleFavorite,
                            selected:
                                widget.selectionMode ? widget.selected : null,
                            onToggleSelected: widget.selectionMode
                                ? widget.onToggleSelected
                                : null,
                            mediaKitInitializer: widget.mediaKitInitializer,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                          child: SizedBox(
                            height: libraryVideoCardMetadataHeightForTextScale(
                              textScaleFactor,
                            ),
                            child: _VideoCardMetadata(
                              item: item,
                              showMore: showMore,
                              onMoreOpened: () =>
                                  setState(() => _moreMenuOpen = true),
                              onMoreClosed: () =>
                                  setState(() => _moreMenuOpen = false),
                              onRevealLocation: widget.selectionMode
                                  ? null
                                  : widget.onRevealLocation,
                              onDelete:
                                  widget.selectionMode ? null : widget.onDelete,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 卡片标题子树。
 *
 * 路径和标签已移除以提高浏览密度；标题右侧固定预留更多按钮槽位，按钮仅在卡片
 * hover、键盘焦点或菜单展开期间可见，避免出现时推动标题换行。
 */
class _VideoCardMetadata extends StatelessWidget {
  const _VideoCardMetadata({
    required this.item,
    required this.showMore,
    required this.onMoreOpened,
    required this.onMoreClosed,
    required this.onRevealLocation,
    required this.onDelete,
  });

  final VideoItem item;
  final bool showMore;
  final VoidCallback onMoreOpened;
  final VoidCallback onMoreClosed;
  final VoidCallback? onRevealLocation;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => LibraryCardUiDiagnostics.buildSubtree(
        'metadata',
        () => LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: libraryText,
                        fontSize:
                            libraryVideoCardTitleFontSize(constraints.maxWidth),
                        fontWeight: FontWeight.w600,
                        height: 1.28,
                        letterSpacing: 0.05,
                      ),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 2),
                SizedBox(
                  width: 28,
                  height: 32,
                  child: ExcludeFocus(
                    excluding: !showMore,
                    child: ExcludeSemantics(
                      excluding: !showMore,
                      child: IgnorePointer(
                        ignoring: !showMore,
                        child: AnimatedOpacity(
                          opacity: showMore ? 1 : 0,
                          duration: libraryCardMoreFadeDuration,
                          curve: Curves.easeOutCubic,
                          child: _VideoCardMoreButton(
                            key: LibrarySmokeKeys.cardMore(item.path),
                            onOpened: onMoreOpened,
                            onClosed: onMoreClosed,
                            onRevealLocation: onRevealLocation,
                            onDelete: onDelete!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

/**
 * 网格卡片标题右侧的悬停更多菜单。
 *
 * 菜单展开时通过 [onOpened] 保持按钮可见；选择或取消后先通知卡片关闭状态，再把
 * 业务动作交还页面层。菜单只保留定位当前文件与删除，删除仍经过页面确认弹窗。
 */
class _VideoCardMoreButton extends StatelessWidget {
  const _VideoCardMoreButton({
    super.key,
    required this.onOpened,
    required this.onClosed,
    required this.onRevealLocation,
    required this.onDelete,
  });

  final VoidCallback onOpened;
  final VoidCallback onClosed;
  final VoidCallback? onRevealLocation;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VideoMoreAction>(
      tooltip: '更多操作',
      icon: const Icon(Icons.more_vert_rounded, size: 21),
      position: PopupMenuPosition.under,
      offset: const Offset(0, -2),
      color: librarySurfaceAlt,
      elevation: 8,
      constraints: libraryVideoMoreMenuConstraints,
      menuPadding: libraryVideoMoreMenuPadding,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: libraryBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      onOpened: onOpened,
      onCanceled: onClosed,
      itemBuilder: (context) => [
        if (onRevealLocation != null)
          const PopupMenuItem(
            key: LibrarySmokeKeys.videoMoreRevealLocation,
            value: VideoMoreAction.revealLocation,
            height: libraryVideoMoreMenuItemHeight,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 19),
                SizedBox(width: 8),
                Text('打开文件'),
              ],
            ),
          ),
        const PopupMenuItem(
          key: LibrarySmokeKeys.videoMoreDelete,
          value: VideoMoreAction.delete,
          height: libraryVideoMoreMenuItemHeight,
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: Color(0xffe26573),
              ),
              SizedBox(width: 8),
              Text('删除文件', style: TextStyle(color: Color(0xffe26573))),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        onClosed();
        switch (value) {
          case VideoMoreAction.revealLocation:
            onRevealLocation?.call();
            break;
          case VideoMoreAction.delete:
            onDelete();
            break;
        }
      },
      style: IconButton.styleFrom(
        foregroundColor: libraryTextMuted,
        fixedSize: const Size(28, 28),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class VideoMoreButton extends StatelessWidget {
  const VideoMoreButton({
    super.key,
    required this.onRevealLocation,
    required this.onDelete,
  });

  final VoidCallback? onRevealLocation;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VideoMoreAction>(
      tooltip: '更多操作',
      icon: const Icon(Icons.more_horiz_rounded),
      position: PopupMenuPosition.under,
      color: librarySurfaceAlt,
      elevation: 8,
      constraints: libraryVideoMoreMenuConstraints,
      menuPadding: libraryVideoMoreMenuPadding,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: libraryBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      itemBuilder: (context) => [
        if (onRevealLocation != null)
          const PopupMenuItem(
            key: LibrarySmokeKeys.videoMoreRevealLocation,
            value: VideoMoreAction.revealLocation,
            height: libraryVideoMoreMenuItemHeight,
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 19),
                SizedBox(width: 8),
                Text('打开文件'),
              ],
            ),
          ),
        const PopupMenuItem(
          key: LibrarySmokeKeys.videoMoreDelete,
          value: VideoMoreAction.delete,
          height: libraryVideoMoreMenuItemHeight,
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: Color(0xffe26573),
              ),
              SizedBox(width: 8),
              Text('删除文件', style: TextStyle(color: Color(0xffe26573))),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case VideoMoreAction.revealLocation:
            onRevealLocation?.call();
            break;
          case VideoMoreAction.delete:
            onDelete();
            break;
        }
      },
      style: IconButton.styleFrom(
        fixedSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/** 媒体卡片更多菜单只保留文件级动作，避免与详情页的标签和改名入口重复。 */
enum VideoMoreAction { revealLocation, delete }
