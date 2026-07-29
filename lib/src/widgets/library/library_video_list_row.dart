import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/playback_settings.dart';
import '../../models/video_item.dart';
import '../../services/media/thumbnail_service.dart';
import '../app_theme_tokens.dart';
import 'library_smoke_keys.dart';
import 'library_video_results.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

class InteractiveVideoListRow extends StatelessWidget {
  const InteractiveVideoListRow({
    required this.item,
    required this.thumbnailService,
    required this.playbackSettings,
    this.onVisible,
    required this.onOpen,
    this.onRevealLocation,
    required this.onToggleFavorite,
    required this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
  });

  final VideoItem item;

  final ThumbnailService thumbnailService;

  final PlaybackSettings playbackSettings;

  /** 当前行进入真实构建范围时的轻量优先级通知。 */
  final ValueChanged<VideoItem>? onVisible;

  final VoidCallback onOpen;

  /** 通过页面注入的平台边界在文件管理器中定位当前行的视频文件。 */
  final VoidCallback? onRevealLocation;

  final VoidCallback onToggleFavorite;

  final VoidCallback onDelete;

  /** 多选模式下整行点击只切换选择。 */
  final bool selectionMode;

  /** 当前行是否已选择。 */
  final bool selected;

  /** 多选状态切换回调。 */
  final VoidCallback? onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final tags = item.tags.toList()..sort();
    return Material(
      key: LibrarySmokeKeys.videoListRow(item.path),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selectionMode ? onToggleSelected : null,
        onDoubleTap: selectionMode ? null : onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: librarySurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: libraryBorder),
          ),
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final thumbnailWidth = narrow ? 116.0 : 146.0;
              final showMediaSummary = constraints.maxWidth >= 1050;
              final showWideTagColumn = constraints.maxWidth >= 1500;
              final visibleTagCount = constraints.maxWidth >= 1300
                  ? 8
                  : narrow
                      ? 2
                      : 4;
              // 中等宽度窗口下右侧标签面板会压缩列表列宽；行按钮应先降级为图标，
              // 而不是继续保留 276px 操作区导致整行底部出现 overflow 条纹。
              final compactActions = constraints.maxWidth < 700;
              return Row(
                children: [
                  if (selectionMode) ...[
                    Checkbox(
                      key: LibrarySmokeKeys.cardSelection(item.path),
                      value: selected,
                      onChanged: onToggleSelected == null
                          ? null
                          : (_) => onToggleSelected!(),
                      shape: const CircleBorder(),
                      activeColor: appAccentViolet,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(
                    width: thumbnailWidth,
                    child: VideoPreview(
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
                                    color: libraryText,
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
                            color: libraryTextMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!showWideTagColumn) ...[
                          const SizedBox(height: 8),
                          _ListTagSummary(
                            tags: tags,
                            visibleTagCount: visibleTagCount,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (showWideTagColumn) ...[
                    // 最大化超宽窗口把标签提升为独立列，避免标题和媒体信息之间形成空带。
                    SizedBox(
                      width: math.min(480, constraints.maxWidth * 0.22),
                      child: _ListTagSummary(
                        tags: tags,
                        visibleTagCount: visibleTagCount,
                        showLabel: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                  if (showMediaSummary) ...[
                    // 超宽列表把既有媒体详情转成固定信息列，填补横向空白但不触发新探测。
                    SizedBox(
                      width: 230,
                      child: _ListMediaSummary(item: item),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (!selectionMode)
                    _ListRowActions(
                      item: item,
                      onOpen: onOpen,
                      onToggleFavorite: onToggleFavorite,
                      onRevealLocation: onRevealLocation,
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

/** 列表行标签摘要；超宽模式可显示列标题，普通模式继续使用原紧凑横向 pills。 */
class _ListTagSummary extends StatelessWidget {
  const _ListTagSummary({
    required this.tags,
    required this.visibleTagCount,
    this.showLabel = false,
  });

  /** 已排序标签名称。 */
  final List<String> tags;

  /** 当前响应式宽度允许直接展示的标签数。 */
  final int visibleTagCount;

  /** 是否在超宽独立列中显示“标签”提示。 */
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          const Text(
            '标签',
            style: TextStyle(
              color: libraryTextMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
        ],
        SizedBox(
          height: 24,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (tags.isEmpty)
                const _ListTagPill(label: '\u672a\u6dfb\u52a0\u6807\u7b7e')
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
    );
  }
}

/** 超宽列表复用已缓存媒体详情和文件大小，不在 build 阶段访问磁盘。 */
class _ListMediaSummary extends StatelessWidget {
  const _ListMediaSummary({required this.item});

  /** 当前列表行的视频；只读取内存字段。 */
  final VideoItem item;

  @override
  Widget build(BuildContext context) {
    final details = item.mediaDetails;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          details?.videoLabel ?? '媒体信息读取中',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: libraryText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${details?.audioLabel ?? '音频信息读取中'} · '
          '${libraryVideoFileSizeLabel(item.fileSize)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: libraryTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/** 把内存中的文件大小转换为列表紧凑标签；未知值不伪造为 0 B。 */
String libraryVideoFileSizeLabel(int? bytes) {
  if (bytes == null || bytes < 0) {
    return '大小读取中';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
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
        color: librarySurfaceAlt,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: libraryBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: libraryTextMuted,
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
    required this.onRevealLocation,
    required this.onDelete,
    required this.compact,
  });

  final VideoItem item;

  final VoidCallback onOpen;

  final VoidCallback onToggleFavorite;

  final VoidCallback? onRevealLocation;

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
            child: VideoMoreButton(
              key: LibrarySmokeKeys.listMore(item.path),
              onRevealLocation: onRevealLocation,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}
