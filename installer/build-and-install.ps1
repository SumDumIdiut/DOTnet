<#
.SYNOPSIS
    Decompiles, patches, builds, and installs the multiplayer mod against
    whatever copy of the game is actually present on this machine. Never
    ships any of the game's own code - it only ever reads/writes files
    that are already on this PC.

.PARAMETER Target
    Playtest, Demo, or Both (default).
#>
param(
    [ValidateSet('Playtest', 'Demo', 'Both')]
    [string]$Target = 'Both'
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$ilspycmd = Join-Path $root 'tools\ilspycmd\ilspycmd.dll'

$allTargets = @(
    @{
        Name    = 'Playtest'
        GameDir = "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That's Also a Platformer Playtest"
        AwakeAnchor = "`t`t`t`tstartButtonText.StringReference = startButtonNewGame;`r`n`t`t`t}`r`n`t`t}"
    },
    @{
        Name    = 'Demo'
        GameDir = "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That's Also a Platformer Demo"
        AwakeAnchor = "`t`t`tdeleteSaveButton.text = deleteSaveMessages[0].GetLocalizedString();`r`n`t`t}"
    }
)
$targets = if ($Target -eq 'Both') { $allTargets } else { $allTargets | Where-Object { $_.Name -eq $Target } }

function Get-DotnetExe {
    $sdks = & dotnet --list-sdks 2>$null
    if ($LASTEXITCODE -eq 0 -and $sdks) { return 'dotnet' }

    # most players won't have a system SDK - fetch a portable one instead of just erroring out
    $localSdkDir = Join-Path $root '.dotnet-sdk'
    $localDotnetExe = Join-Path $localSdkDir 'dotnet.exe'
    if (Test-Path $localDotnetExe) {
        $sdks = & $localDotnetExe --list-sdks 2>$null
        if ($LASTEXITCODE -eq 0 -and $sdks) { return $localDotnetExe }
    }

    Write-Host "No .NET SDK found - downloading a portable copy (one-time, roughly 200 MB)..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $localSdkDir | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $installScript = Join-Path $env:TEMP 'dotnet-install.ps1'
        Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installScript -UseBasicParsing
        & $installScript -Channel LTS -InstallDir $localSdkDir -NoPath
    }
    catch {
        Write-Warning "Portable .NET SDK download failed: $($_.Exception.Message)"
    }

    if (Test-Path $localDotnetExe) {
        $sdks = & $localDotnetExe --list-sdks 2>$null
        if ($LASTEXITCODE -eq 0 -and $sdks) {
            Write-Host "Portable .NET SDK ready." -ForegroundColor Green
            return $localDotnetExe
        }
    }
    throw "Could not obtain a .NET SDK (none installed, and the automatic portable download failed - check your internet connection). Install the .NET SDK from https://dotnet.microsoft.com/download and run this installer again."
}

$dotnetExe = Get-DotnetExe
$hookInsert = "`t`ttry { MpMenuBuilder.Install(this); }`r`n`t`tcatch (System.Exception e) { Debug.LogError(`"[Multiplayer] menu install failed: `" + e); }"
$propsInsert = "`tpublic GameObject mainBitPublic => mainBit;`r`n`tpublic GameObject settingsBitPublic => settingsBit;`r`n`r`n"

foreach ($t in $targets) {
    Write-Host "`n=== $($t.Name) ===" -ForegroundColor Cyan

    if (-not (Test-Path $t.GameDir)) {
        Write-Host "$($t.Name): not installed here, skipping." -ForegroundColor DarkGray
        continue
    }

    $proc = Get-CimInstance Win32_Process -Filter "Name='IGTAPsnfDemo.exe'" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Warning "$($t.Name): the game is running. Close it and run this installer again - skipping."
        continue
    }

    $managed = Join-Path $t.GameDir 'IGTAPsnfDemo_Data\Managed'
    $deployed = Join-Path $managed 'Assembly-CSharp.dll'
    $backup = Join-Path $managed 'Assembly-CSharp.ORIGINAL.dll'

    if (-not (Test-Path $backup)) {
        Copy-Item $deployed $backup
    }
    $sourceDll = $backup

    $work = Join-Path $env:TEMP "igtap-mp-build-$($t.Name)"
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    Write-Host "$($t.Name): decompiling..."
    & $dotnetExe $ilspycmd -p -o $work -r $managed $sourceDll *> (Join-Path $work 'decompile.log')
    $pauseMenuPath = Join-Path $work 'pauseMenuScript.cs'
    if (-not (Test-Path $pauseMenuPath)) {
        Write-Warning "$($t.Name): decompile failed, see $work\decompile.log - skipping."
        continue
    }

    $src = Get-Content $pauseMenuPath -Raw
    if ($src -notmatch [regex]::Escape($t.AwakeAnchor)) {
        Write-Warning "$($t.Name): pauseMenuScript.cs didn't match the expected shape (game may have updated) - skipping. Report this."
        continue
    }
    $src = $src -replace [regex]::Escape($t.AwakeAnchor), ($t.AwakeAnchor + "`r`n" + $hookInsert)
    $src = $src -replace "(?m)^\tprivate void Start\(\)", ($propsInsert + "`tprivate void Start()")
    Set-Content -Path $pauseMenuPath -Value $src -NoNewline

    Copy-Item (Join-Path $root 'mod\*.cs') $work

    $csprojPath = Join-Path $work 'Assembly-CSharp.csproj'
    $refs = @(
        'UnityEngine.CoreModule', 'UnityEngine.ParticleSystemModule', 'UnityEngine.AudioModule',
        'Unity.TextMeshPro', 'Unity.Localization', 'UnityEngine.AnimationModule', 'Unity.InputSystem',
        'UnityEngine.Physics2DModule', 'UnityEngine.UI', 'Unity.RenderPipelines.Universal.2D.Runtime',
        'com.rlabrecque.steamworks.net', 'UnityEngine.TilemapModule', 'UnityEngine.UIModule', 'DOTween',
        'UnityEngine.JSONSerializeModule', 'Unity.Mathematics', 'Assembly-CSharp-firstpass', 'UnityEngine',
        'UnityEngine.UIElementsModule', 'Newtonsoft.Json', 'UnityEngine.TextRenderingModule'
    )
    $refXml = ($refs | ForEach-Object {
        "    <Reference Include=`"$_`"><HintPath>$managed\$_.dll</HintPath></Reference>"
    }) -join "`n"
    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <AssemblyName>Assembly-CSharp</AssemblyName>
    <GenerateAssemblyInfo>False</GenerateAssemblyInfo>
    <TargetFramework>netstandard2.1</TargetFramework>
    <LangVersion>latest</LangVersion>
    <AllowUnsafeBlocks>True</AllowUnsafeBlocks>
    <CheckForOverflowUnderflow>False</CheckForOverflowUnderflow>
  </PropertyGroup>
  <ItemGroup>
$refXml
  </ItemGroup>
</Project>
"@ | Set-Content -Path $csprojPath

    Write-Host "$($t.Name): building..."
    & $dotnetExe build $csprojPath -c Release *> (Join-Path $work 'build.log')
    $built = Join-Path $work 'bin\Release\netstandard2.1\Assembly-CSharp.dll'
    if (-not (Test-Path $built)) {
        Write-Warning "$($t.Name): build failed, see $work\build.log - skipping."
        continue
    }

    Copy-Item $built $deployed -Force
    Write-Host "$($t.Name): installed." -ForegroundColor Green
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Write-Host "`nDone." -ForegroundColor Cyan
