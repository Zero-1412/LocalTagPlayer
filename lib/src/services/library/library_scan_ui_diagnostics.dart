part of '../../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * debug 模式下一次媒体库扫描的 UI 帧和同步重算诊断。
 *
 * 诊断只记录数量与耗时，不包含路径、标题或标签内容。固定 3 秒帧驱动使
 * 大量差量与零差量使用相同采样窗口，避免空闲页面不产生帧而无法对比。
 */
class LibraryScanUiDiagnostics {
  LibraryScanUiDiagnostics()
      : _startedAt = DateTime.now(),
        _watch = Stopwatch()..start();

  static const Duration sampleWindow = Duration(seconds: 3);

  /** 采样开始时间。 */
  final DateTime _startedAt;

  /** 整体采样时钟。 */
  final Stopwatch _watch;

  /** 按 scan/postApply 阶段保存的帧耗时。 */
  final Map<String, List<ui.FrameTiming>> _frames =
      <String, List<ui.FrameTiming>>{
    'scan': <ui.FrameTiming>[],
    'postApply': <ui.FrameTiming>[],
  };

  /** folder 重算、filter 差量替换等同步阶段。 */
  final List<LibraryLoadStageSample> _stages = <LibraryLoadStageSample>[];

  String _phase = 'scan';
  Timer? _frameDriver;
  late final TimingsCallback _timingsCallback;
  var _started = false;
  var _finished = false;

  /** 注册帧回调并以统一 60Hz 节奏驱动诊断帧。 */
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _timingsCallback = (timings) {
      if (_finished) {
        return;
      }
      (_frames[_phase] ??= <ui.FrameTiming>[]).addAll(timings);
    };
    WidgetsBinding.instance.addTimingsCallback(_timingsCallback);
    _frameDriver = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_finished) {
        SchedulerBinding.instance.scheduleFrame();
      }
    });
  }

  /** 扫描与数据库提交已完成，后续帧归入 UI 差量应用阶段。 */
  void markPostApply() {
    _phase = 'postApply';
  }

  /** 记录一个不包含用户内容的同步重算阶段。 */
  void recordStage(String name, Duration elapsed, {int? itemCount}) {
    if (_finished) {
      return;
    }
    _stages.add(LibraryLoadStageSample(
      name: name,
      elapsed: elapsed,
      itemCount: itemCount,
    ));
  }

  /**
   * 在固定窗口结束后写入 JSONL，便于连续扫描两次后直接对比。
   */
  Future<void> finish(LibraryScanCommitResult result) async {
    final remaining = sampleWindow - _watch.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (_finished) {
      return;
    }
    _finished = true;
    _watch.stop();
    _frameDriver?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_timingsCallback);
    final changedCount = result.changedVideos.length;
    final scenario = changedCount == 0
        ? 'zero_delta'
        : changedCount >= 1000
            ? 'large_delta'
            : 'small_delta';
    final output = <String, Object?>{
      'startedAt': _startedAt.toIso8601String(),
      'scenario': scenario,
      'sampleWindowMs': _watch.elapsedMilliseconds,
      'changedCount': changedCount,
      'addedCount': result.addedCount,
      'modifiedCount': result.modifiedCount,
      'missingCount': result.missingCount,
      'relinkedCount': result.relinkedCount,
      'frames': <String, Object?>{
        for (final entry in _frames.entries)
          entry.key: _frameSummary(entry.value),
      },
      'stages': _stages.map((stage) => stage.toJson()).toList(),
    };
    try {
      final file = File(p.join(
        Directory.systemTemp.path,
        'local_tag_player_scan_ui_diagnostics.jsonl',
      ));
      await file.writeAsString(
        '${jsonEncode(output)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // debug 诊断文件不得影响扫描事务或用户交互。
    }
  }

  /** 新扫描覆盖或页面退出时立即解除帧回调。 */
  void abort() {
    if (_finished) {
      return;
    }
    _finished = true;
    _watch.stop();
    _frameDriver?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeTimingsCallback(_timingsCallback);
    }
  }

  /** 输出帧数、平均值、P95、峰值和超预算数量。 */
  Map<String, Object?> _frameSummary(List<ui.FrameTiming> frames) {
    final totals = frames
        .map((frame) => frame.totalSpan.inMicroseconds / 1000)
        .toList()
      ..sort();
    final builds = frames
        .map((frame) => frame.buildDuration.inMicroseconds / 1000)
        .toList()
      ..sort();
    final rasters = frames
        .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
        .toList()
      ..sort();
    double average(List<double> values) => values.isEmpty
        ? 0
        : values.reduce((left, right) => left + right) / values.length;
    double percentile(List<double> values, double ratio) {
      if (values.isEmpty) {
        return 0;
      }
      final index = ((values.length - 1) * ratio).round();
      return values[index];
    }

    double rounded(double value) => double.parse(value.toStringAsFixed(3));
    return <String, Object?>{
      'count': frames.length,
      'totalAverageMs': rounded(average(totals)),
      'totalP95Ms': rounded(percentile(totals, 0.95)),
      'totalMaxMs': rounded(totals.isEmpty ? 0 : totals.last),
      'buildP95Ms': rounded(percentile(builds, 0.95)),
      'buildMaxMs': rounded(builds.isEmpty ? 0 : builds.last),
      'rasterP95Ms': rounded(percentile(rasters, 0.95)),
      'rasterMaxMs': rounded(rasters.isEmpty ? 0 : rasters.last),
      'over16_7ms': totals.where((value) => value > 16.7).length,
      'over33_3ms': totals.where((value) => value > 33.3).length,
    };
  }
}
