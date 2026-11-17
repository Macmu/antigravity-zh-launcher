$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($file in @('install.ps1','uninstall.ps1','bin/agy-zh.ps1','lib/options.ps1','lib/locale.ps1','lib/zh-overlay.ps1')) {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$file : $($errors.Message -join '; ')" }
    Write-Host "PASS syntax: $file"
}
$psLauncher = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'bin/agy-zh.ps1')
if ($psLauncher -match 'return\s*,\s*\$pids') { throw 'Nested PID array regression in bin/agy-zh.ps1' }
if ($psLauncher -match '/IM\s+Antigravity\.exe') { throw 'Unscoped /IM taskkill regression in bin/agy-zh.ps1' }
. (Join-Path $root 'lib/options.ps1')
foreach ($lang in @('zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR')) {
    $result = Read-AgyOptions -Arguments @('--lang',$lang,'--dry-run') -Switches @('--dry-run')
    if ($result.Lang -cne $lang -or -not $result.dryrun) { throw "Argument parser failed: $lang" }
}
foreach ($bad in @(@('--lang'),@('--lang','en'),@('--unknown'))) {
    $failed = $false
    try { Read-AgyOptions -Arguments $bad | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw "Invalid arguments accepted: $bad" }
}
if ((Read-AgyOptions -Arguments @()).Lang -cne 'zh-CN') { throw 'Default language changed' }
Write-Host 'PASS language arguments, defaults, rejected invalid inputs'
# Build all nine overlays offline, including legacy Chinese anchor fallback.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('agy-ps-test-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory $tempRoot | Out-Null
    $AssetRoot = $root
    . (Join-Path $root 'lib/locale.ps1')
    . (Join-Path $root 'lib/zh-overlay.ps1')
    $BaseOverlayJs = Join-Path $tempRoot 'base.js'
    $OverlayVersion = 'agy-zh-v5'
    [IO.File]::WriteAllText($BaseOverlayJs, ('window.__antigravityZhPatchInstalled = true;' + (' ' * 1100)))
    foreach ($Lang in @('zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR')) {
        $OverlayJs = Join-Path $tempRoot ($Lang + '.js')
        Build-AgyOverlay
        & node --check $OverlayJs
        if ($LASTEXITCODE -ne 0) { throw "Invalid generated overlay: $Lang" }
        Write-Host "PASS PowerShell overlay build: $Lang"
    }
} finally { if (Test-Path $tempRoot) { Remove-Item -Recurse -Force $tempRoot } }
# Exercise real entry-point parsing without Windows COM or the Antigravity process.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('agy-entry-test-' + [Guid]::NewGuid().ToString('N'))
$oldLocal = $env:LOCALAPPDATA; $oldProfile = $env:USERPROFILE; $oldSystemRoot = $env:SystemRoot; $oldConfig = $env:GEMINI_CONFIG_DIR
try {
    New-Item -ItemType Directory $tempRoot | Out-Null
    $env:LOCALAPPDATA = $tempRoot; $env:USERPROFILE = $tempRoot; $env:SystemRoot = $tempRoot; $env:GEMINI_CONFIG_DIR = Join-Path $tempRoot 'config'
    foreach ($lang in @('zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR')) {
        & (Join-Path $root 'install.ps1') --lang $lang --dry-run
        & (Join-Path $root 'uninstall.ps1') --lang $lang --dry-run
    }
    & (Join-Path $root 'bin/agy-zh.ps1') --help
    & (Join-Path $root 'bin/agy-zh.ps1') prompt on --lang ja
    & (Join-Path $root 'bin/agy-zh.ps1') --lang ko prompt on
    $data = Get-Content -Raw -Encoding UTF8 (Join-Path $env:GEMINI_CONFIG_DIR 'config.json') | ConvertFrom-Json
    if ($data.plugins.'antigravity-ja-prompt'.enabled -ne $false -or $data.plugins.'antigravity-ko-prompt'.enabled -ne $true) {
        throw 'Language prompt mutual exclusion failed'
    }
    Write-Host 'PASS nine-language installer/uninstaller dry-runs and runtime prompt selection'
} finally {
    $env:LOCALAPPDATA = $oldLocal; $env:USERPROFILE = $oldProfile; $env:SystemRoot = $oldSystemRoot; $env:GEMINI_CONFIG_DIR = $oldConfig
    if (Test-Path $tempRoot) { Remove-Item -Recurse -Force $tempRoot }
}
