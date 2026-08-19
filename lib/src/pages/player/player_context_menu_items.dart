import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';

/// 构建播放器上下文菜单的展示项。
///
/// 临时 [GlobalKey] 仍由调用方持有，用于 overlay 边界测量；菜单项内部的稳定
/// [ValueKey] 只服务挂载、键盘和语义回归，不承载播放器状态或业务动作。
List<PopupMenuEntry<String>> buildPlayerContextMenuItems({
  required GlobalKey infoItemKey,
  required GlobalKey diagnosticsItemKey,
  bool includePrecisionControls = false,
  bool includeExternalSubtitle = false,
}) {
  return [
    PopupMenuItem(
      key: infoItemKey,
      value: 'info',
      child: Semantics(
        key: const ValueKey('player.contextMenu.info'),
        container: true,
        button: true,
        label: '视频信息',
        child: ListTile(
          dense: true,
          // PopupMenuRoute 不保证把父级 PopupMenuTheme 的文字色传入自定义
          // ListTile；这里显式指定前景色，避免播放器深色表面退回黑色文字。
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: const TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: const Icon(
            Icons.info_outline,
            color: playerTextMuted,
          ),
          title: const Text(
            '视频信息',
            style: TextStyle(
              color: playerText,
              fontSize: AppTypography.body,
            ),
          ),
        ),
      ),
    ),
    PopupMenuItem(
      key: diagnosticsItemKey,
      value: 'diagnostics',
      child: Semantics(
        key: const ValueKey('player.contextMenu.diagnostics'),
        container: true,
        button: true,
        label: '诊断检查',
        child: ListTile(
          dense: true,
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: const TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: const Icon(
            Icons.monitor_heart_outlined,
            color: playerTextMuted,
          ),
          title: const Text(
            '诊断检查',
            style: TextStyle(
              color: playerText,
              fontSize: AppTypography.body,
            ),
          ),
        ),
      ),
    ),
    if (includePrecisionControls) ...[
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'frame-backward',
        child: ListTile(
          dense: true,
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: Icon(Icons.keyboard_double_arrow_left),
          title: Text('后退一帧'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'frame-forward',
        child: ListTile(
          dense: true,
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: Icon(Icons.keyboard_double_arrow_right),
          title: Text('前进一帧'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'ab-loop-start',
        child: ListTile(
          dense: true,
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: Icon(Icons.looks_one_rounded),
          title: Text('设置 A 点'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'ab-loop-end',
        child: ListTile(
          dense: true,
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: Icon(Icons.looks_two_rounded),
          title: Text('设置 B 点'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'ab-loop-clear',
        child: ListTile(
          dense: true,
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: Icon(Icons.clear_rounded),
          title: Text('清除 A-B loop'),
        ),
      ),
    ],
    if (includeExternalSubtitle)
      const PopupMenuItem<String>(
        value: 'external-subtitle',
        child: ListTile(
          dense: true,
          iconColor: playerTextMuted,
          textColor: playerText,
          titleTextStyle: TextStyle(
            color: playerText,
            fontSize: AppTypography.body,
          ),
          leading: Icon(Icons.subtitles_rounded),
          title: Text('加载外挂字幕'),
        ),
      ),
  ];
}
