#define MyAppName "DOTnet"
#define MyAppVersion "2.5.0"
#define ExeName "IGTAPsnfDemo.exe"
#define DemoDir "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That''s Also a Platformer Demo"

[Setup]
AppId={{5E7982D5-978E-441A-954D-7D2BF0D93F61}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\DOTnet Mod
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=DOTnetSetup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
WizardStyle=modern

[Files]
Source: "..\mod\*.cs"; DestDir: "{app}\mod"; Flags: ignoreversion
Source: "build-and-install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "tools\ilspycmd\*"; DestDir: "{app}\tools\ilspycmd"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
var
  ProgressPage: TOutputProgressWizardPage;

function IsGameRunning(): Boolean;
var
  ResultCode: Integer;
  ListFile: string;
  Content: AnsiString;
begin
  Result := False;
  ListFile := ExpandConstant('{tmp}\igtap_tasklist.txt');
  Exec(ExpandConstant('{cmd}'), '/C tasklist /FI "IMAGENAME eq {#ExeName}" > "' + ListFile + '"', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if LoadStringFromFile(ListFile, Content) then
    Result := Pos(Lowercase('{#ExeName}'), Lowercase(Content)) > 0;
end;

function GetFileSize64(const FileName: string): Int64;
var
  FindRec: TFindRec;
begin
  Result := -1;
  if FindFirst(FileName, FindRec) then
  begin
    Result := FindRec.SizeHigh;
    Result := (Result shl 32) or FindRec.SizeLow;
    FindClose(FindRec);
  end;
end;

// The backup gets created as soon as an install is attempted, whether or not
// it succeeds, so its mere existence isn't proof of anything - the real
// signal is that the deployed DLL now differs from that backup (our build
// always changes the file size), meaning a patched build actually made it
// into place instead of the attempt silently failing partway through.
function CheckInstalled(): Boolean;
var
  ManagedDir, DeployedDll, BackupDll: string;
begin
  Result := False;
  ManagedDir := '{#DemoDir}' + '\IGTAPsnfDemo_Data\Managed';
  DeployedDll := ManagedDir + '\Assembly-CSharp.dll';
  BackupDll := ManagedDir + '\Assembly-CSharp.ORIGINAL.dll';
  if not (FileExists(DeployedDll) and FileExists(BackupDll)) then Exit;
  Result := GetFileSize64(DeployedDll) <> GetFileSize64(BackupDll);
end;

function IsDotnetSdkPresent(): Boolean;
var
  ResultCode: Integer;
  ListFile: string;
  Content: AnsiString;
begin
  Result := False;
  ListFile := ExpandConstant('{tmp}\dotnet_sdks_check.txt');
  if Exec(ExpandConstant('{cmd}'), '/C dotnet --list-sdks > "' + ListFile + '" 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    if (ResultCode = 0) and LoadStringFromFile(ListFile, Content) then
      Result := Length(Trim(Content)) > 0;
end;

// Runs build-and-install.ps1 without a visible console window, showing our
// own native progress page instead - the script writes its current phase to
// StatusFile, which we poll and reflect here, ending on the STATUS_DONE
// sentinel it always appends last (success or failure) so we're never stuck
// waiting on a process handle we don't have a reliable way to query directly.
procedure RunBuildScript(AllowSdkDownload: Boolean);
var
  ResultCode: Integer;
  StatusFilePath, Params, LastText: string;
  Content: AnsiString;
  Iterations: Integer;
begin
  StatusFilePath := ExpandConstant('{tmp}\dotnet_mod_status.txt');
  DeleteFile(StatusFilePath);

  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\build-and-install.ps1') +
    '" -StatusFile "' + StatusFilePath + '"';
  if not AllowSdkDownload then
    Params := Params + ' -NoSdkDownload';

  ProgressPage.SetText('Getting things ready...', '');
  ProgressPage.Show;
  try
    if not Exec('powershell.exe', Params, '', SW_HIDE, ewNoWait, ResultCode) then
    begin
      MsgBox('Could not start the setup script.', mbError, MB_OK);
      Exit;
    end;

    LastText := '';
    Iterations := 0;
    while True do
    begin
      Sleep(400);
      Iterations := Iterations + 1;
      if LoadStringFromFile(StatusFilePath, Content) then
      begin
        if Pos('STATUS_DONE', Content) > 0 then Break;
        if Content <> LastText then
        begin
          ProgressPage.SetText(Content, '');
          LastText := Content;
        end;
      end;
      // ~10 minute safety net in case something hangs with no status update at all
      if Iterations > 1500 then
      begin
        MsgBox('This is taking much longer than expected and may be stuck. Setup will continue in the background; check the result after a few minutes by opening the game.', mbInformation, MB_OK);
        Break;
      end;
    end;
  finally
    ProgressPage.Hide;
  end;
end;

procedure InitializeWizard();
begin
  ProgressPage := CreateOutputProgressPage('Installing the multiplayer mod', 'Please wait...');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  sdkPresent, allowDownload: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    if not DirExists('{#DemoDir}') then
    begin
      MsgBox('IGTAP Demo wasn''t found on this PC, so there was nothing to patch. Install it, then run this installer again.', mbError, MB_OK);
      Exit;
    end;

    sdkPresent := IsDotnetSdkPresent();
    allowDownload := sdkPresent;
    if not sdkPresent then
    begin
      if MsgBox('Building the mod needs the .NET SDK, which isn''t installed on this PC. Download a portable copy automatically? (About 200 MB, one-time - it''s cached for next time.)',
        mbConfirmation, MB_YESNO) = IDYES then
        allowDownload := True
      else
      begin
        MsgBox('No problem - install the .NET SDK yourself from dotnet.microsoft.com/download, then run this installer again.', mbInformation, MB_OK);
        Exit;
      end;
    end;

    RunBuildScript(allowDownload);

    if CheckInstalled() then
      MsgBox('Installed! Look for "Multiplayer" in the pause menu.', mbInformation, MB_OK)
    else
      MsgBox('Something went wrong - check your internet connection and try running the installer again.', mbError, MB_OK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ManagedDir, DeployedDll, BackupDll: string;
begin
  if CurUninstallStep = usUninstall then
  begin
    if not DirExists('{#DemoDir}') then Exit;
    if IsGameRunning() then
    begin
      MsgBox('IGTAP is currently running. Close it, then uninstall again to restore the original files.', mbError, MB_OK);
      Exit;
    end;
    ManagedDir := '{#DemoDir}' + '\IGTAPsnfDemo_Data\Managed';
    DeployedDll := ManagedDir + '\Assembly-CSharp.dll';
    BackupDll := ManagedDir + '\Assembly-CSharp.ORIGINAL.dll';
    if FileExists(BackupDll) then
    begin
      if CopyFile(BackupDll, DeployedDll, False) then
        DeleteFile(BackupDll)
      else
        MsgBox('Failed to restore the original DLL.', mbError, MB_OK);
    end;
  end;
end;
