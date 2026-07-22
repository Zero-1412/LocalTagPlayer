import '../../platform/platform_interfaces.dart';
import '../../core/playback_settings.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 在现有 libmpv GPU 渲染管线内切换实时画质超分配置。
 *
 * 该能力不在 Flutter UI isolate 运行图像模型，也不改变解码器、播放队列或媒体
 * 缓存。`scaler-resizes-only` 保证源画面没有被放大时不执行高质量亮度缩放；关闭
 * 后恢复项目原有的 Lanczos 基线，避免历史设置残留到后续媒体。
 */
class PlayerVideoSuperResolution {
  const PlayerVideoSuperResolution._();

  /** 按后端隔离的属性应用队尾，避免媒体 open 与用户点击交错写入半套配置。 */
  static final _applyTails = Expando<Future<void>>(
    'player-video-super-resolution-apply-tail',
  );

  /** 开启超分时交给 mpv GPU renderer 的固定、可回滚属性。 */
  static const enabledProperties = <String, String>{
    'scale': 'ewa_lanczossharp',
    'cscale': 'lanczos',
    'sigmoid-upscaling': 'yes',
    'scaler-resizes-only': 'yes',
  };

  /**
   * 把 [enabled] 对应的完整配置串行送入 [backend]。
   *
   * 属性数量固定且很小；串行顺序避免原生后端在媒体 open 前后交错处理半套配置。
   * 不支持某项属性的后端按 `PlayerBackend` 契约安全忽略，不能阻止视频继续播放。
   */
  static Future<void> apply({
    required PlayerBackend backend,
    required bool enabled,
    PlayerVideoScaler baseScaler = PlayerVideoScaler.lanczos,
  }) {
    final previous = _applyTails[backend] ?? Future<void>.value();
    final operation = previous.then(
      (_) => _applyProperties(
        backend: backend,
        enabled: enabled,
        baseScaler: baseScaler,
      ),
    );
    _applyTails[backend] = operation;
    return operation;
  }

  /** 按固定顺序应用单次完整属性快照；调用方负责同一后端的串行化。 */
  static Future<void> _applyProperties({
    required PlayerBackend backend,
    required bool enabled,
    required PlayerVideoScaler baseScaler,
  }) async {
    final scaler = switch (baseScaler) {
      PlayerVideoScaler.bicubic => 'bicubic',
      PlayerVideoScaler.lanczos => 'lanczos',
    };
    // 超分关闭时恢复用户选择的基线，避免设置页显示 Bicubic 而后端仍保留 Lanczos。
    final properties = enabled
        ? enabledProperties
        : <String, String>{
            'scale': scaler,
            'cscale': scaler,
            'sigmoid-upscaling': 'no',
            'scaler-resizes-only': 'yes',
          };
    for (final entry in properties.entries) {
      try {
        await backend.setProperty(entry.key, entry.value);
      } catch (_) {
        // 某个旧版或实验后端不支持属性时继续播放，并尝试应用剩余安全配置。
      }
    }
  }
}
