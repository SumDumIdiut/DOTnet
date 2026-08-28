<#
.SYNOPSIS
    Installs/updates or uninstalls the IGTAP multiplayer mod's patched
    Assembly-CSharp.dll into the Playtest and/or Demo Steam installs.

.PARAMETER Target
    Playtest, Demo, or Both (default).

.PARAMETER Uninstall
    Restore each target's original (pre-mod) DLL from its backup instead of installing.

.PARAMETER SkipBuild
    Redeploy the existing bin\Release build output instead of rebuilding first.

.EXAMPLE
    .\install-mod.ps1
    .\install-mod.ps1 -Target Playtest
    .\install-mod.ps1 -Uninstall
#>
param(
    [ValidateSet('Playtest', 'Demo', 'Both')]
    [string]$Target = 'Both',
    [switch]$Uninstall,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$allTargets = @(
    @{
        Name       = 'Playtest'
        ProjectDir = 'D:\Scripts\csharp\igtap-install-mod'
        GameDir    = "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That's Also a Platformer Playtest"
        ExeName    = 'IGTAPsnfDemo.exe'
    },
    @{
        Name       = 'Demo'
        ProjectDir = 'D:\Scripts\csharp\igtap-install-mod-demo'
        GameDir    = "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That's Also a Platformer Demo"
        ExeName    = 'IGTAPsnfDemo.exe'
    }
)

$targets = if ($Target -eq 'Both') { $allTargets } else { $allTargets | Where-Object { $_.Name -eq $Target } }

function Get-DotnetExe {
    $sdks = & dotnet --list-sdks 2>$null
    if ($LASTEXITCODE -eq 0 -and $sdks) { return 'dotnet' }
    $local = 'D:\Scripts\csharp\igtap-map-editor-ARCHIVED-2026-08-12\.dotnet-sdk\dotnet.exe'
    if (Test-Path $local) { return $local }
    throw "No .NET SDK found: system 'dotnet' has no SDK installed, and the local fallback SDK at $local is missing."
}

$dotnetExe = Get-DotnetExe
$failed = $false

foreach ($t in $targets) {
    Write-Host "`n=== $($t.Name) ===" -ForegroundColor Cyan

    if (-not (Test-Path $t.GameDir)) {
        Write-Warning "$($t.Name): game install not found at '$($t.GameDir)' - skipping."
        continue
    }

    $managedDir  = Join-Path $t.GameDir 'IGTAPsnfDemo_Data\Managed'
    $deployedDll = Join-Path $managedDir 'Assembly-CSharp.dll'
    $backupDll   = Join-Path $t.ProjectDir 'backup\Assembly-CSharp.ORIGINAL.dll'

    $proc = Get-CimInstance Win32_Process -Filter "Name='$($t.ExeName)'" -ErrorAction SilentlyContinue
    if ($proc) {
        $pids = ($proc | Select-Object -ExpandProperty ProcessId) -join ', '
        Write-Warning "$($t.Name): $($t.ExeName) is running (PID $pids). Close the game first - skipping."
        $failed = $true
        continue
    }

    if ($Uninstall) {
        if (-not (Test-Path $backupDll)) {
            Write-Warning "$($t.Name): no backup found at '$backupDll' - cannot uninstall."
            $failed = $true
            continue
        }
        Copy-Item $backupDll $deployedDll -Force
        $srcHash = (Get-FileHash $backupDll -Algorithm MD5).Hash
        $dstHash = (Get-FileHash $deployedDll -Algorithm MD5).Hash
        if ($srcHash -eq $dstHash) {
            Write-Host "$($t.Name): restored original DLL (hash $srcHash). OK" -ForegroundColor Green
        }
        else {
            Write-Error "$($t.Name): hash mismatch after restore! backup=$srcHash deployed=$dstHash"
            $failed = $true
        }
        continue
    }

    if (-not (Test-Path $backupDll)) {
        if (-not (Test-Path $deployedDll)) {
            Write-Warning "$($t.Name): no deployed DLL found at '$deployedDll' to back up from - skipping."
            $failed = $true
            continue
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $backupDll) | Out-Null
        Copy-Item $deployedDll $backupDll
        Write-Host "$($t.Name): backed up original DLL -> $backupDll" -ForegroundColor Yellow
    }

    $csproj      = Join-Path $t.ProjectDir 'decompiled\Assembly-CSharp.csproj'
    $buildOutput = Join-Path $t.ProjectDir 'decompiled\bin\Release\netstandard2.1\Assembly-CSharp.dll'

    if (-not $SkipBuild) {
        Write-Host "$($t.Name): building..."
        $buildLog = & $dotnetExe build $csproj -c Release 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "$($t.Name): build FAILED:`n$($buildLog -join "`n")"
            $failed = $true
            continue
        }
        Write-Host "$($t.Name): build succeeded." -ForegroundColor Green
    }

    if (-not (Test-Path $buildOutput)) {
        Write-Warning "$($t.Name): build output not found at '$buildOutput' - skipping."
        $failed = $true
        continue
    }

    Copy-Item $buildOutput $deployedDll -Force
    $srcHash = (Get-FileHash $buildOutput -Algorithm MD5).Hash
    $dstHash = (Get-FileHash $deployedDll -Algorithm MD5).Hash
    if ($srcHash -eq $dstHash) {
        Write-Host "$($t.Name): deployed (hash $srcHash). OK" -ForegroundColor Green
    }
    else {
        Write-Error "$($t.Name): hash mismatch after deploy! build=$srcHash deployed=$dstHash"
        $failed = $true
    }
}

Write-Host ""
if ($failed) {
    Write-Host "Done - one or more targets had problems, see above." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "Done." -ForegroundColor Cyan
}
