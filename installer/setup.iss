#define MyAppName "IGTAP Multiplayer Mod"
#define MyAppVersion "1.0"
#define ExeName "IGTAPsnfDemo.exe"
#define PlaytestDir "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That''s Also a Platformer Playtest"
#define DemoDir "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That''s Also a Platformer Demo"

[Setup]
AppId={{5E7982D5-978E-441A-954D-7D2BF0D93F61}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableWelcomePage=no
PrivilegesRequired=admin
OutputDir=output
OutputBaseFilename=IGTAPMultiplayerModSetup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
WizardStyle=modern

[Files]
Source: "build\PlaytestPatched.dll"; DestDir: "{tmp}"; Flags: dontcopy nocompression skipifsourcedoesntexist
Source: "build\PlaytestOriginal.dll"; DestDir: "{tmp}"; Flags: dontcopy nocompression skipifsourcedoesntexist
Source: "build\DemoPatched.dll"; DestDir: "{tmp}"; Flags: dontcopy nocompression skipifsourcedoesntexist
Source: "build\DemoOriginal.dll"; DestDir: "{tmp}"; Flags: dontcopy nocompression skipifsourcedoesntexist

[Code]
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

function StageFile(const StagedName: string): string;
begin
  ExtractTemporaryFile(StagedName);
  Result := ExpandConstant('{tmp}\' + StagedName);
end;

// BackupDll always ends up holding a copy of the bundled *known-original* DLL, never
// whatever happened to be deployed at install time - so uninstall can't accidentally
// treat an already-patched DLL as "the original" and restore nothing.
procedure InstallOne(const GameDir, PatchedName, OriginalName, Label_: string);
var
  ManagedDir, DeployedDll, BackupDll, PatchedPath, OriginalPath: string;
begin
  if not DirExists(GameDir) then
  begin
    Log(Label_ + ': not installed here, skipping');
    Exit;
  end;

  ManagedDir := GameDir + '\IGTAPsnfDemo_Data\Managed';
  DeployedDll := ManagedDir + '\Assembly-CSharp.dll';
  BackupDll := ManagedDir + '\Assembly-CSharp.ORIGINAL.dll';

  OriginalPath := StageFile(OriginalName);
  if not FileExists(OriginalPath) then
  begin
    Log(Label_ + ': no bundled original for this target, skipping');
    Exit;
  end;
  if not CopyFile(OriginalPath, BackupDll, False) then
  begin
    MsgBox(Label_ + ': could not write the backup DLL, skipping.', mbError, MB_OK);
    Exit;
  end;

  PatchedPath := StageFile(PatchedName);
  if not FileExists(PatchedPath) then
  begin
    Log(Label_ + ': no bundled patched build for this target, skipping');
    Exit;
  end;
  if not CopyFile(PatchedPath, DeployedDll, False) then
    MsgBox(Label_ + ': failed to install the patched DLL.', mbError, MB_OK);
end;

procedure RestoreOne(const GameDir, Label_: string);
var
  ManagedDir, DeployedDll, BackupDll: string;
begin
  if not DirExists(GameDir) then Exit;
  ManagedDir := GameDir + '\IGTAPsnfDemo_Data\Managed';
  DeployedDll := ManagedDir + '\Assembly-CSharp.dll';
  BackupDll := ManagedDir + '\Assembly-CSharp.ORIGINAL.dll';
  if FileExists(BackupDll) then
  begin
    if CopyFile(BackupDll, DeployedDll, False) then
      DeleteFile(BackupDll)
    else
      MsgBox(Label_ + ': failed to restore the original DLL.', mbError, MB_OK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if IsGameRunning() then
    begin
      MsgBox('IGTAP is currently running. Close it, then run this installer again.', mbError, MB_OK);
      Exit;
    end;
    InstallOne('{#PlaytestDir}', 'PlaytestPatched.dll', 'PlaytestOriginal.dll', 'Playtest');
    InstallOne('{#DemoDir}', 'DemoPatched.dll', 'DemoOriginal.dll', 'Demo');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    if IsGameRunning() then
    begin
      MsgBox('IGTAP is currently running. Close it, then uninstall again to restore the original files.', mbError, MB_OK);
      Exit;
    end;
    RestoreOne('{#PlaytestDir}', 'Playtest');
    RestoreOne('{#DemoDir}', 'Demo');
  end;
end;
