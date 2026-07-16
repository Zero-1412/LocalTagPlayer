import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

/**
 * 计算网格视频卡片高度。
 *
 * 卡片只保留 16:9 缩略图与两行标题；收藏和时长位于缩略图叠层，不再为标签、路径或
 * 底部操作区预留垂直空间。单列仍按更宽缩略图单独留足高度，避免窗口缩小时溢出。
 */
double libraryVideoCardMainAxisExtent({
  required double gridWidth,
  required bool narrow,
  required bool compact,
}) {
  final horizontalPadding = compact ? 28.0 : 44.0;
  final spacing = compact ? 10.0 : 14.0;
  final usableWidth = math.max(1.0, gridWidth - horizontalPadding);
  final columnCount = libraryVideoGridColumnCount(
    gridWidth: gridWidth,
    narrow: narrow,
    compact: compact,
  );
  final cardWidth = (usableWidth - spacing * (columnCount - 1)) / columnCount;
  // 66px 覆盖上下内边距、缩略图与标题间距及两行标题；叠层角标不增加高度。
  return cardWidth * 9 / 16 + 66;
}

/** 计算当前响应式网格列数，增量加载和卡片尺寸必须复用同一结果。 */
int libraryVideoGridColumnCount({
  required double gridWidth,
  required bool narrow,
  required bool compact,
}) {
  final horizontalPadding = compact ? 28.0 : 44.0;
  final spacing = compact ? 10.0 : 14.0;
  final maxExtent = narrow ? 500.0 : (compact ? 248.0 : 286.0);
  final usableWidth = math.max(1.0, gridWidth - horizontalPadding);
  return math.max(1, (usableWidth / (maxExtent + spacing)).ceil()).toInt();
}

/** 将已知媒体总时长格式化为卡片角标；未知时长不伪装成 `0:00`。 */
String libraryVideoDurationLabel(Duration duration) {
  if (duration <= Duration.zero) {
    return '--:--';
  }
  final totalSeconds = duration.inSeconds;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final totalMinutes = totalSeconds ~/ 60;
  if (totalMinutes < 60) {
    return '$totalMinutes:$seconds';
  }
  final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
  return '${totalMinutes ~/ 60}:$minutes:$seconds';
}

/** 媒体库每次增量挂载的行数；网格条目数由当前响应式列数换算。 */
const int libraryRowsPerLoad = 10;

/**
 * 距离当前批次末尾多少行时预加载下一批。
 *
 * 该值小于单批 10 行，保证只提前一批，不会在快速滚动时连续扩张到完整结果集。
 */
const int libraryPreloadRowsAhead = 4;

/** 计算首次或下一批应挂载的条目数，不得超过完整筛选结果。 */
int libraryIncrementalItemCount({
  required int totalCount,
  required int currentCount,
  required int columnCount,
}) {
  if (totalCount <= 0) {
    return 0;
  }
  final batchSize = math.max(1, columnCount).toInt() * libraryRowsPerLoad;
  return math
      .min(totalCount, math.max(currentCount, 0).toInt() + batchSize)
      .toInt();
}

/**
 * 媒体库增量滚动结果视图。
 *
 * [videos] 始终保留完整排序/筛选结果，首次和每次触底只追加 10 行可见 Widget。打开
 * 视频时仍把完整列表传给播放器，保证 filtered queue 不被增量挂载边界截断。
 */
class VideoGrid extends StatefulWidget {
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
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  /** 网格和列表共享一个滚动位置；追加批次时不替换控制器，避免画面跳动。 */
  late final ScrollController _scrollController;

  /** 已明确追加的条目数；首次批次会在 build 中按当前列数计算。 */
  var _loadedItemCount = 0;

  /** 当前网格列数；列表模式固定为 1，用于把 10 行换算成条目数。 */
  var _currentColumnCount = 1;

  /** 当前单行高度，用于在距离末尾 4 行时提前追加下一批。 */
  var _currentRowExtent = 120.0;

  /** 合并同一帧内的多个滚动通知，防止一次触底重复追加并引发抖动。 */
  var _loadMoreScheduled = false;

  /** 当前 Sliver 已挂载范围的稳定身份索引；只在结果引用或挂载数量变化时重建。 */
  List<VideoItem>? _indexedVideos;
  var _indexedItemCount = -1;
  Map<String, int> _visibleIndexByVideoId = const <String, int>{};

