import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

/** 读取源文件，锁定共享 libmpv 实例的跨媒体写入顺序。 */
String _source(String relativePath) =>
    File('${Directory.current.path}/$relativePath').readAsStringSync();

void main() {
  test('新媒体打开前等待旧 GPU 属性任务结束', () {
    final source = _source('lib/src/pages/player/player_state_opening.dart');
    final waitIndex = source.indexOf('await previousGpuTask;');
    final openIndex = source.indexOf('await playerService.openPath(path);');

    expect(waitIndex, greaterThanOrEqualTo(0));
    expect(openIndex, greaterThan(waitIndex));
    expect(
      source,
      contains('if (openRequests.hasSuperseded(request)) continue;'),
    );
  });

  test('GPU 能力结果发布前绑定当前打开代次与路径', () {
    final source = _source(
      'lib/src/pages/player/player_state_gpu_capabilities.dart',
    );

    expect(
      source,
      contains(
        'Future<void> detectCurrentGpuCapabilities('
        'PlayerOpenRequest request)',
      ),
    );
    expect(
      RegExp(r'openRequests\.hasSuperseded\(request\)').allMatches(source),
      hasLength(greaterThanOrEqualTo(5)),
    );
    expect(source, contains('request.path != openedPath'));
  });

  test('媒体打开只应用一次引擎快照和一次媒体呈现快照', () {
    final source = _source('lib/src/pages/player/player_state_opening.dart');

    expect(
      RegExp(r'await applyPlaybackEngineProfile\(\);').allMatches(source),
      hasLength(1),
    );
    expect(
      RegExp(r'await applyMediaPresentationProfile\(\);').allMatches(source),
      hasLength(1),
    );
    expect(
      source.indexOf('await applyPlaybackEngineProfile();'),
      lessThan(source.indexOf('await playerService.openPath(path);')),
    );
    expect(
      source.indexOf('await applyMediaPresentationProfile();'),
      greaterThan(source.indexOf('await playerService.openPath(path);')),
    );
  });
}
