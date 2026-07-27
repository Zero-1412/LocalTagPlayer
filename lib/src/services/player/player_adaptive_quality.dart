import '../../platform/platform_interfaces.dart';
import 'player_nvidia_video_enhancement_experiment.dart';

// ignore_for_file: slash_for_doc_comments

/** 自动画质协调器当前实际启用的观感增强档位。 */
enum PlayerAdaptiveQualityLevel {
  off,
  deblock,
  deblockDenoise,
  deblockDenoiseSharpen,
}

/** 基线按分辨率和真实解码路径划分的运行档案。 */
class PlayerQualityBaselineProfile {
  const PlayerQualityBaselineProfile({
    required this.label,
    required this.maximumLevel,
  });

  /** 诊断中显示的匿名基线名称。 */
  final String label;

  /** 当前基线允许自动升级到的最高档位。 */
  final PlayerAdaptiveQualityLevel maximumLevel;

  /**
   * 根据真实分辨率和 `hwdec-current` 选择保守上限。
   *
   * 2026-07-22 参考机基线显示 4K 软件解码已经出现掉帧，因此不能再叠加 CPU
   * 视频滤镜；4K 硬解也只开放最低档，优先保护 60 fps 播放余量。
   */
  static PlayerQualityBaselineProfile resolve({
    required int? width,
    required int? height,
    required String? hwdecCurrent,
  }) {
    if (width == null || width <= 0 || height == null || height <= 0) {
      return const PlayerQualityBaselineProfile(
        label: '分辨率未知 · 保守关闭',
        maximumLevel: PlayerAdaptiveQualityLevel.off,
      );
    }
    final longEdge = width;
    final shortEdge = height;
    final is4k = longEdge >= 3200 || shortEdge >= 2160;
    final isHardware = hwdecCurrent != null &&
        hwdecCurrent != 'no' &&
        hwdecCurrent != 'empty' &&
        hwdecCurrent != 'unavailable';
    if (is4k && !isHardware) {
      return const PlayerQualityBaselineProfile(
        label: '4K · CPU 软件解码',
        maximumLevel: PlayerAdaptiveQualityLevel.off,
      );
    }
    if (is4k) {
      return const PlayerQualityBaselineProfile(
        label: '4K · GPU 硬解',
        maximumLevel: PlayerAdaptiveQualityLevel.deblock,
      );
    }
    if (!isHardware) {
      return const PlayerQualityBaselineProfile(
        label: '1080p 及以下 · CPU 软件解码',
        maximumLevel: PlayerAdaptiveQualityLevel.deblockDenoise,
      );
    }
    return const PlayerQualityBaselineProfile(
      label: '1080p 及以下 · GPU 硬解',
      maximumLevel: PlayerAdaptiveQualityLevel.deblockDenoiseSharpen,
    );
  }
}

/** 每秒送入协调器的只读实时余量样本。 */
class PlayerAdaptiveQualitySample {
  const PlayerAdaptiveQualitySample({
    required this.sampledAt,
    required this.playing,
    required this.buffering,
    required this.recentSeek,
    required this.videoAdvanced,
    required this.videoStalled,
    required this.audioStalled,
    required this.width,
    required this.height,
    required this.hwdecCurrent,
    required this.sourceFps,
    required this.estimatedFps,
    required this.cacheDuration,
    required this.decoderDroppedFrames,
    required this.outputDroppedFrames,
    required this.totalDroppedFrames,
  });

  final DateTime sampledAt;
  final bool playing;
  final bool buffering;
  final bool recentSeek;
  final bool videoAdvanced;
  final bool videoStalled;
  final bool audioStalled;
  final int? width;
  final int? height;
  final String? hwdecCurrent;
  final double? sourceFps;
  final double? estimatedFps;
  final double? cacheDuration;
  final int? decoderDroppedFrames;
  final int? outputDroppedFrames;
  final int? totalDroppedFrames;
}

/** 一次协调结果；只有 [changed] 为 true 时才需要改写后端滤镜链。 */
class PlayerAdaptiveQualityDecision {
  const PlayerAdaptiveQualityDecision({
    required this.level,
    required this.profile,
    required this.reason,
    required this.changed,
  });

  final PlayerAdaptiveQualityLevel level;
  final PlayerQualityBaselineProfile profile;
  final String reason;
  final bool changed;
}

