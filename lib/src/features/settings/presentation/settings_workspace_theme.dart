import 'package:flutter/material.dart';

import '../../../widgets/app_theme_tokens.dart';
import '../../../widgets/maintenance_feedback.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 设置工作区在维护页主题基线上收敛卡片、菜单和交互反馈。
 *
 * 该函数只定义展示令牌，不持有 Route、设置状态或业务服务，供真实设置页与 focused
 * widget tests 使用同一套视觉契约。
 */
ThemeData settingsWorkspaceTheme(ThemeData base) {
  // 设置页的真实下拉、tooltip 和非阻塞反馈共享维护浮层基线；页面仍只负责
  // section 编排，设置 controller、持久化和异步动作不进入主题层。
  final workspace = maintenanceFeedbackTheme(base);
  return workspace.copyWith(
    // DropdownButton 的弹出路由读取 canvasColor；显式保持深色抬升表面，
    // 避免深色文字主题落到默认浅色菜单上而失去可读性。
    canvasColor: librarySurfaceAlt,
    hoverColor: appAccentViolet.withValues(alpha: 0.10),
    focusColor: appAccentViolet.withValues(alpha: 0.16),
    highlightColor: appAccentViolet.withValues(alpha: 0.12),
    splashColor: appAccentViolet.withValues(alpha: 0.08),
    cardTheme: workspace.cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: libraryBorder),
      ),
    ),
  );
}
