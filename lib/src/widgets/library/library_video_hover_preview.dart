import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/library/library_card_ui_diagnostics.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/player/media_kit_initializer.dart';
import '../app_theme_tokens.dart';
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
  Timer? _hoverExitTimer;
  Player? _hoverPlayer;
  VideoController? _hoverController;
  var _isHoverPreviewLoading = false;
  var _isHoverPreviewReady = false;
  var _isHoverPreviewVisible = false;
  /** 每次创建或停止预览都会递增，阻止旧 open Future 恢复过期画面。 */
  var _hoverPreviewGeneration = 0;

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
      _stopHoverPreview();
    }
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.thumbnailService != widget.thumbnailService) {
      _stopHoverPreview();
      _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
      widget.onVisible?.call(widget.item);
    }
  }

  @override
  void dispose() {
    _hoverExitTimer?.cancel();
    unawaited(_disposeHoverPlayer());
    super.dispose();
  }

  /** 重新进入正在淡出的预览时复用现有播放器，避免边缘移动反复初始化。 */
  void _onEnter() {
    if (!widget.hoverPreviewEnabled) {
      return;
    }
    _hoverExitTimer?.cancel();
    _hoverExitTimer = null;
    if (_isHoverPreviewReady && !_isHoverPreviewVisible && mounted) {
      setState(() => _isHoverPreviewVisible = true);
    }
  }

  /** 已显示的预览先淡出；尚在加载的预览直接取消，避免离开后才闪出首帧。 */
  void _onExit() {
    if (_isHoverPreviewReady && _hoverPlayer != null) {
      setState(() => _isHoverPreviewVisible = false);
      _hoverExitTimer?.cancel();
      _hoverExitTimer = Timer(
        libraryHoverPreviewFadeDuration,
        _stopHoverPreview,
      );
      return;
    }
    _stopHoverPreview();
  }

  /** 创建静音原生播放器，并仅在当前卡片仍持有该播放器时展示首帧。 */
  Future<void> _startHoverPreview() async {
    if (!mounted ||
        !widget.hoverPreviewEnabled ||
        _hoverPlayer != null ||
        _isHoverPreviewLoading) {
      return;
    }
    setState(() => _isHoverPreviewLoading = true);
    final generation = ++_hoverPreviewGeneration;
    Player? player;
    try {
      // 上次为避免首帧前阻塞将 media_kit 改为延迟初始化；悬停
      // 预览也是真实 Player 消费者，必须与正式播放共用同一门禁。
      (widget.mediaKitInitializer ?? defaultMediaKitInitializer)
          .ensureInitialized();
      if (!mounted ||
          !widget.hoverPreviewEnabled ||
          generation != _hoverPreviewGeneration) {
        if (mounted && generation == _hoverPreviewGeneration) {
          setState(() => _isHoverPreviewLoading = false);
        }
        return;
      }
      player = Player(
        configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
      );
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          width: 640,
          height: 360,
          hwdec: widget.playbackSettings.hwdec,
          enableHardwareAcceleration:
              widget.playbackSettings.hardwareDecodingEnabled,
        ),
      );

      _hoverPlayer = player;
      _hoverController = controller;
      await player.setVolume(0);
      await player.open(Media(widget.item.path), play: true).timeout(
            const Duration(seconds: 10),
          );
      await controller.platform.future
          .then((platform) => platform.waitUntilFirstFrameRendered)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      if (!mounted ||
          generation != _hoverPreviewGeneration ||
          _hoverPlayer != player) {
        // 停止路径已经接管并释放该 Player，旧 Future 不得重复 dispose。
        return;
      }
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = true;
        _isHoverPreviewVisible = true;
      });
    } catch (error) {
      final generationStillCurrent = generation == _hoverPreviewGeneration;
      final ownsPlayer = _hoverPlayer == player;
      if (ownsPlayer) {
        _hoverPlayer = null;
        _hoverController = null;
      }
      if (player != null && (ownsPlayer || generationStillCurrent)) {
        await player.dispose();
      }
      if (!generationStillCurrent) {
        // 用户已离开或进入正式播放时属于主动取消，不记录为预览失败。
        return;
      }
      if (mounted) {
        setState(() {
          _isHoverPreviewLoading = false;
          _isHoverPreviewReady = false;
          _isHoverPreviewVisible = false;
        });
      }
      // 只记录文件名与错误，不输出用户完整媒体路径。
      debugPrint(
        'LIBRARY_HOVER_PREVIEW status=failed '
        'file=${p.basename(widget.item.path)} error=$error',
      );
    }
  }

  /** 取消淡出计时并释放当前卡片独占的动态预览资源。 */
  void _stopHoverPreview() {
    unawaited(_releaseHoverPlayer(stopMediaFirst: false));
  }

  /**
   * 卡片进入正式播放前停止悬停媒体，再把原生销毁尾部留在后台完成。
   *
   * `stop` 会先关闭当前媒体与视频输出，避免媒体库下层 Route 的预览纹理与正式
   * Player 同时切换分辨率；dispose 不阻塞页面跳转，以保持点击后的响应速度。
   */
  Future<void> releaseForPlayback() =>
      _releaseHoverPlayer(stopMediaFirst: true);

  /** 统一取消旧代次并释放当前预览 Player，防止异步 open 回写已停止状态。 */
  Future<void> _releaseHoverPlayer({required bool stopMediaFirst}) async {
    _hoverPreviewGeneration++;
    _hoverExitTimer?.cancel();
    _hoverExitTimer = null;
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (mounted) {
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = false;
        _isHoverPreviewVisible = false;
      });
    }
    if (player != null) {
      if (stopMediaFirst) {
        try {
          await player.stop().timeout(const Duration(milliseconds: 800));
        } catch (_) {
          // stop 超时仍继续销毁；正式播放器不等待预览原生线程的延迟回收尾部。
        }
      }
      unawaited(player.dispose());
    }
  }

  Future<void> _disposeHoverPlayer() async {
    _hoverPreviewGeneration++;
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (player != null) {
      await player.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoverController = _hoverController;
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
                          if (_isHoverPreviewReady && hoverController != null)
                            LibraryHoverPreviewFade(
                              key: LibrarySmokeKeys.cardHoverPreview(
                                widget.item.path,
                              ),
                              visible: _isHoverPreviewVisible,
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
                    if (_isHoverPreviewLoading)
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
                          _isHoverPreviewVisible,
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

/**
 * 媒体库结果区的桌面文件拖放边界。
 *
 * 组件只负责接收路径和提供轻量覆盖反馈；目录识别、视频扩展名校验和扫描由页面应用链路负责，
 * 避免拖动经过 UI 时触发文件系统访问或全列表 rebuild。
 */
