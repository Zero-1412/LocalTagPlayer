import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/layout_size.dart';
import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/library/library_card_ui_diagnostics.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class VideoGrid extends StatelessWidget {
  const VideoGrid({
    required this.videos,
    required this.thumbnailService,
    required this.playbackSettings,
    required this.dense,
    this.onVisible,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  final List<VideoItem> videos;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  final bool dense;

  /** 实际构建到视口附近时通知页面提升媒体详情任务，不在 build 中做磁盘访问。 */
  final ValueChanged<VideoItem>? onVisible;

  final void Function(VideoItem item, List<VideoItem> playlist) onOpen;

  final ValueChanged<VideoItem> onEditTags;

  final ValueChanged<VideoItem> onToggleFavorite;

  /** 请求删除视频记录；是否同步删除本地文件由 Application 层确认。 */
  final ValueChanged<VideoItem> onDelete;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < LayoutBreakpoints.compactMaxWidth;
        final narrow = constraints.maxWidth < 560;
        if (dense) {
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 22,
              2,
              compact ? 14 : 22,
              22,
            ),
            itemExtent: narrow ? 132 : 120,
            scrollCacheExtent: const ScrollCacheExtent.pixels(720),
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final item = videos[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InteractiveVideoListRow(
                  item: item,
                  thumbnailService: thumbnailService,
                  playbackSettings: playbackSettings,
                  onVisible: onVisible,
                  onOpen: () => onOpen(item, videos),
                  onEditTags: () => onEditTags(item),
                  onToggleFavorite: () => onToggleFavorite(item),
                  onDelete: () => onDelete(item),
                ),
              );
            },
          );
        }
        return GridView.builder(
          padding:
              EdgeInsets.fromLTRB(compact ? 14 : 22, 2, compact ? 14 : 22, 22),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: narrow ? 500 : (compact ? 248 : 286),
            // 单列网格会把 16:9 缩略图拉高，卡片高度必须跟着增长；
            // 否则普通窗口下标题、标签和底部按钮会挤出可视区域。
            mainAxisExtent: narrow ? 430 : (compact ? 300 : 340),
            mainAxisSpacing: compact ? 14 : 16,
            crossAxisSpacing: compact ? 10 : 14,
          ),
          itemCount: videos.length,
          scrollCacheExtent: const ScrollCacheExtent.pixels(720),
          itemBuilder: (context, index) {
            final item = videos[index];
            return InteractiveVideoCard(
              item: item,
              thumbnailService: thumbnailService,
              playbackSettings: playbackSettings,
              onVisible: onVisible,
              onOpen: () => onOpen(item, videos),
              onEditTags: () => onEditTags(item),
              onToggleFavorite: () => onToggleFavorite(item),
              onDelete: () => onDelete(item),
            );
          },
        );
      },
    );
  }
}

/**
 * 列表模式下的单条视频结果。
 *
 * 行内容限制在可读宽度内，避免超宽桌面窗口把“播放 / 收藏 / 更多”
 * 操作区推到视线外，导致入口存在但真实点击和视觉发现都不稳定。
 */
