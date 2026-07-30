import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 安装器固定使用经校验的简体中文语言文件', () {
    final script =
        File('packaging/windows/local_tag_player.iss').readAsStringSync();
    final workflow =
        File('.github/workflows/release-packages.yml').readAsStringSync();

    expect(script, contains('[Languages]'));
    expect(
      script,
      contains(
        'Name: "chinesesimplified"; '
        r'MessagesFile: "compiler:Languages\ChineseSimplified.isl"',
      ),
    );
    expect(script, contains('ShowLanguageDialog=no'));
    expect(script, contains('UsePreviousLanguage=no'));
    expect(script, isNot(contains('compiler:Default.isl')));
    expect(script, contains('Description: "{cm:CreateDesktopIcon}"'));
    expect(script, contains('GroupDescription: "{cm:AdditionalIcons}"'));
    expect(script, contains('Description: "{cm:LaunchProgram,{#MyAppName}}"'));

    expect(
      workflow,
      contains(
        'jrsoftware/issrc/'
        '899f6edd3538517b12b7c039979f3b76d9eebd95/'
        'Files/Languages/ChineseSimplified.isl',
      ),
    );
    expect(
      workflow,
      contains(
        '6753BE2C5E2740D859900FD902824DB2EC568DA5C5B52486524C9762D778B0B0',
      ),
    );
  });

  test('正式发布业务门禁不会吞掉 Flutter 原生命令失败', () {
    // 先统一换行符，确保本测试在 GitHub Windows 的 CRLF 检出下仍验证同一语义。
    final workflow = File(
      '.github/workflows/release-packages.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final integrationGateStart = workflow.indexOf('integration_gate:');
    final windowsJobStart = workflow.indexOf(
      '\n  windows:',
      integrationGateStart,
    );

    expect(
      integrationGateStart,
      greaterThanOrEqualTo(0),
      reason: '必须能定位正式发布的集成门禁',
    );
    expect(
      windowsJobStart,
      greaterThan(integrationGateStart),
      reason: '必须能隔离集成门禁，避免误匹配后续构建任务',
    );

    final integrationGate =
        workflow.substring(integrationGateStart, windowsJobStart);
    const exitOnNativeFailure =
        r'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }';

    // pwsh 不会默认把所有原生命令的非零退出码提升为步骤失败，因此逐项保护。
    for (final command in <String>[
      'flutter pub get',
      'flutter test',
      'flutter analyze',
      'flutter build windows --debug',
    ]) {
      expect(
        integrationGate,
        contains('$command\n          $exitOnNativeFailure'),
        reason: '$command 失败后必须立即终止正式发布门禁',
      );
    }
  });
}
