#ifndef SourceDir
  #error SourceDir was not provided.
#endif
#ifndef OutputDir
  #error OutputDir was not provided.
#endif
#ifndef AppVersion
  #define AppVersion "6.2.8"
#endif
#ifndef BuildNumber
  #define BuildNumber "13"
#endif

[Setup]
AppId={{4E7B9FD2-221F-4E3A-8B20-6C024613B106}}
AppName=THQ Business
AppVersion={#AppVersion}
AppVerName=THQ Business {#AppVersion} (Build {#BuildNumber})
AppPublisher=THQ
DefaultDirName={autopf}\THQ ERP\Business
DefaultGroupName=THQ ERP
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=THQ-Business-v6.2.8-build13-windows-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\thq_business.exe
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoCompany=THQ
VersionInfoDescription=THQ Business Installer
VersionInfoProductName=THQ Business
#ifdef EnableSigning
SignTool=thq
SignedUninstaller=yes
#endif

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef VcRedistPath
Source: "{#VcRedistPath}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafterinstall
#endif

[Icons]
Name: "{group}\THQ Business"; Filename: "{app}\thq_business.exe"
Name: "{autodesktop}\THQ Business"; Filename: "{app}\thq_business.exe"; Tasks: desktopicon

[Run]
#ifdef VcRedistPath
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Flags: waituntilterminated
#endif
Filename: "{app}\thq_business.exe"; Description: "Launch THQ Business"; Flags: nowait postinstall skipifsilent
