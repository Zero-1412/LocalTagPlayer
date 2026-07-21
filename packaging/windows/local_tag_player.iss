; Local Tag Player 的 Windows x64 安装器定义。
;
; 安装器只管理应用程序文件和快捷方式，不删除位于用户配置目录中的
; 媒体库数据库、标签、收藏或播放记录。

#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif

#ifndef MySourceDir
  #define MySourceDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef MyOutputDir
  #define MyOutputDir "..\..\artifacts"
#endif

#define MyAppName "Local Tag Player"
#define MyAppExeName "local_tag_player.exe"

[Setup]
AppId={{EDE34760-080D-4F09-8743-C5D72029DB8C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Local Tag Player
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#MyOutputDir}
OutputBaseFilename=LocalTagPlayer-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=no
ChangesEnvironment=no

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式："; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
