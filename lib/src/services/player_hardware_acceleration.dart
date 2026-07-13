part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 把用户可理解的解码档位映射为当前平台实际交给 mpv 的硬解请求。
 */
class PlayerHardwareAcceleration {
  const PlayerHardwareAcceleration._();

  /**
   * Windows 的 `auto-safe` 可能退回软件解码，`auto-copy` 还会枚举 CUDA 等候选后端；
   * 推荐档固定使用已经过真实样本验证的 D3D11VA 拷贝模式，减少无关驱动初始化。
   */
  static String resolve(String configured) {
    if (Platform.isWindows && configured == 'auto-safe') {
      return 'd3d11va-copy';
    }
    return configured;
  }
}
