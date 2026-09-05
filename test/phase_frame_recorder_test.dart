import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import '../integration_test/support/phase_frame_recorder.dart';

void main() {
  test('延迟送达和跨阶段帧按开始时刻归属，两个时钟 epoch 不必相同', () {
    final recorder = PhaseFrameRecorder();
    recorder.enter('search', nowUs: 1000000);
    recorder.enter('tag_animation', nowUs: 1100000);
    recorder.enter('idle', nowUs: 1200000);
    recorder.collect([
      ui.FrameTiming(
          vsyncStart: 5000,
          buildStart: 6000,
          buildFinish: 26000,
          rasterStart: 27000,
          rasterFinish: 45000,
          rasterFinishWallTime: 1120000),
      ui.FrameTiming(
          vsyncStart: 100000,
          buildStart: 101000,
          buildFinish: 102000,
          rasterStart: 103000,
          rasterFinish: 105000,
          rasterFinishWallTime: 1150000),
    ]);
    final records = recorder.records();
    expect(records.map((r) => r['phase']), ['search', 'tag_animation']);
    expect(records.first['crossesBoundary'], isTrue);
    expect(records.first['buildMs'], 20.0);
    expect(records.first['rasterMs'], 18.0);
    expect(frameStats(records)['slowOver33ms'], 1);
    expect(frameStats(records)['crossesBoundary'], 1);
  });
  test('空阶段不生成虚假的分位数', () {
    expect(sampleStats([]), {'n': 0});
    expect(sampleStats([1, 2, 3])['p99Ms'], 3);
  });
  test('超时窗口不计入成功操作的帧分母', () {
    final recorder = PhaseFrameRecorder();
    recorder.enter('search', nowUs: 1000000);
    recorder.failCurrentPhase();
    recorder.enter('capture', nowUs: 2000000);
    recorder.collect([
      ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 1,
          buildFinish: 2,
          rasterStart: 3,
          rasterFinish: 5,
          rasterFinishWallTime: 1500005)
    ]);
    expect(recorder.records().single['phase'], 'search_failed');
  });
}
