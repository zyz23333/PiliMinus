# Android development commands. Keep SDK and dependency patches local to this project.
$ErrorActionPreference = 'Stop'

$devAction = if ($args.Count -gt 0) { [string]$args[0] } else { 'setup' }
$devArguments = @($args | Select-Object -Skip 1)
$devActions = @('setup', 'doctor', 'analyze', 'test', 'build', 'devices', 'emulators', 'emulator', 'run', 'flutter', 'dart')
if ($devAction -notin $devActions) {
    throw ('Usage: tool/dev.ps1 [' + ($devActions -join '|') + '] [arguments]')
}

$devRoot = Split-Path -Parent $PSScriptRoot
$devSdk = Join-Path $devRoot '.fvm/flutter_sdk'
$devCache = Join-Path $devRoot '.pub-cache'
$devSdkState = Join-Path $devRoot '.fvm/android-sdk-patches.json'
$devVersion = (Get-Content -LiteralPath (Join-Path $devRoot '.fvmrc') -Raw | ConvertFrom-Json).flutter
$devSdkPatchNames = @(
    'modal_barrier', 'text_selection', 'mouse_cursor', 'image_anim', 'layout_builder',
    'navigation_drawer', 'popup_menu', 'fab', 'null_safety_for_selectable_region',
    'selectable_region', 'editable_text', 'text_field', 'scroll_position', 'scrollable',
    'scrollable_gesture', 'draggable_scrollable_sheet', 'scaffold', 'text', 'text_painter',
    'sliver', 'refresh_indicator', 'double_tap_gesture', 'bottom_sheet_android',
    'scroll_view', 'navigator'
)
$devMaterialPatchNames = @(
    'modal_barrier_material', 'navigation_drawer', 'popup_menu', 'fab',
    'text_field', 'scaffold', 'refresh_indicator', 'tabs', 'bottom_sheet_android'
)

function Invoke-DevNative {
    param([string]$Program, [string[]]$NativeArguments)
    & $Program @NativeArguments
    if ($LASTEXITCODE -ne 0) {
        throw ('Command failed (' + $LASTEXITCODE + '): ' + $Program + ' ' + ($NativeArguments -join ' '))
    }
}

function Get-DevPatchFingerprint {
    param([string]$PatchDirectory, [string[]]$PatchNames)
    return (($PatchNames | ForEach-Object {
        $patchFile = Join-Path $PatchDirectory ($_ + '.patch')
        ([IO.Path]::GetFileName($patchFile) + ':' + (Get-FileHash -LiteralPath $patchFile -Algorithm SHA256).Hash)
    }) -join "`n")
}

function Add-DevPatches {
    param([string]$TargetDirectory, [string]$PatchDirectory, [string[]]$PatchNames)
    foreach ($patchName in $PatchNames) {
        $patchFile = Join-Path $PatchDirectory ($patchName + '.patch')
        $forwardCheck = & git -C $TargetDirectory apply --check $patchFile 2>&1
        if ($LASTEXITCODE -eq 0) {
            Invoke-DevNative -Program git -NativeArguments @('-C', $TargetDirectory, 'apply', $patchFile)
            Write-Host ('Applied: ' + $patchName)
            continue
        }
        $reverseCheck = & git -C $TargetDirectory apply --reverse --check $patchFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ('Cannot apply or verify patch ' + $patchName + ': ' + ($forwardCheck -join ' '))
        }
        Write-Host ('Already applied: ' + $patchName)
    }
}