  /**
   * 用结果数量和首尾稳定身份识别筛选/排序结果变化。
   *
   * 该检查为 O(1)，避免每次收藏或媒体详情更新时扫描 11,000 条结果计算签名。
   */
  (int, String?, String?) _resultBoundarySignature(List<VideoItem> videos) => (
        videos.length,
        videos.isEmpty ? null : videos.first.videoId,
        videos.isEmpty ? null : videos.last.videoId,
      );

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant VideoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resultChanged = _resultBoundarySignature(oldWidget.videos) !=
        _resultBoundarySignature(widget.videos);
    if (resultChanged || oldWidget.dense != widget.dense) {
      // 新筛选、排序或视图模式从首批 10 行开始，并在下一帧安全回到顶部。
      _resetIncrementalResults();
    }
  }

  /** 重置为首批结果；滚动复位延后到布局完成，避免控制器尚未挂载。 */
  void _resetIncrementalResults() {
    _loadedItemCount = 0;
    _loadMoreScheduled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(0);
    });
  }

  /**
   * 返回当前已挂载范围的 videoId -> index 映射。
   *
   * Sliver 通过该映射在筛选后搬移仍存在的 Element；缓存避免媒体详情等外围 setState
   * 在连续加载数百行后反复扫描已挂载范围。
   */
  Map<String, int> _visibleIndexMap(int visibleItemCount) {
    if (identical(_indexedVideos, widget.videos) &&
        _indexedItemCount == visibleItemCount) {
      return _visibleIndexByVideoId;
    }
    _indexedVideos = widget.videos;
    _indexedItemCount = visibleItemCount;
    _visibleIndexByVideoId = <String, int>{
      for (var index = 0; index < visibleItemCount; index++)
        widget.videos[index].videoId: index,
    };
    return _visibleIndexByVideoId;
  }

  /**
   * 下滑到当前批次最后 4 行前追加 10 行，同一帧只允许调度一次。
   *
   * 追加发生在用户触底前；Sliver 仍只构建视口与 cacheExtent 附近项目，因此连续加载
   * 数百行只增长轻量 itemCount，不会同时保活数百行 Widget。
   */
  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _loadMoreScheduled ||
        widget.videos.isEmpty) {
      return;
    }
    if (LibraryCardUiDiagnostics.scrollStatsEnabled) {
      LibraryCardUiDiagnostics.recordScrollActivity(
        loadedItemCount: _loadedItemCount,
      );
    }
    final position = _scrollController.position;
    if (position.extentAfter > _currentRowExtent * libraryPreloadRowsAhead) {
      return;
    }
    final initialCount = libraryIncrementalItemCount(
      totalCount: widget.videos.length,
      currentCount: 0,
      columnCount: _currentColumnCount,
    );
    final currentCount = math.max(_loadedItemCount, initialCount).toInt();
    if (currentCount >= widget.videos.length) {
      return;
    }
    _loadMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final nextCount = libraryIncrementalItemCount(
        totalCount: widget.videos.length,
        currentCount: currentCount,
        columnCount: _currentColumnCount,
      );
      setState(() {
        // 只扩大尾部范围，已有条目、滚动偏移和缩略图 Future 均保持稳定。
        _loadedItemCount = math.max(_loadedItemCount, nextCount).toInt();
        _loadMoreScheduled = false;
      });
      if (LibraryCardUiDiagnostics.scrollStatsEnabled) {
        LibraryCardUiDiagnostics.recordScrollActivity(
          loadedItemCount: nextCount,
        );
      }
    });
  }

  @override
  void dispose() {
    if (LibraryCardUiDiagnostics.scrollStatsEnabled) {
      LibraryCardUiDiagnostics.finishScrollSample();
    }
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < LayoutBreakpoints.compactMaxWidth;
        final narrow = constraints.maxWidth < 560;
        final columnCount = widget.dense
            ? 1
            : libraryVideoGridColumnCount(
                gridWidth: constraints.maxWidth,
                narrow: narrow,
                compact: compact,
              );
        final rowExtent = widget.dense
            ? (narrow ? 132.0 : 120.0)
            : libraryVideoCardMainAxisExtent(
                  gridWidth: constraints.maxWidth,
                  narrow: narrow,
                  compact: compact,
                ) +
                (compact ? 14 : 16);
        _currentColumnCount = columnCount;
        _currentRowExtent = rowExtent;
        final initialCount = libraryIncrementalItemCount(
          totalCount: widget.videos.length,
          currentCount: 0,
          columnCount: columnCount,
        );
        // 窗口改变列数时只允许扩大首批范围，不能让已显示卡片倒退消失。
        final visibleItemCount = math
            .min(
              widget.videos.length,
              math.max(_loadedItemCount, initialCount),
            )
            .toInt();
        // 同步真实首批数量，供预加载阈值和显式压测统计使用；不触发额外 build。
        _loadedItemCount = visibleItemCount;
        final visibleIndexByVideoId = _visibleIndexMap(visibleItemCount);
        final Widget results;
        if (widget.dense) {
          results = ListView.builder(
            key: LibrarySmokeKeys.incrementalResults,
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 22,
              2,
              compact ? 14 : 22,
              12,
            ),
            itemExtent: narrow ? 132 : 120,
            scrollCacheExtent: const ScrollCacheExtent.pixels(720),
            itemCount: visibleItemCount,
            findChildIndexCallback: (key) {
              if (key case ValueKey<String>(value: final value)) {
                return visibleIndexByVideoId[value];
              }
              return null;
            },
            itemBuilder: (context, index) {
              final item = widget.videos[index];
              return Padding(
                key: ValueKey<String>(item.videoId),
                padding: const EdgeInsets.only(bottom: 8),
                child: InteractiveVideoListRow(
                  item: item,
                  thumbnailService: widget.thumbnailService,
                  playbackSettings: widget.playbackSettings,
                  onVisible: widget.onVisible,
                  onOpen: () => widget.onOpen(item, widget.videos),
                  onEditTags: () => widget.onEditTags(item),
                  onToggleFavorite: () => widget.onToggleFavorite(item),
                  onDelete: () => widget.onDelete(item),
                ),
              );
            },
          );
        } else {
          results = GridView.builder(
            key: LibrarySmokeKeys.incrementalResults,
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 22,
              2,
              compact ? 14 : 22,
              12,
            ),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: narrow ? 500 : (compact ? 248 : 286),
              mainAxisExtent: libraryVideoCardMainAxisExtent(
                gridWidth: constraints.maxWidth,
                narrow: narrow,
                compact: compact,
              ),
              mainAxisSpacing: compact ? 14 : 16,
              crossAxisSpacing: compact ? 10 : 14,
            ),
            itemCount: visibleItemCount,
            scrollCacheExtent: const ScrollCacheExtent.pixels(720),
            findChildIndexCallback: (key) {
              if (key case ValueKey<String>(value: final value)) {
                return visibleIndexByVideoId[value];
              }
              return null;
            },
            itemBuilder: (context, index) {
              final item = widget.videos[index];
              return KeyedSubtree(
                key: ValueKey<String>(item.videoId),
                child: InteractiveVideoCard(
                  item: item,
                  thumbnailService: widget.thumbnailService,
                  playbackSettings: widget.playbackSettings,
                  onVisible: widget.onVisible,
                  onOpen: () => widget.onOpen(item, widget.videos),
                  onToggleFavorite: () => widget.onToggleFavorite(item),
                ),
              );
            },
          );
        }
        return results;
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
    required this.onToggleFavorite,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 当前卡片进入真实构建范围时的轻量优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;

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
                  key: LibrarySmokeKeys.cardOpen(item.path),
                  borderRadius: BorderRadius.circular(8),
                  // 独立播放按钮移除后，卡片本身成为唯一清晰的打开入口。
                  onTap: widget.onOpen,
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
                          onToggleFavorite: widget.onToggleFavorite,
                        ),
                        const SizedBox(height: 6),
                        _VideoCardMetadata(item: item),
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

