part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 使用现有 media_kit/libmpv 实现 PlayerBackend 的兼容适配器。
 *
 * Player 与 VideoController 的所有权完全留在此类内部；页面只能通过稳定命令、
 * 轻量状态和纹理表面访问播放器，为后续 Windows C++ 后端保留可替换边界。
 */
class MediaKitPlayerBackend implements PlayerBackend {
  MediaKitPlayerBackend({
    required String hwdec,
    required bool enableHardwareAcceleration,
  })  : _player = Player(
          // 4K 长视频需要稳定输入窗口；该预算只属于当前播放会话，
          // 不扩大缩略图或媒体详情后台任务的内存占用。
          configuration:
              const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
        ),
        _controllerConfiguration = VideoControllerConfiguration(
          width: 1920,
          height: 1080,
          hwdec: hwdec,
          enableHardwareAcceleration: enableHardwareAcceleration,
        ) {
    _controller = VideoController(
      _player,
      configuration: _controllerConfiguration,
    );
  }

  /** 当前适配器独占的 media_kit Player。 */
  final Player _player;

  /** 创建纹理控制器使用的固定配置。 */
  final VideoControllerConfiguration _controllerConfiguration;

  /** 当前适配器独占的视频纹理控制器。 */
  late final VideoController _controller;

  /** dispose 完成信号，保证下一播放器不会越过旧原生资源释放。 */
  final Completer<void> _released = Completer<void>();

  @override
  PlayerBackendState get state => PlayerBackendState(
        position: _player.state.position,
        duration: _player.state.duration,
        playing: _player.state.playing,
        buffering: _player.state.buffering,
        volume: _player.state.volume,
        videoTrackCount: _player.state.tracks.video.length,
        audioTrackCount: _player.state.tracks.audio.length,
      );

  @override
  Stream<Duration> get positionChanges => _player.stream.position;

  @override
  Stream<bool> get playingChanges => _player.stream.playing;

  @override
  Stream<bool> get completedChanges => _player.stream.completed;

  @override
  Stream<String> get errorChanges => _player.stream.error;

  @override
  ValueListenable<int?> get textureId => _controller.id;

  @override
  Future<void> openPath(String path) => _player.open(Media(path));

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> setProperty(String property, String value) async {
    try {
      final platform = _player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty(property, value);
      }
    } catch (_) {
      // libmpv 构建可能不支持少数属性；诊断读取会反映最终实际值。
    }
  }

  @override
  Future<String> getProperty(String property) async {
    try {
      final platform = _player.platform;
      if (platform == null) return 'unavailable';
      final value = await (platform as dynamic).getProperty(property);
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? 'empty' : text;
    } catch (_) {
      return 'unavailable';
    }
  }

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) =>
      _player.screenshot(format: format);

  @override
  Widget buildVideoSurface({required Widget controls}) {
    return Video(
      controller: _controller,
      controls: (_) => controls,
    );
  }

  @override
  Future<void> dispose() async {
    if (_released.isCompleted) return;
    try {
      await _player.dispose();
    } finally {
      if (!_released.isCompleted) _released.complete();
    }
  }

  @override
  Future<void> get released => _released.future;
}