function Initialize-DevSdk {
    if (-not (Test-Path -LiteralPath $devSdk)) {
        $sourceCommand = Get-Command flutter -ErrorAction Stop
        $sourceSdk = Split-Path -Parent (Split-Path -Parent $sourceCommand.Source)
        $sourceVersion = (& $sourceCommand.Source --version --machine | ConvertFrom-Json).frameworkVersion
        if ($LASTEXITCODE -ne 0 -or $sourceVersion -ne $devVersion) {
            throw ('Install Flutter ' + $devVersion + ' on PATH before setup; detected ' + $sourceVersion)
        }
        $sourceRevision = (& git -C $sourceSdk rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'The source Flutter SDK must be a Git checkout.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $devSdk) -Force | Out-Null
        Invoke-DevNative -Program git -NativeArguments @('clone', '--no-hardlinks', '--no-checkout', $sourceSdk, $devSdk)
        Invoke-DevNative -Program git -NativeArguments @('-C', $devSdk, 'checkout', '-B', 'stable', $sourceRevision)
        Invoke-DevNative -Program git -NativeArguments @('-C', $devSdk, 'remote', 'set-url', 'origin', 'https://github.com/flutter/flutter.git')
        $sourceEngineCache = Join-Path $sourceSdk 'bin/cache'
        if (Test-Path -LiteralPath $sourceEngineCache) {
            & robocopy $sourceEngineCache (Join-Path $devSdk 'bin/cache') /E /R:1 /W:1 /NFL /NDL /NJH /NJS /XJ /XD dart-sdk.old1 downloads flutter_web_sdk windows-x64 windows-x64-profile windows-x64-release linux-x64 linux-x64-profile linux-x64-release /XF flutter.bat.lock lockfile
            if ($LASTEXITCODE -ge 8) { throw ('SDK cache copy failed: ' + $LASTEXITCODE) }
        }
    }

    $patchDirectory = Join-Path $devRoot 'lib/scripts'
    $fingerprint = Get-DevPatchFingerprint $patchDirectory $devSdkPatchNames
    $sdkRevision = (& git -C $devSdk rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Project Flutter SDK is not a valid Git checkout.' }
    if (Test-Path -LiteralPath $devSdkState) {
        $state = Get-Content -LiteralPath $devSdkState -Raw | ConvertFrom-Json
        if ($state.version -ne $devVersion -or $state.revision -ne $sdkRevision -or $state.fingerprint -ne $fingerprint) {
            throw 'Flutter version or SDK patches changed. Prepare a fresh project SDK before setup.'
        }
        Write-Host ('Project Flutter ' + $devVersion + ': SDK patches already prepared.')
        return
    }

    Add-DevPatches $devSdk $patchDirectory $devSdkPatchNames
    @{ version = $devVersion; revision = $sdkRevision; fingerprint = $fingerprint } |
        ConvertTo-Json | Set-Content -LiteralPath $devSdkState -Encoding UTF8
}

function Initialize-DevMaterial {
    $configPath = Join-Path $devRoot '.dart_tool/package_config.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $package = $config.packages | Where-Object name -eq 'material_ui' | Select-Object -First 1
    if (-not $package) { throw 'material_ui was not resolved by pub get.' }
    $configUri = [Uri]::new([IO.Path]::GetFullPath($configPath))
    $packageDirectory = [IO.Path]::GetFullPath([Uri]::new($configUri, $package.rootUri).LocalPath)
    $cachePrefix = [IO.Path]::GetFullPath($devCache).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
    if (-not $packageDirectory.StartsWith($cachePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to patch material_ui outside the project dependency cache.'
    }
    $patchDirectory = Join-Path $devRoot 'lib/scripts/material'
    $fingerprint = Get-DevPatchFingerprint $patchDirectory $devMaterialPatchNames
    $marker = Join-Path $packageDirectory '.piliminus-android-patches.json'
    if (Test-Path -LiteralPath $marker) {
        $state = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
        if ($state.fingerprint -ne $fingerprint) {
            throw 'material_ui patches changed. Prepare a fresh package copy before setup.'
        }
        Write-Host 'Project material_ui: patches already prepared.'
        return
    }

    # Use a package-local repository so git apply resolves paths inside this package.
    Invoke-DevNative -Program git -NativeArguments @('init', '--quiet', $packageDirectory)
    Add-DevPatches $packageDirectory $patchDirectory $devMaterialPatchNames
    @{ fingerprint = $fingerprint } | ConvertTo-Json |
        Set-Content -LiteralPath $marker -Encoding UTF8
}

function Initialize-DevGitDependencies {
    $gitCache = Join-Path $devCache 'git'
    if (-not (Test-Path -LiteralPath $gitCache)) { return }
    foreach ($dependency in (Get-ChildItem -LiteralPath $gitCache -Directory)) {
        if (-not (Test-Path -LiteralPath (Join-Path $dependency.FullName '.git'))) { continue }
        Invoke-DevNative -Program git -NativeArguments @('-C', $dependency.FullName, 'config', 'core.longpaths', 'true')
        # An existing Windows cache can contain an incomplete checkout. Restore only missing tracked files.
        $missingFiles = @(& git -C $dependency.FullName diff --name-only --diff-filter=D)
        if ($LASTEXITCODE -ne 0) { throw ('Cannot inspect Git dependency: ' + $dependency.Name) }
        if ($missingFiles.Count -gt 0) {
            Invoke-DevNative -Program git -NativeArguments (@('-C', $dependency.FullName, 'restore', '--worktree', '--') + $missingFiles)
            Write-Host ('Restored ' + $missingFiles.Count + ' missing files in ' + $dependency.Name)
        }
    }
}

function Initialize-DevNetwork {
    $gradleSettings = Join-Path $devRoot '.gradle/gradle.properties'
    if (Test-Path -LiteralPath $gradleSettings) { return }
    $gitProxy = & git config --get http.proxy
    if ($LASTEXITCODE -ne 0 -or -not $gitProxy) { return }
    $proxy = [Uri]$gitProxy.Trim()
    # Reuse a local HTTP proxy; keep credentials and remote proxy configuration out of generated files.
    if (-not $proxy.IsLoopback -or $proxy.Scheme -notin @('http', 'https') -or $proxy.UserInfo) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $gradleSettings) -Force | Out-Null
    @(
        ('systemProp.http.proxyHost=' + $proxy.Host),
        ('systemProp.http.proxyPort=' + $proxy.Port),
        ('systemProp.https.proxyHost=' + $proxy.Host),
        ('systemProp.https.proxyPort=' + $proxy.Port)
    ) | Set-Content -LiteralPath $gradleSettings -Encoding ASCII
    Write-Host 'Configured the project Gradle cache to use the existing local Git proxy.'
}

function Initialize-DevWorkspace {
    $workspace = @{
        folders = @(@{ path = '..' })
        settings = @{
            'dart.env' = @{
                PUB_CACHE = $devCache
                PUB_HOSTED_URL = 'https://pub.dev'
                GRADLE_USER_HOME = (Join-Path $devRoot '.gradle')
            }
        }
    }
    $workspace | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $devRoot '.fvm/piliminus.code-workspace') -Encoding UTF8
}

$devSavedEnvironment = @{}
$devGitConfigIndex = if ($env:GIT_CONFIG_COUNT) { [int]$env:GIT_CONFIG_COUNT } else { 0 }
$devGitConfigKey = 'GIT_CONFIG_KEY_' + $devGitConfigIndex
$devGitConfigValue = 'GIT_CONFIG_VALUE_' + $devGitConfigIndex
foreach ($name in @('PATH', 'FLUTTER_ROOT', 'PUB_CACHE', 'PUB_HOSTED_URL', 'GRADLE_USER_HOME', 'GIT_TERMINAL_PROMPT', 'GIT_CONFIG_COUNT', $devGitConfigKey, $devGitConfigValue)) {
    $devSavedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$devPreviousDirectory = Get-Location

try {
    Set-Location -LiteralPath $devRoot
    # Pub's initial Git checkout must also support long Android plugin paths.
    $env:GIT_CONFIG_COUNT = [string]($devGitConfigIndex + 1)
    [Environment]::SetEnvironmentVariable($devGitConfigKey, 'core.longpaths', 'Process')
    [Environment]::SetEnvironmentVariable($devGitConfigValue, 'true', 'Process')
    if ($devAction -eq 'setup') { Initialize-DevSdk }
    if (-not (Test-Path -LiteralPath $devSdkState)) {
        throw 'Run tool/dev.ps1 setup before using development commands.'
    }
    $env:PATH = (Join-Path $devSdk 'bin') + ';' + $env:PATH
    $env:FLUTTER_ROOT = $devSdk
    $env:PUB_CACHE = $devCache
    # Match the source recorded by the upstream lockfile, independent of global mirrors.
    $env:PUB_HOSTED_URL = 'https://pub.dev'
    $env:GRADLE_USER_HOME = Join-Path $devRoot '.gradle'
    $env:GIT_TERMINAL_PROMPT = '0'
    $flutterCommand = Join-Path $devSdk 'bin/flutter.bat'

    switch ($devAction) {
        'setup' {
            Invoke-DevNative -Program $flutterCommand -NativeArguments @('pub', 'get', '--enforce-lockfile')
            Initialize-DevGitDependencies
            Initialize-DevMaterial
            Initialize-DevNetwork
            Initialize-DevWorkspace
            Write-Host 'Android development dependencies and patches are ready.'
        }
        'doctor' { Invoke-DevNative -Program $flutterCommand -NativeArguments @('doctor', '-v') }
        'analyze' { Invoke-DevNative -Program $flutterCommand -NativeArguments (@('analyze', '--no-pub') + $devArguments) }
        'test' { Invoke-DevNative -Program $flutterCommand -NativeArguments (@('test', '--no-pub') + $devArguments) }
        'build' { Invoke-DevNative -Program $flutterCommand -NativeArguments (@('build', 'apk', '--debug', '--no-pub') + $devArguments) }
        'devices' { Invoke-DevNative -Program $flutterCommand -NativeArguments @('devices') }
        'emulators' { Invoke-DevNative -Program $flutterCommand -NativeArguments (@('emulators') + $devArguments) }
        'emulator' {
            $adbPath = (Get-Command adb -ErrorAction Stop).Source
            $androidSdk = Split-Path -Parent (Split-Path -Parent $adbPath)
            $emulatorCommand = Join-Path $androidSdk 'emulator/emulator.exe'
            Invoke-DevNative -Program $emulatorCommand -NativeArguments (@('-avd', 'PiliMinus_API35', '-gpu', 'swiftshader_indirect', '-feature', '-Vulkan') + $devArguments)
        }
        'run' { Invoke-DevNative -Program $flutterCommand -NativeArguments (@('run', '--no-pub') + $devArguments) }
        'flutter' { Invoke-DevNative -Program $flutterCommand -NativeArguments $devArguments }
        'dart' { Invoke-DevNative -Program (Join-Path $devSdk 'bin/dart.bat') -NativeArguments $devArguments }
    }
}
finally {
    Set-Location -LiteralPath $devPreviousDirectory.Path
    foreach ($name in $devSavedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $devSavedEnvironment[$name], 'Process')
    }
}
