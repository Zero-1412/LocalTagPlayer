import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_theme_tokens.dart';

export 'library_video_card.dart';
export 'library_video_grid.dart';
export 'library_video_hover_preview.dart';
export 'library_video_hover_primitives.dart';
export 'library_video_import_empty.dart';
export 'library_video_list_row.dart';

// ignore_for_file: slash_for_doc_comments, use_key_in_widget_constructors

/**
 * 计算网格视频卡片高度。
 *
 * 卡片只保留 16:9 缩略图与两行标题；收藏和时长位于缩略图叠层，不再为标签、路径或
 * 底部操作区预留垂直空间。单列仍按更宽缩略图单独留足高度，避免窗口缩小时溢出。
 */
double libraryVideoCardMainAxisExtent({
  required double gridWidth,
  required bool narrow,
  required bool compact,
  double textScaleFactor = 1,
}) {
  final columnCount = libraryVideoGridColumnCount(
    gridWidth: gridWidth,
    narrow: narrow,
    compact: compact,
  );
  return libraryVideoCardMainAxisExtentForColumnCount(
    gridWidth: gridWidth,
    compact: compact,
    columnCount: columnCount,
    textScaleFactor: textScaleFactor,
  );
}

/**
 * 按已锁定的列数计算卡片高度。
 *
 * 侧栏动画期间列数保持不变，但结果区宽度连续变化；卡片因此能够平滑改变尺寸，
 * 不会逐帧跨越列数断点，也不会把旧宽度网格裁切到新的结果区中。[crossAxisSpacing]
 * 可由调用方传入当前锁定间距，保证高度计算与真实网格代理使用同一组几何参数。
 */
double libraryVideoCardMainAxisExtentForColumnCount({
  required double gridWidth,
  required bool compact,
  required int columnCount,
  double? crossAxisSpacing,
  double textScaleFactor = 1,
}) {
  final safeColumnCount = math.max(1, columnCount);
  final horizontalPadding = libraryVideoGridHorizontalPadding(compact);
  final spacing = crossAxisSpacing ??
      libraryVideoGridCrossAxisSpacing(
        gridWidth: gridWidth,
        compact: compact,
      );
  final usableWidth = math.max(1.0, gridWidth - horizontalPadding);
  final cardWidth =
      (usableWidth - spacing * (safeColumnCount - 1)) / safeColumnCount;
  // 标题槽位跟随系统文字缩放增长；只改变可见卡片几何，不参与网格列数或数据加载计算。
  final metadataHeight =
      libraryVideoCardMetadataHeightForTextScale(textScaleFactor);
  // 额外 2px 吸收高 DPI 下 AspectRatio 与网格像素舍入误差，避免 150% 出现亚像素溢出。
  return cardWidth * 9 / 16 + metadataHeight + 16;
}

/**
 * 卡片标题内容区固定高度。
 *
 * 一行和两行标题都占用同一垂直槽位，保证同一网格行的卡片底部、点击区域和下一行
 * 起点一致；外层 8px 顶部与 6px 底部间距仍由卡片布局单独承担。
 */
const double libraryVideoCardMetadataHeight = 42;

/**
 * 按系统文字缩放计算两行标题槽位高度。
 *
 * 100% 继续使用原始密度；125% 和 150% 只增加标题容器，不压缩缩略图，也不截断
 * 系统放大后的第二行文字。上限用于防止异常缩放把虚拟网格行高无限放大。
 */
double libraryVideoCardMetadataHeightForTextScale(double textScaleFactor) {
  final safeScale = textScaleFactor.isFinite
      ? textScaleFactor.clamp(1.0, 2.0).toDouble()
      : 1.0;
  return libraryVideoCardMetadataHeight + (safeScale - 1) * 32;
}

/** 桌面结果区略收紧左右留白，把宽度优先分配给缩略图。 */
double libraryVideoGridHorizontalPadding(bool compact) => compact ? 28 : 44;

/**
 * 计算视频网格的横向列间距。
 *
 * 窄窗口优先保证卡片宽度，超宽窗口逐步增加留白，避免高分辨率下形成密集小卡片墙。
 */
double libraryVideoGridCrossAxisSpacing({
  required double gridWidth,
  required bool compact,
}) {
  if (compact || gridWidth < 720) {
    return 10;
  }
  if (gridWidth < 1000) {
    return 12;
  }
  if (gridWidth < 1400) {
    return 16;
  }
  return 20;
}

/** 行间距与卡片标题高度配合，宽窗口增加呼吸感但不降低首屏浏览数量。 */
double libraryVideoGridMainAxisSpacing({
  required double gridWidth,
  required bool compact,
}) {
  if (compact || gridWidth < 720) {
    return 14;
  }
  if (gridWidth < 1000) {
    return 16;
  }
  if (gridWidth < 1400) {
    return 18;
  }
  return 22;
}

/** 超宽结果区适度放大卡片上限，使桌面信息密度接近内容平台而不是文件缩略图墙。 */
double libraryVideoGridMaxCrossAxisExtent({
  required double gridWidth,
  required bool narrow,
  required bool compact,
}) {
  if (narrow) {
    return 500;
  }
  if (compact) {
    return 260;
  }
  if (gridWidth < 1000) {
    return 310;
  }
  if (gridWidth < 1400) {
    return 340;
  }
  if (gridWidth < 1800) {
    return 430;
  }
  return 500;
}

/** 卡片标题按实际卡片宽度分档，保持窄卡不拥挤、宽卡不显得过小。 */
double libraryVideoCardTitleFontSize(double cardWidth) {
  if (cardWidth < 220) {
    return 13.5;
  }
  if (cardWidth < 300) {
    return 14.5;
  }
  if (cardWidth < 380) {
    return 15.5;
  }
  return 16;
}

