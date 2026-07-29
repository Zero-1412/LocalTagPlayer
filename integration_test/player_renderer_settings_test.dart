import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_tag_player/src/core/playback_settings.dart';
import 'package:local_tag_player/src/features/settings/presentation/playback_and_decoding_settings_card.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 在真实 Windows Flutter 窗口验证正式播放后端只展示 MediaKit Texture。
 *
 * 历史渲染器偏好已统一迁移，设置页不得继续提供两个实际相同的伪切换入口；
 * 原生 Windows 后端仅由显式 QA 环境变量进入，不属于正式设置。
 */
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('播放设置只展示唯一正式 MediaKit Texture 后端', (tester) async {
    final outputPath =
        Platform.environment['LOCAL_TAG_PLAYER_RENDERER_QA_OUTPUT']?.trim();
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('缺少隔离播放后端设置截图目录');
    }
    final outputDirectory = Directory(outputPath)..createSync(recursive: true);
    final captureKey = GlobalKey();

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
                  child: PlaybackAndDecodingSettingsCard(
                    settings: PlaybackSettings.defaults,
                    onChanged: (_) async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MediaKit Texture'), findsOneWidget);
    expect(find.textContaining('不会自动激活 NVIDIA VSR/HDR'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<PlayerRendererPreference>),
      findsNothing,
    );
    expect(find.text('切换播放渲染器'), findsNothing);
    await _capture(captureKey, outputDirectory, 'backend-mediakit-texture.png');
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