class InteractiveVideoListRow extends StatelessWidget {
  const InteractiveVideoListRow({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.onVisible,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  final VideoItem item;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  /** 当前行进入真实构建范围时的轻量优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;

  final VoidCallback onOpen;

  final VoidCallback onEditTags;

  final VoidCallback onToggleFavorite;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tags = item.tags.toList()..sort();
    return Material(
      key: LibrarySmokeKeys.videoListRow(item.path),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onDoubleTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: appPanel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: appBorder),
          ),
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final thumbnailWidth = narrow ? 116.0 : 146.0;
              final visibleTagCount = narrow ? 2 : 4;
              // 中等宽度窗口下右侧标签面板会压缩列表列宽；行按钮应先降级为图标，
              // 而不是继续保留 276px 操作区导致整行底部出现 overflow 条纹。
              final compactActions = constraints.maxWidth < 700;
              return Row(
                children: [
                  SizedBox(
                    width: thumbnailWidth,
                    child: _VideoPreview(
                      item: item,
                      thumbnailService: thumbnailService,
                      playbackSettings: playbackSettings,
                      onVisible: onVisible,
                      onOpen: (_) => onOpen(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: narrow ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: appText,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff718096),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 24,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              if (tags.isEmpty)
                                const _ListTagPill(
                                  label: '\u672a\u6dfb\u52a0\u6807\u7b7e',
                                )
                              else ...[
                                for (final tag in tags.take(visibleTagCount))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: _ListTagPill(label: tag),
                                  ),
                                if (tags.length > visibleTagCount)
                                  _ListTagPill(
                                    label: '+${tags.length - visibleTagCount}',
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _ListRowActions(
                    item: item,
                    onOpen: onOpen,
                    onToggleFavorite: onToggleFavorite,
                    onEditTags: onEditTags,
                    onDelete: onDelete,
                    compact: compactActions,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ListTagPill extends StatelessWidget {
  const _ListTagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xfff4f6fb),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: appBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xff4b5565),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ListRowActions extends StatelessWidget {
  const _ListRowActions({
    required this.item,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onEditTags,
    required this.onDelete,
    required this.compact,
  });

  final VideoItem item;

  final VoidCallback onOpen;

  final VoidCallback onToggleFavorite;

  final VoidCallback onEditTags;

  final VoidCallback onDelete;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 112 : 276,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!compact) ...[
            Semantics(
              button: true,
              label: LibrarySmokeSemantics.videoPlay(item),
              child: SizedBox(
                width: 78,
                height: 34,
                child: GestureDetector(
                  key: LibrarySmokeKeys.listPlay(item.path),
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: appAccentViolet,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded,
                            size: 18, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '\u64ad\u653e',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Semantics(
            button: true,
            label: LibrarySmokeSemantics.videoFavorite(item),
            selected: item.isFavorite,
            child: IconButton.outlined(
              key: LibrarySmokeKeys.listFavorite(item.path),
              tooltip: item.isFavorite
                  ? '\u53d6\u6d88\u6536\u85cf'
                  : '\u6dfb\u52a0\u6536\u85cf',
              onPressed: onToggleFavorite,
              icon: Icon(
                  item.isFavorite ? Icons.favorite : Icons.favorite_border),
              style: IconButton.styleFrom(
                fixedSize: const Size(34, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: LibrarySmokeSemantics.videoMore(item),
            child: _VideoMoreButton(
              key: LibrarySmokeKeys.listMore(item.path),
              onEditTags: onEditTags,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class InteractiveVideoCard extends StatefulWidget {
  const InteractiveVideoCard({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.onVisible,
    required this.onOpen,
    required this.onEditTags,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 当前卡片进入真实构建范围时的轻量优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;
  final VoidCallback onOpen;
  final VoidCallback onEditTags;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  @override
  State<InteractiveVideoCard> createState() => InteractiveVideoCardState();
}

class InteractiveVideoCardState extends State<InteractiveVideoCard> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
            duration: appMotionDuration,
            curve: appMotionCurve,
            scale: _pressed ? 0.992 : 1,
            child: AnimatedContainer(
              duration: appMotionDuration,
              curve: appMotionCurve,
              decoration: BoxDecoration(
                color: appPanel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hovered ? appAccentViolet : appBorder,
                ),
                boxShadow: [
                  ...appSoftShadow,
                  if (_hovered)
                    BoxShadow(
                      color: appAccentViolet.withAlpha(45),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onDoubleTap: widget.onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _VideoPreview(
                          item: item,
                          thumbnailService: widget.thumbnailService,
                          playbackSettings: widget.playbackSettings,
                          onVisible: widget.onVisible,
                          onOpen: (_) => widget.onOpen(),
                        ),
                        const SizedBox(height: 6),
                        _VideoCardMetadata(item: item),
                        const SizedBox(height: 5),
                        _VideoCardTags(item: item),
                        const Spacer(),
                        _VideoCardActions(
                          item: item,
                          onOpen: widget.onOpen,
                          onToggleFavorite: widget.onToggleFavorite,
                          onEditTags: widget.onEditTags,
                          onDelete: widget.onDelete,
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

/** 卡片标题与路径子树；诊断探针不改变原有行高和文本截断规则。 */
class _VideoCardMetadata extends StatelessWidget {
  const _VideoCardMetadata({required this.item});

  final VideoItem item;

  @override
  Widget build(BuildContext context) => LibraryCardUiDiagnostics.buildSubtree(
        'metadata',
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              item.folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff718096),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

/** 卡片标签子树；排序和 Chip 构建都计入 build 样本。 */
class _VideoCardTags extends StatelessWidget {
  const _VideoCardTags({required this.item});

  final VideoItem item;

  @override
  Widget build(BuildContext context) => LibraryCardUiDiagnostics.buildSubtree(
        'tags',
        () {
          final tags = item.tags.toList()..sort();
          return SizedBox(
            height: 26,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tags.isEmpty
                    ? const [
                        Text(
                          '\u672a\u6dfb\u52a0\u6807\u7b7e',
                          style: TextStyle(color: Colors.black45),
                        ),
                      ]
                    : [
                        for (final tag in tags)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Chip(
                              label: Text(tag),
                              labelStyle: const TextStyle(fontSize: 12),
                              visualDensity: const VisualDensity(
                                horizontal: -3,
                                vertical: -4,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
              ),
            ),
          );
        },
      );
}

/** 卡片底部操作子树；保留原有语义、key 与窄卡片图标模式。 */
class _VideoCardActions extends StatelessWidget {
  const _VideoCardActions({
    required this.item,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onEditTags,
    required this.onDelete,
  });

  final VideoItem item;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditTags;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => LibraryCardUiDiagnostics.buildSubtree(
        'actions',
        () => LayoutBuilder(
          builder: (context, constraints) {
            final iconOnly = constraints.maxWidth < 260;
            return Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: LibrarySmokeSemantics.videoPlay(item),
                    child: FilledButton.icon(
                      key: LibrarySmokeKeys.cardPlay(item.path),
                      onPressed: onOpen,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(iconOnly ? '' : '\u64ad\u653e'),
                      style: FilledButton.styleFrom(
                        backgroundColor: appAccentViolet,
                        foregroundColor: Colors.white,
                        fixedSize: const Size.fromHeight(34),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  selected: item.isFavorite,
                  label: LibrarySmokeSemantics.videoFavorite(item),
                  child: IconButton.outlined(
                    key: LibrarySmokeKeys.cardFavorite(item.path),
                    tooltip: item.isFavorite
                        ? '\u53d6\u6d88\u6536\u85cf'
                        : '\u6dfb\u52a0\u6536\u85cf',
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      item.isFavorite ? Icons.favorite : Icons.favorite_border,
                    ),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(34, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: LibrarySmokeSemantics.videoMore(item),
                  child: _VideoMoreButton(
                    key: LibrarySmokeKeys.cardMore(item.path),
                    onEditTags: onEditTags,
                    onDelete: onDelete,
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _VideoMoreButton extends StatelessWidget {
  const _VideoMoreButton({
    super.key,
    required this.onEditTags,
    required this.onDelete,
  });

  final VoidCallback onEditTags;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_VideoMoreAction>(
      tooltip: '更多操作',
      icon: const Icon(Icons.more_horiz_rounded),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => const [
        PopupMenuItem(
          key: LibrarySmokeKeys.videoMoreEditTags,
          value: _VideoMoreAction.editTags,
          child: Row(
            children: [
              Icon(Icons.sell_outlined),
              SizedBox(width: 10),
              Text('编辑标签'),
            ],
          ),
        ),
        PopupMenuItem(
          key: LibrarySmokeKeys.videoMoreDelete,
          value: _VideoMoreAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Color(0xffc53b4d)),
              SizedBox(width: 10),
              Text('删除', style: TextStyle(color: Color(0xffc53b4d))),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case _VideoMoreAction.editTags:
            onEditTags();
            break;
          case _VideoMoreAction.delete:
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

enum _VideoMoreAction { editTags, delete }

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.onVisible,
    required this.onOpen,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 只通知页面提升媒体详情任务；缩略图仍由共享服务自身的优先队列处理。 */
  final ValueChanged<VideoItem>? onVisible;
  final ValueChanged<VideoItem> onOpen;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late Future<File?> _future;
  Timer? _hoverTimer;
  Player? _hoverPlayer;
  VideoController? _hoverController;
  var _isHoverPreviewLoading = false;
  var _isHoverPreviewReady = false;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
    widget.onVisible?.call(widget.item);
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path ||
        oldWidget.thumbnailService != widget.thumbnailService) {
      _stopHoverPreview();
      _future = widget.thumbnailService.ensureThumbnailFor(widget.item);
      widget.onVisible?.call(widget.item);
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    unawaited(_disposeHoverPlayer());
    super.dispose();
  }

  void _onEnter(PointerEnterEvent _) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 900), _startHoverPreview);
  }

  void _onExit(PointerExitEvent _) {
    _hoverTimer?.cancel();
    _stopHoverPreview();
  }

  Future<void> _startHoverPreview() async {
    if (_hoverPlayer != null || _isHoverPreviewLoading) {
      return;
    }
    setState(() => _isHoverPreviewLoading = true);

    final player = Player(
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

    try {
      await player.setVolume(0);
      await player.open(Media(widget.item.path), play: true).timeout(
            const Duration(seconds: 10),
          );
      await controller.platform.future
          .then((platform) => platform.waitUntilFirstFrameRendered)
          .timeout(const Duration(seconds: 8), onTimeout: () {});
      if (!mounted || _hoverPlayer != player) {
        await player.dispose();
        return;
      }
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = true;
      });
    } catch (_) {
      if (_hoverPlayer == player) {
        _hoverPlayer = null;
        _hoverController = null;
      }
      await player.dispose();
      if (mounted) {
        setState(() {
          _isHoverPreviewLoading = false;
          _isHoverPreviewReady = false;
        });
      }
    }
  }

  void _stopHoverPreview() {
    final player = _hoverPlayer;
    _hoverPlayer = null;
    _hoverController = null;
    if (mounted) {
      setState(() {
        _isHoverPreviewLoading = false;
        _isHoverPreviewReady = false;
      });
    }
    if (player != null) {
      unawaited(player.dispose());
    }
  }

  Future<void> _disposeHoverPlayer() async {
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
      () => MouseRegion(
        onEnter: _onEnter,
        onExit: _onExit,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<File?>(
                  key: ValueKey(widget.item.path),
                  future: _future,
                  builder: (context, snapshot) {
                    final file = snapshot.data;
                    // Future 完成前已验证 JPEG 存在性与完整性，build 阶段不再同步 stat。
                    if (file != null) {
                      return Image.file(
                        file,
                        key: ValueKey(file.path),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: false,
                        // 历史 fallback 缓存中仍有 4K JPEG，按卡片尺寸解码避免占用数十 MiB。
                        cacheWidth: libraryThumbnailWidth,
                      );
                    }
                    return Container(
                      color: const Color(0xffd8f0f0),
                      child: Center(
                        child: snapshot.connectionState ==
                                ConnectionState.waiting
                            ? const SizedBox.square(
                                dimension: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : const Icon(Icons.movie_outlined, size: 42),
                      ),
                    );
                  },
                ),
                if (_isHoverPreviewReady && hoverController != null)
                  Video(
                    controller: hoverController,
                    controls: NoVideoControls,
                    fit: BoxFit.cover,
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
                Center(
                  child: _isHoverPreviewLoading
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.86),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(18),
                            child: SizedBox.square(
                              dimension: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        )
                      : IconButton.filled(
                          tooltip: _isHoverPreviewReady
                              ? '\u6b63\u5728\u9884\u89c8\uff0c\u70b9\u51fb\u64ad\u653e'
                              : '\u64ad\u653e',
                          onPressed: () => widget.onOpen(widget.item),
                          icon: const Icon(Icons.play_arrow_rounded, size: 34),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.88),
                            foregroundColor: const Color(0xff073b3b),
                            fixedSize: const Size(58, 58),
                          ),
                        ),
                ),
              ],
            ),
          ),
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
class LibraryImportDropRegion extends StatefulWidget {
  const LibraryImportDropRegion({
    super.key,
    required this.enabled,
    required this.onDropPaths,
    required this.child,
  });

  /** 当前是否允许接收桌面拖放；扫描期间关闭以避免并发扫描。 */
  final bool enabled;

  /** 用户释放文件后收到的原始本地路径。 */
  final ValueChanged<List<String>> onDropPaths;

  /** 原媒体库结果内容。 */
  final Widget child;

  @override
  State<LibraryImportDropRegion> createState() =>
      _LibraryImportDropRegionState();
}

class _LibraryImportDropRegionState extends State<LibraryImportDropRegion> {
  /** 文件是否正在结果区上方悬停，仅用于绘制反馈，不参与业务筛选。 */
  var _dragging = false;

  /** 更新拖放悬停态；禁用后不保留过期覆盖层。 */
  void _setDragging(bool value) {
    final next = widget.enabled && value;
    if (_dragging == next) {
      return;
    }
    setState(() => _dragging = next);
  }

  @override
  void didUpdateWidget(covariant LibraryImportDropRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _dragging) {
      _dragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      key: LibrarySmokeKeys.importDropRegion,
      enable: widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) {
        _setDragging(false);
        final paths = <String>[
          for (final item in details.files)
            if (item.path.trim().isNotEmpty) item.path,
        ];
        if (paths.isNotEmpty) {
          widget.onDropPaths(paths);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: AnimatedOpacity(
              key: LibrarySmokeKeys.importDropOverlay,
              opacity: _dragging ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: appAccentViolet.withValues(alpha: 0.12),
                  border: Border.all(color: appAccentViolet, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: appPanel,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      boxShadow: appSoftShadow,
                    ),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_download_outlined,
                              size: 42, color: appAccentViolet),
                          SizedBox(height: 10),
                          Text(
                            '释放以添加视频或目录',
                            style: TextStyle(
                              color: appText,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
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
        ],
      ),
    );
  }
}

/** 媒体库、筛选结果和维护页面共用的空状态。 */
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.hasLibrary,
    this.message,
    this.onAddFiles,
  });

  final bool hasLibrary;

  final String? message;

  /** 仅在全库没有视频时提供的多文件选择入口。 */
  final VoidCallback? onAddFiles;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onAddFiles != null) ...[
            Semantics(
              button: true,
              label: '添加视频文件',
              child: Material(
                key: LibrarySmokeKeys.emptyAddFiles,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onAddFiles,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: appPanel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: appAccentViolet, width: 2),
                      boxShadow: appSoftShadow,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 58,
                      color: appAccentViolet,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '添加视频文件',
              style: TextStyle(
                color: appText,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '选择视频文件，或将文件 / 文件夹拖到媒体库区域',
              textAlign: TextAlign.center,
              style: TextStyle(color: appTextMuted, height: 1.4),
            ),
          ] else ...[
            Icon(
              hasLibrary
                  ? Icons.filter_alt_off_outlined
                  : Icons.video_library_outlined,
              size: 54,
              color: Colors.black38,
            ),
            const SizedBox(height: 12),
            Text(message ??
                (hasLibrary
                    ? '\u6ca1\u6709\u5339\u914d\u7684\u89c6\u9891'
                    : '\u6dfb\u52a0\u89c6\u9891\u76ee\u5f55\u540e\u5f00\u59cb\u626b\u63cf')),
          ],
        ],
      ),
    );
  }
}
