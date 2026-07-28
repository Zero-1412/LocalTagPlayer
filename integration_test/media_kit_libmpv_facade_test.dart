import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:media_kit/media_kit.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 验证 PlayerFacade 增强配置复用 media_kit 的同一个 NativePlayer 与 Texture。
 *
 * 真实片源由本机环境变量提供，仓库和测试输出都不记录路径；未提供时安全跳过。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final samplePath =
      Platform.environment['LOCAL_TAG_PLAYER_MEDIA_KIT_SAMPLE']?.trim();

  testWidgets(
    'MediaKit Texture 与同实例 libmpv 高级属性共同推进',
    (tester) async {
      MediaKit.ensureInitialized();
      final backend = MediaKitPlayerBackend(
        hwdec: 'd3d11va-copy',
        enableHardwareAcceleration: true,
      );
      addTearDown(backend.dispose);

      // 必须把正式视频表面挂入 Widget 树；只创建 VideoController 会得到白色测试窗，
      // 也无法证明 Flutter Texture 与上层控件处于同一合成层。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: backend.buildVideoSurface(
              controls: const Align(
                alignment: Alignment.topLeft,
                child: ColoredBox(
                  color: Color(0x99000000),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'MediaKit + libmpv 同实例验证',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await backend.setProperties(const <String, String>{
        'video-aspect-override': '-1',
        'panscan': '0',
        'scale': 'lanczos',
        'cscale': 'lanczos',
      });
      await backend.openPath(samplePath!);
      await backend.play();

      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(seconds: 20) &&
          (backend.state.position < const Duration(seconds: 1) ||
              backend.textureId.value == null)) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(backend.textureId.value, isNotNull);
      expect(
        backend.state.position,
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      expect(await backend.getProperty('scale'), 'lanczos');
      expect(await backend.getProperty('cscale'), 'lanczos');
      expect(
        await backend.getProperty('hwdec-current'),
        anyOf('d3d11va', 'd3d11va-copy'),
      );

      final before = backend.state.position;
      await tester.pump(const Duration(seconds: 1));
      expect(backend.state.position, greaterThan(before));

      // 先解除 Video/Texture 挂载，再等待 media_kit 完成原生播放器销毁。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await backend.dispose();
    },
    skip: samplePath == null ||
        samplePath.isEmpty ||
        !File(samplePath).existsSync(),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
