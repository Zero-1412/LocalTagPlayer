import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 真实媒体库压测使用的卡片子树 build/layout 聚合器。
 *
 * 只有 debug 构建且显式提供 `LOCAL_TAG_PLAYER_STRESS_OUTPUT` 时启用。每个探针只在
 * 内存追加微秒样本，阶段切换后才写 JSONL，避免诊断文件 I/O 本身污染滚动帧耗时。
 * build 只统计传入 builder 的直接执行时间，不包含后代 Widget 后续由框架触发的 build；
 * layout 为包含子节点的根布局耗时，各子树之间存在包含关系，不能直接相加。
 * 轻量滚动帧统计使用独立环境变量，只监听引擎 FrameTiming，不会启用上述布局探针。
 */
class LibraryCardUiDiagnostics {
  const LibraryCardUiDiagnostics._();

  static final bool _enabled = kDebugMode &&
      (Platform.environment['LOCAL_TAG_PLAYER_STRESS_OUTPUT']
              ?.trim()
              .isNotEmpty ??
          false);
  static final String? _scrollStatsOutput =
      Platform.environment['LOCAL_TAG_PLAYER_SCROLL_STATS_OUTPUT'];
  static final bool _scrollStatsEnabled =
      kDebugMode && (_scrollStatsOutput?.trim().isNotEmpty ?? false);
  static final Map<String, _LibraryCardSubtreeSamples> _samples =
      <String, _LibraryCardSubtreeSamples>{};
  static String _phase = 'startup';
  static int _cycle = 0;
  static final List<ui.FrameTiming> _scrollFrames = <ui.FrameTiming>[];
  static Timer? _scrollIdleTimer;
  static DateTime? _scrollStartedAt;
  static var _scrollStartItemCount = 0;
  static var _scrollLatestItemCount = 0;
  static var _scrollSample = 0;
  static var _isSamplingScroll = false;

  /** 接收 Flutter 引擎批量回传的帧耗时；采样期间只在内存追加。 */
  static void _recordScrollFrames(List<ui.FrameTiming> timings) {
    _scrollFrames.addAll(timings);
  }

  /** 当前进程是否由显式压测环境启用卡片探针。 */
  static bool get enabled => _enabled;

  /** 当前进程是否仅启用轻量滚动帧统计。 */
  static bool get scrollStatsEnabled => _scrollStatsEnabled;

  /**
   * 记录一次滚动活动并在静止 300ms 后输出聚合帧统计。
   *
   * 仅显式压测环境启用；高频回调不做文件 I/O，避免诊断本身干扰滚动。连续滚动会合并
   * 为同一段样本，输出只包含行数和耗时，不包含视频标题或本地路径。
   */
  static void recordScrollActivity({required int loadedItemCount}) {
    if (!_scrollStatsEnabled) {
      return;
    }
    if (!_isSamplingScroll) {
      _isSamplingScroll = true;
      _scrollFrames.clear();
      _scrollStartedAt = DateTime.now();
      _scrollStartItemCount = loadedItemCount;
      WidgetsBinding.instance.addTimingsCallback(_recordScrollFrames);
    }
    _scrollLatestItemCount = loadedItemCount;
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(
      const Duration(milliseconds: 300),
      finishScrollSample,
    );
  }

