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
 * 产品设置选择 `windowsLibmpv` 时使用已通过 NVIDIA A/B 的 child HWND 路径；
 * 关闭硬解或运行在其它平台时回退 MediaKit，避免原生后端静默覆盖用户的软解
 * 选择。`automatic` 仍保持当前稳定默认，直到跨 DPI 与长期生命周期门禁完成。
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
  if (rendererPreference == PlayerRendererPreference.windowsLibmpv &&
      hardwareDecodingEnabled) {
    return PlayerBackendSelection.windowsNativeHwnd;
  }
  return PlayerBackendSelection.mediaKit;
}