/**
 * 按连续健康样本、滞回和冷却时间协调第二阶段观感增强。
 *
 * 升级必须连续健康 8 个样本且距离上次切换至少 10 秒；播放器当前每两秒提供一个
 * 扩展样本。新增掉帧、停滞、缓冲或明显 FPS 余量不足时立即降级。协调器只做纯状态
 * 判断，不访问 UI 或播放器后端。
 */
class PlayerAdaptiveQualityCoordinator {
  PlayerAdaptiveQualityCoordinator({
    this.healthySamplesToUpgrade = 8,
    this.upgradeCooldown = const Duration(seconds: 10),
  });

  /** 升一级前需要的连续健康样本数。 */
  final int healthySamplesToUpgrade;

  /** 两次升级之间的最短间隔，避免频繁重建滤镜链。 */
  final Duration upgradeCooldown;

  PlayerAdaptiveQualityLevel _level = PlayerAdaptiveQualityLevel.off;
  int _healthySamples = 0;
  DateTime? _lastLevelChangeAt;
  int? _previousDecoderDrops;
  int? _previousOutputDrops;
  int? _previousTotalDrops;
  /** 清晰增强只在新媒体或用户刚切换档位后的首个稳定样本快速请求最高安全档。 */
  bool _clarityBoostPending = true;
  String _reason = '等待稳定播放样本';
  PlayerQualityBaselineProfile _profile = PlayerQualityBaselineProfile.resolve(
    width: null,
    height: null,
    hwdecCurrent: null,
  );

  PlayerAdaptiveQualityLevel get level => _level;
  int get healthySamples => _healthySamples;
  String get reason => _reason;
  PlayerQualityBaselineProfile get profile => _profile;

  /** 打开新媒体前恢复关闭态，禁止沿用上一条视频的余量结论。 */
  void reset() {
    _level = PlayerAdaptiveQualityLevel.off;
    _healthySamples = 0;
    _lastLevelChangeAt = null;
    _previousDecoderDrops = null;
    _previousOutputDrops = null;
    _previousTotalDrops = null;
    _clarityBoostPending = true;
    _reason = '等待稳定播放样本';
    _profile = PlayerQualityBaselineProfile.resolve(
      width: null,
      height: null,
      hwdecCurrent: null,
    );
  }

  /**
   * 评估一次实时样本并返回是否需要切换滤镜档位。
   *
   * [preferClarity] 只让首个无压力样本直接请求当前基线最高档；一旦出现压力，
   * 后续恢复仍使用原有连续健康样本与冷却规则，避免清晰档在降级后反复抖动。
   */
  PlayerAdaptiveQualityDecision evaluate(
    PlayerAdaptiveQualitySample sample, {
    bool preferClarity = false,
  }) {
    _profile = PlayerQualityBaselineProfile.resolve(
      width: sample.width,
      height: sample.height,
      hwdecCurrent: sample.hwdecCurrent,
    );
    final decoderDelta = _counterDelta(
      sample.decoderDroppedFrames,
      _previousDecoderDrops,
    );
    final outputDelta = _counterDelta(
      sample.outputDroppedFrames,
      _previousOutputDrops,
    );
    final totalDelta = _counterDelta(
      sample.totalDroppedFrames,
      _previousTotalDrops,
    );
    _previousDecoderDrops = sample.decoderDroppedFrames;
    _previousOutputDrops = sample.outputDroppedFrames;
    _previousTotalDrops = sample.totalDroppedFrames;

    if (!sample.playing || sample.recentSeek) {
      _healthySamples = 0;
      _reason = sample.recentSeek ? 'seek 后等待播放重新稳定' : '暂停时保持当前档位';
      return _decision(changed: false);
    }

    final fpsRatio = sample.sourceFps == null ||
            sample.sourceFps! <= 0 ||
            sample.estimatedFps == null
        ? null
        : sample.estimatedFps! / sample.sourceFps!;
    final severePressure = sample.buffering ||
        sample.videoStalled ||
        sample.audioStalled ||
        decoderDelta > 0 ||
        outputDelta > 0 ||
        totalDelta > 0 ||
        (fpsRatio != null && fpsRatio < 0.92);
    final moderatePressure = !sample.videoAdvanced ||
        (sample.cacheDuration != null && sample.cacheDuration! < 3) ||
        (fpsRatio != null && fpsRatio < 0.97);

    if (severePressure) {
      _healthySamples = 0;
      _clarityBoostPending = false;
      _reason = '检测到掉帧、缓冲、停滞或 FPS 余量不足，立即关闭增强';
      return _setLevel(
        PlayerAdaptiveQualityLevel.off,
        sample.sampledAt,
      );
    }
    if (moderatePressure) {
      _healthySamples = 0;
      _clarityBoostPending = false;
      _reason = '实时余量偏低，降低一级以保护流畅度';
      return _setLevel(_previousLevel(_level), sample.sampledAt);
    }
    if (_level.index > _profile.maximumLevel.index) {
      _healthySamples = 0;
      _reason = '当前媒体超过基线档位上限，回落到安全级别';
      return _setLevel(_profile.maximumLevel, sample.sampledAt);
    }
    if (preferClarity && _clarityBoostPending) {
      _healthySamples = 0;
      if (_profile.maximumLevel == PlayerAdaptiveQualityLevel.off) {
        // 首帧尚未拿到分辨率时保留一次快速请求机会，避免清晰档退化为慢速自动升级。
        _reason = '${_profile.label} 没有可用增强余量';
        return PlayerAdaptiveQualityDecision(
          level: _level,
          profile: _profile,
          reason: _reason,
          changed: false,
        );
      }
      _clarityBoostPending = false;
      _reason = '清晰增强已请求当前基线最高安全档';
      return _setLevel(_profile.maximumLevel, sample.sampledAt);
    }
    if (_level == _profile.maximumLevel) {
      _healthySamples = 0;
      _reason = '${_profile.label} 已达到安全上限';
      return _decision(changed: false);
    }

    _healthySamples++;
    final cooldownComplete = _lastLevelChangeAt == null ||
        sample.sampledAt.difference(_lastLevelChangeAt!) >= upgradeCooldown;
    if (_healthySamples >= healthySamplesToUpgrade && cooldownComplete) {
      _healthySamples = 0;
      _reason = '连续健康样本确认存在余量，提升一级';
      return _setLevel(_nextLevel(_level), sample.sampledAt);
    }
    _reason = '连续健康样本 $_healthySamples / $healthySamplesToUpgrade';
    return _decision(changed: false);
  }

