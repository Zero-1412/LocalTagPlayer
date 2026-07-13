part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/** Windows 原生播放器后端使用的方法通道名称。 */
const _windowsNativePlayerChannel =
    MethodChannel('local_tag_player/native_player');

/**
 * Windows C++ 播放器骨架的 Flutter 适配器。
 *
 * 当前仅用于显式 A/B 开关验证纹理、命令串行化和生命周期；默认生产路径继续使用
 * MediaKitPlayerBackend，直到 libmpv/D3D11 后端通过同媒体基准验收。
 */
class WindowsNativePlayerBackend implements PlayerBackend {
  WindowsNativePlayerBackend()
      : _positionChanges = StreamController<Duration>.broadcast(),
        _playingChanges = StreamController<bool>.broadcast(),
        _completedChanges = StreamController<bool>.broadcast(),
        _errorChanges = StreamController<String>.broadcast() {
    _ready = _initialize();
  }

  final StreamController<Duration> _positionChanges;
  final StreamController<bool> _playingChanges;
  final StreamController<bool> _completedChanges;
  final StreamController<String> _errorChanges;
  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  final Completer<void> _released = Completer<void>();
  late final Future<void> _ready;
  Timer? _pollTimer;
  PlayerBackendState _state = const PlayerBackendState(
    position: Duration.zero,
    duration: Duration.zero,
    playing: false,
    buffering: false,
    volume: 100,
    videoTrackCount: 0,
    audioTrackCount: 0,
  );
  String _lifecycle = 'creating';
  bool _disposed = false;

  /** 创建原生假纹理并启动低频状态轮询。 */
  Future<void> _initialize() async {
    final value = await _windowsNativePlayerChannel
        .invokeMapMethod<String, Object?>('create');
    _applyState(value);
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => unawaited(_pollState()),
    );
  }

  /** 状态轮询仅用于骨架；真实后端将改为原生节流事件流。 */
  Future<void> _pollState() async {
    if (_disposed) return;
    try {
      final value = await _windowsNativePlayerChannel
          .invokeMapMethod<String, Object?>('state');
      _applyState(value);
    } catch (error) {
      _errorChanges.add(error.runtimeType.toString());
    }
  }

  /** 合并原生轻量快照，并只在字段变化时通知页面。 */
  void _applyState(Map<String, Object?>? value) {
    if (value == null || _disposed) return;
    final previous = _state;
    final position = Duration(milliseconds: value['positionMs'] as int? ?? 0);
    final duration = Duration(milliseconds: value['durationMs'] as int? ?? 0);
    final playing = value['playing'] as bool? ?? false;
    _state = PlayerBackendState(
      position: position,
      duration: duration,
      playing: playing,
      buffering: value['buffering'] as bool? ?? false,
      volume: (value['volume'] as num?)?.toDouble() ?? 100,
      videoTrackCount: duration > Duration.zero ? 1 : 0,
      audioTrackCount: 0,
    );
    _lifecycle = value['lifecycle'] as String? ?? _lifecycle;
    final texture = value['textureId'] as int?;
    _textureId.value = texture == null || texture < 0 ? null : texture;
    if (position != previous.position) _positionChanges.add(position);
    if (playing != previous.playing) _playingChanges.add(playing);
  }

  /** 将所有控制动作送入同一个原生串行队列。 */
  Future<void> _command(String name, {String? text, int? integer}) async {
    await _ready;
    await _windowsNativePlayerChannel.invokeMethod<void>('command', {
      'name': name,
      if (text != null) 'text': text,
      if (integer != null) 'integer': integer,
    });
    await _pollState();
  }

  @override
  PlayerBackendState get state => _state;

  @override
  Stream<Duration> get positionChanges => _positionChanges.stream;

  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  @override
  Stream<bool> get completedChanges => _completedChanges.stream;

  @override
  Stream<String> get errorChanges => _errorChanges.stream;

  @override
  ValueListenable<int?> get textureId => _textureId;

  @override
  Future<void> openPath(String path) => _command('open', text: path);

  @override
  Future<void> play() => _command('play');

  @override
  Future<void> pause() => _command('pause');

  @override
  Future<void> stop() => _command('stop');

  @override
  Future<void> seek(Duration position) =>
      _command('seek', integer: position.inMilliseconds);

  @override
  Future<void> setRate(double rate) =>
      _command('rate', integer: (rate * 1000).round());

  @override
  Future<void> setVolume(double volume) =>
      _command('volume', integer: (volume * 1000).round());

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> setProperty(String property, String value) =>
      _command('property', text: '$property=$value');

  @override
  Future<String> getProperty(String property) async {
    await _ready;
    if (property == 'video-codec') return 'native-stub';
    if (property == 'hwdec-current') return 'native-stub';
    if (property == 'current-vo') return 'flutter-pixel-buffer';
    if (property == 'native-lifecycle') return _lifecycle;
    return 'unavailable';
  }

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async => null;

  @override
  Widget buildVideoSurface({required Widget controls}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<int?>(
          valueListenable: _textureId,
          builder: (_, texture, __) => texture == null
              ? const ColoredBox(color: Colors.black)
              : Texture(textureId: texture),
        ),
        controls,
      ],
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    try {
      await _ready;
      await _windowsNativePlayerChannel.invokeMethod<void>('dispose');
    } finally {
      _textureId.value = null;
      await Future.wait<void>([
        _positionChanges.close(),
        _playingChanges.close(),
        _completedChanges.close(),
        _errorChanges.close(),
      ]);
      _textureId.dispose();
      if (!_released.isCompleted) _released.complete();
    }
  }

  @override
  Future<void> get released => _released.future;
}
