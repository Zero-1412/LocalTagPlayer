import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P0 manifest 固定 12 个内容 case 与七类 action', () {
    final template = jsonDecode(
      File('tool/qa/player_p0_manifest.template.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cases =
        (template['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
    final actions = (template['actions'] as List<dynamic>).cast<String>();

    expect(cases, hasLength(12));
    expect(
      cases.map((item) => item['id']).toSet(),
      <String>{
        '1080p-h264-short-gop',
        '1080p-h264-long-gop',
        '1080p-hevc-short-gop',
        '1080p-hevc-long-gop',
        '1080p-av1-short-gop',
        '1080p-av1-long-gop',
        '4k-h264-short-gop',
        '4k-h264-long-gop',
        '4k-hevc-short-gop',
        '4k-hevc-long-gop',
        '4k-av1-short-gop',
        '4k-av1-long-gop',
      },
    );
    expect(
      actions,
      <String>[
        'startup',
        'shortForward',
        'shortBackward',
        'drag',
        'longForward',
        'longBackward',
        'fullscreen',
      ],
    );
  });

  test('P0 校验器保留 DWM、掉帧、Texture 与 unknown 边界', () {
    final script =
        File('tool/validate_player_p0_evidence.ps1').readAsStringSync();
    final document = File(
      'docs/qa/player_p0_p1_evidence_package_20260820.md',
    ).readAsStringSync();

    // 证据终点必须是实际桌面合成，不能退回后端帧号或命令完成。
    expect(script, contains('desktop-composited-pixel-change'));
    expect(script, contains('first-real-dwm-frame'));
    expect(script, contains('decoder-drop'));
    expect(script, contains('vo-drop'));
    expect(script, contains('steady-total-drop'));
    expect(script, contains('texture-generation-recorded'));
    expect(script, contains('player_resources_released'));
    expect(script, contains("'pass', 'fail', 'unknown'"));
    expect(script, contains(r"$totalStatus = 'unknown'"));

    // 文档必须把 HWND 不可发布、反向 latest-only 和 P1 可见性边界说清楚。
    expect(document, contains('HWND QA 路径不可发布'));
    expect(document, contains('latest-only keyframe preview'));
    expect(document, contains('命令可用'));
    expect(document, contains('可见性 unknown'));
    expect(document, contains('真人实体 WM_KEYDOWN/UP'));
  });

  test('本机 manifest 生成器使用只读数据库、ffprobe 和有界探测', () {
    final generator =
        File('tool/generate_player_p0_manifest.dart').readAsStringSync();

    // 生成器只能产生本机 QA 产物；候选不足或 ffprobe 超时必须保留 partial/unknown。
    expect(generator, contains('OpenDatabaseOptions(readOnly: true'));
    expect(generator, contains('ffprobe'));
    expect(generator, contains('read_intervals'));
    expect(generator, contains('packet=pts_time,flags'));
    expect(generator, contains('_keyframeWindowSeconds'));
    expect(generator, contains('shortGopMaxSeconds'));
    expect(generator, contains('longGopMinSeconds'));
    expect(generator, contains('probeTimeoutSeconds'));
    expect(generator, contains('maxProbes'));
    expect(generator, contains('for (var round = 0; probeCount < maxProbes'));
    expect(generator, contains('_spreadIndices'));
    expect(generator, contains('if (limit == 1) return <int>[0]'));
    expect(generator, contains('candidateCounts'));
    expect(generator, contains('probedGopCounts'));
    expect(generator, contains('probeOutcomeCounts'));
    expect(generator, contains('gop-outside-target'));
    expect(generator, contains('executableSha256'));
    expect(generator, contains('sha256.bind'));
    expect(generator, contains('if (missing > 0) exitCode = 3'));
    expect(generator, contains('database=readonly'));
  });
}