  PlayerAdaptiveQualityDecision _setLevel(
    PlayerAdaptiveQualityLevel next,
    DateTime changedAt,
  ) {
    final bounded =
        next.index > _profile.maximumLevel.index ? _profile.maximumLevel : next;
    if (bounded == _level) {
      return _decision(changed: false);
    }
    _level = bounded;
    _lastLevelChangeAt = changedAt;
    return _decision(changed: true);
  }

  PlayerAdaptiveQualityDecision _decision({required bool changed}) =>
      PlayerAdaptiveQualityDecision(
        level: _level,
        profile: _profile,
        reason: _reason,
        changed: changed,
      );

  static int _counterDelta(int? current, int? previous) {
    if (current == null || previous == null || current < previous) return 0;
    return current - previous;
  }

  static PlayerAdaptiveQualityLevel _nextLevel(
    PlayerAdaptiveQualityLevel level,
  ) =>
      PlayerAdaptiveQualityLevel.values[(level.index + 1).clamp(
        0,
        PlayerAdaptiveQualityLevel.values.length - 1,
      )];

  static PlayerAdaptiveQualityLevel _previousLevel(
    PlayerAdaptiveQualityLevel level,
  ) =>
      PlayerAdaptiveQualityLevel.values[(level.index - 1).clamp(
        0,
        PlayerAdaptiveQualityLevel.values.length - 1,
      )];
}

/**
 * 串行应用压缩增强或 NVIDIA D3D11 滤镜，避免两个所有者互相覆盖 `vf`。
 *
 * 隔离验证证明 D3D11 纹理直接进入 CPU `lavfi` 时，mpv 会停用其中一条滤镜；
 * 因此 NVIDIA 路径必须独占 `vf`，并同步关闭压缩增强的 GPU 去色带。
 */
class PlayerAdaptiveQualityEnhancer {
  const PlayerAdaptiveQualityEnhancer._();

  static final Expando<Future<void>> _applyTails =
      Expando<Future<void>>('player-adaptive-quality-tail');

  /** 官方 FFmpeg 滤镜使用保守参数，锐化只处理亮度且不增强色度噪点。 */
  static const _filters = <PlayerAdaptiveQualityLevel, List<String>>{
    PlayerAdaptiveQualityLevel.off: <String>[],
    PlayerAdaptiveQualityLevel.deblock: <String>[
      'deblock=filter=weak:block=8:alpha=0.06:beta=0.03:gamma=0.03:delta=0.03'
    ],
    PlayerAdaptiveQualityLevel.deblockDenoise: <String>[
      'deblock=filter=weak:block=8:alpha=0.06:beta=0.03:gamma=0.03:delta=0.03',
      // hqdn3d 后两项是时间域亮度/色度强度，当前“降噪”已包含保守时域降噪。
      'hqdn3d=1.2:0.9:1.8:1.35',
    ],
    PlayerAdaptiveQualityLevel.deblockDenoiseSharpen: <String>[
      'deblock=filter=weak:block=8:alpha=0.06:beta=0.03:gamma=0.03:delta=0.03',
      'hqdn3d=1.2:0.9:1.8:1.35',
      'unsharp=5:5:0.35:5:5:0.0',
    ],
  };

