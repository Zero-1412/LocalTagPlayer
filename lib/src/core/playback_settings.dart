import 'dart:convert';

import 'app_paths.dart';

// ignore_for_file: slash_for_doc_comments

/** 有有效播放进度时的默认起播行为。 */
enum PlaybackResumeBehavior { continueWatching, restart, ask }

/** 用户可配置的播放器单键快捷功能。 */
enum PlayerShortcutAction {
  playPause,
  seekBackward,
  seekForward,
  previous,
  next,
  editTags,
  fullscreen,
  screenshot,
  speedDown,
  speedUp,
}

class PlaybackSettings {
  const PlaybackSettings({
    required this.hwdec,
    required this.resumeBehavior,
    required this.shortcuts,
    required this.fullscreenQueueEdgeWidth,
    required this.fullscreenQueueHideDelayMs,
  });

  static const defaults = PlaybackSettings(
    hwdec: 'auto-safe',
    resumeBehavior: PlaybackResumeBehavior.continueWatching,
    shortcuts: defaultShortcuts,
    fullscreenQueueEdgeWidth: 12,
    fullscreenQueueHideDelayMs: 180,
  );
  static const defaultShortcuts = <PlayerShortcutAction, String>{
    PlayerShortcutAction.playPause: 'Space',
    PlayerShortcutAction.seekBackward: 'J',
    PlayerShortcutAction.seekForward: 'L',
    PlayerShortcutAction.previous: 'PageUp',
    PlayerShortcutAction.next: 'PageDown',
    PlayerShortcutAction.editTags: 'T',
    PlayerShortcutAction.fullscreen: 'F',
    PlayerShortcutAction.screenshot: 'S',
    PlayerShortcutAction.speedDown: 'BracketLeft',
    PlayerShortcutAction.speedUp: 'BracketRight',
  };
  static const shortcutKeyOptions = <String>[
    'Space',
    'J',
    'L',
    'T',
    'F',
    'S',
    'PageUp',
    'PageDown',
    'ArrowLeft',
    'ArrowRight',
    'BracketLeft',
    'BracketRight',
  ];
  static const commonDecoderOptions = <String>['auto-safe', 'auto', 'no'];
  static const decoderOptions = <String>[
    'auto',
    'auto-safe',
    'auto-copy',
    'd3d11va',
    'd3d11va-copy',
    'dxva2',
    'dxva2-copy',
    'nvdec',
    'nvdec-copy',
    'cuda',
    'cuda-copy',
    'vulkan',
    'vulkan-copy',
    'no',
  ];

  final String hwdec;
  /** 用户在设置页选择的继续观看默认策略。 */
  final PlaybackResumeBehavior resumeBehavior;
  /** 播放器功能到单键标识的持久化绑定。 */
  final Map<PlayerShortcutAction, String> shortcuts;
  /** 全屏时用于唤出播放队列的右侧鼠标热区宽度，单位为逻辑像素。 */
  final int fullscreenQueueEdgeWidth;
  /** 鼠标离开全屏队列后的自动隐藏延迟，单位为毫秒。 */
  final int fullscreenQueueHideDelayMs;

  bool get hardwareDecodingEnabled => hwdec != 'no';

  PlaybackSettings copyWith({
    String? hwdec,
    PlaybackResumeBehavior? resumeBehavior,
    Map<PlayerShortcutAction, String>? shortcuts,
    int? fullscreenQueueEdgeWidth,
    int? fullscreenQueueHideDelayMs,
  }) {
    return PlaybackSettings(
      hwdec: hwdec ?? this.hwdec,
      resumeBehavior: resumeBehavior ?? this.resumeBehavior,
      shortcuts: shortcuts ?? this.shortcuts,
      fullscreenQueueEdgeWidth:
          fullscreenQueueEdgeWidth ?? this.fullscreenQueueEdgeWidth,
      fullscreenQueueHideDelayMs:
          fullscreenQueueHideDelayMs ?? this.fullscreenQueueHideDelayMs,
    );
  }

  /** 仅恢复全屏队列交互默认值，保留其它所有播放设置。 */
  PlaybackSettings resetFullscreenQueueInteraction() => copyWith(
        fullscreenQueueEdgeWidth: defaults.fullscreenQueueEdgeWidth,
        fullscreenQueueHideDelayMs: defaults.fullscreenQueueHideDelayMs,
      );

  Map<String, Object?> toJson() => {
        'hwdec': hwdec,
        'resumeBehavior': resumeBehavior.name,
        'shortcuts': {
          for (final entry in shortcuts.entries) entry.key.name: entry.value,
        },
        'fullscreenQueueEdgeWidth': fullscreenQueueEdgeWidth,
        'fullscreenQueueHideDelayMs': fullscreenQueueHideDelayMs,
      };

