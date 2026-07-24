// ignore_for_file: slash_for_doc_comments

import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../../models/app_release.dart';
import 'app_update_service.dart';

/**
 * 通过公开 GitHub Releases API 检查 Local Tag Player 正式更新。
 *
 * 请求在首帧后异步执行并设置短超时；失败由调用方静默忽略，不影响离线媒体库启动。
 */
class GitHubReleaseUpdateService implements AppUpdateService {
  GitHubReleaseUpdateService({
    HttpClient? httpClient,
    this.repository = 'Zero-1412/LocalTagPlayer',
  }) : _httpClient = httpClient ?? HttpClient();

  /** GitHub `owner/repository` 标识。 */
  final String repository;

  /** 独立网络客户端，便于测试且不与媒体探测任务共享连接状态。 */
  final HttpClient _httpClient;

  @override
  Future<AppRelease?> checkForUpdate() async {
    final package = await PackageInfo.fromPlatform();
    final request = await _httpClient
        .getUrl(
            Uri.https('api.github.com', '/repos/$repository/releases/latest'))
        .timeout(const Duration(seconds: 4));
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set('X-GitHub-Api-Version', '2022-11-28')
      ..set(HttpHeaders.userAgentHeader, 'LocalTagPlayer/${package.version}');
    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final payload = jsonDecode(await utf8.decoder.bind(response).join());
    if (payload is! Map<String, dynamic> ||
        payload['draft'] == true ||
        payload['prerelease'] == true) {
      return null;
    }
    final release = appReleaseFromGitHubJson(payload);
    return compareAppVersions(release.version, package.version) > 0
        ? release
        : null;
  }
}

/** 把 GitHub 响应收窄为 UI 所需字段，并优先选择 Windows 正式安装器。 */
AppRelease appReleaseFromGitHubJson(Map<String, dynamic> json) {
  final rawTag = (json['tag_name'] as String? ?? '').trim();
  final version = rawTag.replaceFirst(RegExp(r'^[vV]'), '');
  final pageUrl = Uri.parse(json['html_url'] as String);
  Uri? downloadUrl;
  final assets = json['assets'];
  if (Platform.isWindows && assets is List) {
    for (final asset in assets.whereType<Map>()) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String?;
      if (url != null &&
          name.endsWith('-windows-x64-setup.exe') &&
          name.contains(version.toLowerCase())) {
        downloadUrl = Uri.tryParse(url);
        break;
      }
    }
  }
  final rawTitle = (json['name'] as String? ?? '').trim();
  return AppRelease(
    version: version,
    title: rawTitle.isEmpty ? 'Local Tag Player $version' : rawTitle,
    notes: (json['body'] as String? ?? '').trim(),
    pageUrl: pageUrl,
    downloadUrl: downloadUrl,
  );
}
