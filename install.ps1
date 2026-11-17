& {
    $ErrorActionPreference = 'Stop'
    try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}
    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $RepoRawBase = if ($env:AGY_ZH_REPO_RAW) { $env:AGY_ZH_REPO_RAW } else { 'https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main' }
    $tempRoot = $null
    try {
        $SourceRoot = $PSScriptRoot
        $local = $SourceRoot -and (Test-Path (Join-Path $SourceRoot 'locales\index.json'))
        if (-not $local) {
            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agy-install-' + [Guid]::NewGuid().ToString('N'))
            $SourceRoot = $tempRoot
            New-Item -ItemType Directory -Force (Join-Path $SourceRoot 'lib') | Out-Null
            Invoke-WebRequest -UseBasicParsing -Uri "$RepoRawBase/lib/options.ps1" -OutFile (Join-Path $SourceRoot 'lib\options.ps1')
        }
        . (Join-Path $SourceRoot 'lib\options.ps1')
        $options = Read-AgyOptions -Arguments $args -Switches @('--update-engine','-UpdateEngine','--no-shortcut','-NoShortcut','--dry-run','-DryRun')
        if ($options.Help) {
            Write-Host 'install.ps1 [--lang <code>] [--update-engine] [--no-shortcut] [--dry-run]'
            Write-Host ("Languages: zh-CN zh-TW ja ko es fr de ru pt-BR. Default: zh-CN / Antigravity " + [regex]::Unescape('\u4e2d\u6587'))
            return
        }
        $Lang = $options.Lang
        $UpdateEngine = $options.updateengine -or ($env:AGY_ZH_UPDATE_ENGINE -eq '1')
        $NoShortcut = $options.noshortcut -or ($env:AGY_ZH_NO_SHORTCUT -eq '1')
        function Get-SourceFile {
            param([string]$Relative)
            $path = Join-Path $SourceRoot $Relative
            if (-not $local) {
                New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
                Invoke-WebRequest -UseBasicParsing -Uri "$RepoRawBase/$($Relative.Replace('\','/'))" -OutFile $path
            }
            if (-not (Test-Path $path)) { throw "Missing source file: $Relative" }
            return $path
        }
        $index = Get-Content -Raw -Encoding UTF8 (Get-SourceFile 'locales\index.json') | ConvertFrom-Json
        $meta = $index.$Lang
        $InstallRoot = Join-Path $env:LOCALAPPDATA 'antigravity-zh-launcher'
        $BinDir = Join-Path $InstallRoot 'bin'
        $AssetRoot = Join-Path $BinDir 'agy-i18n'
        $ConfigDir = if ($env:GEMINI_CONFIG_DIR) { $env:GEMINI_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.gemini\config' }
        $PluginName = $meta.pluginName
        $PluginDir = Join-Path $ConfigDir "plugins\$PluginName"
        if ($options.dryrun) {
            Write-Host "[dry-run] $Lang -> $($meta.appName); CLI: $BinDir; plugin: $PluginDir; shortcut: $(-not $NoShortcut)"
            return
        }
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Use install.sh on macOS. install.ps1 requires Windows.' }
        # Fetch all required source files before replacing the installed runtime.
        $files = @('bin\agy-zh.ps1','lib\options.ps1','lib\locale.ps1','lib\zh-overlay.ps1','lib\overlay.js','locales\index.json',
                   "plugins\$PluginName\plugin.json", "plugins\$PluginName\rules\AGENTS.md", 'plugins\antigravity-zh-prompt\assets\logo.svg')
        foreach ($item in $index.PSObject.Properties) { $files += "locales\$($item.Name).json" }
        foreach ($file in $files) { Get-SourceFile $file | Out-Null }
        New-Item -ItemType Directory -Force $BinDir, (Join-Path $AssetRoot 'lib'), (Join-Path $AssetRoot 'locales'), (Join-Path $AssetRoot 'installed'), (Join-Path $PluginDir 'assets'), (Join-Path $PluginDir 'rules') | Out-Null
        foreach ($file in $files | Where-Object { $_ -like 'lib\*' -or $_ -like 'locales\*' }) {
            Copy-Item -Force (Join-Path $SourceRoot $file) (Join-Path $AssetRoot $file)
        }
        $AgyZhPs1 = Join-Path $BinDir 'agy-zh.ps1'
        Copy-Item -Force (Join-Path $SourceRoot 'bin\agy-zh.ps1') $AgyZhPs1
        $PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $cmdTemplate = '@echo off' + "`r`n" + '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0agy-zh.ps1" '
        [IO.File]::WriteAllText((Join-Path $BinDir 'agy-zh.cmd'), $cmdTemplate + '%*' + "`r`n", [Text.Encoding]::ASCII)
        if ($meta.command -ne 'agy-zh') {
            [IO.File]::WriteAllText((Join-Path $BinDir ($meta.command + '.cmd')), $cmdTemplate + '--lang ' + $Lang + ' %*' + "`r`n", [Text.Encoding]::ASCII)
        }
        Copy-Item -Force (Join-Path $SourceRoot "plugins\$PluginName\plugin.json") (Join-Path $PluginDir 'plugin.json')
        Copy-Item -Force (Join-Path $SourceRoot "plugins\$PluginName\rules\AGENTS.md") (Join-Path $PluginDir 'rules\AGENTS.md')
        Copy-Item -Force (Join-Path $SourceRoot 'plugins\antigravity-zh-prompt\assets\logo.svg') (Join-Path $PluginDir 'assets\logo.svg')
        $buildArgs = @('--lang', $Lang, 'build-overlay')
        if ($UpdateEngine) { $buildArgs += '--force' }
        & $PsExe -NoProfile -ExecutionPolicy Bypass -File $AgyZhPs1 @buildArgs
        if ($LASTEXITCODE -ne 0) { throw "Overlay build failed ($LASTEXITCODE)." }
        & $PsExe -NoProfile -ExecutionPolicy Bypass -File $AgyZhPs1 --lang $Lang prompt off
        if ($LASTEXITCODE -ne 0) { throw "Prompt configuration failed ($LASTEXITCODE)." }
        if (-not $NoShortcut) {
            & $PsExe -NoProfile -ExecutionPolicy Bypass -File $AgyZhPs1 --lang $Lang shortcut
            if ($LASTEXITCODE -ne 0) { throw "Shortcut creation failed ($LASTEXITCODE)." }
        }
        [IO.File]::WriteAllText((Join-Path $AssetRoot "installed\$Lang"), '')
        if ($Lang -eq 'zh-CN') { Remove-Item -Force (Join-Path $BinDir 'antigravity-hans.exe') -ErrorAction SilentlyContinue }
        foreach ($scope in @('User','Process')) {
            $pathValue = [Environment]::GetEnvironmentVariable('Path', $scope)
            $segments = @($pathValue -split ';' | Where-Object { $_ })
            if (-not ($segments | Where-Object { $_.Trim().TrimEnd('\') -ieq $BinDir.TrimEnd('\') })) {
                [Environment]::SetEnvironmentVariable('Path', (($segments + $BinDir) -join ';'), $scope)
            }
        }
        Write-Host "$([regex]::Unescape('[\u6210\u529f]')) $($meta.appName) ($Lang). Start: $($meta.command) start"
        Write-Host ([regex]::Unescape('[\u4fe1\u606f] Prompt \u63d2\u4ef6\u9ed8\u8ba4\u5173\u95ed\uff0c\u539f\u7248\u5e94\u7528\u6587\u4ef6\u4fdd\u6301\u4e0d\u53d8\u3002'))
    } finally {
        if ($tempRoot -and (Test-Path $tempRoot)) { Remove-Item -Recurse -Force $tempRoot }
    }
} @args
