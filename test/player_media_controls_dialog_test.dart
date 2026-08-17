import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/models/player_media_controls.dart';
import 'package:local_tag_player/src/pages/player/player_state_dialogs.dart';

void main() {
  testWidgets('媒体控制面板将点击明确转发给当前播放器会话', (tester) async {
    final commands = <String>[];
    const snapshot = PlayerMediaControlsSnapshot(
      supported: true,
      audioTracks: <PlayerMediaTrack>[
        PlayerMediaTrack(
          id: '1',
          title: '中文',
          language: 'zh',
          codec: null,
          isDefault: true,
          selected: true,
        ),
      ],
      subtitleTracks: <PlayerMediaTrack>[
        PlayerMediaTrack(
          id: '2',
          title: 'English',
          language: 'en',
          codec: null,
          isDefault: true,
          selected: true,
        ),
      ],
      chapters: <PlayerMediaChapter>[
        PlayerMediaChapter(
          index: 0,
          position: Duration(seconds: 12),
          title: null,
        ),
      ],
      subtitleDelay: Duration.zero,
      audioDelay: Duration.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PlayerMediaControlsDialog(
                    read: () async => snapshot,
                    selectAudio: (id) async => commands.add('audio:$id'),
                    selectSubtitle: (id) async => commands.add('subtitle:$id'),
                    seekChapter: (index) async =>
                        commands.add('chapter:$index'),
                    adjustSubtitleDelay: (delta) async =>
                        commands.add('subtitle-delay:${delta.inMilliseconds}'),
                    adjustAudioDelay: (delta) async =>
                        commands.add('audio-delay:${delta.inMilliseconds}'),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('媒体控制'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player.mediaControls.dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player.mediaControls.audioTracks')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('媒体控制分组：音轨'),
      findsOneWidget,
    );

    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭字幕'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('player.mediaControls.subtitleDelay')),
        matching: find.byTooltip('增加 0.1 秒'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      commands,
      <String>[
        'audio:1',
        'subtitle:no',
        'subtitle-delay:100',
      ],
    );
  });

  testWidgets('媒体控制外壳在高对比度和 150% 文字下保持四组可达', (tester) async {
    const snapshot = PlayerMediaControlsSnapshot(
      supported: true,
      audioTracks: <PlayerMediaTrack>[],
      subtitleTracks: <PlayerMediaTrack>[],
      chapters: <PlayerMediaChapter>[],
      subtitleDelay: Duration.zero,
      audioDelay: Duration.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            highContrast: true,
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: Center(
              child: PlayerMediaControlsDialog(
                read: () async => snapshot,
                selectAudio: (_) async {},
                selectSubtitle: (_) async {},
                seekChapter: (_) async {},
                adjustSubtitleDelay: (_) async {},
                adjustAudioDelay: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('player.mediaControls.audioTracks')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player.mediaControls.subtitles')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player.mediaControls.sync')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey('player.mediaControls.content')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('player.mediaControls.chapters')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
