#ifndef MyAppVersion
  #define MyAppVersion "1.0.1"
#endif

#define MyAppName "FlowTV"
#define MyAppExeName "FlowTV.exe"

[Setup]
AppId={{B1C8D6B0-2F31-4D3D-8A8C-202610150001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=FlowTV
DefaultDirName={autopf}\FlowTV
DefaultGroupName=FlowTV
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
SetupIconFile=FlowTV.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\dist
OutputBaseFilename=FlowTV-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
Uninstallable=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FlowTV\FlowTV"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\FlowTV"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch FlowTV"; Flags: postinstall nowait skipifsilent
