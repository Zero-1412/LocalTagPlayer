// ignore_for_file: slash_for_doc_comments

/**
 * 应用更新专用的 HTTP 代理设置。
 *
 * 该设置只提供给更新服务的独立网络客户端，不影响媒体播放、媒体扫描、FFmpeg 或系统代理。
 * 为避免把敏感信息写入设置文件，不接受带账号密码的代理地址。
 */
class AppUpdateProxySettings {
  const AppUpdateProxySettings({
    required this.enabled,
    required this.address,
  });

  /** 旧版本没有配置文件时保持直连。 */
  static const defaults = AppUpdateProxySettings(
    enabled: false,
    address: '',
  );

  /** 是否让应用更新检查与安装包下载经过代理。 */
  final bool enabled;

  /** 用户输入的代理地址；保存时会规范化为 `host:port`。 */
  final String address;

  AppUpdateProxySettings copyWith({bool? enabled, String? address}) =>
      AppUpdateProxySettings(
        enabled: enabled ?? this.enabled,
        address: address ?? this.address,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'address': address,
      };

  /** 损坏或旧格式配置安全回退直连，且不把无效文本或凭据带入运行时。 */
  static AppUpdateProxySettings fromJson(Map<String, Object?> json) {
    final rawAddress = json['address'];
    final address = rawAddress is String
        ? normalizeAppUpdateProxyAddress(rawAddress) ?? ''
        : '';
    final requestedEnabled = json['enabled'] == true;
    return AppUpdateProxySettings(
      enabled: requestedEnabled && address.isNotEmpty,
      address: address,
    );
  }

  /** 保存前规范化地址；启用状态下的无效地址显式失败，不静默回退直连。 */
  AppUpdateProxySettings normalized() {
    final trimmed = address.trim();
    if (!enabled) {
      // 关闭时保留合法地址便于下次启用，但无效文本（尤其是凭据）绝不落盘。
      return AppUpdateProxySettings(
        enabled: false,
        address: normalizeAppUpdateProxyAddress(trimmed) ?? '',
      );
    }
    final normalized = normalizeAppUpdateProxyAddress(trimmed);
    if (normalized == null) {
      throw const FormatException('请输入有效的 HTTP 代理地址，例如 127.0.0.1:7890');
    }
    return AppUpdateProxySettings(enabled: true, address: normalized);
  }
}

/** 更新设置页依赖的最小代理读写边界。 */
abstract interface class AppUpdateProxySettingsService {
  /** 读取当前代理设置；缺失或损坏时返回安全的直连默认值。 */
  Future<AppUpdateProxySettings> loadProxySettings();

  /** 持久化设置，并让后续更新请求立即采用新配置。 */
  Future<void> saveProxySettings(AppUpdateProxySettings settings);
}

/**
 * 把用户输入规范化为 Dart `HttpClient` 代理指令使用的 `host:port`。
 *
 * 允许省略 `http://`，但必须显式提供端口；账号密码、路径、查询和片段均被拒绝。
 */
String? normalizeAppUpdateProxyAddress(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final hasScheme = trimmed.contains('://');
  final uri = Uri.tryParse(hasScheme ? trimmed : 'http://$trimmed');
  if (uri == null ||
      uri.scheme.toLowerCase() != 'http' ||
      uri.host.isEmpty ||
      !uri.hasPort ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri.authority;
}

/** 更新客户端的单一代理决策函数，便于覆盖 API 与下载重定向的回归测试。 */
String appUpdateProxyDirective(
  AppUpdateProxySettings settings,
  Uri requestUri,
) {
  final address = settings.enabled
      ? normalizeAppUpdateProxyAddress(settings.address)
      : null;
  return address == null ? 'DIRECT' : 'PROXY $address';
}