  static PlaybackSettings fromJson(Map<String, Object?> json) {
    final value = json['hwdec']?.toString();
    final shortcutJson = json['shortcuts'];
    final shortcuts = Map<PlayerShortcutAction, String>.of(defaultShortcuts);
    if (shortcutJson is Map) {
      for (final action in PlayerShortcutAction.values) {
        final key = shortcutJson[action.name]?.toString();
        if (key != null && shortcutKeyOptions.contains(key)) {
          shortcuts[action] = key;
        }
      }
    }
    return PlaybackSettings(
      hwdec: decoderOptions.contains(value) ? value! : defaults.hwdec,
      resumeBehavior: PlaybackResumeBehavior.values.firstWhere(
        (behavior) => behavior.name == json['resumeBehavior']?.toString(),
        orElse: () => defaults.resumeBehavior,
      ),
      shortcuts: Map.unmodifiable(shortcuts),
      fullscreenQueueEdgeWidth: _boundedInt(
        json['fullscreenQueueEdgeWidth'],
        fallback: defaults.fullscreenQueueEdgeWidth,
        min: 4,
        max: 40,
      ),
      fullscreenQueueHideDelayMs: _boundedInt(
        json['fullscreenQueueHideDelayMs'],
        fallback: defaults.fullscreenQueueHideDelayMs,
        min: 0,
        max: 1000,
      ),
    );
  }

  /** 读取旧版或手工编辑的设置值，并约束到播放器可安全使用的范围。 */
  static int _boundedInt(
    Object? value, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed == null ? fallback : parsed.clamp(min, max);
  }

  static Future<PlaybackSettings> load(AppPaths paths) async {
    try {
      final file = await paths.settingsFile();
      if (!await file.exists()) {
        return defaults;
      }
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, Object?>) {
        return fromJson(json);
      }
    } catch (_) {
      return defaults;
    }
    return defaults;
  }

  Future<void> save(AppPaths paths) async {
    final file = await paths.settingsFile();
    await file.writeAsString(jsonEncode(toJson()), flush: true);
  }

  static String labelFor(String value) {
    return switch (value) {
      'auto' => 'auto - \u542f\u7528\u4efb\u610f\u53ef\u7528\u89e3\u7801\u5668',
      'auto-safe' =>
        'auto-safe - \u542f\u7528\u6700\u4f73\u5b89\u5168\u89e3\u7801\u5668',
      'auto-copy' =>
        'auto-copy - \u542f\u7528\u5e26\u62f7\u8d1d\u7684\u6700\u4f73\u89e3\u7801\u5668',
      'd3d11va' => 'd3d11va - DirectX11',
      'd3d11va-copy' => 'd3d11va-copy - DirectX11 \u975e\u76f4\u901a',
      'dxva2' => 'dxva2 - Windows DXVA2',
      'dxva2-copy' => 'dxva2-copy - DXVA2 \u975e\u76f4\u901a',
      'nvdec' => 'nvdec - NVIDIA',
      'nvdec-copy' => 'nvdec-copy - NVIDIA \u975e\u76f4\u901a',
      'cuda' => 'cuda - NVIDIA CUDA',
      'cuda-copy' => 'cuda-copy - CUDA \u975e\u76f4\u901a',
      'vulkan' => 'vulkan - \u5168\u5e73\u53f0\u5b9e\u9a8c',
      'vulkan-copy' => 'vulkan-copy - Vulkan \u975e\u76f4\u901a',
      'no' => 'no - \u5173\u95ed\u786c\u4ef6\u89e3\u7801',
      _ => value,
    };
  }

  /** 设置页常用解码档位使用面向产品目标的名称。 */
  static String commonLabelFor(String value) => switch (value) {
        'auto-safe' => '推荐：自动安全',
        'auto' => '性能优先：自动零拷贝',
        'no' => '兼容优先：软件解码',
        _ => labelFor(value),
      };

  /** 设置页继续观看行为名称。 */
  static String resumeLabelFor(PlaybackResumeBehavior behavior) =>
      switch (behavior) {
        PlaybackResumeBehavior.continueWatching => '从上次位置继续',
        PlaybackResumeBehavior.restart => '从头播放',
        PlaybackResumeBehavior.ask => '每次询问',
      };

  static String shortcutActionLabel(PlayerShortcutAction action) =>
      switch (action) {
        PlayerShortcutAction.playPause => '播放 / 暂停',
        PlayerShortcutAction.seekBackward => '快退 5 秒',
        PlayerShortcutAction.seekForward => '快进 5 秒',
        PlayerShortcutAction.previous => '上一条',
        PlayerShortcutAction.next => '下一条',
        PlayerShortcutAction.editTags => '编辑标签',
        PlayerShortcutAction.fullscreen => '全屏 / 退出全屏',
        PlayerShortcutAction.screenshot => '截图',
        PlayerShortcutAction.speedDown => '降低倍速',
        PlayerShortcutAction.speedUp => '提高倍速',
      };

  static String shortcutKeyLabel(String key) => switch (key) {
        'Space' => '空格',
        'PageUp' => 'PageUp',
        'PageDown' => 'PageDown',
        'ArrowLeft' => '←',
        'ArrowRight' => '→',
        'BracketLeft' => '[',
        'BracketRight' => ']',
        _ => key,
      };
}
