import 'dart:ui' as ui;

// ignore_for_file: slash_for_doc_comments

/** 保存互不重叠的阶段窗口；按帧的开始时间归属，避免批量回调跨阶段污染。 */
class PhaseFrameRecorder {
  final windows = <Map<String, Object>>[];
  final frames = <ui.FrameTiming>[];
  String _phase = 'startup';
  int _start = DateTime.now().microsecondsSinceEpoch;

  void enter(String phase, {int? nowUs}) {
    final end = nowUs ?? DateTime.now().microsecondsSinceEpoch;
    windows.add({'phase': _phase, 'startUs': _start, 'endUs': end});
    _phase = phase;
    _start = end;
  }

  void collect(List<ui.FrameTiming> values) => frames.addAll(values);

  /** 整个失败操作窗口单列，不能把超时等待中的低负载帧混入成功样本。 */
  void failCurrentPhase() => _phase = '${_phase}_failed';

  List<Map<String, Object>> records() => frames.map((frame) {
        // 引擎提供 rasterFinish 的墙钟值，用其与 vsync 的差还原帧开始；
        // 不假设 Dart Stopwatch、Timeline 和引擎的单调时钟具有相同 epoch。
        final finish =
            frame.timestampInMicroseconds(ui.FramePhase.rasterFinishWallTime);
        final start = finish - frame.totalSpan.inMicroseconds;
        final window = windows.where((w) =>
            start >= (w['startUs'] as int) && start < (w['endUs'] as int));
        return {
          'phase': window.isEmpty ? 'outside' : window.first['phase']!,
          'vsyncWallUs': start,
          'crossesBoundary':
              window.isNotEmpty && finish > (window.first['endUs'] as int),
          'buildMs': frame.buildDuration.inMicroseconds / 1000,
          'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
          'totalMs': frame.totalSpan.inMicroseconds / 1000,
        };
      }).toList();
}

Map<String, Object?> sampleStats(List<double> values) {
  if (values.isEmpty) return {'n': 0};
  final sorted = [...values]..sort();
  double percentile(double p) => sorted[(sorted.length * p).ceil() - 1];
  return {
    'n': sorted.length,
    'p50Ms': percentile(.5),
    'p95Ms': percentile(.95),
    'p99Ms': percentile(.99),
    'maxMs': sorted.last
  };
}

/** 同时报告 UI、raster 与总帧时间，保留长帧比例而不只报告平均值。 */
Map<String, Object?> frameStats(List<Map<String, Object>> records) => {
      for (final metric in ['buildMs', 'rasterMs', 'totalMs'])
        metric: sampleStats(records.map((r) => r[metric] as double).toList()),
      'slowOver33ms':
          records.where((r) => (r['totalMs'] as double) > 33.3).length,
      'over100ms': records.where((r) => (r['totalMs'] as double) > 100).length,
      'crossesBoundary':
          records.where((r) => r['crossesBoundary'] == true).length,
    };
