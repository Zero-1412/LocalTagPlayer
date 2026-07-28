import '../../core/playback_settings.dart';

// ignore_for_file: slash_for_doc_comments

/**
 * 组合根允许创建的播放器后端类型。
 *
 * 页面只传递 [PlayerRendererPreference]，不能取得或据此构造具体后端。
 */
enum PlayerBackendSelection {
  mediaKit,
  windowsNativeMpv,
  windowsNativeHwnd,
  windowsNativeStub,
}

/**
 * 把平台、用户偏好和显式 QA 覆盖解析为唯一后端。
 *
 * [environmentOverride] 只接受仓库已有的三个 QA 值，并且仅在 Windows 生效。
 * Windows 的 `automatic` 与显式 `windowsLibmpv` 默认使用 Flutter Texture
 * 容器合成，确保播放列表、控制条和弹层与视频处于同一 Flutter 层级。child HWND
 * 只允许显式 QA 覆盖，用来继续研究 NVIDIA 原生增强，不能再成为普通界面默认值。
 * 显式 `mediaKit`、关闭硬解或其它平台仍回退 MediaKit。
 */
PlayerBackendSelection resolvePlayerBackendSelection({
  required bool isWindows,
  required bool hardwareDecodingEnabled,
  required PlayerRendererPreference rendererPreference,
  String? environmentOverride,
}) {
  if (!isWindows) {
    return PlayerBackendSelection.mediaKit;
  }
  final normalizedOverride = environmentOverride?.trim();
  if (normalizedOverride == 'windows-native-mpv') {
    return PlayerBackendSelection.windowsNativeMpv;
  }
  if (normalizedOverride == 'windows-native-hwnd') {
    return PlayerBackendSelection.windowsNativeHwnd;
  }
  if (normalizedOverride == 'windows-native-stub') {
    return PlayerBackendSelection.windowsNativeStub;
  }
  if (hardwareDecodingEnabled &&
      rendererPreference != PlayerRendererPreference.mediaKit) {
    return PlayerBackendSelection.windowsNativeMpv;
  }
  return PlayerBackendSelection.mediaKit;
}
