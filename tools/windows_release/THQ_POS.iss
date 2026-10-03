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
AppId={{16779573-A282-46C5-A098-3419C1D8BFD6}}
AppName=THQ POS
AppVersion={#AppVersion}
AppVerName=THQ POS {#AppVersion} (Build {#BuildNumber})
AppPublisher=THQ
DefaultDirName={autopf}\THQ ERP\POS
DefaultGroupName=THQ ERP
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=THQ-POS-v6.2.8-build13-windows-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\thq_pos.exe
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoCompany=THQ
VersionInfoDescription=THQ POS Installer
VersionInfoProductName=THQ POS
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
Name: "{group}\THQ POS"; Filename: "{app}\thq_pos.exe"
Name: "{autodesktop}\THQ POS"; Filename: "{app}\thq_pos.exe"; Tasks: desktopicon

[Run]
#ifdef VcRedistPath
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Flags: waituntilterminated
#endif
Filename: "{app}\thq_pos.exe"; Description: "Launch THQ POS"; Flags: nowait postinstall skipifsilent
