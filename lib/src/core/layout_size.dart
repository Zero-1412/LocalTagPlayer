enum LayoutSize { compact, medium, expanded }

/// 主界面 expanded 状态下三块区域的宽度分配。
///
/// 左侧导航、中央结果区和右侧标签筛选必须跟随窗口尺寸一起变化，
/// 否则用户放大窗口时两侧区域会固定在旧像素宽度，主界面比例会失真。
class MainLibraryLayoutSlots {
  const MainLibraryLayoutSlots({
    required this.sidebarWidth,
    required this.filterPanelWidth,
    required this.contentWidth,
  });

  /// 左侧主导航栏宽度。
  final double sidebarWidth;

  /// 右侧标签筛选面板外框宽度，包含面板外边距。
  final double filterPanelWidth;

  /// 中央结果区剩余宽度。
  final double contentWidth;
}

class LayoutBreakpoints {
  const LayoutBreakpoints._();

  static const double compactMaxWidth = 700;
  static const double mediumMaxWidth = 980;

  static LayoutSize fromWidth(double width) {
    if (width < compactMaxWidth) {
      return LayoutSize.compact;
    }
    if (width < mediumMaxWidth) {
      return LayoutSize.medium;
    }
    return LayoutSize.expanded;
  }
}

/// 根据窗口总宽度计算 expanded 主界面三栏比例。
///
/// 参数 [totalWidth] 使用 Scaffold 可用总宽度，而不是扣除侧栏后的宽度，
/// 这样左侧导航、中央结果区和右侧标签筛选能在窗口缩放时保持相对占比。
MainLibraryLayoutSlots mainLibraryLayoutSlotsForWidth(double totalWidth) {
  final safeWidth = totalWidth.isFinite && totalWidth > 0 ? totalWidth : 1280.0;
  final sidebarWidth = (safeWidth * 0.20).clamp(248.0, 340.0).toDouble();
  var filterPanelWidth = (safeWidth * 0.32).clamp(320.0, 620.0).toDouble();

  // 紧凑 expanded 宽度下优先保护中央结果区，避免视频卡片被右侧面板挤压。
  const minimumUsefulContentWidth = 520.0;
  final tightFilterWidth = safeWidth - sidebarWidth - minimumUsefulContentWidth;
  if (tightFilterWidth < filterPanelWidth) {
    filterPanelWidth =
        tightFilterWidth.clamp(300.0, filterPanelWidth).toDouble();
  }

  final contentWidth = (safeWidth - sidebarWidth - filterPanelWidth)
      .clamp(0.0, safeWidth)
      .toDouble();
  return MainLibraryLayoutSlots(
    sidebarWidth: sidebarWidth,
    filterPanelWidth: filterPanelWidth,
    contentWidth: contentWidth,
  );
}
