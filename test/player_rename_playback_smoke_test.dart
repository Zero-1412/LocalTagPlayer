import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';
import 'package:path/path.dart' as p;

// ignore_for_file: slash_for_doc_comments

/**
 * 记录重命名回退期间的播放器命令，避免测试启动真实解码器或访问用户媒体库。
 */
class _RenameSmokePlayerBackend implements PlayerBackend {
  _RenameSmokePlayerBackend()
      : _state = const PlayerBackendState(
          position: Duration(seconds: 42),
          duration: Duration(minutes: 5),
          playing: true,
          buffering: false,
          volume: 100,
          videoTrackCount: 1,
          audioTrackCount: 1,
        );

  PlayerBackendState _state;
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(1);
  final List<String> calls = <String>[];

  @override
  PlayerBackendState get state => _state;

  @override
  Stream<Duration> get positionChanges => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingChanges => const Stream<bool>.empty();

  @override
  Stream<bool> get completedChanges => const Stream<bool>.empty();

  @override
  Stream<String> get errorChanges => const Stream<String>.empty();

  @override
  ValueListenable<int?> get textureId => _textureId;

  /** 保留未变化字段，只替换测试关心的播放位置或播放态。 */
  void _update({Duration? position, bool? playing}) {
    _state = PlayerBackendState(
      position: position ?? _state.position,
      duration: _state.duration,
      playing: playing ?? _state.playing,
      buffering: _state.buffering,
      volume: _state.volume,
      videoTrackCount: _state.videoTrackCount,
      audioTrackCount: _state.audioTrackCount,
    );
  }

  @override
  Future<void> openPath(String path) async => calls.add('open:$path');

  @override
  Future<void> play() async {
    calls.add('play');
    _update(playing: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _update(playing: false);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _update(playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    _update(position: position);
  }

  @override
  Future<void> setRate(double rate) async => calls.add('rate:$rate');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> playOrPause() async => _update(playing: !_state.playing);

  @override
  Future<void> setProperty(String property, String value) async =>
      calls.add('property:$property=$value');

  @override
  Future<String> getProperty(String property) async => 'unknown';

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async => null;

  @override
  Widget buildVideoSurface({
    required Widget controls,
    BoxFit fit = BoxFit.contain,
    double? aspectRatio,
    bool mirror = false,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: Colors.black),
        controls,
      ],
    );
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    _textureId.dispose();
  }

  @override
  Future<void> get released async {}
}

/** 缩略图在该冒烟测试中只显示占位，不启动 FFmpeg 或媒体探测。 */
class _RenameSmokeFFmpegBackend implements FFmpegBackend {
  @override
  Future<ExternalMediaToolsState> locateTools() async =>
      const ExternalMediaToolsState();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<String?> version() async => null;

  @override
  Future<File?> createThumbnail({
    required VideoItem item,
    required File output,
    bool allowFallback = true,
  }) async =>
      null;

  @override
  Future<File?> createFramePreview({
    required VideoItem item,
    required File output,
    required Duration position,
  }) async =>
      null;

  @override
  Future<MediaDetails?> probe(VideoItem item) async => null;
}

/** 冒烟测试不需要媒体详情，只提供可取消的空批次平台边界。 */
class _RenameSmokeProbeBackend implements MediaProbeBackend {
  @override
  Future<List<MediaProbeResult>> probeBatch({
    required int generationId,
    required List<MediaProbeRequest> requests,
  }) async =>
      const <MediaProbeResult>[];

  @override
  Future<void> cancelGeneration(int generationId) async {}
}

void main() {
  testWidgets(
      'isolated file rename confirmation releases lock and restores playback',
      (tester) async {
    final root = Directory(
      p.join(
        Directory.systemTemp.path,
        'ltp_rename_playback_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final source = File(p.join(root.path, 'before.mp4'));
    source.writeAsBytesSync(<int>[1, 2, 3], flush: true);
    final item = VideoItem(
      videoId: 'rename-playback-smoke',
      path: source.path,
      title: 'before',
      folder: root.path,
      tags: const <String>{'手动保留'},
      addedAt: DateTime.utc(2026, 7, 21),
      isFavorite: true,
    );
    final stableVideoId = item.videoId;
    final backend = _RenameSmokePlayerBackend();
    final fileSystem = const DesktopFileSystemAdapter();
    final thumbnailService = ThumbnailService.forDirectory(
      Directory(p.join(root.path, 'thumbs')),
      _RenameSmokeFFmpegBackend(),
    );
    final disposalCompleter = Completer<void>();
    final playerKey = GlobalKey<PlayerPageState>();
    var renameAttempts = 0;

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          key: playerKey,
          initialItem: item,
          playlist: <VideoItem>[item],
          thumbnailService: thumbnailService,
          playbackSettings: PlaybackSettings.defaults,
          onPlaybackSettingsChanged: (_) async {},
          activeTags: const <String>[],
          activeChildTag: null,
          queueTitle: '隔离重命名测试',
          onDeleteVideo: (_, __) async {},
          onToggleFavorite: (_) async {},
          onRenameFile: (target, newBaseName) async {
            renameAttempts += 1;
            if (renameAttempts == 1) {
              // 首次失败模拟 Windows 播放句柄占用；播放器必须先释放再重试。
              throw FileSystemException('sharing violation', target.path);
            }
            final nextPath = p.join(root.path, '$newBaseName.mp4');
            // widget test 使用同步临时文件 I/O，避免 FakeAsync 截留真实文件 Future。
            final renamedPath = fileSystem.normalizePath(
              File(target.path).renameSync(nextPath).path,
            );
            target
              ..path = renamedPath
              ..title = newBaseName;
          },
          onEditManualTags: (_) async {},
          onRelinkMissing: (_) async => false,
          onPlaybackProgressUpdated: (_, __, ___, ____) async {},
          onMediaDetailsUpdated: (_, __, ___) async {},
          disposalCompleter: disposalCompleter,
          fileSystem: fileSystem,
          playerBackendFactory: ({
            required String hwdec,
            required bool enableHardwareAcceleration,
          }) =>
              backend,
          mediaProbeBackendFactory: _RenameSmokeProbeBackend.new,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    unawaited(playerKey.currentState!.renameCurrentFileForTesting());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('player.renameFile.input')),
      'after',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('player.renameFile.confirm')),
    );
    await tester.pump(const Duration(seconds: 1));

    final renamed = File(p.join(root.path, 'after.mp4'));
    expect(renameAttempts, 2);
    expect(source.existsSync(), isFalse);
    expect(renamed.existsSync(), isTrue);
    expect(item.videoId, stableVideoId);
    expect(item.path, fileSystem.normalizePath(renamed.path));
    expect(item.tags, contains('手动保留'));
    expect(item.isFavorite, isTrue);
    expect(
        backend.calls,
        containsAllInOrder(<String>[
          'pause',
          'stop',
          'open:${fileSystem.normalizePath(renamed.path)}',
          'seek:42',
          'play',
        ]));
    expect(backend.state.position, const Duration(seconds: 42));
    expect(backend.state.playing, isTrue);
    expect(find.text('文件已重命名，播放状态已恢复'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
