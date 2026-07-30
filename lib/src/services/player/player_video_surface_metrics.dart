import 'package:flutter/widgets.dart';

import '../../models/player_video_surface_diagnostics.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 汇总原生 Texture、Flutter 布局与 DPR，并生成同物理像素口径的只读快照。
 *
 * 该 helper 不持有 Player、VideoController 或 BuildContext，也不会触发纹理重建。
 */
class PlayerVideoSurfaceMetricsTracker {
  PlayerVideoSurfaceMetricsTracker({
    required FilterQuality filterQuality,
  })  : _filterQuality = filterQuality,
        _snapshot = PlayerVideoSurfaceDiagnostics(
          supported: true,
          textureWidthPx: null,
          textureHeightPx: null,
          widgetLogicalWidth: null,
          widgetLogicalHeight: null,
          devicePixelRatio: null,
          widgetPhysicalWidthPx: null,
          widgetPhysicalHeightPx: null,
          fittedVideoPhysicalWidthPx: null,
          fittedVideoPhysicalHeightPx: null,
          horizontalScale: null,
          verticalScale: null,
          fit: BoxFit.contain.name,
          filterQuality: filterQuality.name,
          sampledAt: null,
        );

  /** 当前 Flutter Texture 的固定采样档位。 */
  final FilterQuality _filterQuality;

  /** 最近一次原生插件回传的 Texture 像素尺寸。 */
  Size? _texturePixelSize;

  /** 最近一次 Flutter 视频表面的逻辑布局尺寸。 */
  Size? _widgetLogicalSize;

  /** 最近一次 Flutter View 的设备像素比。 */
  double? _devicePixelRatio;

  /** 最近一次视频表面使用的 BoxFit。 */
  BoxFit _surfaceFit = BoxFit.contain;

  /** 用户显式画面比例；null 表示沿用 Texture 比例。 */
  double? _surfaceAspectRatio;

  /** 最近一次完整或部分尺寸快照。 */
  PlayerVideoSurfaceDiagnostics _snapshot;

  /** 当前匿名视频表面快照。 */
  PlayerVideoSurfaceDiagnostics get snapshot => _snapshot;

  /** 记录原生插件回传的 Texture 像素矩形。 */
  void recordTextureSize(Size size) {
    if (size.width <= 1 ||
        size.height <= 1 ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        _texturePixelSize == size) {
      return;
    }
    _texturePixelSize = size;
    _refresh();
  }

  /**
   * 记录 Flutter 布局后的表面逻辑尺寸与 DPR。
   *
   * 相同指标不会重复生成快照，避免播放进度刷新制造无意义写入。
   */
  void recordWidgetSurfaceMetrics(
    Size logicalSize,
    double devicePixelRatio,
    BoxFit fit,
    double? aspectRatio,
  ) {
    if (logicalSize.isEmpty ||
        !logicalSize.width.isFinite ||
        !logicalSize.height.isFinite ||
        devicePixelRatio <= 0 ||
        !devicePixelRatio.isFinite) {
      return;
    }
    if (_widgetLogicalSize == logicalSize &&
        _devicePixelRatio == devicePixelRatio &&
        _surfaceFit == fit &&
        _surfaceAspectRatio == aspectRatio) {
      return;
    }
    _widgetLogicalSize = logicalSize;
    _devicePixelRatio = devicePixelRatio;
    _surfaceFit = fit;
    _surfaceAspectRatio = aspectRatio;
    _refresh();
  }

  /** 把 Texture 与 Widget 尺寸统一换算为物理像素并计算实际合成缩放倍率。 */
  void _refresh() {
    final textureSize = _texturePixelSize;
    final logicalSize = _widgetLogicalSize;
    final dpr = _devicePixelRatio;
    Size? widgetPhysicalSize;
    Size? fittedVideoPhysicalSize;
    double? horizontalScale;
    double? verticalScale;
    if (textureSize != null && logicalSize != null && dpr != null) {
      widgetPhysicalSize = Size(
        logicalSize.width * dpr,
        logicalSize.height * dpr,
      );
      // Video 在显式比例下先把 Texture 映射到覆盖比例，再由 FittedBox 处理 fit。
      final fitSourceSize = _surfaceAspectRatio == null
          ? textureSize
          : Size(textureSize.height * _surfaceAspectRatio!, textureSize.height);
      final fittedLogicalSize =
          applyBoxFit(_surfaceFit, fitSourceSize, logicalSize).destination;
      fittedVideoPhysicalSize = Size(
        fittedLogicalSize.width * dpr,
        fittedLogicalSize.height * dpr,
      );
      horizontalScale = fittedVideoPhysicalSize.width / textureSize.width;
      verticalScale = fittedVideoPhysicalSize.height / textureSize.height;
    }
    _snapshot = PlayerVideoSurfaceDiagnostics(
      supported: true,
      textureWidthPx: textureSize?.width,
      textureHeightPx: textureSize?.height,
      widgetLogicalWidth: logicalSize?.width,
      widgetLogicalHeight: logicalSize?.height,
      devicePixelRatio: dpr,
      widgetPhysicalWidthPx: widgetPhysicalSize?.width,
      widgetPhysicalHeightPx: widgetPhysicalSize?.height,
      fittedVideoPhysicalWidthPx: fittedVideoPhysicalSize?.width,
      fittedVideoPhysicalHeightPx: fittedVideoPhysicalSize?.height,
      horizontalScale: horizontalScale,
      verticalScale: verticalScale,
      fit: _surfaceFit.name,
      filterQuality: _filterQuality.name,
      sampledAt: DateTime.now(),
    );
  }
}

/**
 * 只观察视频表面的布局约束与 DPR，不参与播放状态或纹理生命周期。
 *
 * 同一组指标只在布局变化后的帧末上报一次，避免在 build 阶段修改后端快照。
 */
class PlayerVideoSurfaceMetricsObserver extends StatefulWidget {
  const PlayerVideoSurfaceMetricsObserver({
    super.key,
    required this.fit,
    required this.aspectRatio,
    required this.onMetricsChanged,
    required this.child,
  });

  /** 当前视频表面的 BoxFit。 */
  final BoxFit fit;

  /** 用户显式比例；null 表示沿用原生 Texture 比例。 */
  final double? aspectRatio;

  /** 帧末尺寸采集回调。 */
  final void Function(Size, double, BoxFit, double?) onMetricsChanged;

  /** 不被观察器修改的视频表面与控制层。 */
  final Widget child;

  @override
  State<PlayerVideoSurfaceMetricsObserver> createState() =>
      _PlayerVideoSurfaceMetricsObserverState();
}

class _PlayerVideoSurfaceMetricsObserverState
    extends State<PlayerVideoSurfaceMetricsObserver> {
  /** 最近已调度的指标签名，用于合并同一帧内重复 build。 */
  Object? _lastSignature;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final signature = (
          size.width,
          size.height,
          dpr,
          widget.fit,
          widget.aspectRatio,
        );
        if (_lastSignature != signature) {
          _lastSignature = signature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _lastSignature != signature) {
              return;
            }
            widget.onMetricsChanged(
              size,
              dpr,
              widget.fit,
              widget.aspectRatio,
            );
          });
        }
        return widget.child;
      },
    );
  }
}
