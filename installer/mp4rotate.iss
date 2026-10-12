; mp4rotate installer - Inno Setup 5.5.9
;
; Build everything with build.cmd in the project folder (or build.cmd NOSIGN for an
; unsigned test build). This script expects the exe, shell DLL and MSIX already built.
;
; Installs for all users (Program Files, HKLM; requires admin).
;
; Context menu:
;   Windows 11  - "MP4 Rotate" (or MOV/M4V/3GP Rotate, matching the file type) submenu in the main context menu (and "Show more options")
;                 via a sparse MSIX package + mp4rotate_shell.dll. Packages are registered
;                 per user: "mp4rotate.exe --register" runs as the logged-in user at the end
;                 of setup, and Active Setup runs it for every other user at their next logon.
;   Windows 10  - classic registry verbs (Windows 10 has only the one context menu).
;                 Not used on Windows 11, where they would duplicate the package's verbs.

#define AppName      "MP4/MOV Rotate"
; Folder name for new installs (a '/' can't be used in a folder name). Upgrades keep their existing folder.
#define AppDirName   "MP4-MOV Rotate"
#define AppVersion   "1.1"
#define AppPublisher "JRN Enterprise Inc"
#define AppExe       "mp4rotate.exe"
#define PublishDir   "..\bin\Release\net9.0\win-x64\publish"
#define ShellDir     "..\shell\bin\x64\Release"
#define PackageDir   "..\package\out"
; Must match Identity Version in package\AppxManifest.xml; bump both when the menu changes.
#define PackageVersion "1.1.0.1"
#define ActiveSetupKey "Software\Microsoft\Active Setup\Installed Components\{{6A4BF151-083D-4235-AEAE-87A255FD9D63}"
#define MenuKey      "Software\Classes\SystemFileAssociations\.mp4\shell"
; Video types handled (all ISO/QuickTime family). Keep in sync with package\AppxManifest.xml.
#dim Exts[4]
#expr Exts[0] = ".mp4"
#expr Exts[1] = ".mov"
#expr Exts[2] = ".m4v"
#expr Exts[3] = ".3gp"
#define I

#ifdef NOSIGN
  #define SignFlag ""
#else
  #define SignFlag "signonce"
#endif

[Setup]
AppId={{6A4BF151-083D-4235-AEAE-87A255FD9D63}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppCopyright=Copyright (C) {#AppPublisher}
VersionInfoVersion={#AppVersion}.0.0
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
DefaultDirName={pf}\{#AppDirName}
DisableProgramGroupPage=yes
; Show the Welcome page (with the large WizardImageFile on the left); Inno 5.5.7+ hides it by default.
DisableWelcomePage=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0
ChangesAssociations=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
SetupIconFile=mp4rotate.ico
WizardImageFile=SetupModern20.bmp
WizardSmallImageFile=SetupSmall.bmp
OutputDir=Output
OutputBaseFilename=MP4Rotate-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
#ifndef NOSIGN
SignTool=AzureSign
SignedUninstaller=yes
#endif

[Files]
Source: "{#PublishDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion {#SignFlag}
; Explorer's COM surrogate (dllhost) can hold the DLL open; replace/delete on reboot if so.
Source: "{#ShellDir}\mp4rotate_shell.dll"; DestDir: "{app}"; Flags: ignoreversion restartreplace uninsrestartdelete {#SignFlag}
Source: "{#PackageDir}\mp4rotate.msix"; DestDir: "{app}"; Flags: ignoreversion {#SignFlag}

[Run]
; Windows 11 Explorer only picks up new context menu handlers when it starts.
; runasoriginaluser: Explorer must come back as the user, not elevated.
Filename: "{app}\{#AppExe}"; Parameters: "--restart-explorer"; Description: "Restart Windows Explorer now"; Flags: postinstall runasoriginaluser skipifsilent; Check: IsWin11

[Messages]
WelcomeLabel1=Welcome to the [name] Setup Wizard
WelcomeLabel2=This will install [name] as an Explorer Shell Extension.%n%nWritten by Justin Nelson with help from Claude Code for the JustinNelsonsProjects YouTube Channel.
UninstalledAll=%1 was successfully removed from your computer.%n%nThe Rotate commands disappear from the right-click menu after you restart Windows Explorer, sign out, or restart the computer.

[Registry]
; --- Windows 10: classic verbs. SystemFileAssociations applies regardless of which app
; opens each file type. MultiSelectModel=Player keeps the verbs visible for >15 selected files.
; Explorer lists verbs in key-name order, hence the 1/2/3 prefixes.
; The #sub below is emitted once per extension in Exts.
#sub VideoMenuEntries
  #define Key "Software\Classes\SystemFileAssociations\" + Exts[I] + "\shell"
Root: HKLM; Subkey: "{#Key}\mp4rotate.1left"; ValueType: string; ValueName: ""; ValueData: "Rotate left"; Flags: uninsdeletekey; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.1left"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.1left\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" left ""%1"""; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.2right"; ValueType: string; ValueName: ""; ValueData: "Rotate right"; Flags: uninsdeletekey; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.2right"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.2right\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" right ""%1"""; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.3rotate180"; ValueType: string; ValueName: ""; ValueData: "Rotate 180"; Flags: uninsdeletekey; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.3rotate180"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.3rotate180"; ValueType: string; ValueName: "SeparatorBefore"; ValueData: ""; Check: not IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.3rotate180\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" 180 ""%1"""; Check: not IsWin11
; Windows 11: no classic verbs (the package's commands already appear in both menus).
Root: HKLM; Subkey: "{#Key}\mp4rotate.1left"; ValueType: none; Flags: deletekey; Check: IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.2right"; ValueType: none; Flags: deletekey; Check: IsWin11
Root: HKLM; Subkey: "{#Key}\mp4rotate.3rotate180"; ValueType: none; Flags: deletekey; Check: IsWin11
#endsub
#for {I = 0; I < DimOf(Exts); I++} VideoMenuEntries

; Classic verb names used by earlier test builds.
Root: HKLM; Subkey: "{#MenuKey}\mp4rotate.left"; ValueType: none; Flags: deletekey
Root: HKLM; Subkey: "{#MenuKey}\mp4rotate.right"; ValueType: none; Flags: deletekey
Root: HKLM; Subkey: "{#MenuKey}\mp4rotate.1right"; ValueType: none; Flags: deletekey
Root: HKLM; Subkey: "{#MenuKey}\mp4rotate.2left"; ValueType: none; Flags: deletekey

; --- Windows 11: register the package for each other user at their next logon.
; Active Setup re-runs StubPath for a user whenever Version is higher than when it last ran,
; so it follows the package version: a changed menu reaches every user at their next logon.
Root: HKLM; Subkey: "{#ActiveSetupKey}"; ValueType: string; ValueName: ""; ValueData: "{#AppName}"; Flags: uninsdeletekey; Check: IsWin11
Root: HKLM; Subkey: "{#ActiveSetupKey}"; ValueType: string; ValueName: "StubPath"; ValueData: """{app}\{#AppExe}"" --register"; Check: IsWin11
Root: HKLM; Subkey: "{#ActiveSetupKey}"; ValueType: string; ValueName: "Version"; ValueData: "{#StringChange(PackageVersion, '.', ',')}"; Check: IsWin11
Root: HKLM; Subkey: "{#ActiveSetupKey}"; ValueType: dword; ValueName: "IsInstalled"; ValueData: 1; Check: IsWin11

[Code]
function IsWin11: Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := Version.Build >= 22000;
end;

// Runs mp4rotate.exe with a package command as the logged-in user (not the elevated
// account, which can differ if UAC asked for another admin's password). Packages are
// per user, so this is the account whose Explorer gets the menu.
function RunAsOriginalUser(const Command: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := ExecAsOriginalUser(ExpandConstant('{app}\{#AppExe}'), Command, '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // Upgrading: unregister first so Explorer releases the old shell DLL before it's replaced.
  if (CurStep = ssInstall) and IsWin11 and FileExists(ExpandConstant('{app}\{#AppExe}')) then
    RunAsOriginalUser('--unregister');

  if (CurStep = ssPostInstall) and IsWin11 then
    if not RunAsOriginalUser('--register') then
      SuppressibleMsgBox('The Explorer context menu could not be registered. ' +
        'The Rotate commands may not appear when right-clicking video files.' #13#13 +
        'Reinstalling may fix this.', mbError, MB_OK, IDOK);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and IsWin11 then
  begin
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 +
      'Windows Explorer must be restarted before the Rotate commands appear when you ' +
      'right-click a video (MP4, MOV, M4V or 3GP). Leave the box below checked to restart it now, or sign out ' +
      'and back in later.' #13#10#13#10 +
      'While Explorer restarts, your taskbar and desktop icons will disappear for a few ' +
      'seconds and any open File Explorer windows will close. This is normal - they come ' +
      'right back.';
    // The label grew, so move the checkbox below it.
    WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
    WizardForm.RunList.Top := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(12);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  // Before files are removed: take the package (and its menu commands) away from every user.
  if (CurUninstallStep = usUninstall) and IsWin11 then
    Exec(ExpandConstant('{app}\{#AppExe}'), '--unregister-all', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
