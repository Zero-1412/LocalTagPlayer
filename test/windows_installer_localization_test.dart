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
}
