import 'dart:convert';

import 'app_paths.dart';

// ignore_for_file: slash_for_doc_comments

/** 有有效播放进度时的默认起播行为。 */
enum PlaybackResumeBehavior { continueWatching, restart, ask }

/** 播放完成后的全局队列策略，不改变 filtered queue 的顺序或来源。 */
enum PlayerPlaybackMode { sequential, shuffle, repeatOne, repeatAll }

/** 全局画面比例模式，只影响视频表面的呈现方式。 */
enum PlayerVideoAspectMode { automatic, ratio4x3, ratio16x9, cover }

/**
 * 播放器渲染器偏好。
 *
 * `mediaKit` 与 `windowsLibmpv` 是设置页唯一可选的两个后端。`automatic`
 * 仅用于读取旧设置，载入时迁移为 MPV，不再展示给用户或参与新持久化。
 */
enum PlayerRendererPreference { automatic, mediaKit, windowsLibmpv }

/** GPU 视频缩放器；只提供已在 libmpv 中稳定支持的两种质量档位。 */
enum PlayerVideoScaler { bicubic, lanczos }

/**
 * 播放流畅度增强档位。
 *
 * `displayInterpolation` 只请求 mpv 基于相邻原始帧的显示同步插值，不代表
 * NVIDIA、RIFE 或其它 AI 生成中间帧能力。
 */
enum PlayerSmoothMotionMode { off, displayInterpolation }

/** 显示输出电平；自动模式由 libmpv 根据输出链路选择安全值。 */
enum PlayerVideoOutputRange { automatic, limited, full }

/**
 * 压缩画质增强的用户档位。
 *
 * 关闭不启用压缩修复滤镜；自动沿用播放余量协调器逐级增强；清晰增强会在首个
 * 稳定样本上请求当前分辨率与解码路径允许的最高档，出现压力后仍自动回滚。
 */
