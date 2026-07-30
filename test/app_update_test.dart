// ignore_for_file: slash_for_doc_comments

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/features/update/data/github_release_update_service.dart';
import 'package:local_tag_player/src/features/update/domain/app_release.dart';
import 'package:local_tag_player/src/features/update/domain/app_update_service.dart';
import 'package:local_tag_player/src/features/update/presentation/about_settings_page.dart';
import 'package:local_tag_player/src/features/update/presentation/app_update_prompt.dart';

class _FakeUpdateService implements AppUpdateService {
  _FakeUpdateService({
    this.release,
    this.checkError,
    bool holdDownload = false,
  }) : _downloadGate = holdDownload ? Completer<void>() : null;

  final AppRelease? release;
  final Object? checkError;
  final Completer<void>? _downloadGate;
  static const AppVersionInfo version = AppVersionInfo(
    appName: 'Local Tag Player',
    version: '0.2.1',
    buildNumber: '3',
  );
  bool launched = false;

  @override
  Future<AppVersionInfo> currentVersion() async => version;

  @override
  Future<AppRelease?> checkForUpdate() async {
    if (checkError != null) {
      throw checkError!;
    }
    return release;
  }

  @override
  Future<void> downloadAndLaunch(
    AppRelease release, {
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const AppUpdateDownloadProgress(
        receivedBytes: 50,
        totalBytes: 100,
        bytesPerSecond: 25 * 1024,
      ),
    );
    await _downloadGate?.future;
    launched = true;
  }

  /** 仅供弹窗测试在检查下载中状态后结束模拟下载。 */
  void completeDownload() {
    _downloadGate?.complete();
  }
}

AppRelease _release() => AppRelease(
      version: '0.3.0',
      title: 'Local Tag Player 0.3.0',
      notes: '新增应用内更新\n增加关于页面',
      pageUrl: Uri.parse(
        'https://github.com/Zero-1412/LocalTagPlayer/releases/tag/v0.3.0',
      ),
      downloadUrl: Uri.parse(
        'https://github.com/Zero-1412/LocalTagPlayer/releases/download/'
        'v0.3.0/LocalTagPlayer-0.3.0-windows-x64-setup.exe',
      ),
      downloadName: 'LocalTagPlayer-0.3.0-windows-x64-setup.exe',
      downloadSha256: 'a' * 64,
    );

void main() {
  test('正式版本比较按数字段判断，不把 0.10 误判为低于 0.9', () {
    expect(compareAppVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareAppVersions('v1.2.0', '1.2'), 0);
    expect(compareAppVersions('1.2.3', '2.0.0'), lessThan(0));
  });

  test('GitHub Release 资产同时保留文件名和 SHA-256', () {
    final release = appReleaseFromGitHubJson({
      'tag_name': 'v0.3.0',
      'name': 'Local Tag Player 0.3.0',
      'body': '更新',
      'html_url':
          'https://github.com/Zero-1412/LocalTagPlayer/releases/tag/v0.3.0',
      'assets': [
        {
          'name': 'LocalTagPlayer-0.3.0-windows-x64-setup.exe',
          'browser_download_url':
              'https://example.invalid/LocalTagPlayer-0.3.0-windows-x64-setup.exe',
          'digest': 'sha256:${'b' * 64}',
        },
      ],
    });

    expect(release.downloadName, 'LocalTagPlayer-0.3.0-windows-x64-setup.exe');
    expect(release.downloadSha256, 'b' * 64);
  });

  test('安装器 SHA-256 文件校验拒绝不匹配内容', () async {
    final payload = List<int>.generate(4096, (index) => index % 251);
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('ltp-update-test-');
    final installer = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}setup.exe',
    );

    try {
      await installer.writeAsBytes(payload, flush: true);
      expect(
        await installerSha256Matches(
          installer,
          sha256.convert(payload).toString(),
        ),
        isTrue,
      );
      expect(
        await installerSha256Matches(installer, '0' * 64),
        isFalse,
      );
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('下载进度按聚合速度估算剩余时间', () {
    const progress = AppUpdateDownloadProgress(
      receivedBytes: 50,
      totalBytes: 100,
      bytesPerSecond: 25,
    );

    expect(progress.fraction, 0.5);
    expect(progress.estimatedRemaining, const Duration(seconds: 2));
  });

  test(
    '已经通过摘要校验的同版本安装包直接复用',
    () async {
      final payload = List<int>.generate(4096, (index) => index % 241);
      final temporaryDirectory =
          await Directory.systemTemp.createTemp('ltp-update-reuse-test-');
      final name = 'LocalTagPlayer-0.3.0-windows-x64-setup.exe';
      final installer = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}$name',
      );
      await installer.writeAsBytes(payload, flush: true);
      String? launchedPath;
      final service = GitHubReleaseUpdateService(
        updateDirectory: temporaryDirectory,
        launchInstaller: (path) async => launchedPath = path,
      );
      final release = AppRelease(
        version: '0.3.0',
        title: 'Local Tag Player 0.3.0',
        notes: '更新',
        pageUrl: Uri.parse('https://example.invalid/release'),
        downloadUrl: Uri.parse('https://example.invalid/$name'),
        downloadName: name,
        downloadSha256: sha256.convert(payload).toString(),
      );

      try {
        await service.downloadAndLaunch(release);
        expect(launchedPath, installer.path);
      } finally {
        await temporaryDirectory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets('启动检查发现新版本后在应用内下载并启动安装器', (tester) async {
    final service = _FakeUpdateService(
      release: _release(),
      holdDownload: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePrompt(
          service: service,
          child: const Scaffold(body: Text('媒体库')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app.update.dialog')), findsOneWidget);
    expect(find.text('新增应用内更新\n增加关于页面'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app.update.download')));
    await tester.pump();

    expect(find.text('正在下载 50% · 25 KB/s · 约 1 秒'), findsOneWidget);
    service.completeDownload();
    await tester.pumpAndSettle();

    expect(service.launched, isTrue);
    expect(find.byKey(const ValueKey('app.update.dialog')), findsNothing);
  });

  testWidgets('没有新版本时不打扰媒体库', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePrompt(
          service: _FakeUpdateService(),
          child: const Scaffold(body: Text('媒体库')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.update.dialog')), findsNothing);
  });

  testWidgets('关于页展示版本并主动检查最新状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutSettingsPage(updateService: _FakeUpdateService()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('版本 0.2.1 (3)'), findsOneWidget);
    expect(find.text('Local Tag Player'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('settings.about.checkUpdate')),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前已是最新正式版本'), findsOneWidget);
  });

  testWidgets('关于页主动检查失败时提供可重试反馈', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AboutSettingsPage(
            updateService: _FakeUpdateService(
              checkError: const FormatException('网络失败'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings.about.checkUpdate')),
    );
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败，请确认网络连接后重试'), findsOneWidget);
  });
}
