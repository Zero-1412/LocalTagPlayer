import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 在真实 Windows Flutter 窗口验证设置页的 MediaKit / MPV 显式选择。
 *
 * 测试只修改隔离内存设置，不读写用户偏好；截图用于复核下拉入口、确认反馈和
 * 两种后端的特色强化说明，后续门禁可据此明确归属播放器后端。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('设置页显式切换 MediaKit 与 MPV 并展示对应强化', (tester) async {
    final outputPath =
        Platform.environment['LOCAL_TAG_PLAYER_RENDERER_QA_OUTPUT']?.trim();
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('缺少隔离渲染器设置截图目录');
    }
    final outputDirectory = Directory(outputPath)..createSync(recursive: true);
    final captureKey = GlobalKey();
    var settings = PlaybackSettings.defaults;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: RepaintBoundary(
            key: captureKey,
            child: ColoredBox(
              color: const Color(0xFF10131A),
              child: Center(
                child: SizedBox(
                  width: 620,
                  child: StatefulBuilder(
                    builder: (context, setState) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '设置 · 播放',
                          style: TextStyle(fontSize: 30),
                        ),
                        const SizedBox(height: 24),
                        PlaybackRendererDropdown(
                          settings: settings,
                          windowsNativeRendererAvailable: true,
                          onChanged: (next) async {
                            setState(() => settings = next);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MPV 容器渲染'), findsOneWidget);
    expect(find.textContaining('NVIDIA VSR/HDR 自动增强'), findsOneWidget);
    await _capture(
      captureKey,
      outputDirectory,
      'renderer-mpv.png',
    );

    await tester.tap(
      find.byType(DropdownButtonFormField<PlayerRendererPreference>),
    );
    await tester.pumpAndSettle();
    expect(find.text('MediaKit 兼容渲染'), findsOneWidget);
    expect(find.text('MPV 容器渲染'), findsWidgets);
    await tester.tap(find.text('MediaKit 兼容渲染'));
    await tester.pumpAndSettle();

    expect(find.text('切换播放渲染器'), findsOneWidget);
    await tester.tap(find.text('确认切换'));
    await tester.pumpAndSettle();

    expect(settings.rendererPreference, PlayerRendererPreference.mediaKit);
    expect(find.textContaining('跨平台兼容'), findsWidgets);
    expect(find.textContaining('镜像、压缩画质增强'), findsOneWidget);
    await _capture(
      captureKey,
      outputDirectory,
      'renderer-mediakit.png',
    );
  });
}

/**
 * 保存 Flutter 窗口截图，供设置页真实交互后的布局与状态反馈复核。
 */
Future<void> _capture(
  GlobalKey captureKey,
  Directory outputDirectory,
  String fileName,
) async {
  final boundary =
      captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) {
    throw StateError('设置页渲染边界未返回 PNG 数据');
  }
  await File('${outputDirectory.path}${Platform.pathSeparator}$fileName')
      .writeAsBytes(byteData.buffer.asUint8List(), flush: true);
}
