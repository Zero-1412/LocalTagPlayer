import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';
import 'player_queue_sidebar.dart';

// ignore_for_file: slash_for_doc_comments

class PlayerChildTagChip extends StatelessWidget {
  const PlayerChildTagChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        selected ? appAccentViolet.withValues(alpha: 0.20) : playerSurfaceAlt;
    final borderColor = selected ? appAccentViolet : playerBorder;
    final textColor = selected ? playerText : playerTextMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight:
                  selected ? AppTypography.strong : AppTypography.medium,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class QueueStateBadge extends StatelessWidget {
  const QueueStateBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.capsule),
        border: Border.all(color: color.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class QueueFloatingLocator extends StatelessWidget {
  const QueueFloatingLocator({
    super.key,
    required this.showPlaying,
    required this.showSelected,
    required this.onReturnToPlaying,
    required this.onLocateSelected,
  });

  final bool showPlaying;
  final bool showSelected;
  final VoidCallback onReturnToPlaying;
  final VoidCallback onLocateSelected;

  @override
  Widget build(BuildContext context) {
    final accessibility = AppAccessibilityScope.of(context);
    return AnimatedOpacity(
      duration: accessibility.fadeDuration(AppMotion.hover),
      opacity: showPlaying || showSelected ? 1 : 0,
      child: SizedBox(
        height: playerQueueLocatorHeight,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: playerSurfaceRaised,
            border: Border(top: BorderSide(color: playerBorder)),
            boxShadow: [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Row(
            // 操作按钮填满停靠栏，整块可见区域均可点击。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPlaying)
                Expanded(
                  child: QueueLocatorButton(
                    icon: Icons.play_arrow_rounded,
                    label: '回到播放',
                    onPressed: onReturnToPlaying,
                  ),
                ),
              if (showPlaying && showSelected)
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: playerBorder,
                ),
              if (showSelected)
                Expanded(
                  child: QueueLocatorButton(
                    icon: Icons.center_focus_strong_rounded,
                    label: '回到选中',
                    onPressed: onLocateSelected,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class QueueLocatorButton extends StatelessWidget {
  const QueueLocatorButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: playerText,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
