import 'package:flutter/material.dart';

import '../../widgets/app_theme_tokens.dart';

/// 构建播放器上下文菜单的展示项。
///
/// 临时 [GlobalKey] 仍由调用方持有，用于 overlay 边界测量；菜单项内部的稳定
/// [ValueKey] 只服务挂载、键盘和语义回归，不承载播放器状态或业务动作。
List<PopupMenuEntry<String>> buildPlayerContextMenuItems({
  required GlobalKey infoItemKey,
  required GlobalKey diagnosticsItemKey,
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
  ];
}
