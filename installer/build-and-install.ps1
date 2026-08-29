<#
.SYNOPSIS
    Decompiles, patches, builds, and installs the multiplayer mod against
    the IGTAP Demo installed on this machine. Never ships any of the
    game's own code - it only ever reads/writes files that are already
    on this PC.

.PARAMETER NoSdkDownload
    Don't auto-download a portable .NET SDK if none is found - just fail.
    Set by the installer when the user declined the download prompt.

.PARAMETER StatusFile
    Path to a text file this script keeps updated with its current phase,
    for the installer's GUI to poll and display. Writes "STATUS_DONE" as
    its last line when finished (success or failure).
#>
param(
    [switch]$NoSdkDownload,
    [string]$StatusFile
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$ilspycmd = Join-Path $root 'tools\ilspycmd\ilspycmd.dll'

function Set-Status([string]$text) {
    Write-Host $text
    if ($StatusFile) { Set-Content -Path $StatusFile -Value $text -Force }
}

$gameDir = "C:\Program Files (x86)\Steam\steamapps\common\IGTAP an Incremental Game That's Also a Platformer Demo"
$awakeAnchor = "`t`t`tdeleteSaveButton.text = deleteSaveMessages[0].GetLocalizedString();`r`n`t`t}"

# ilspycmd is a real published .NET tool with its own target framework - an
# installed SDK that's merely *present* isn't enough, it has to be new enough
# to actually run ilspycmd.dll. Read the requirement from ilspycmd's own
# runtimeconfig.json rather than hardcoding it, so this keeps working if the
# staged ilspycmd build is ever upgraded to target something newer.
$RequiredSdkMajor = 6
$ilspycmdRuntimeConfig = Join-Path $root 'tools\ilspycmd\ilspycmd.runtimeconfig.json'
if (Test-Path $ilspycmdRuntimeConfig) {
    try {
        $cfg = Get-Content $ilspycmdRuntimeConfig -Raw | ConvertFrom-Json
        $RequiredSdkMajor = [int](($cfg.runtimeOptions.framework.version) -split '\.')[0]
    }
    catch { }
}

function Test-SdkCompatible([string]$dotnetExePath) {
    $sdks = & $dotnetExePath --list-sdks 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $sdks) { return $false }
    foreach ($line in $sdks) {
        if ($line -match '^(\d+)\.' -and [int]$Matches[1] -ge $RequiredSdkMajor) { return $true }
    }
    return $false
}

function Get-DotnetExe {
    if (Test-SdkCompatible 'dotnet') { return 'dotnet' }

    $localSdkDir = Join-Path $root '.dotnet-sdk'
    $localDotnetExe = Join-Path $localSdkDir 'dotnet.exe'
    if ((Test-Path $localDotnetExe) -and (Test-SdkCompatible $localDotnetExe)) { return $localDotnetExe }

    if ($NoSdkDownload) {
        throw "No .NET $RequiredSdkMajor+ SDK available and automatic download was declined."
    }

    Set-Status "Downloading the .NET SDK (one-time, roughly 200 MB)..."
    New-Item -ItemType Directory -Force -Path $localSdkDir | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $installScript = Join-Path $env:TEMP 'dotnet-install.ps1'
        Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installScript -UseBasicParsing
        & $installScript -Channel "$RequiredSdkMajor.0" -InstallDir $localSdkDir -NoPath *> (Join-Path $env:TEMP 'dotnet-sdk-install.log')
    }
    catch {
        Set-Status "Portable .NET SDK download failed: $($_.Exception.Message)"
    }

    if ((Test-Path $localDotnetExe) -and (Test-SdkCompatible $localDotnetExe)) { return $localDotnetExe }
    throw "Could not obtain a .NET $RequiredSdkMajor+ SDK (none installed, and the automatic portable download failed or didn't provide a compatible version - check your internet connection)."
}

try {
    if (-not (Test-Path $gameDir)) {
        Set-Status "IGTAP Demo isn't installed here - nothing to do."
        return
    }

    $proc = Get-CimInstance Win32_Process -Filter "Name='IGTAPsnfDemo.exe'" -ErrorAction SilentlyContinue
    if ($proc) {
        Set-Status "The game is running - close it and run this installer again."
        return
    }

    $dotnetExe = Get-DotnetExe
    $hookInsert = "`t`ttry { MpMenuBuilder.Install(this); }`r`n`t`tcatch (System.Exception e) { Debug.LogError(`"[Multiplayer] menu install failed: `" + e); }"
    $propsInsert = "`tpublic GameObject mainBitPublic => mainBit;`r`n`tpublic GameObject settingsBitPublic => settingsBit;`r`n`r`n"

    $managed = Join-Path $gameDir 'IGTAPsnfDemo_Data\Managed'
    $deployed = Join-Path $managed 'Assembly-CSharp.dll'
    $backup = Join-Path $managed 'Assembly-CSharp.ORIGINAL.dll'

    if (-not (Test-Path $backup)) {
        Copy-Item $deployed $backup
    }
    $sourceDll = $backup

    $work = Join-Path $env:TEMP 'igtap-mp-build-Demo'
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    Set-Status "Decompiling..."
    & $dotnetExe $ilspycmd -p -o $work -r $managed $sourceDll *> (Join-Path $work 'decompile.log')
    $pauseMenuPath = Join-Path $work 'pauseMenuScript.cs'
    if (-not (Test-Path $pauseMenuPath)) {
        Set-Status "Decompile failed, see $work\decompile.log."
        return
    }

    $src = Get-Content $pauseMenuPath -Raw
    if ($src -notmatch [regex]::Escape($awakeAnchor)) {
        Set-Status "pauseMenuScript.cs didn't match the expected shape (the game may have updated)."
        return
    }
    $src = $src -replace [regex]::Escape($awakeAnchor), ($awakeAnchor + "`r`n" + $hookInsert)
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

    Set-Status "Building..."
    & $dotnetExe build $csprojPath -c Release *> (Join-Path $work 'build.log')
    $built = Join-Path $work 'bin\Release\netstandard2.1\Assembly-CSharp.dll'
    if (-not (Test-Path $built)) {
        Set-Status "Build failed, see $work\build.log."
        return
    }

    Copy-Item $built $deployed -Force
    Set-Status "Installed."
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
catch {
    Set-Status "Failed: $($_.Exception.Message)"
}
finally {
    if ($StatusFile) { Add-Content -Path $StatusFile -Value 'STATUS_DONE' }
}
