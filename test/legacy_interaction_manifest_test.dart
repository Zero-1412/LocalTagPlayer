import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
        source.readAsStringSync(),
        contains(needle),
        reason: '$id 必须继续在真实页面或组件中挂载',
      );
    }
  });
}
