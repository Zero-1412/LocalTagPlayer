// ignore_for_file: slash_for_doc_comments

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../domain/app_release.dart';
import '../domain/app_update_service.dart';
import 'release_asset_downloader.dart';

/**
 * 通过公开 GitHub Releases API 检查 Local Tag Player 正式更新。
 *
 * 请求在首帧后异步执行并设置短超时；失败由调用方静默忽略，不影响离线媒体库启动。
 */
class GitHubReleaseUpdateService implements AppUpdateService {
  GitHubReleaseUpdateService({
    HttpClient? httpClient,
    this.repository = 'Zero-1412/LocalTagPlayer',
    Future<void> Function(String path)? launchInstaller,
    Directory? updateDirectory,
  })  : _httpClient = httpClient ?? HttpClient(),
        _launchInstaller = launchInstaller ?? _launchWindowsInstaller,
        _updateDirectory = updateDirectory {
    _assetDownloader = ReleaseAssetDownloader(httpClient: _httpClient);
  }

  /** GitHub `owner/repository` 标识。 */
  final String repository;

  /** 独立网络客户端，便于测试且不与媒体探测任务共享连接状态。 */
  final HttpClient _httpClient;

  /** 正式安装包下载器；Range 不可用时自动保留单流兼容路径。 */
  late final ReleaseAssetDownloader _assetDownloader;

  /** 已通过摘要校验的安装器启动器；测试可替换但生产默认走分离进程。 */
  final Future<void> Function(String path) _launchInstaller;

  /** 测试可替换的下载目录；生产始终使用系统临时更新目录。 */
  final Directory? _updateDirectory;

  @override
  Future<AppVersionInfo> currentVersion() async {
    final package = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      appName:
          package.appName.trim().isEmpty ? 'Local Tag Player' : package.appName,
      version: package.version,
      buildNumber: package.buildNumber,
    );
  }

  @override
  Future<AppRelease?> checkForUpdate() async {
    final package = await currentVersion();
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

  @override
  Future<void> downloadAndLaunch(
    AppRelease release, {
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前平台暂不支持应用内启动安装器');
    }
    final url = release.downloadUrl;
    final name = release.downloadName;
    final expectedSha256 = release.downloadSha256?.toLowerCase();
    if (url == null ||
        name == null ||
        p.basename(name) != name ||
        expectedSha256 == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      throw const FormatException('发布资产缺少可验证的 Windows 安装包');
    }

    final updateDirectory = _updateDirectory ??
        Directory(
          p.join(Directory.systemTemp.path, 'LocalTagPlayer', 'updates'),
        );
    await updateDirectory.create(recursive: true);
    final completedFile = File(p.join(updateDirectory.path, name));
    final partialFile = File('${completedFile.path}.part');
    if (await completedFile.exists()) {
      if (await installerSha256Matches(completedFile, expectedSha256)) {
        // 用户重复点击或安装器首次启动失败时复用已经校验的版本文件，避免再次下载。
        await _launchInstaller(completedFile.path);
        return;
      }
      await completedFile.delete();
    }
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    try {
      await _assetDownloader.download(
        url: url,
        partialFile: partialFile,
        userAgent: 'LocalTagPlayer/${release.version}',
        onProgress: onProgress,
      );
      if (!await installerSha256Matches(partialFile, expectedSha256)) {
        throw const FormatException('安装包 SHA-256 校验失败');
      }
      if (await completedFile.exists()) {
        await completedFile.delete();
      }
      await partialFile.rename(completedFile.path);

      // 只启动已经通过 GitHub 资产摘要校验的安装器；安装交互仍由用户确认。
      await _launchInstaller(completedFile.path);
    } catch (_) {
      // 失败的分片永远不能在后续会话中被误认为可执行的完整安装包。
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      rethrow;
    }
  }
}

/**
 * 流式计算下载文件的 SHA-256，避免把百兆安装包整体载入内存。
 *
 * 该纯文件校验入口也作为下载与执行之间的确定性安全合同测试点。
 */
Future<bool> installerSha256Matches(File file, String expectedSha256) async {
  final actualSha256 = (await sha256.bind(file.openRead()).first).toString();
  return actualSha256 == expectedSha256.toLowerCase();
}

/** Windows 生产路径只启动交互式安装器，不传递静默安装或提权参数。 */
Future<void> _launchWindowsInstaller(String path) async {
  await Process.start(
    path,
    const <String>[],
    mode: ProcessStartMode.detached,
  );
}

/** 把 GitHub 响应收窄为 UI 所需字段，并优先选择 Windows 正式安装器。 */
AppRelease appReleaseFromGitHubJson(Map<String, dynamic> json) {
  final rawTag = (json['tag_name'] as String? ?? '').trim();
  final version = rawTag.replaceFirst(RegExp(r'^[vV]'), '');
  final pageUrl = Uri.parse(json['html_url'] as String);
  Uri? downloadUrl;
  String? downloadName;
  String? downloadSha256;
  final assets = json['assets'];
  if (Platform.isWindows && assets is List) {
    for (final asset in assets.whereType<Map>()) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String?;
      if (url != null &&
          name.endsWith('-windows-x64-setup.exe') &&
          name.contains(version.toLowerCase())) {
        downloadUrl = Uri.tryParse(url);
        final rawDigest = (asset['digest'] as String? ?? '').trim();
        final digestMatch =
            RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(rawDigest);
        downloadName = asset['name'] as String?;
        downloadSha256 = digestMatch?.group(1)?.toLowerCase();
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
    downloadName: downloadName,
    downloadSha256: downloadSha256,
  );
}
