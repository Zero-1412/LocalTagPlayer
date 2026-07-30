// ignore_for_file: slash_for_doc_comments

/**
 * 单个播放器视频表面的只读尺寸与采样快照。
 *
 * Texture 尺寸来自原生插件回传的像素矩形；Widget 尺寸来自 Flutter 布局约束。
 * 两者必须通过 DPR 换算到同一物理像素口径后才能判断真正的放大或缩小。
 */
class PlayerVideoSurfaceDiagnostics {
  const PlayerVideoSurfaceDiagnostics({
    required this.supported,
    required this.textureWidthPx,
    required this.textureHeightPx,
    required this.widgetLogicalWidth,
    required this.widgetLogicalHeight,
    required this.devicePixelRatio,
    required this.widgetPhysicalWidthPx,
    required this.widgetPhysicalHeightPx,
    required this.fittedVideoPhysicalWidthPx,
    required this.fittedVideoPhysicalHeightPx,
    required this.horizontalScale,
    required this.verticalScale,
    required this.fit,
    required this.filterQuality,
    required this.sampledAt,
  });

  /** 后端不提供 Texture 诊断时使用的显式占位快照。 */
  const PlayerVideoSurfaceDiagnostics.unsupported()
      : supported = false,
        textureWidthPx = null,
        textureHeightPx = null,
        widgetLogicalWidth = null,
        widgetLogicalHeight = null,
        devicePixelRatio = null,
        widgetPhysicalWidthPx = null,
        widgetPhysicalHeightPx = null,
        fittedVideoPhysicalWidthPx = null,
        fittedVideoPhysicalHeightPx = null,
        horizontalScale = null,
        verticalScale = null,
        fit = null,
        filterQuality = null,
        sampledAt = null;

  /** 当前后端是否实现了视频表面诊断边界。 */
  final bool supported;

  /** 原生插件回传的 Texture 宽度，单位为物理像素。 */
  final double? textureWidthPx;

  /** 原生插件回传的 Texture 高度，单位为物理像素。 */
  final double? textureHeightPx;

  /** Flutter 视频表面可布局宽度，单位为逻辑像素。 */
  final double? widgetLogicalWidth;

  /** Flutter 视频表面可布局高度，单位为逻辑像素。 */
  final double? widgetLogicalHeight;

  /** 当前 Flutter View 的设备像素比。 */
  final double? devicePixelRatio;

  /** 视频表面完整区域换算后的物理像素宽度。 */
  final double? widgetPhysicalWidthPx;

  /** 视频表面完整区域换算后的物理像素高度。 */
  final double? widgetPhysicalHeightPx;

  /** 应用 BoxFit 后视频有效画面的物理目标宽度。 */
  final double? fittedVideoPhysicalWidthPx;

  /** 应用 BoxFit 后视频有效画面的物理目标高度。 */
  final double? fittedVideoPhysicalHeightPx;

  /** 视频有效目标宽度相对原生 Texture 宽度的缩放倍率。 */
  final double? horizontalScale;

  /** 视频有效目标高度相对原生 Texture 高度的缩放倍率。 */
  final double? verticalScale;

  /** 当前 Flutter 视频表面的 BoxFit 名称。 */
  final String? fit;

  /** 当前 Texture Widget 的 FilterQuality 名称。 */
  final String? filterQuality;

  /** 最近一次尺寸或 DPR 变化被采集的时间。 */
  final DateTime? sampledAt;

  /** 任一轴小于 1 即表示 Flutter 合成层正在缩小原生 Texture。 */
  bool get isDownscaling =>
      (horizontalScale != null && horizontalScale! < 0.999) ||
      (verticalScale != null && verticalScale! < 0.999);

  /** 写入 QA 报告的路径无关结构化数据。 */
  Map<String, Object?> toJson() => <String, Object?>{
        'supported': supported,
        'textureWidthPx': textureWidthPx,
        'textureHeightPx': textureHeightPx,
        'widgetLogicalWidth': widgetLogicalWidth,
        'widgetLogicalHeight': widgetLogicalHeight,
        'devicePixelRatio': devicePixelRatio,
        'widgetPhysicalWidthPx': widgetPhysicalWidthPx,
        'widgetPhysicalHeightPx': widgetPhysicalHeightPx,
        'fittedVideoPhysicalWidthPx': fittedVideoPhysicalWidthPx,
        'fittedVideoPhysicalHeightPx': fittedVideoPhysicalHeightPx,
        'horizontalScale': horizontalScale,
        'verticalScale': verticalScale,
        'isDownscaling': isDownscaling,
        'fit': fit,
        'filterQuality': filterQuality,
        'sampledAt': sampledAt?.toIso8601String(),
      };
}
