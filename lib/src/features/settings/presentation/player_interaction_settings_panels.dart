import 'package:flutter/material.dart';

import '../../../core/playback_settings.dart';
import '../../../widgets/app_theme_tokens.dart';
import '../../../widgets/player_shortcut_input.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 全屏右侧边缘播放列表的展示卡。
 *
 * 组件不保存设置或触发播放器命令，只把用户意图交还设置页。
 */
class FullscreenQueueSettingsCard extends StatelessWidget {
  const FullscreenQueueSettingsCard({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /** 当前是否允许鼠标触碰右侧边缘展开播放列表。 */
  final bool enabled;

  /** 开关意图回调。 */
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('settings.fullscreenQueue.card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SwitchListTile.adaptive(
          key: const ValueKey('settings.fullscreenQueue.edgeHoverEnabled'),
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: onChanged,
          secondary: DecoratedBox(
            decoration: BoxDecoration(
              color: appAccentViolet.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: const SizedBox.square(
              dimension: 42,
              child: Icon(
                Icons.playlist_play_rounded,
                color: libraryAccent,
              ),
            ),
          ),
          title: const Text(
            '全屏边缘播放列表',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          subtitle: const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Text(
              '开启后将鼠标移到屏幕右侧边缘即可展开；触发范围与隐藏延迟使用流畅度验证后的默认值。',
              style: TextStyle(color: libraryTextMuted, height: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * 播放器快捷键设置卡。
 *
 * [shortcuts] 和 [errors] 都是页面当前快照；录制、冲突判断、恢复默认与持久化仍由
 * `CacheSettingsPage` 通过回调完成，组件不维护第二份快捷键状态。
 */
class PlayerShortcutsSettingsCard extends StatelessWidget {
  const PlayerShortcutsSettingsCard({
    super.key,
    required this.shortcuts,
    required this.errors,
    required this.onReset,
    required this.onCaptured,
  });

  /** 每个播放器动作的当前快捷键。 */
  final Map<PlayerShortcutAction, String> shortcuts;

  /** 页面已计算的逐动作冲突说明。 */
  final Map<PlayerShortcutAction, String?> errors;

  /** 恢复默认意图。 */
  final VoidCallback onReset;

  /** 录制结果回调；返回 false 时录制器继续展示错误状态。 */
  final bool Function(PlayerShortcutAction action, String shortcut) onCaptured;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '播放器快捷键',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '点击动作后直接按键；冲突时会就地提示，不会自动交换或覆盖。',
                        style: TextStyle(color: libraryTextMuted),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('settings.shortcuts.reset'),
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('恢复默认'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 14.0;
                final fieldWidth = constraints.maxWidth >= 680
                    ? (constraints.maxWidth - spacing) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: spacing,
                  runSpacing: 12,
                  children: [
                    for (final action in PlayerShortcutAction.values)
                      SizedBox(
                        width: fieldWidth,
                        child: PlayerShortcutRecorder(
                          action: action,
                          shortcut: shortcuts[action]!,
                          errorText: errors[action],
                          onCaptured: (shortcut) =>
                              onCaptured(action, shortcut),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            const Text(
              '支持常用单键及 Ctrl / Alt / Shift 组合键。Esc 在全屏时始终优先退出全屏，避免失去安全出口。',
              style: TextStyle(color: libraryTextMuted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