/** 缩略图与悬停外框共用的小圆角，接近内容平台的紧凑视觉。 */
const double libraryVideoCardRadius = AppRadius.card;

/** 标题右侧更多按钮的淡入淡出时长；短过渡避免快速扫过卡片时产生闪烁。 */
const Duration libraryCardMoreFadeDuration = Duration(milliseconds: 120);

/** 媒体卡片双项菜单宽度；只容纳“打开文件 / 删除文件”，避免遮挡相邻内容。 */
const BoxConstraints libraryVideoMoreMenuConstraints = BoxConstraints(
  minWidth: 136,
  maxWidth: 156,
);

/** 媒体卡片菜单单项最小高度；保持紧凑，同时保留可用的桌面点击目标。 */
const double libraryVideoMoreMenuItemHeight = 40;

/** 媒体卡片菜单外层留白；文字缩放时条目仍可按内容向下扩展。 */
const EdgeInsets libraryVideoMoreMenuPadding =
    EdgeInsets.symmetric(vertical: 4);

/** 收藏与时长叠层的响应式视觉参数。 */
class LibraryVideoOverlayMetrics {
  const LibraryVideoOverlayMetrics({
    required this.edgeInset,
    required this.favoriteButtonSize,
    required this.favoriteIconSize,
    required this.durationFontSize,
    required this.durationHorizontalPadding,
    required this.durationVerticalPadding,
  });

  /** 叠层距离缩略图边缘的距离。 */
  final double edgeInset;

  /** 收藏按钮的视觉和桌面点击区域尺寸。 */
  final double favoriteButtonSize;

  /** 红心图标尺寸。 */
  final double favoriteIconSize;

  /** 时长文字字号。 */
  final double durationFontSize;

  /** 时长角标左右内边距。 */
  final double durationHorizontalPadding;

  /** 时长角标上下内边距。 */
  final double durationVerticalPadding;
}

/**
 * 按卡片宽度选择叠层尺寸。
 *
 * 点击区域与视觉尺寸一起分档，避免窄卡遮挡画面，同时确保桌面鼠标仍容易命中。
 */
LibraryVideoOverlayMetrics libraryVideoOverlayMetrics(double cardWidth) {
  if (cardWidth < 220) {
    return const LibraryVideoOverlayMetrics(
      edgeInset: 6,
      favoriteButtonSize: 30,
      favoriteIconSize: 17.5,
      durationFontSize: 10,
      durationHorizontalPadding: 5,
      durationVerticalPadding: 2,
    );
  }
  if (cardWidth < 380) {
    return const LibraryVideoOverlayMetrics(
      edgeInset: 7,
      favoriteButtonSize: 32,
      favoriteIconSize: 19,
      durationFontSize: 10.5,
      durationHorizontalPadding: 5.5,
      durationVerticalPadding: 2.5,
    );
  }
  return const LibraryVideoOverlayMetrics(
    edgeInset: 9,
    favoriteButtonSize: 34,
    favoriteIconSize: 20,
    durationFontSize: 11,
    durationHorizontalPadding: 6,
    durationVerticalPadding: 3,
  );
}

/** 收藏按钮底色保持完全透明，仅由红心轮廓和阴影保证亮色视频上的可见性。 */
const double libraryFavoriteOverlayOpacity = 0;

/** 时长角标使用比旧版更透明的底色，并由文字阴影补足亮色视频上的可读性。 */
const double libraryDurationOverlayOpacity = 0.56;

/** 动态预览真正显示时隐藏静态视频时长，退出预览后恢复。 */
double libraryDurationOpacityForPreview(bool previewVisible) =>
    previewVisible ? 0 : 1;

/**
 * 计算当前响应式网格列数。
 *
 * 增量加载与卡片尺寸必须复用同一结果，避免展示数量和布局列数产生偏差。
 */
int libraryVideoGridColumnCount({
  required double gridWidth,
  required bool narrow,
  required bool compact,
}) {
  final horizontalPadding = libraryVideoGridHorizontalPadding(compact);
  final spacing = libraryVideoGridCrossAxisSpacing(
    gridWidth: gridWidth,
    compact: compact,
  );
  final maxExtent = libraryVideoGridMaxCrossAxisExtent(
    gridWidth: gridWidth,
    narrow: narrow,
    compact: compact,
  );
  final usableWidth = math.max(1.0, gridWidth - horizontalPadding);
  return math.max(1, (usableWidth / (maxExtent + spacing)).ceil()).toInt();
}

/**
 * 将已知媒体总时长格式化为卡片角标。
 *
 * 未知时长保持明确占位，不能伪装成零时长媒体。
 */
String libraryVideoDurationLabel(Duration duration) {
  if (duration <= Duration.zero) {
    return '--:--';
  }
  final totalSeconds = duration.inSeconds;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final totalMinutes = totalSeconds ~/ 60;
  if (totalMinutes < 60) {
    return '$totalMinutes:$seconds';
  }
  final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
  return '${totalMinutes ~/ 60}:$minutes:$seconds';
}

/** 缩略图占位状态；只描述展示结果，不改变生成服务的失败或重试语义。 */
enum LibraryThumbnailPlaceholderState { loading, failed, empty }

/** 深色缩略图占位背景的起止色，加载切换时与媒体库表面保持连续。 */
const Color libraryThumbnailPlaceholderTop = Color(0xff243145);
const Color libraryThumbnailPlaceholderBottom = Color(0xff182332);

/**
 * 加载中、生成异常和无可用缩略图共用的深色占位组件。
 *
 * 三种状态仅替换中心图标与文案，尺寸和背景保持一致，避免异步完成前后出现浅色闪烁。
 */
