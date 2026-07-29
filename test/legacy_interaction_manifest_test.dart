import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 读取清单入口对应的真实可达组件边界。
 *
 * 播放器页面拆为独立 library 后，清单仍以 Route 文件作为 owner，但挂载证据需要覆盖
 * 由该入口直接导出并调用的视图、控制条和顶栏模块。
 */
String _readReachableSource(String sourcePath) {
  if (sourcePath != 'lib/src/pages/player/player_page.dart') {
    return File(sourcePath).readAsStringSync();
  }
  const playerPaths = <String>[
    'lib/src/pages/player/player_page.dart',
    'lib/src/pages/player/player_state_controls.dart',
    'lib/src/pages/player/player_state_resources.dart',
    'lib/src/pages/player/player_state_view.dart',
    'lib/src/pages/player/player_top_bar.dart',
  ];
  return playerPaths.map((path) => File(path).readAsStringSync()).join('\n');
}

void main() {
  test('旧交互清单中的页面入口、返回路径和关键挂载仍可达', () {
    final manifest = jsonDecode(
      File('test/fixtures/legacy_interaction_manifest.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final authorizedDeletions =
        (manifest['authorizedDeletions'] as List<Object?>).cast<String>();
    final entries =
        (manifest['entries'] as List<Object?>).cast<Map<String, Object?>>();

    expect(authorizedDeletions, isEmpty, reason: '本次架构迁移没有获授权删除旧功能');
    expect(entries.length, greaterThanOrEqualTo(10));
    for (final entry in entries) {
      final id = entry['id']! as String;
      final sourcePath = entry['source']! as String;
      final needle = entry['needle']! as String;
      final source = File(sourcePath);
      expect(source.existsSync(), isTrue, reason: '$id 的挂载源文件必须存在');
      expect(
        _readReachableSource(sourcePath),
        contains(needle),
        reason: '$id 必须继续在真实页面或组件中挂载',
      );
    }
  });
}