  /** 完成当前滚动样本；页面销毁时也调用，避免遗留 callback 或 timer。 */
  static void finishScrollSample() {
    if (!_scrollStatsEnabled || !_isSamplingScroll) {
      return;
    }
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = null;
    WidgetsBinding.instance.removeTimingsCallback(_recordScrollFrames);
    _isSamplingScroll = false;
    final startedAt = _scrollStartedAt;
    _scrollStartedAt = null;
    final output = _scrollStatsOutput;
    if (output == null || output.trim().isEmpty || _scrollFrames.isEmpty) {
      _scrollFrames.clear();
      return;
    }
    final frames = List<ui.FrameTiming>.of(_scrollFrames);
    _scrollFrames.clear();
    final totals = frames
        .map((frame) => frame.totalSpan.inMicroseconds / 1000)
        .toList(growable: false);
    final builds = frames
        .map((frame) => frame.buildDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final rasters = frames
        .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final row = <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'sample': ++_scrollSample,
      'elapsedMs': startedAt == null
          ? null
          : DateTime.now().difference(startedAt).inMilliseconds,
      'loadedItemsStart': _scrollStartItemCount,
      'loadedItemsEnd': _scrollLatestItemCount,
      'frames': frames.length,
      'totalP50Ms': _percentileDouble(totals, 0.50),
      'totalP95Ms': _percentileDouble(totals, 0.95),
      'totalMaxMs': totals.reduce(math.max),
      'buildP95Ms': _percentileDouble(builds, 0.95),
      'rasterP95Ms': _percentileDouble(rasters, 0.95),
      'over16_7Ms': totals.where((value) => value > 16.7).length,
      'over33_3Ms': totals.where((value) => value > 33.3).length,
    };
    final file = File('$output\\scroll-frame-timings.jsonl');
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
    } on FileSystemException {
      // 诊断目录只影响可选统计，路径失效或磁盘只读时不得打断媒体库滚动。
    }
  }

  /** 对已排序副本取分位数；帧样本仅在一次滚动结束时执行。 */
  static double _percentileDouble(List<double> values, double percentile) {
    if (values.isEmpty) {
      return 0;
    }
    final sorted = List<double>.of(values)..sort();
    final index = ((sorted.length - 1) * percentile).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  /**
   * 构建并记录一个卡片子树。
   *
   * builder 耗时只代表本层应用代码直接创建 Widget 的成本，不代表后代 Widget 的完整
   * build 成本；返回的布局探针测量该子树根节点的包含式布局耗时。
   */
  static Widget buildSubtree(String name, Widget Function() builder) {
    if (!_enabled) {
      return builder();
    }
    final watch = Stopwatch()..start();
    final child = builder();
    watch.stop();
    (_samples[name] ??= _LibraryCardSubtreeSamples()).buildMicros.add(
          watch.elapsedMicroseconds,
        );
    return _LibraryCardLayoutProbe(name: name, child: child);
  }

  /** 记录 RenderObject 已经完成的包含式布局耗时。 */
  static void recordLayout(String name, int elapsedMicroseconds) {
    if (!_enabled) {
      return;
    }
    (_samples[name] ??= _LibraryCardSubtreeSamples()).layoutMicros.add(
          elapsedMicroseconds,
        );
  }

  /** 切换业务阶段；先提交上一阶段，禁止把扫描、滚动和播放器返回混在一起。 */
  static void beginPhase(String phase, int cycle) {
    if (!_enabled) {
      return;
    }
    flush();
    _phase = phase;
    _cycle = cycle;
  }

  /** 把当前阶段按子树聚合为 JSONL；文件只包含耗时和计数，不包含媒体路径。 */
  static void flush() {
    if (!_enabled || _samples.isEmpty) {
      return;
    }
    final output = Platform.environment['LOCAL_TAG_PLAYER_STRESS_OUTPUT'];
    if (output == null || output.trim().isEmpty) {
      _samples.clear();
      return;
    }
    final file = File('$output\\card-subtree-timings.jsonl');
    for (final entry in _samples.entries) {
      final row = <String, Object?>{
        'timestamp': DateTime.now().toIso8601String(),
        'phase': _phase,
        'cycle': _cycle,
        'subtree': entry.key,
        ...entry.value.toJson(),
      };
      file.writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
    }
    _samples.clear();
  }
}

/** 单个卡片子树在一个业务阶段内的原始微秒样本。 */
class _LibraryCardSubtreeSamples {
  final List<int> buildMicros = <int>[];
  final List<int> layoutMicros = <int>[];

  /** 输出计数、总耗时、P50/P95 和峰值，便于区分频繁小开销与单次尖峰。 */
  Map<String, Object?> toJson() => <String, Object?>{
        'buildCount': buildMicros.length,
        'buildTotalMs': _totalMs(buildMicros),
        'buildP50Ms': _percentileMs(buildMicros, 0.50),
        'buildP95Ms': _percentileMs(buildMicros, 0.95),
        'buildMaxMs': _maxMs(buildMicros),
        'layoutCount': layoutMicros.length,
        'layoutTotalMs': _totalMs(layoutMicros),
        'layoutP50Ms': _percentileMs(layoutMicros, 0.50),
        'layoutP95Ms': _percentileMs(layoutMicros, 0.95),
        'layoutMaxMs': _maxMs(layoutMicros),
      };

  double _totalMs(List<int> values) =>
      values.fold<int>(0, (sum, value) => sum + value) / 1000;

  double _maxMs(List<int> values) =>
      values.isEmpty ? 0 : values.reduce(math.max) / 1000;

  double _percentileMs(List<int> values, double percentile) {
    if (values.isEmpty) {
      return 0;
    }
    final sorted = List<int>.of(values)..sort();
    final index = ((sorted.length - 1) * percentile).round();
    return sorted[index.clamp(0, sorted.length - 1)] / 1000;
  }
}

/** 为一个卡片子树增加不改变约束、尺寸或绘制的布局计时边界。 */
class _LibraryCardLayoutProbe extends SingleChildRenderObjectWidget {
  const _LibraryCardLayoutProbe({
    required this.name,
    required super.child,
  });

  final String name;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLibraryCardLayoutProbe(name);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderLibraryCardLayoutProbe renderObject,
  ) {
    renderObject.name = name;
  }
}

/** 仅代理原布局并记录耗时，不修改父子约束和尺寸。 */
class _RenderLibraryCardLayoutProbe extends RenderProxyBox {
  _RenderLibraryCardLayoutProbe(this.name);

  String name;

  @override
  void performLayout() {
    final watch = Stopwatch()..start();
    super.performLayout();
    watch.stop();
    LibraryCardUiDiagnostics.recordLayout(name, watch.elapsedMicroseconds);
  }
}
