; The Windows installer as one setup exe, Burnout3_Takedown_Installer-setup-x86_64.exe.
; Per user, no administrator rights, no questions but one: run it and the installer
; window opens. After Xerenge's windows-setup.iss in what it asks for (almost nothing)
; and what it needs (nothing system-wide); unlike that one it installs the installer
; app (a Start menu entry, an optional desktop icon, an uninstaller), so that running
; it again for an update or a retry is one click.
;
; It installs only the installer app: the window, its Qt libraries, the payload (a
; source snapshot, the toolkit) and the licences. The game the app builds from the
; player's disc, and its data and saves, live elsewhere (the folder chosen in the app,
; by default %LOCALAPPDATA%\Burnout3) and are not touched by this setup or by
; its uninstaller.
;
;   ISCC.exe /DPackage=<package dir> /DVersion=<x.y.z> /O<out dir> windows-setup.iss
; <package dir> is the one make-windows-cross.sh makes (it holds installer.ico); see
; make-windows-setup.ps1, which also fetches ISCC (portable, pinned).

#ifndef Package
  #error Package (the folder with burnout3-installer.exe, payload\ and installer.ico) is required
#endif
#ifndef Version
  #define Version "0.0.0"
#endif

[Setup]
AppId={{6F0E7A4B-5C1D-4E6B-9B52-3B1B0C0D2A71}
AppName=Burnout 3: Takedown installer
AppVersion={#Version}
AppPublisher=burnout3-recomp
; Per user: nothing asks for administrator rights and nothing is written outside the
; user's own profile.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Burnout 3 Takedown Installer
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/max
SolidCompression=yes
OutputBaseFilename=Burnout3_Takedown_Installer-setup-x86_64
SetupIconFile={#Package}\installer.ico
UninstallDisplayIcon={app}\burnout3-installer.exe
UninstallDisplayName=Burnout 3: Takedown installer
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; Flags: unchecked

[Files]
Source: "{#Package}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{userprograms}\Burnout 3 Takedown Installer"; Filename: "{app}\burnout3-installer.exe"
Name: "{userdesktop}\Burnout 3 Takedown Installer"; Filename: "{app}\burnout3-installer.exe"; Tasks: desktopicon

[Run]
; The window opens when setup is done (not in a silent run).
Filename: "{app}\burnout3-installer.exe"; WorkingDir: "{app}"; Flags: nowait skipifsilent

[Code]
// The uninstaller removes the installer app only; say so, and where the rest is.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usDone) and not UninstallSilent then
    MsgBox('The installer app was removed.' + #13#10#13#10 +
           'The game you built with it, and its data and saves, are not part of this app and were not removed. ' +
           'They are in the folder you chose in the installer (by default ' +
           ExpandConstant('{localappdata}') + '\Burnout3). Delete that folder yourself to remove the game.',
           mbInformation, MB_OK);
end;
