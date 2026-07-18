import 'dart:convert';

import 'app_paths.dart';

// ignore_for_file: slash_for_doc_comments

/** 有有效播放进度时的默认起播行为。 */
enum PlaybackResumeBehavior { continueWatching, restart, ask }

/** 播放完成后的全局队列策略，不改变 filtered queue 的顺序或来源。 */
enum PlayerPlaybackMode { sequential, shuffle, repeatOne, repeatAll }

/** 全局画面比例模式，只影响视频表面的呈现方式。 */
enum PlayerVideoAspectMode { automatic, ratio4x3, ratio16x9, cover }

/** 用户可配置的播放器快捷功能，绑定可包含 Control、Alt 与 Shift 修饰键。 */
enum PlayerShortcutAction {
  navigateBack,
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
    required this.mirrorVideo,
    required this.playbackMode,
    required this.videoAspectMode,
    required this.playbackRate,
    required this.confirmBeforeDeletingVideo,
    required this.moveDeletedFileToTrash,
  });

  static const defaults = PlaybackSettings(
    hwdec: 'auto-safe',
    resumeBehavior: PlaybackResumeBehavior.continueWatching,
    shortcuts: defaultShortcuts,
    fullscreenQueueEdgeWidth: 12,
    fullscreenQueueHideDelayMs: 180,
    mirrorVideo: false,
    playbackMode: PlayerPlaybackMode.sequential,
    videoAspectMode: PlayerVideoAspectMode.automatic,
    playbackRate: 1,
    confirmBeforeDeletingVideo: true,
    moveDeletedFileToTrash: false,
  );
  /** 播放内核已验证并允许持久化的固定倍速档位。 */
  static const playbackRates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
  static const defaultShortcuts = <PlayerShortcutAction, String>{
    PlayerShortcutAction.navigateBack: 'Escape',
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
    'Escape',
    'Enter',
    'Tab',
    'Backspace',
    'Delete',
    'Insert',
    'Home',
    'End',
    'PageUp',
    'PageDown',
    'ArrowLeft',
    'ArrowRight',
    'ArrowUp',
    'ArrowDown',
    'BracketLeft',
    'BracketRight',
    'Minus',
    'Equal',
    'Comma',
    'Period',
    'Slash',
    'Semicolon',
    'Quote',
    'Backquote',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'F1',
    'F2',
    'F3',
    'F4',
    'F5',
    'F6',
    'F7',
    'F8',
    'F9',
    'F10',
    'F11',
    'F12',
  ];

  /** 仍由播放器固定消费、不能覆盖的组合键及其动作说明。 */
  static const reservedShortcuts = <String, String>{
    'Alt+Insert': '切换收藏',
    'Control+Shift+Delete': '删除视频',
    'ArrowUp': '提高音量',
    'ArrowDown': '降低音量',
    'Home': '定位队列首项',
    'End': '定位队列末项',
    'Enter': '播放所选队列项',
  };
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
  /** 播放器功能到规范化快捷键标识的持久化绑定。 */
  final Map<PlayerShortcutAction, String> shortcuts;
  /** 全屏时用于唤出播放队列的右侧鼠标热区宽度，单位为逻辑像素。 */
  final int fullscreenQueueEdgeWidth;
  /** 鼠标离开全屏队列后的自动隐藏延迟，单位为毫秒。 */
  final int fullscreenQueueHideDelayMs;
  /** 是否全局水平翻转视频画面，不影响控制条和鼠标命中区域。 */
  final bool mirrorVideo;
  /** 全局队列播放方式；新播放器会话沿用最后一次选择。 */
  final PlayerPlaybackMode playbackMode;
  /** 全局画面比例；每次打开媒体后重新应用到播放后端。 */
  final PlayerVideoAspectMode videoAspectMode;
  /** 全局播放倍速；每次打开媒体后重新应用到播放后端。 */
  final double playbackRate;
  /** 删除视频前是否显示影响范围与回收站选择确认。 */
  final bool confirmBeforeDeletingVideo;
  /** 删除确认或无提示删除时，是否先把本地文件移入系统回收站。 */
  final bool moveDeletedFileToTrash;

  bool get hardwareDecodingEnabled => hwdec != 'no';

  PlaybackSettings copyWith({
    String? hwdec,
    PlaybackResumeBehavior? resumeBehavior,
    Map<PlayerShortcutAction, String>? shortcuts,
    int? fullscreenQueueEdgeWidth,
    int? fullscreenQueueHideDelayMs,
    bool? mirrorVideo,
    PlayerPlaybackMode? playbackMode,
    PlayerVideoAspectMode? videoAspectMode,
    double? playbackRate,
    bool? confirmBeforeDeletingVideo,
    bool? moveDeletedFileToTrash,
  }) {
    return PlaybackSettings(
      hwdec: hwdec ?? this.hwdec,
      resumeBehavior: resumeBehavior ?? this.resumeBehavior,
      shortcuts: shortcuts ?? this.shortcuts,
      fullscreenQueueEdgeWidth:
          fullscreenQueueEdgeWidth ?? this.fullscreenQueueEdgeWidth,
      fullscreenQueueHideDelayMs:
          fullscreenQueueHideDelayMs ?? this.fullscreenQueueHideDelayMs,
      mirrorVideo: mirrorVideo ?? this.mirrorVideo,
      playbackMode: playbackMode ?? this.playbackMode,
      videoAspectMode: videoAspectMode ?? this.videoAspectMode,
      playbackRate: playbackRate ?? this.playbackRate,
      confirmBeforeDeletingVideo:
          confirmBeforeDeletingVideo ?? this.confirmBeforeDeletingVideo,
      moveDeletedFileToTrash:
          moveDeletedFileToTrash ?? this.moveDeletedFileToTrash,
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
        'mirrorVideo': mirrorVideo,
        'playbackMode': playbackMode.name,
        'videoAspectMode': videoAspectMode.name,
        'playbackRate': playbackRate,
        'confirmBeforeDeletingVideo': confirmBeforeDeletingVideo,
        'moveDeletedFileToTrash': moveDeletedFileToTrash,
      };

  static PlaybackSettings fromJson(Map<String, Object?> json) {
    final value = json['hwdec']?.toString();
    final shortcutJson = json['shortcuts'];
    final shortcuts = Map<PlayerShortcutAction, String>.of(defaultShortcuts);
    if (shortcutJson is Map) {
      for (final action in PlayerShortcutAction.values) {
        final key = shortcutJson[action.name]?.toString();
        if (key != null && isSupportedShortcut(key)) {
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
      mirrorVideo: json['mirrorVideo'] is bool
          ? json['mirrorVideo']! as bool
          : defaults.mirrorVideo,
      playbackMode: _enumByName(
        PlayerPlaybackMode.values,
        json['playbackMode'],
        defaults.playbackMode,
      ),
      videoAspectMode: _enumByName(
        PlayerVideoAspectMode.values,
        json['videoAspectMode'],
        defaults.videoAspectMode,
      ),
      playbackRate: _supportedPlaybackRate(json['playbackRate']),
      confirmBeforeDeletingVideo: json['confirmBeforeDeletingVideo'] is bool
          ? json['confirmBeforeDeletingVideo']! as bool
          : defaults.confirmBeforeDeletingVideo,
      moveDeletedFileToTrash: json['moveDeletedFileToTrash'] is bool
          ? json['moveDeletedFileToTrash']! as bool
          : defaults.moveDeletedFileToTrash,
    );
  }

  /** 解析持久化枚举名称；旧文件缺字段或手工写入异常值时使用安全默认值。 */
  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? value,
    T fallback,
  ) {
    final name = value?.toString();
    for (final candidate in values) {
      if (candidate.name == name) {
        return candidate;
      }
    }
    return fallback;
  }

  /** 只接受播放器公开的固定倍速，避免异常配置把内核置于不可预期状态。 */
  static double _supportedPlaybackRate(Object? value) {
    final parsed = double.tryParse(value?.toString() ?? '');
    return parsed != null && playbackRates.contains(parsed)
        ? parsed
        : defaults.playbackRate;
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
        PlayerShortcutAction.navigateBack => '返回上一页',
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

  /** 验证持久化快捷键；支持零到三个修饰键加一个基础键。 */
  static bool isSupportedShortcut(String shortcut) {
    final parts = shortcut.split('+');
    if (parts.isEmpty || parts.length > 4) {
      return false;
    }
    final base = parts.last;
    if (!shortcutKeyOptions.contains(base)) {
      return false;
    }
    const modifierOrder = <String>['Control', 'Alt', 'Shift'];
    final modifiers = parts.take(parts.length - 1).toList();
    if (modifiers.toSet().length != modifiers.length) {
      return false;
    }
    final ordered = [
      for (final value in modifierOrder)
        if (modifiers.contains(value)) value
    ];
    return ordered.length == modifiers.length &&
        List.generate(
                modifiers.length, (index) => modifiers[index] == ordered[index])
            .every((matches) => matches);
  }

  /** 把稳定快捷键标识转换为设置页与 tooltip 使用的紧凑文本。 */
  static String shortcutKeyLabel(String key) {
    final parts = key.split('+');
    return parts.map(_shortcutPartLabel).join(' + ');
  }

  static String _shortcutPartLabel(String key) => switch (key) {
        'Control' => 'Ctrl',
        'Space' => '空格',
        'Escape' => 'Esc',
        'Enter' => 'Enter',
        'PageUp' => 'PageUp',
        'PageDown' => 'PageDown',
        'ArrowLeft' => '←',
        'ArrowRight' => '→',
        'BracketLeft' => '[',
        'BracketRight' => ']',
        'Minus' => '-',
        'Equal' => '=',
        'Comma' => ',',
        'Period' => '.',
        'Slash' => '/',
        'Semicolon' => ';',
        'Quote' => "'",
        'Backquote' => '`',
        _ => key,
      };
}
