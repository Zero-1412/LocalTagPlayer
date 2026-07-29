import 'package:flutter/material.dart';

import '../../models/media_details.dart';
import '../../models/video_item.dart';
import '../../widgets/app_theme_tokens.dart';

// ignore_for_file: slash_for_doc_comments

/** 把队列条目的只读媒体详情格式化为稳定的辅助文案。 */
String queueListItemDetailsLine(VideoItem item, MediaDetails? details) {
  if (item.isMissing) {
    return '路径失效 · 可重新关联';
  }
  if (details == null) {
    return '\u5a92\u4f53\u4fe1\u606f\u8bfb\u53d6\u4e2d';
  }
  return '${details.videoLabel}  |  ${details.audioLabel}';
}

/**
 * 队列条目滑开后显示的收藏与删除操作区。
 *
 * 组件只接收当前条目快照与已包装的回调；滑动状态、队列所有权和删除确认仍由调用方
 * 持有。
 */
class QueueListItemActionBackground extends StatelessWidget {
  const QueueListItemActionBackground({
    super.key,
    required this.item,
    required this.width,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  /** 当前队列条目的只读快照。 */
  final VideoItem item;

  /** 与前景滑动距离一致的操作区宽度。 */
  final double width;

  /** 请求调用方切换收藏并收起操作区。 */
  final VoidCallback onToggleFavorite;

  /** 请求调用方进入删除确认并收起操作区。 */
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: playerSurface),
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Padding(
            // 操作面板与前景卡片共享 Stack 的完整高度，只保留横向呼吸空间。
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: DecoratedBox(
              key: ValueKey('player.queue.actionPanel.${item.videoId}'),
              decoration: BoxDecoration(
                color: playerSurfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: playerBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: item.isFavorite ? '取消收藏' : '收藏',
                        child: Material(
                          key: ValueKey(
                            'player.queue.favoriteActionSurface.${item.videoId}',
                          ),
                          // 红心本身已明确表达收藏状态，不再叠加发光式色块。
                          color: Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          child: InkWell(
                            key: ValueKey(
                              'player.queue.favoriteAction.${item.videoId}',
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            onTap: onToggleFavorite,
                            child: Icon(
                              item.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: playerDanger,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: playerBorder,
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: '删除',
                        child: Material(
                          color: Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          child: InkWell(
                            key: ValueKey(
                              'player.queue.deleteAction.${item.videoId}',
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            onTap: onDelete,
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: playerDanger,
                              size: 20,
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
        ),
      ),
    );
  }
}
