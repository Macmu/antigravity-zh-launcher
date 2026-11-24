& {
    $ErrorActionPreference = 'Stop'
    try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}
    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

    function Resolve-ZhText {
        param([string]$Text)
        return [regex]::Unescape($Text)
    }

    $TagOk   = Resolve-ZhText '[\u6210\u529f]'
    $TagWarn = Resolve-ZhText '[\u63d0\u793a]'
    $Purge   = ($env:AGY_ZH_PURGE -eq '1')

    $InstallRoot = Join-Path $env:LOCALAPPDATA 'antigravity-zh-launcher'
    $BinDir = Join-Path $InstallRoot 'bin'
    $AssetRoot = Join-Path $BinDir 'agy-i18n'
    $sourceRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'locales\index.json'))) { $PSScriptRoot } else { $AssetRoot }
    # Legacy no-argument uninstall needs no downloaded helpers.
    $Lang = 'zh-CN'
    $DryRun = $false
    if ($args.Count -gt 0) {
        . (Join-Path $sourceRoot 'lib\options.ps1')
        $options = Read-AgyOptions -Arguments $args -Switches @('--purge','-Purge','--dry-run','-DryRun')
        if ($options.Help) {
            Write-Host 'uninstall.ps1 [--lang <code>] [--purge] [--dry-run] (default: zh-CN)'
            return
        }
        $Lang = $options.Lang
        $Purge = $Purge -or $options.purge
        $DryRun = $options.dryrun
    }
    $PluginName = 'antigravity-zh-prompt'
    $ShortcutName = Resolve-ZhText 'Antigravity \u4e2d\u6587.lnk'
    $CommandName = 'agy-zh'
    if (Test-Path (Join-Path $sourceRoot 'locales\index.json')) {
        $index = Get-Content -Raw -Encoding UTF8 (Join-Path $sourceRoot 'locales\index.json') | ConvertFrom-Json
        $meta = $index.$Lang
        $PluginName = $meta.pluginName
        $ShortcutName = $meta.appName + '.lnk'
        $CommandName = $meta.command
    }
    $HansExe = Join-Path $BinDir 'antigravity-hans.exe'
    $BaseOverlay = Join-Path $BinDir 'antigravity-hans-overlay.base.js'
    $OverlayJs = Join-Path $BinDir $(if ($Lang -eq 'zh-CN') { 'antigravity-hans-overlay.js' } else { 'antigravity-' + $Lang + '-overlay.js' })
    $AgyZhPs1 = Join-Path $BinDir 'agy-zh.ps1'
    $PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $ConfigDir = if ($env:GEMINI_CONFIG_DIR) { $env:GEMINI_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.gemini\config' }
    $ConfigFile = Join-Path $ConfigDir 'config.json'
    $PluginDir = Join-Path $ConfigDir "plugins\$PluginName"
    if ($DryRun) { Write-Host "[dry-run] $Lang -> $ShortcutName / $PluginDir; purge=$Purge"; return }

    if (Test-Path $AgyZhPs1) {
        try {
            if (Test-Path $AssetRoot) { & $PsExe -NoProfile -ExecutionPolicy Bypass -File $AgyZhPs1 --lang $Lang stop | Out-Null }
            elseif ($Lang -eq 'zh-CN') { & $PsExe -NoProfile -ExecutionPolicy Bypass -File $AgyZhPs1 stop | Out-Null }
        } catch {}
    } elseif ($Lang -eq 'zh-CN' -and (Test-Path $HansExe)) {
        try { & $HansExe --stop --app 2>$null | Out-Null } catch {}
    }

    if (Test-Path $ConfigFile) {
        try {
            $raw = Get-Content -Raw -Encoding UTF8 -Path $ConfigFile
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $data = $raw | ConvertFrom-Json
                if ($null -ne $data -and ($data.PSObject.Properties.Name -contains 'plugins') -and $null -ne $data.plugins) {
                    if ($data.plugins.PSObject.Properties.Name -contains $PluginName) {
                        $data.plugins.PSObject.Properties.Remove($PluginName)
                        $json = ($data | ConvertTo-Json -Depth 20) + "`n"
                        $tmpPath = Join-Path $ConfigDir ('.config.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
                        [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.UTF8Encoding]::new($false))
                        Move-Item -Force $tmpPath $ConfigFile
                        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u4ece config.json \u79fb\u9664 antigravity-zh-prompt \u8bb0\u5f55:') $ConfigFile"
                    }
                }
            }
        } catch { throw "Could not update config.json: $_" }
    }

    if (Test-Path $PluginDir) {
        Remove-Item -Recurse -Force $PluginDir
        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u5220\u9664\u63d2\u4ef6\u76ee\u5f55:') $PluginDir"
    }

    foreach ($dir in @(([Environment]::GetFolderPath('Desktop')), ([Environment]::GetFolderPath('Programs')))) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $lnkPath = Join-Path $dir $ShortcutName
        if (Test-Path $lnkPath) {
            Remove-Item -Force $lnkPath
            Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u5220\u9664\u5feb\u6377\u65b9\u5f0f:') $lnkPath"
        }
    }

    $marker = Join-Path $AssetRoot "installed\$Lang"
    if (Test-Path $marker) { Remove-Item -Force $marker }
    $vbsName = if ($Lang -eq 'zh-CN') { 'agy-zh-launch.vbs' } else { $CommandName + '-launch.vbs' }
    $files = @($OverlayJs, (Join-Path $BinDir $vbsName))
    if ($Lang -ne 'zh-CN') { $files += Join-Path $BinDir ($CommandName + '.cmd') }
    if ($Lang -eq 'zh-CN') { $files += $HansExe; if ($Purge) { $files += $BaseOverlay } }
    foreach ($file in $files) { if (Test-Path $file) { Remove-Item -Force $file } }
    $pidName = if ($Lang -eq 'zh-CN') { 'watcher.pid' } else { $CommandName + '.pid' }
    $pidPath = Join-Path $InstallRoot "logs\$pidName"
    if (Test-Path $pidPath) { Remove-Item -Force $pidPath }
    $logName = if ($Lang -eq 'zh-CN') { 'agy-zh.log' } else { $CommandName + '.log' }
    $logPath = Join-Path $InstallRoot "logs\$logName"
    foreach ($lf in @($logPath, ($logPath + '.1'))) {
        if (Test-Path $lf) { Remove-Item -Force $lf }
    }
    $installedDir = Join-Path $AssetRoot 'installed'
    $remaining = @(if (Test-Path $installedDir) { Get-ChildItem -File $installedDir })
    if ($remaining.Count -eq 0) {
        foreach ($file in @($AgyZhPs1, (Join-Path $BinDir 'agy-zh.cmd'))) { if (Test-Path $file) { Remove-Item -Force $file } }
        if (Test-Path $AssetRoot) { Remove-Item -Recurse -Force $AssetRoot }
        $userPath = [Environment]::GetEnvironmentVariable('Path','User')
        if ($userPath) {
            $kept = @($userPath -split ';' | Where-Object { $_ -and $_.Trim().TrimEnd('\') -ine $BinDir.TrimEnd('\') })
            [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
        }
        if ($Purge -and (Test-Path $InstallRoot)) { Remove-Item -Recurse -Force $InstallRoot }
    }
    Write-Host ''
    Write-Host (Resolve-ZhText '\u5378\u8f7d\u5b8c\u6210\u3002\u539f\u7248 Antigravity \u4fdd\u6301\u5b8c\u6574\u65e0\u635f\u3002')
} @args
