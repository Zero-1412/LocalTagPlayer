/*
 * 播放器滑条展示组件的兼容聚合入口。
 *
 * 指标计算、主进度交互、通用滑条表面和矢量绘制彼此独立；调用方继续只需导入
 * 本文件，不改变 seek、预览加载或隐藏进度条的既有挂载路径。
 */
export 'player_control_slider_metrics.dart';
export 'player_control_slider_shapes.dart';
export 'player_control_slider_surface.dart';
export 'player_progress_slider.dart';
