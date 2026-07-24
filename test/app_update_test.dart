import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_tag_player/src/app.dart';

class _FakeUpdateService implements AppUpdateService {
  const _FakeUpdateService(this.release);

  final AppRelease? release;

  @override
  Future<AppRelease?> checkForUpdate() async => release;
}

void main() {
  test('正式版本比较按数字段判断，不把 0.10 误判为低于 0.9', () {
    expect(compareAppVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareAppVersions('v1.2.0', '1.2'), 0);
    expect(compareAppVersions('1.2.3', '2.0.0'), lessThan(0));
  });

  testWidgets('启动检查发现新版本后展示更新说明并打开安装包', (tester) async {
    final release = AppRelease(
      version: '0.2.0',
      title: 'Local Tag Player 0.2.0',
      notes: '新增远程更新提醒\n修复播放器稳定性',
      pageUrl: Uri.parse(
        'https://github.com/Zero-1412/LocalTagPlayer/releases/tag/v0.2.0',
      ),
      downloadUrl: Uri.parse(
        'https://github.com/Zero-1412/LocalTagPlayer/releases/download/'
        'v0.2.0/LocalTagPlayer-0.2.0-windows-x64-setup.exe',
      ),
    );
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdatePrompt(
          service: _FakeUpdateService(release),
          launchExternalUrl: (url) async {
            opened = url;
            return true;
          },
          child: const Scaffold(body: Text('媒体库')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app.update.dialog')), findsOneWidget);
    expect(find.text('新增远程更新提醒\n修复播放器稳定性'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app.update.download')));
    await tester.pumpAndSettle();

    expect(opened, release.downloadUrl);
    expect(find.byKey(const ValueKey('app.update.dialog')), findsNothing);
  });

  testWidgets('没有新版本时不打扰媒体库', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppUpdatePrompt(
          service: _FakeUpdateService(null),
          child: Scaffold(body: Text('媒体库')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.update.dialog')), findsNothing);
  });
}
