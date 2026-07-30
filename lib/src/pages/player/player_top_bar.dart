import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import '../../widgets/design_system/app_interaction_surface.dart';

// ignore_for_file: slash_for_doc_comments

/** 普通窗口播放器顶栏的固定高度，供右侧覆盖队列保持同一内容起点。 */
const playerTopBarHeight = 64.0;

/**
 * Apple 式播放器顶栏。
 *
 * 顶栏只展示当前播放文件名和导航动作；队列搜索保留在右侧列表内部，避免同一功能
 * 重复占用视频上方空间，也不提供绕过媒体库与 filtered queue 的“打开文件”。
 */
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.currentFileName,
    this.contextLabel,
    required this.onBack,
  });

  /** 当前实际播放视频的完整文件名，包含扩展名。 */
  final String currentFileName;

  /** 当前 filtered queue 的序号与筛选摘要，只读展示且不参与队列计算。 */
  final String? contextLabel;

  /** 返回媒体库并释放当前播放器会话。 */
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: playerTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: const BoxDecoration(
        color: playerSurface,
        border: Border(bottom: BorderSide(color: playerBorder)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PlayerTopBarAction(
              key: const ValueKey('player.back'),
              tooltip: '返回媒体库',
              semanticLabel: '返回媒体库',
              onPressed: onBack,
              icon: Icons.arrow_back_ios_new_rounded,
            ),
          ),
          Padding(
            // 两侧保留对称安全区，使标题不受队列按钮显隐影响而偏移。
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Tooltip(
                message: currentFileName,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      currentFileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: playerText,
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: AppTypography.strong,
                        height: 1.15,
                      ),
                    ),
                    if (contextLabel != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        contextLabel!,
                        key: const ValueKey('player.topbar.context'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: playerTextMuted,
                          fontSize: AppTypography.caption,
                          fontWeight: AppTypography.medium,
                          height: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/** 顶栏紧凑动作，复用共享 press、hover、focus 与 reduced-motion 反馈。 */
class PlayerTopBarAction extends StatelessWidget {
  const PlayerTopBarAction({
    super.key,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AppInteractionSurface(
        onTap: onPressed,
        semanticLabel: semanticLabel,
        padding: EdgeInsets.zero,
        backgroundColor: playerSurfaceAlt,
        child: SizedBox.square(
          dimension: 40,
          child: Icon(icon, size: 19, color: playerText),
        ),
      ),
    );
  }
}