  /**
   * GPU 去色带使用低于 mpv 默认值的保守参数。
   *
   * 单次迭代与较低阈值优先减轻低码率渐变断层，较少颗粒只用于掩盖残余量化带，
   * 避免把正常纹理抹平；是否启用与实际增强档位一起接受性能回滚。
   */
  static const conservativeDebandProperties = <String, String>{
    'deband-iterations': '1',
    'deband-threshold': '24',
    'deband-range': '12',
    'deband-grain': '8',
  };

  /**
   * 把自动档位与 SDR 暗部增强合成为一条原子 `vf` 快照。
   *
   * 暗部增强使用轻量 gamma 曲线并降低高光权重，同时以小幅负 brightness 抵消
   * Limited Range 黑位抬升。固定 SDR 样本验证 YMIN 保持 16，是否为已确认 SDR
   * 由播放器能力检测层决定。
   */
  static String filterGraph({
    required PlayerAdaptiveQualityLevel level,
    required bool darkSceneEnhancementEnabled,
    bool nvidiaVideoEnhancementEnabled = false,
  }) {
    if (nvidiaVideoEnhancementEnabled) {
      return PlayerNvidiaVideoEnhancementExperiment.filterGraph;
    }
    final filters = <String>[
      ..._filters[level]!,
      if (darkSceneEnhancementEnabled)
        'eq=gamma=1.06:gamma_weight=0.82:brightness=-0.006',
    ];
    return filters.isEmpty ? '' : 'lavfi=[${filters.join(',')}]';
  }

  /** 同一后端上的 open 重放和动态切换按调用顺序串行执行。 */
  static Future<void> apply({
    required PlayerRuntimeAccess backend,
    required PlayerAdaptiveQualityLevel level,
    bool darkSceneEnhancementEnabled = false,
    bool nvidiaVideoEnhancementEnabled = false,
  }) {
    final previous = _applyTails[backend] ?? Future<void>.value();
    final operation = previous.then((_) async {
      /** 单个旧后端不支持 GPU 去色带属性时仍继续应用其余画质设置。 */
      Future<void> setPropertySafely(String property, String value) async {
        try {
          await backend.setProperty(property, value);
        } catch (_) {
          // 可选滤镜不可用时不得阻止播放；诊断读取最终属性供用户确认。
        }
      }

      final debandEnabled = !nvidiaVideoEnhancementEnabled &&
          level != PlayerAdaptiveQualityLevel.off;
      if (!debandEnabled) {
        // 回滚先关闭 GPU 去色带，再清理 CPU 滤镜，尽快释放额外渲染开销。
        await setPropertySafely('deband', 'no');
      } else {
        for (final entry in conservativeDebandProperties.entries) {
          await setPropertySafely(entry.key, entry.value);
        }
      }
      // 当前产品没有其它视频滤镜；设置完整 `vf` 快照可确定地清除上一档。
      await setPropertySafely(
        'vf',
        filterGraph(
          level: level,
          darkSceneEnhancementEnabled: darkSceneEnhancementEnabled,
          nvidiaVideoEnhancementEnabled: nvidiaVideoEnhancementEnabled,
        ),
      );
      if (debandEnabled) {
        // 参数完整写入后再启用，避免用户切换时短暂运行半套去色带配置。
        await setPropertySafely('deband', 'yes');
      }
    });
    _applyTails[backend] = operation;
    return operation;
  }
}

/** 面向设置和诊断的自动增强档位名称。 */
String playerAdaptiveQualityLevelLabel(PlayerAdaptiveQualityLevel level) =>
    switch (level) {
      PlayerAdaptiveQualityLevel.off => '关闭',
      PlayerAdaptiveQualityLevel.deblock => '去块',
      PlayerAdaptiveQualityLevel.deblockDenoise => '去块 + 时空降噪',
      PlayerAdaptiveQualityLevel.deblockDenoiseSharpen => '去块 + 时空降噪 + 锐化',
    };
