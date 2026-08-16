import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/library/library_card_ui_diagnostics.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/media_kit_initializer.dart';
import '../app_theme_tokens.dart';
import 'library_hover_preview_coordinator.dart';
import 'library_smoke_keys.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class VideoPreview extends StatefulWidget {
  const VideoPreview({
    super.key,
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.hovered = false,
    this.hoverPreviewEnabled = true,
    this.onVisible,
    this.onToggleFavorite,
    this.selected,
    this.onToggleSelected,
    this.mediaKitInitializer,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 网格卡片 hover 状态；列表预览保持 false，不引入额外动画。 */
  final bool hovered;
  /** 多选模式关闭动态预览，避免选择过程中创建原生播放器和画面干扰。 */
  final bool hoverPreviewEnabled;
  /** 只通知页面提升媒体详情任务；缩略图仍由共享服务自身的优先队列处理。 */
  final ValueChanged<VideoItem>? onVisible;
  /** 网格卡片传入时在缩略图左上角显示收藏入口；列表预览保持原有紧凑动作区。 */
  final VoidCallback? onToggleFavorite;
  /** 非 null 表示多选模式，并作为圆形复选框当前值。 */
  final bool? selected;
  /** 多选模式切换回调；与 [selected] 同时存在时替换收藏红心。 */
  final VoidCallback? onToggleSelected;

  /** 悬停预览创建 Player 前使用的初始化门禁。 */
  final MediaKitInitializer? mediaKitInitializer;

  @override
  State<VideoPreview> createState() => VideoPreviewState();
}

class VideoPreviewState extends State<VideoPreview> {
  late Future<File?> _future;
  LibraryHoverPreviewCoordinator? _previewCoordinator;
  LibraryHoverPreviewCoordinator? _ownedPreviewCoordinator;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
    widget.onVisible?.call(widget.item);
  }

  @override
  void didUpdateWidget(covariant VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoverPreviewEnabled && !widget.hoverPreviewEnabled) {
      _onExit();
    }
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.thumbnailService != widget.thumbnailService) {
      _previewCoordinator?.exit(oldWidget.item);
      _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
      widget.onVisible?.call(widget.item);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scoped = LibraryHoverPreviewScope.maybeOf(context);
    final next = scoped ??
        (_ownedPreviewCoordinator ??= LibraryHoverPreviewCoordinator());
    if (identical(_previewCoordinator, next)) {
      return;
    }
    _previewCoordinator?.removeListener(_handlePreviewChanged);
    _previewCoordinator = next;
    _previewCoordinator!.addListener(_handlePreviewChanged);
  }

  void _handlePreviewChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _previewCoordinator?.removeListener(_handlePreviewChanged);
    if (identical(_previewCoordinator, _ownedPreviewCoordinator)) {
      unawaited(_ownedPreviewCoordinator!.disposeAsync());
    }
    super.dispose();
  }

  /** 重新进入正在淡出的预览时复用现有播放器，避免边缘移动反复初始化。 */
  void _onEnter() {
    if (!widget.hoverPreviewEnabled) {
      return;
    }
    _previewCoordinator?.reenter(widget.item);
  }

  /** 已显示的预览先淡出；尚在加载的预览直接取消，避免离开后才闪出首帧。 */
  void _onExit() {
    _previewCoordinator?.exit(
      widget.item,
      delay: libraryHoverPreviewFadeDuration,
    );
  }

  /** 创建静音原生播放器，并仅在当前卡片仍持有该播放器时展示首帧。 */
  Future<void> _startHoverPreview() async {
    final coordinator = _previewCoordinator;
    if (!mounted ||
        !widget.hoverPreviewEnabled ||
        coordinator == null ||
        coordinator.isLoadingFor(widget.item) ||
        coordinator.isReadyFor(widget.item)) {
      return;
    }
    await coordinator.open(
      item: widget.item,
      settings: widget.playbackSettings,
      initializer: widget.mediaKitInitializer ?? defaultMediaKitInitializer,
    );
  }

  /**
   * 卡片进入正式播放前释放媒体库共享预览，再创建正式播放器。
   *
   * 共享预览不能与正式播放器同时保留两条原生解码链；释放动作有界等待，避免点击
   * 被悬停预览的 native 尾部回收拖住。
   */
  Future<void> releaseForPlayback() =>
      _previewCoordinator?.releaseForPlayback() ?? Future<void>.value();

  @override
  Widget build(BuildContext context) {
    final coordinator = _previewCoordinator;
    final hoverController = coordinator?.controller;
    final previewReady = coordinator?.isReadyFor(widget.item) ?? false;
    final previewVisible = coordinator?.isVisibleFor(widget.item) ?? false;
    final previewLoading = coordinator?.isLoadingFor(widget.item) ?? false;
    return LibraryCardUiDiagnostics.buildSubtree(
      'preview',
      () => LibraryHoverIntentRegion(
        key: ValueKey<String>('hover-intent:${widget.item.path}'),
        onEnter: _onEnter,
        onIntent: () => unawaited(_startHoverPreview()),
        onExit: _onExit,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final overlay = libraryVideoOverlayMetrics(constraints.maxWidth);
            return ClipRRect(
              borderRadius: BorderRadius.circular(libraryVideoCardRadius),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LibraryThumbnailHoverScale(
                      key: LibrarySmokeKeys.cardThumbnailZoom(widget.item.path),
                      hovered: widget.hovered,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          FutureBuilder<File?>(
                            key: ValueKey(widget.item.path),
                            future: _future,
                            // 已在本进程验证过的 JPEG 直接用于首帧；Future 继续负责缓存失效后的
                            // 异步校验/生成，筛选重排时不再先闪回加载占位。
                            initialData: widget.thumbnailService
                                .cachedThumbnailFor(widget.item),
                            builder: (context, snapshot) {
                              final file = snapshot.data;
                              // Future 完成前已验证 JPEG 存在性与完整性，build 阶段不再同步 stat。
                              if (file != null) {
                                return Image.file(
                                  file,
                                  key: ValueKey(file.path),
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.medium,
                                  gaplessPlayback: true,
                                  // 历史 fallback 缓存中仍有 4K JPEG，按卡片尺寸解码避免占用数十 MiB。
                                  cacheWidth: libraryThumbnailWidth,
                                );
                              }
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const LibraryThumbnailPlaceholder(
                                  state:
                                      LibraryThumbnailPlaceholderState.loading,
                                );
                              }
                              if (snapshot.hasError) {
                                return const LibraryThumbnailPlaceholder(
                                  state:
                                      LibraryThumbnailPlaceholderState.failed,
                                );
                              }
                              return const LibraryThumbnailPlaceholder(
                                state: LibraryThumbnailPlaceholderState.empty,
                              );
                            },
                          ),
                          if (previewReady && hoverController != null)
                            LibraryHoverPreviewFade(
                              key: LibrarySmokeKeys.cardHoverPreview(
                                widget.item.path,
                              ),
                              visible: previewVisible,
                              child: Video(
                                controller: hoverController,
                                controls: NoVideoControls,
                                fit: BoxFit.cover,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.02),
                              Colors.black.withValues(alpha: 0.34),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (previewLoading)
                      Center(
                        key: LibrarySmokeKeys.cardHoverPreviewLoading(
                          widget.item.path,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.64),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(18),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: appAccentViolet,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (widget.selected != null &&
                        widget.onToggleSelected != null)
                      Positioned(
                        top: overlay.edgeInset,
                        left: overlay.edgeInset,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            shape: BoxShape.circle,
                          ),
                          child: Checkbox(
                            key: LibrarySmokeKeys.cardSelection(
                              widget.item.path,
                            ),
                            value: widget.selected,
                            onChanged: (_) => widget.onToggleSelected!(),
                            shape: const CircleBorder(),
                            activeColor: appAccentViolet,
                            checkColor: Colors.white,
                            side: const BorderSide(
                              color: Colors.white,
                              width: 1.6,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      )
                    else if (widget.onToggleFavorite != null)
                      Positioned(
                        top: overlay.edgeInset,
                        left: overlay.edgeInset,
                        child: Semantics(
                          button: true,
                          selected: widget.item.isFavorite,
                          label:
                              LibrarySmokeSemantics.videoFavorite(widget.item),
                          child: IconButton(
                            key:
                                LibrarySmokeKeys.cardFavorite(widget.item.path),
                            tooltip: widget.item.isFavorite ? '取消收藏' : '添加收藏',
                            onPressed: widget.onToggleFavorite,
                            icon: Icon(
                              widget.item.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: overlay.favoriteIconSize,
                              shadows: const <Shadow>[
                                Shadow(
                                  color: Color(0x99000000),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              focusColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              foregroundColor: widget.item.isFavorite
                                  ? const Color(0xffff5a6f)
                                  : Colors.white.withValues(alpha: 0.94),
                              fixedSize:
                                  Size.square(overlay.favoriteButtonSize),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: overlay.edgeInset,
                      bottom: overlay.edgeInset,
                      child: AnimatedOpacity(
                        key: LibrarySmokeKeys.cardDuration(widget.item.path),
                        opacity: libraryDurationOpacityForPreview(
                          previewVisible,
                        ),
                        duration: libraryHoverPreviewFadeDuration,
                        curve: Curves.easeOutCubic,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                              alpha: libraryDurationOverlayOpacity,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: overlay.durationHorizontalPadding,
                              vertical: overlay.durationVerticalPadding,
                            ),
                            child: Text(
                              libraryVideoDurationLabel(
                                widget.item.playbackDuration,
                              ),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: overlay.durationFontSize,
                                fontWeight: FontWeight.w600,
                                height: 1,
                                shadows: const <Shadow>[
                                  Shadow(
                                    color: Color(0xcc000000),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
