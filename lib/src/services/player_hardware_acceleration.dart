part of '../app.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 把用户可理解的解码档位映射为当前平台实际交给 mpv 的硬解请求。
 */
class PlayerHardwareAcceleration {
  const PlayerHardwareAcceleration._();

  /**
   * Windows 的 `auto-safe` 可能退回软件解码；推荐档改用带内存拷贝的自动硬解，
   * 牺牲少量复制开销换取比零拷贝更稳定的设备兼容性。
   */
  static String resolve(String configured) {
    if (Platform.isWindows && configured == 'auto-safe') {
      return 'auto-copy';
    }
    return configured;
  }
}