/** 卡片标题子树；路径、标签和操作区已从网格卡片移除以提高浏览密度。 */
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
          ],
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
    this.onToggleFavorite,
  });

  final VideoItem item;
  final ThumbnailService thumbnailService;
  final PlaybackSettings playbackSettings;
  /** 只通知页面提升媒体详情任务；缩略图仍由共享服务自身的优先队列处理。 */
  final ValueChanged<VideoItem>? onVisible;

  /** 网格卡片传入时在缩略图左上角显示收藏入口；列表预览保持原有紧凑动作区。 */
  final VoidCallback? onToggleFavorite;

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
                  // 已在本进程验证过的 JPEG 直接用于首帧；Future 继续负责缓存失效后的
                  // 异步校验/生成，筛选重排时不再先闪回加载占位。
                  initialData:
                      widget.thumbnailService.cachedThumbnailFor(widget.item),
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
                if (_isHoverPreviewLoading)
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.86),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(18),
                        child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ),
                if (widget.onToggleFavorite != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Semantics(
                      button: true,
                      selected: widget.item.isFavorite,
                      label: LibrarySmokeSemantics.videoFavorite(widget.item),
                      child: IconButton.filled(
                        key: LibrarySmokeKeys.cardFavorite(widget.item.path),
                        tooltip: widget.item.isFavorite ? '取消收藏' : '添加收藏',
                        onPressed: widget.onToggleFavorite,
                        icon: Icon(
                          widget.item.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x99000000),
                          foregroundColor: widget.item.isFavorite
                              ? const Color(0xffff5a6f)
                              : Colors.white,
                          fixedSize: const Size(34, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xb3000000),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Text(
                        libraryVideoDurationLabel(
                          widget.item.playbackDuration,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
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
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      // 使用接近页面底色的浅紫灰，而不是独立白卡片，降低空状态入口的突兀感。
                      color: const Color(0xffeef1fa),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0x596d5dfc),
                        width: 1.25,
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x126d5dfc),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 48,
                      color: Color(0xff756ae8),
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
                fontSize: 16,
                fontWeight: FontWeight.w700,
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
