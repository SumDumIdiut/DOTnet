#define MyAppName "DOTnet"
#define MyAppVersion "2.2.1"
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
PrivilegesRequired=admin
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

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\build-and-install.ps1"""; \
    StatusMsg: "Decompiling, patching, and building the mod for your installed copy..."; Flags: waituntilterminated

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
