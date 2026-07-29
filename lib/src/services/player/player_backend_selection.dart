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
 * 全部历史渲染器偏好统一使用 media_kit_video 已验证的 Flutter Texture 生命周期，
 * 并通过同一 NativePlayer 提交可验证的高级 libmpv 属性。
 * 自研 Texture 与 child HWND 只允许 Windows 显式 QA 覆盖，用来继续研究原生
 * D3D11/NVIDIA 能力，不能再成为普通界面默认值。是否开启硬解只改变 media_kit
 * 的解码配置，不再替换播放器生命周期。
 */
PlayerBackendSelection resolvePlayerBackendSelection({
  required bool isWindows,
  required bool hardwareDecodingEnabled,
  required PlayerRendererPreference rendererPreference,
  String? environmentOverride,
}) {
  if (isWindows) {
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
  }
  return PlayerBackendSelection.mediaKit;
}
