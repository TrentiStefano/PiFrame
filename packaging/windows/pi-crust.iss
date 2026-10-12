#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{A9C50DD7-27AF-44C0-A1A4-9C132A354C4A}
AppName=Pi-Crust
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Pi-Crust
DefaultGroupName=Pi-Crust
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\pi_crust.exe
OutputDir={#OutputDir}
OutputBaseFilename=Pi-Crust-Setup-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Pi-Crust"; Filename: "{app}\pi_crust.exe"
Name: "{autodesktop}\Pi-Crust"; Filename: "{app}\pi_crust.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pi_crust.exe"; Description: "Launch Pi-Crust"; Flags: postinstall nowait skipifsilent
