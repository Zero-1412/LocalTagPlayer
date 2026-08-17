import 'package:flutter/material.dart';

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
          leading: const Icon(Icons.info_outline),
          title: const Text('视频信息'),
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
          leading: const Icon(Icons.monitor_heart_outlined),
          title: const Text('诊断检查'),
        ),
      ),
    ),
  ];
}