enum PlayerCompressionEnhancementMode { off, automatic, clarity }

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
    required this.rendererPreference,
    required this.resumeBehavior,
    required this.shortcuts,
    required this.fullscreenQueueEdgeHoverEnabled,
    required this.fullscreenQueueEdgeWidth,
    required this.fullscreenQueueHideDelayMs,
    required this.mirrorVideo,
    required this.playbackMode,
    required this.videoAspectMode,
    required this.videoScaler,
    required this.smoothMotionMode,
    required this.videoOutputRange,
    required this.highQualityStreamCacheEnabled,
    required this.playbackRate,
    required this.seekStepSeconds,
    required this.videoSuperResolutionEnabled,
    PlayerCompressionEnhancementMode? compressionEnhancementMode,
    bool? automaticQualityEnhancementEnabled,
    required this.darkSceneEnhancementEnabled,
    required this.hdrDynamicToneMappingExperimentEnabled,
    required this.confirmBeforeDeletingVideo,
    required this.moveDeletedFileToTrash,
    this.autoRemoveMissingOrUnreadableVideos = true,
  }) : compressionEnhancementMode = compressionEnhancementMode ??
            (automaticQualityEnhancementEnabled == true
                ? PlayerCompressionEnhancementMode.automatic
                : PlayerCompressionEnhancementMode.off);

  static const defaults = PlaybackSettings(
    hwdec: 'auto-safe',
    rendererPreference: PlayerRendererPreference.windowsLibmpv,
    resumeBehavior: PlaybackResumeBehavior.continueWatching,
    shortcuts: defaultShortcuts,
    fullscreenQueueEdgeHoverEnabled: true,
    fullscreenQueueEdgeWidth: 12,
    fullscreenQueueHideDelayMs: 180,
    mirrorVideo: false,
    playbackMode: PlayerPlaybackMode.sequential,
    videoAspectMode: PlayerVideoAspectMode.automatic,
    videoScaler: PlayerVideoScaler.lanczos,
    smoothMotionMode: PlayerSmoothMotionMode.off,
    videoOutputRange: PlayerVideoOutputRange.automatic,
    highQualityStreamCacheEnabled: true,
    playbackRate: 1,
    seekStepSeconds: 5,
    videoSuperResolutionEnabled: false,
    compressionEnhancementMode: PlayerCompressionEnhancementMode.off,
    darkSceneEnhancementEnabled: false,
    hdrDynamicToneMappingExperimentEnabled: false,
    confirmBeforeDeletingVideo: true,
    moveDeletedFileToTrash: false,
    autoRemoveMissingOrUnreadableVideos: true,
  );
  /** 播放内核已验证并允许持久化的固定倍速档位。 */
  static const playbackRates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
  /** 播放器快进与快退允许选择的固定秒数，避免异常配置产生过大的跳转。 */
  static const seekStepOptions = <int>[5, 10, 15, 30, 60];
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
  /** 下一次创建播放器 Route 时使用的渲染器偏好；当前会话不热拆后端。 */
  final PlayerRendererPreference rendererPreference;
  /** 用户在设置页选择的继续观看默认策略。 */
  final PlaybackResumeBehavior resumeBehavior;
  /** 播放器功能到规范化快捷键标识的持久化绑定。 */
  final Map<PlayerShortcutAction, String> shortcuts;
  /** 是否允许鼠标移到全屏右侧边缘时自动唤出播放队列。 */
  final bool fullscreenQueueEdgeHoverEnabled;
  /** 兼容旧设置文件的历史热区参数；播放器改用内部验证过的固定值。 */
  final int fullscreenQueueEdgeWidth;
  /** 兼容旧设置文件的历史隐藏延迟；播放器改用内部验证过的固定值。 */
  final int fullscreenQueueHideDelayMs;
  /** 是否全局水平翻转视频画面，不影响控制条和鼠标命中区域。 */
  final bool mirrorVideo;
  /** 全局队列播放方式；新播放器会话沿用最后一次选择。 */
  final PlayerPlaybackMode playbackMode;
  /** 全局画面比例；每次打开媒体后重新应用到播放后端。 */
  final PlayerVideoAspectMode videoAspectMode;
  /** 未开启超分时使用的 GPU 缩放器；超分关闭后必须恢复此值。 */
  final PlayerVideoScaler videoScaler;
  /** 显示同步插值偏好；旧设置迁移时默认关闭，不冒充 AI 补帧。 */
  final PlayerSmoothMotionMode smoothMotionMode;
  /** 输出到显示设备的 Limited / Full Range 策略。 */
  final PlayerVideoOutputRange videoOutputRange;
  /** 是否为当前播放会话保留原始压缩码流的高质量内存缓存窗口。 */
  final bool highQualityStreamCacheEnabled;
  /** 全局播放倍速；每次打开媒体后重新应用到播放后端。 */
  final double playbackRate;
  /** 快进与快退快捷键共用的全局跳转秒数。 */
  final int seekStepSeconds;
  /** 是否启用只在画面放大时运行的 libmpv GPU 高质量缩放；不代表厂商 AI 超分。 */
  final bool videoSuperResolutionEnabled;
  /** 压缩画质增强档位；旧布尔设置会安全迁移为关闭或自动。 */
  final PlayerCompressionEnhancementMode compressionEnhancementMode;
  /** 是否对已确认的 SDR 视频启用经过独立基线验证的保守暗部细节增强。 */
  final bool darkSceneEnhancementEnabled;
  /** 是否启用默认关闭、关闭即恢复 mpv 自动值的 HDR 动态映射。 */
  final bool hdrDynamicToneMappingExperimentEnabled;
  /** 删除视频前是否显示影响范围与回收站选择确认。 */
  final bool confirmBeforeDeletingVideo;
  /** 删除确认或无提示删除时，是否先把本地文件移入系统回收站。 */
  final bool moveDeletedFileToTrash;
  /** 是否只从数据库自动移除安全确认的 missing 或不可读视频；不授权删除磁盘文件。 */
  final bool autoRemoveMissingOrUnreadableVideos;

  bool get hardwareDecodingEnabled => hwdec != 'no';

  /**
   * 兼容旧调用方的布尔视图。
   *
   * 清晰增强同样需要播放健康采样，因此对旧逻辑表现为已启用。
   */
  bool get automaticQualityEnhancementEnabled =>
      compressionEnhancementMode != PlayerCompressionEnhancementMode.off;

  PlaybackSettings copyWith({
    String? hwdec,
    PlayerRendererPreference? rendererPreference,
    PlaybackResumeBehavior? resumeBehavior,
    Map<PlayerShortcutAction, String>? shortcuts,
    bool? fullscreenQueueEdgeHoverEnabled,
    int? fullscreenQueueEdgeWidth,
    int? fullscreenQueueHideDelayMs,
    bool? mirrorVideo,
    PlayerPlaybackMode? playbackMode,
    PlayerVideoAspectMode? videoAspectMode,
    PlayerVideoScaler? videoScaler,
    PlayerSmoothMotionMode? smoothMotionMode,
    PlayerVideoOutputRange? videoOutputRange,
    bool? highQualityStreamCacheEnabled,
    double? playbackRate,
    int? seekStepSeconds,
    bool? videoSuperResolutionEnabled,
    PlayerCompressionEnhancementMode? compressionEnhancementMode,
    bool? automaticQualityEnhancementEnabled,
    bool? darkSceneEnhancementEnabled,
    bool? hdrDynamicToneMappingExperimentEnabled,
    bool? confirmBeforeDeletingVideo,
    bool? moveDeletedFileToTrash,
    bool? autoRemoveMissingOrUnreadableVideos,
  }) {
    final resolvedCompressionMode = compressionEnhancementMode ??
        (automaticQualityEnhancementEnabled == null
            ? this.compressionEnhancementMode
            : automaticQualityEnhancementEnabled
                ? PlayerCompressionEnhancementMode.automatic
                : PlayerCompressionEnhancementMode.off);
    return PlaybackSettings(
      hwdec: hwdec ?? this.hwdec,
      rendererPreference: rendererPreference ?? this.rendererPreference,
      resumeBehavior: resumeBehavior ?? this.resumeBehavior,
      shortcuts: shortcuts ?? this.shortcuts,
      fullscreenQueueEdgeHoverEnabled: fullscreenQueueEdgeHoverEnabled ??
          this.fullscreenQueueEdgeHoverEnabled,
      fullscreenQueueEdgeWidth:
          fullscreenQueueEdgeWidth ?? this.fullscreenQueueEdgeWidth,
      fullscreenQueueHideDelayMs:
          fullscreenQueueHideDelayMs ?? this.fullscreenQueueHideDelayMs,
      mirrorVideo: mirrorVideo ?? this.mirrorVideo,
      playbackMode: playbackMode ?? this.playbackMode,
      videoAspectMode: videoAspectMode ?? this.videoAspectMode,
      videoScaler: videoScaler ?? this.videoScaler,
      smoothMotionMode: smoothMotionMode ?? this.smoothMotionMode,
      videoOutputRange: videoOutputRange ?? this.videoOutputRange,
      highQualityStreamCacheEnabled:
          highQualityStreamCacheEnabled ?? this.highQualityStreamCacheEnabled,
      playbackRate: playbackRate ?? this.playbackRate,
      seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
      videoSuperResolutionEnabled:
          videoSuperResolutionEnabled ?? this.videoSuperResolutionEnabled,
      compressionEnhancementMode: resolvedCompressionMode,
      darkSceneEnhancementEnabled:
          darkSceneEnhancementEnabled ?? this.darkSceneEnhancementEnabled,
      hdrDynamicToneMappingExperimentEnabled:
          hdrDynamicToneMappingExperimentEnabled ??
              this.hdrDynamicToneMappingExperimentEnabled,
      confirmBeforeDeletingVideo:
          confirmBeforeDeletingVideo ?? this.confirmBeforeDeletingVideo,
      moveDeletedFileToTrash:
          moveDeletedFileToTrash ?? this.moveDeletedFileToTrash,
      autoRemoveMissingOrUnreadableVideos:
          autoRemoveMissingOrUnreadableVideos ??
              this.autoRemoveMissingOrUnreadableVideos,
    );
  }

  /** 仅恢复全屏队列交互默认值，保留其它所有播放设置。 */
  PlaybackSettings resetFullscreenQueueInteraction() => copyWith(
        fullscreenQueueEdgeHoverEnabled:
            defaults.fullscreenQueueEdgeHoverEnabled,
        fullscreenQueueEdgeWidth: defaults.fullscreenQueueEdgeWidth,
        fullscreenQueueHideDelayMs: defaults.fullscreenQueueHideDelayMs,
      );

  Map<String, Object?> toJson() => {
        'hwdec': hwdec,
        'rendererPreference': rendererPreference.name,
        'resumeBehavior': resumeBehavior.name,
        'shortcuts': {
          for (final entry in shortcuts.entries) entry.key.name: entry.value,
        },
        'fullscreenQueueEdgeHoverEnabled': fullscreenQueueEdgeHoverEnabled,
        'fullscreenQueueEdgeWidth': fullscreenQueueEdgeWidth,
        'fullscreenQueueHideDelayMs': fullscreenQueueHideDelayMs,
        'mirrorVideo': mirrorVideo,
        'playbackMode': playbackMode.name,
        'videoAspectMode': videoAspectMode.name,
        'videoScaler': videoScaler.name,
        'smoothMotionMode': smoothMotionMode.name,
        'videoOutputRange': videoOutputRange.name,
        'highQualityStreamCacheEnabled': highQualityStreamCacheEnabled,
        'playbackRate': playbackRate,
        'seekStepSeconds': seekStepSeconds,
        'videoSuperResolutionEnabled': videoSuperResolutionEnabled,
        'compressionEnhancementMode': compressionEnhancementMode.name,
        // 保留旧键，确保降级读取设置时仍能得到“关闭 / 已启用”的安全语义。
        'automaticQualityEnhancementEnabled':
            automaticQualityEnhancementEnabled,
        'darkSceneEnhancementEnabled': darkSceneEnhancementEnabled,
        'hdrDynamicToneMappingExperimentEnabled':
            hdrDynamicToneMappingExperimentEnabled,
        'confirmBeforeDeletingVideo': confirmBeforeDeletingVideo,
        'moveDeletedFileToTrash': moveDeletedFileToTrash,
        'autoRemoveMissingOrUnreadableVideos':
            autoRemoveMissingOrUnreadableVideos,
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
      rendererPreference: _rendererPreferenceFromJson(
        json['rendererPreference'],
      ),
      resumeBehavior: PlaybackResumeBehavior.values.firstWhere(
        (behavior) => behavior.name == json['resumeBehavior']?.toString(),
        orElse: () => defaults.resumeBehavior,
      ),
      shortcuts: Map.unmodifiable(shortcuts),
      fullscreenQueueEdgeHoverEnabled:
          json['fullscreenQueueEdgeHoverEnabled'] is bool
              ? json['fullscreenQueueEdgeHoverEnabled']! as bool
              : defaults.fullscreenQueueEdgeHoverEnabled,
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
      videoScaler: _enumByName(
        PlayerVideoScaler.values,
        json['videoScaler'],
        defaults.videoScaler,
      ),
      smoothMotionMode: _enumByName(
        PlayerSmoothMotionMode.values,
        json['smoothMotionMode'],
        defaults.smoothMotionMode,
      ),
      videoOutputRange: _enumByName(
        PlayerVideoOutputRange.values,
        json['videoOutputRange'],
        defaults.videoOutputRange,
      ),
      highQualityStreamCacheEnabled:
          json['highQualityStreamCacheEnabled'] is bool
              ? json['highQualityStreamCacheEnabled']! as bool
              : defaults.highQualityStreamCacheEnabled,
      playbackRate: _supportedPlaybackRate(json['playbackRate']),
      seekStepSeconds: _supportedSeekStep(json['seekStepSeconds']),
      videoSuperResolutionEnabled: json['videoSuperResolutionEnabled'] is bool
          ? json['videoSuperResolutionEnabled']! as bool
          : defaults.videoSuperResolutionEnabled,
      compressionEnhancementMode: json['compressionEnhancementMode'] == null
          ? (json['automaticQualityEnhancementEnabled'] == true
              ? PlayerCompressionEnhancementMode.automatic
              : defaults.compressionEnhancementMode)
          : _enumByName(
              PlayerCompressionEnhancementMode.values,
              json['compressionEnhancementMode'],
              defaults.compressionEnhancementMode,
            ),
      darkSceneEnhancementEnabled: json['darkSceneEnhancementEnabled'] is bool
          ? json['darkSceneEnhancementEnabled']! as bool
          : defaults.darkSceneEnhancementEnabled,
      hdrDynamicToneMappingExperimentEnabled:
          json['hdrDynamicToneMappingExperimentEnabled'] is bool
              ? json['hdrDynamicToneMappingExperimentEnabled']! as bool
              : defaults.hdrDynamicToneMappingExperimentEnabled,
      confirmBeforeDeletingVideo: json['confirmBeforeDeletingVideo'] is bool
          ? json['confirmBeforeDeletingVideo']! as bool
          : defaults.confirmBeforeDeletingVideo,
      moveDeletedFileToTrash: json['moveDeletedFileToTrash'] is bool
          ? json['moveDeletedFileToTrash']! as bool
          : defaults.moveDeletedFileToTrash,
      autoRemoveMissingOrUnreadableVideos:
          json['autoRemoveMissingOrUnreadableVideos'] is bool
              ? json['autoRemoveMissingOrUnreadableVideos']! as bool
              : defaults.autoRemoveMissingOrUnreadableVideos,
    );
  }

  /**
   * 把旧三态渲染器设置迁移为用户可见的 MediaKit / MPV 两态。
   *
   * 历史 `automatic` 与 `windowsLibmpv` 都表示用户未强制兼容后端，因此迁移
   * 到 MPV；只有明确保存的 `mediaKit` 保持 MediaKit。
   */
  static PlayerRendererPreference _rendererPreferenceFromJson(Object? value) {
    return value?.toString() == PlayerRendererPreference.mediaKit.name
        ? PlayerRendererPreference.mediaKit
        : PlayerRendererPreference.windowsLibmpv;
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

  /** 只接受界面公开的离散快进档位，旧设置缺字段时继续使用 5 秒。 */
  static int _supportedSeekStep(Object? value) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && seekStepOptions.contains(parsed)
        ? parsed
        : defaults.seekStepSeconds;
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

  /** 把渲染器枚举转换为面向用户的稳定名称。 */
  static String rendererLabelFor(PlayerRendererPreference value) =>
      switch (value) {
        PlayerRendererPreference.automatic ||
        PlayerRendererPreference.windowsLibmpv =>
          'MPV 容器渲染',
        PlayerRendererPreference.mediaKit => 'MediaKit 兼容渲染',
      };

  /** 解释渲染器的真实能力和生效边界，避免把兼容后端描述为 NVIDIA AI。 */
  static String rendererDescriptionFor(PlayerRendererPreference value) =>
      switch (value) {
        PlayerRendererPreference.automatic ||
        PlayerRendererPreference.windowsLibmpv =>
          '下次进入播放器使用 Flutter Texture；播放列表与弹层可正常覆盖',
        PlayerRendererPreference.mediaKit => '跨平台兼容性优先；Windows NVIDIA 原生增强不可用',
      };

  /** 设置页按所选后端展示真实可用的特色强化，不把 MPV 能力归给 MediaKit。 */
  static String rendererFeaturesFor(PlayerRendererPreference value) =>
      switch (value) {
        PlayerRendererPreference.automatic ||
        PlayerRendererPreference.windowsLibmpv =>
          '特色强化：MPV 滤镜、GPU 高质量缩放、压缩画质增强',
        PlayerRendererPreference.mediaKit => '特色强化：跨平台兼容、镜像、压缩画质增强',
      };

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

  /** 设置页画面比例名称。 */
  static String videoAspectLabelFor(PlayerVideoAspectMode mode) =>
      switch (mode) {
        PlayerVideoAspectMode.automatic => '自动保持源比例',
        PlayerVideoAspectMode.ratio4x3 => '固定 4:3',
        PlayerVideoAspectMode.ratio16x9 => '固定 16:9',
        PlayerVideoAspectMode.cover => '铺满并等比裁边',
      };

  /** 设置页缩放器名称。 */
  static String videoScalerLabelFor(PlayerVideoScaler scaler) =>
      switch (scaler) {
        PlayerVideoScaler.bicubic => 'Bicubic（平衡）',
        PlayerVideoScaler.lanczos => 'Lanczos（高质量）',
      };

  /** 设置页流畅度增强名称；明确区分显示插值与 AI 生成帧。 */
  static String smoothMotionLabelFor(PlayerSmoothMotionMode mode) =>
      switch (mode) {
        PlayerSmoothMotionMode.off => '关闭',
        PlayerSmoothMotionMode.displayInterpolation => '显示同步插值',
      };

  /** 解释显示同步插值的性能边界和失败回退。 */
  static String smoothMotionDescriptionFor(PlayerSmoothMotionMode mode) =>
      switch (mode) {
        PlayerSmoothMotionMode.off => '保持源帧率，不增加时间采样开销',
        PlayerSmoothMotionMode.displayInterpolation =>
          '缓解帧率与刷新率不匹配的顿挫；非 AI 补帧，播放压力出现时仅回滚当前视频',
      };

  /** 设置页输出电平名称。 */
  static String videoOutputRangeLabelFor(PlayerVideoOutputRange range) =>
      switch (range) {
        PlayerVideoOutputRange.automatic => '自动（推荐）',
        PlayerVideoOutputRange.limited => 'Limited（16–235）',
        PlayerVideoOutputRange.full => 'Full（0–255）',
      };

  /** 设置页与播放器齿轮共用的压缩画质增强名称。 */
  static String compressionEnhancementLabelFor(
    PlayerCompressionEnhancementMode mode,
  ) =>
      switch (mode) {
        PlayerCompressionEnhancementMode.off => '关闭',
        PlayerCompressionEnhancementMode.automatic => '自动',
        PlayerCompressionEnhancementMode.clarity => '清晰增强',
      };

  static String shortcutActionLabel(PlayerShortcutAction action) =>
      switch (action) {
        PlayerShortcutAction.navigateBack => '返回上一页',
        PlayerShortcutAction.playPause => '播放 / 暂停',
        PlayerShortcutAction.seekBackward => '快退（播放器档位）',
        PlayerShortcutAction.seekForward => '快进（播放器档位）',
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
