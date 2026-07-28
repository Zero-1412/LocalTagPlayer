import '../../core/playback_settings.dart';
import '../../platform/platform_interfaces.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 一次显示同步插值配置的可验证结果。
 *
 * [active] 只表示后端把三个 mpv 配置完整读回为预期值；逐帧运行状态仍必须看
 * `display-sync-active`，不能由写入结果推断。[verified] 用于区分“已确认关闭”
 * 与“不支持读回但已安全回退”。
 */
class PlayerSmoothMotionApplyResult {
  const PlayerSmoothMotionApplyResult({
    required this.requestedMode,
    required this.active,
    required this.verified,
    required this.reason,
  });

  /** 本次用户请求的类型化档位。 */
  final PlayerSmoothMotionMode requestedMode;

  /** 当前媒体是否已确认接受显示同步插值配置。 */
  final bool active;

  /** 后端属性读回是否与请求完整一致。 */
  final bool verified;

  /** 不含文件路径和原生异常文本的稳定诊断原因。 */
  final String reason;
}

/**
 * 跨后端的显示同步插值协调器。
 *
 * Flutter 页面只能提交类型化意图；具体 mpv 属性通过 [PlayerRuntimeAccess] 边界
 * 写入。MediaKit、不支持属性读回的后端和 Windows 原生 libmpv 共用同一失败语义。
 */
abstract final class PlayerSmoothMotion {
  /** 应用一个流畅度档位，并在写入或读回失败时立即关闭插值。 */
  static Future<PlayerSmoothMotionApplyResult> apply({
    required PlayerRuntimeAccess backend,
    required PlayerSmoothMotionMode mode,
  }) async {
    if (mode == PlayerSmoothMotionMode.off) {
      return _disable(backend: backend, requestedMode: mode);
    }

    try {
      // 最后才打开 interpolation；支持批量边界时三项仍按插入顺序一次提交。
      await _setProperties(backend, const <String, String>{
        'video-sync': 'display-resample',
        'tscale': 'oversample',
        'interpolation': 'yes',
      });
      final videoSync = _normalize(await backend.getProperty('video-sync'));
      final temporalScaler = _normalize(await backend.getProperty('tscale'));
      final interpolation =
          _normalize(await backend.getProperty('interpolation'));
      final verified = videoSync == 'display-resample' &&
          temporalScaler == 'oversample' &&
          _isEnabled(interpolation);
      if (verified) {
        return const PlayerSmoothMotionApplyResult(
          requestedMode: PlayerSmoothMotionMode.displayInterpolation,
          active: true,
          verified: true,
          reason: '后端已确认显示同步插值配置',
        );
      }
    } catch (_) {
      // 后端能力差异统一折叠成安全回退，不向诊断或 UI 泄漏原生异常和本地路径。
    }
    await _bestEffortDisable(backend);
    return const PlayerSmoothMotionApplyResult(
      requestedMode: PlayerSmoothMotionMode.displayInterpolation,
      active: false,
      verified: false,
      reason: '后端未完整确认插值属性，当前视频已回退',
    );
  }

  /** 关闭插值并尽量读回确认；保持 display-resample 作为既有基础同步策略。 */
  static Future<PlayerSmoothMotionApplyResult> _disable({
    required PlayerRuntimeAccess backend,
    required PlayerSmoothMotionMode requestedMode,
  }) async {
    try {
      await _bestEffortDisable(backend);
      final interpolation =
          _normalize(await backend.getProperty('interpolation'));
      if (_isDisabled(interpolation)) {
        return PlayerSmoothMotionApplyResult(
          requestedMode: requestedMode,
          active: false,
          verified: true,
          reason: '显示同步插值已关闭',
        );
      }
    } catch (_) {
      // 关闭失败也不能中断媒体打开；结果明确标记为未验证。
    }
    return PlayerSmoothMotionApplyResult(
      requestedMode: requestedMode,
      active: false,
      verified: false,
      reason: '关闭请求已发送，但后端未提供可靠读回',
    );
  }

  /** 尽最大努力先关闭主开关，再恢复稳定的基础同步与默认时间缩放器。 */
  static Future<void> _bestEffortDisable(PlayerRuntimeAccess backend) async {
    try {
      await _setProperties(backend, const <String, String>{
        'interpolation': 'no',
        'tscale': 'oversample',
        'video-sync': 'display-resample',
      });
    } catch (_) {
      // 单个属性不支持时不能阻止媒体打开；普通后端由辅助方法保持逐项尽力写入。
    }
  }

  /** 支持批量边界时一次提交；普通后端保持逐项尽力写入。 */
  static Future<void> _setProperties(
    PlayerRuntimeAccess backend,
    Map<String, String> properties,
  ) async {
    final batch = backend is PlayerPropertyBatchBoundary
        ? backend as PlayerPropertyBatchBoundary
        : null;
    if (batch != null) {
      await batch.setProperties(properties);
      return;
    }
    for (final entry in properties.entries) {
      try {
        await backend.setProperty(entry.key, entry.value);
      } catch (_) {
        // 单个属性不支持时继续关闭其余属性，避免可选能力阻断媒体打开。
      }
    }
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  static bool _isEnabled(String value) =>
      value == 'yes' || value == 'true' || value == '1';

  static bool _isDisabled(String value) =>
      value == 'no' || value == 'false' || value == '0';
}
