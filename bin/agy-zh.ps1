# UTF-8 BOM is retained for Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$AssetRoot = if (Test-Path (Join-Path $PSScriptRoot '..\locales\index.json')) {
    Split-Path -Parent $PSScriptRoot
} else { Join-Path $PSScriptRoot 'agy-i18n' }
. (Join-Path $AssetRoot 'lib\options.ps1')
$options = Read-AgyOptions -Arguments $args -Runtime
$Lang = $options.Lang
$SubCommand = if ($options.Help) { 'help' } elseif ($options.Rest.Count) { $options.Rest[0] } else { 'start' }
$RestArgs = @($options.Rest | Select-Object -Skip 1)
$index = Get-Content -Raw -Encoding UTF8 (Join-Path $AssetRoot 'locales\index.json') | ConvertFrom-Json
$meta = $index.$Lang
. (Join-Path $AssetRoot 'lib\locale.ps1')
. (Join-Path $AssetRoot 'lib\zh-overlay.ps1')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

function Resolve-ZhText {
    param([string]$Text)
    $value = [regex]::Unescape($Text)
    if ($Lang -ne 'zh-CN') {
        $value = $value.Replace('Antigravity 中文', $meta.appName).Replace('antigravity-zh-prompt', $PluginName).Replace('中文', $meta.name)
    }
    return $value
}

$TagInfo = Resolve-ZhText '[\u4fe1\u606f]'
$TagOk   = Resolve-ZhText '[\u6210\u529f]'
$TagWarn = Resolve-ZhText '[\u63d0\u793a]'
$OverlayVersion = 'agy-zh-v5'
$ShortcutName   = $meta.appName + '.lnk'
$OverlayUrl     = if ($env:AGY_ZH_OVERLAY_URL) { $env:AGY_ZH_OVERLAY_URL } else { 'https://raw.githubusercontent.com/yuexps/Antigravity-Hans/main/antigravity-hans-overlay.js' }
$PluginName     = $meta.pluginName
$ConfigDir      = if ($env:GEMINI_CONFIG_DIR) { $env:GEMINI_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.gemini\config' }
$ConfigFile     = Join-Path $ConfigDir 'config.json'
$PluginDir      = Join-Path $ConfigDir "plugins\$PluginName"
$InstallRoot    = Split-Path -Parent $PSScriptRoot
$LogsDir        = Join-Path $InstallRoot 'logs'
$WatcherPidFile = Join-Path $LogsDir $(if ($Lang -eq 'zh-CN') { 'watcher.pid' } else { $meta.command + '.pid' })
$BaseOverlayJs  = Join-Path $PSScriptRoot 'antigravity-hans-overlay.base.js'
$OverlayJs      = Join-Path $PSScriptRoot $(if ($Lang -eq 'zh-CN') { 'antigravity-hans-overlay.js' } else { 'antigravity-' + $Lang + '-overlay.js' })

$script:CdpHttpHandler = [System.Net.Http.HttpClientHandler]::new()
$script:CdpHttpHandler.UseProxy = $false
$script:CdpHttpClient = [System.Net.Http.HttpClient]::new($script:CdpHttpHandler)
$script:CdpHttpClient.Timeout = [TimeSpan]::FromMilliseconds(1500)
$script:CdpCmdId = 1

function Set-ZhPluginEnabled {
    param([bool]$Enabled)
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $data = [PSCustomObject]@{}
    if (Test-Path $ConfigFile) {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $ConfigFile
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $parsed = $raw | ConvertFrom-Json
            if ($null -ne $parsed) { $data = $parsed }
        }
    }
    if (-not ($data.PSObject.Properties.Name -contains 'plugins') -or $null -eq $data.plugins) {
        $data | Add-Member -NotePropertyName 'plugins' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if ($Enabled) {
        foreach ($item in $index.PSObject.Properties) {
            $other = $item.Value.pluginName
            if ($other -ne $PluginName -and $data.plugins.PSObject.Properties.Name -contains $other) {
                $data.plugins.$other | Add-Member -NotePropertyName enabled -NotePropertyValue $false -Force
            }
        }
    }
    $entry = $null
    if ($data.plugins.PSObject.Properties.Name -contains $PluginName) {
        $entry = $data.plugins.$PluginName
    }
    if ($null -eq $entry) {
        $entry = [PSCustomObject]@{}
        $data.plugins | Add-Member -NotePropertyName $PluginName -NotePropertyValue $entry -Force
    }
    $entry | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $Enabled -Force

    $json = ($data | ConvertTo-Json -Depth 20) + "`n"
    $tmpPath = Join-Path $ConfigDir ('.config.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Force $tmpPath $ConfigFile
}

function Get-ZhPluginEnabled {
    if (Test-Path $ConfigFile) {
        try {
            $data = Get-Content -Raw -Encoding UTF8 -Path $ConfigFile | ConvertFrom-Json
            if ($null -ne $data.plugins -and ($data.plugins.PSObject.Properties.Name -contains $PluginName)) {
                $val = $data.plugins.$PluginName.enabled
                if ($val -is [bool]) { return $val }
            }
        } catch {}
    }
    $pluginJson = Join-Path $PluginDir 'plugin.json'
    if (Test-Path $pluginJson) {
        try {
            $pdata = Get-Content -Raw -Encoding UTF8 -Path $pluginJson | ConvertFrom-Json
            if ($pdata.disabled -eq $true) { return $false }
            return $true
        } catch {}
    }
    return $false
}

function Get-ActiveWatcherPids {
    if (-not (Test-Path $WatcherPidFile)) { return @() }
    try {
        $watcherId = [int](Get-Content -Raw $WatcherPidFile).Trim()
        if ($watcherId -eq $PID) { return @() }
        $p = Get-CimInstance Win32_Process -Filter "ProcessId = $watcherId" -ErrorAction SilentlyContinue
        if ($p -and $p.CommandLine -match 'agy-zh\.ps1') { return @($watcherId) }
    } catch {}
    return @()
}

function Stop-PreviousLanguageWatchers {
    foreach ($item in $index.PSObject.Properties) {
        $pidPath = Join-Path $LogsDir $(if ($item.Name -eq 'zh-CN') { 'watcher.pid' } else { $item.Value.command + '.pid' })
        if (Test-Path $pidPath) {
            try {
                $watcherId = [int](Get-Content -Raw $pidPath).Trim()
                $p = Get-CimInstance Win32_Process -Filter "ProcessId = $watcherId" -ErrorAction SilentlyContinue
                if ($watcherId -ne $PID -and $p -and $p.CommandLine -match 'agy-zh\.ps1') {
                    Stop-Process -Id $watcherId -Force -ErrorAction Stop
                    Wait-Process -Id $watcherId -Timeout 10 -ErrorAction SilentlyContinue
                }
            } catch { throw "Could not stop previous language session: $_" }
        }
    }
}

function Test-ActiveWatcher {
    return (@(Get-ActiveWatcherPids).Count -gt 0)
}

function Find-OriginalExe {
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\Antigravity.exe') }
    if (${env:ProgramFiles}) {
        $candidates += (Join-Path ${env:ProgramFiles} 'Antigravity\Antigravity.exe')
        $candidates += (Join-Path ${env:ProgramFiles} 'Google Antigravity\Antigravity.exe')
    }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Antigravity\Antigravity.exe') }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }

    try {
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($dir in @(([Environment]::GetFolderPath('Desktop')), ([Environment]::GetFolderPath('Programs')))) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $lnk = Join-Path $dir 'Antigravity.lnk'
            if (Test-Path $lnk) {
                $target = $wsh.CreateShortcut($lnk).TargetPath
                if ($target -and $target.EndsWith('\Antigravity.exe', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $target)) {
                    return $target
                }
            }
        }
    } catch {}

    foreach ($regPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            $items = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Antigravity*' }
            foreach ($item in $items) {
                if (-not [string]::IsNullOrWhiteSpace($item.InstallLocation)) {
                    $exeFromLoc = Join-Path $item.InstallLocation.Trim().Trim('"') 'Antigravity.exe'
                    if (Test-Path $exeFromLoc) { return $exeFromLoc }
                }
                if (-not [string]::IsNullOrWhiteSpace($item.DisplayIcon)) {
                    $exeFromIcon = ($item.DisplayIcon.Trim() -replace ',\s*-?\d+$', '').Trim().Trim('"')
                    if ($exeFromIcon -and $exeFromIcon.EndsWith('\Antigravity.exe', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $exeFromIcon)) {
                        return $exeFromIcon
                    }
                }
            }
        } catch {}
    }

    return $null
}

function Get-SameSessionAntigravityPids {
    $mySession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $pids = [int[]]@(
        Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $mySession } |
            ForEach-Object { [int]$_.Id }
    )
    return $pids
}

function Test-VisibleWindowForPids {
    param([int[]]$TargetPids)
    if ($null -eq $TargetPids -or $TargetPids.Count -eq 0) { return $false }
    $win32Code = @(
        'using System;',
        'using System.Runtime.InteropServices;',
        'public static class AgyWin32 {',
        '    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);',
        '    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);',
        '    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);',
        '    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);',
        '    public static bool HasVisibleWindow(int[] targetPids) {',
        '        if (targetPids == null || targetPids.Length == 0) return false;',
        '        bool found = false;',
        '        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {',
        '            if (!IsWindowVisible(hWnd)) return true;',
        '            uint pid = 0;',
        '            if (GetWindowThreadProcessId(hWnd, out pid) != 0 && Array.IndexOf(targetPids, (int)pid) >= 0) {',
        '                found = true;',
        '                return false;',
        '            }',
        '            return true;',
        '        }, IntPtr.Zero);',
        '        return found;',
        '    }',
        '}'
    ) -join "`n"
    if (-not ('AgyWin32' -as [type])) {
        try { Add-Type -TypeDefinition $win32Code -ErrorAction Stop } catch {}
    }
    if ('AgyWin32' -as [type]) {
        return [AgyWin32]::HasVisibleWindow($TargetPids)
    }
    return (@(Get-Process -Id $TargetPids -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count -gt 0)
}

function Invoke-LocalCdpJson {
    param(
        [int]$Port,
        [string]$Path
    )
    if ($Port -le 0 -or $Port -gt 65535) { return $null }
    try {
        $json = $script:CdpHttpClient.GetStringAsync("http://127.0.0.1:$Port$Path").GetAwaiter().GetResult()
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }
        return ($json | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-DebugAntigravityPort {
    $pids = @(Get-SameSessionAntigravityPids)
    if ($pids.Count -eq 0) { return 0 }
    $cimProcs = @(Get-CimInstance Win32_Process -Filter "Name = 'Antigravity.exe'" -ErrorAction SilentlyContinue)
    foreach ($p in $cimProcs) {
        if ($pids -contains [int]$p.ProcessId -and $p.CommandLine -match '--remote-debugging-port=(\d+)') {
            $port = [int]$Matches[1]
            $ver = Invoke-LocalCdpJson -Port $port -Path '/json/version'
            if ($null -ne $ver) {
                return $port
            }
        }
    }
    return 0
}

function Stop-AntigravityProcessesByIds {
    param([int[]]$TargetPids)
    if ($null -eq $TargetPids -or $TargetPids.Count -eq 0) { return }
    Stop-Process -Id $TargetPids -Force -ErrorAction SilentlyContinue
    foreach ($id in $TargetPids) {
        if (Get-Process -Id $id -ErrorAction SilentlyContinue) {
            try { & taskkill.exe /F /PID $id 2>$null | Out-Null } catch {}
        }
    }
    for ($i = 0; $i -lt 25; $i++) {
        if (@(Get-SameSessionAntigravityPids).Count -eq 0) { break }
        Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Milliseconds 500
}

function Prepare-AntigravityForZhLaunch {
    param([bool]$NoGui = $false)
    if ((Get-DebugAntigravityPort) -gt 0) {
        return $true
    }
    $pids = @(Get-SameSessionAntigravityPids)
    if ($pids.Count -eq 0) { return $true }

    $hasVisible = Test-VisibleWindowForPids -TargetPids $pids
    if (-not $hasVisible) {
        if (-not $NoGui) {
            $pidText = ($pids -join ', ')
            Write-Host "$TagWarn $(Resolve-ZhText '\u68c0\u6d4b\u5230 Antigravity \u65e0\u754c\u9762\u540e\u53f0\u8fdb\u7a0b') (PID: $pidText)$(Resolve-ZhText '\uff0c\u6b63\u5728\u81ea\u52a8\u6e05\u7406...')"
        }
        Stop-AntigravityProcessesByIds -TargetPids $pids
        return $true
    }

    if ($NoGui) {
        $wsh = New-Object -ComObject WScript.Shell
        $msg = Resolve-ZhText '\u68c0\u6d4b\u5230\u539f\u7248 Antigravity \u7a97\u53e3\u6b63\u5728\u8fd0\u884c\uff08\u672a\u5f00\u542f\u4e2d\u6587\u8c03\u8bd5\u7aef\u53e3\uff09\u3002\n\n\u662f\u5426\u4fdd\u5b58\u72b6\u6001\u5e76\u91cd\u542f\u4e3a\u300cAntigravity \u4e2d\u6587\u300d\uff1f'
        $title = Resolve-ZhText 'Antigravity \u4e2d\u6587'
        $ans = $wsh.Popup($msg, 0, $title, 0x1024)
        if ($ans -ne 6) { return $false }
    } else {
        Write-Host "$TagWarn $(Resolve-ZhText '\u6b63\u5728\u8bf7\u6c42\u5df2\u8fd0\u884c\u7684 Antigravity \u4fdd\u5b58\u72b6\u6001\u5e76\u9000\u51fa...')"
    }

    foreach ($id in $pids) {
        try { & taskkill.exe /PID $id 2>$null | Out-Null } catch {}
    }
    for ($i = 0; $i -lt 25; $i++) {
        $cur = @(Get-SameSessionAntigravityPids)
        if ($cur.Count -eq 0) { return $true }
        if (-not (Test-VisibleWindowForPids -TargetPids $cur)) { break }
        Start-Sleep -Milliseconds 200
    }
    $rem = @(Get-SameSessionAntigravityPids)
    if ($rem.Count -gt 0 -and ($NoGui -or -not (Test-VisibleWindowForPids -TargetPids $rem))) {
        Stop-AntigravityProcessesByIds -TargetPids $rem
    }
    return $true
}

function Get-FreeLoopbackPort {
    foreach ($p in 58321..58325) {
        $listener = $null
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
            $listener.Start()
            return $p
        } catch {
        } finally {
            if ($null -ne $listener) {
                try { $listener.Stop() } catch {}
            }
        }
    }
    throw (Resolve-ZhText '\u5019\u9009\u8c03\u8bd5\u7aef\u53e3 (58321-58325) \u5747\u88ab\u5360\u7528\u3002')
}

function Test-ValidCdpWsUrl {
    param(
        [string]$WsUrl,
        [int]$ExpectedPort
    )
    if ([string]::IsNullOrWhiteSpace($WsUrl)) { return $false }
    try {
        $u = [Uri]$WsUrl
        if ($u.Scheme -ne 'ws') { return $false }
        $h = $u.Host.ToLowerInvariant()
        if ($h -ne '127.0.0.1' -and $h -ne 'localhost') { return $false }
        if ($u.Port -ne $ExpectedPort) { return $false }
        return ($u.AbsolutePath.StartsWith('/devtools/page/') -or $u.AbsolutePath.StartsWith('/devtools/browser/'))
    } catch {
        return $false
    }
}

function Test-CdpTargetMatch {
    param([object]$Target)
    if ($null -eq $Target) { return $false }
    $tType = [string]$Target.type
    if ($tType -in @('worker', 'service_worker', 'shared_worker', 'background_page')) { return $false }
    $rawUrl = [string]$Target.url
    if ([string]::IsNullOrWhiteSpace($rawUrl)) { return $false }
    $lower = $rawUrl.ToLowerInvariant()
    if ($lower.StartsWith('data:text/html')) { return $true }
    try {
        $u = [Uri]$rawUrl
        if (($u.Scheme -eq 'http' -or $u.Scheme -eq 'https') -and [string]::IsNullOrEmpty($u.UserInfo)) {
            $h = $u.Host.ToLowerInvariant()
            if ($h -eq '127.0.0.1' -or $h -eq 'localhost' -or $h -eq '::1') { return $true }
        }
        if ($tType -eq 'iframe' -and $u.Scheme -eq 'plugin' -and [string]::IsNullOrEmpty($u.UserInfo) -and $u.IsDefaultPort -and ($u.AbsolutePath -eq '' -or $u.AbsolutePath -eq '/') -and [string]::IsNullOrEmpty($u.Query) -and [string]::IsNullOrEmpty($u.Fragment)) {
            if ($u.Host.ToLowerInvariant() -match '^swarm--swarm_board-[a-z0-9]{5}$') { return $true }
        }
    } catch {}
    return $false
}

function Connect-LocalWebSocket {
    param([string]$WsUrl)
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    try { $ws.Options.Proxy = $null } catch {}
    $cts = [System.Threading.CancellationTokenSource]::new(5000)
    try {
        $null = $ws.ConnectAsync([Uri]$WsUrl, $cts.Token).GetAwaiter().GetResult()
        return $ws
    } catch {
        $ws.Dispose()
        throw
    } finally {
        $cts.Dispose()
    }
}

function Invoke-CdpWsCommand {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Ws,
        [string]$Method,
        [object]$Params = @{}
    )
    $cmdId = $script:CdpCmdId
    $script:CdpCmdId++
    $payloadObj = @{
        id     = $cmdId
        method = $Method
        params = $Params
    }
    $jsonText = $payloadObj | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
    $sendSeg = [System.ArraySegment[byte]]::new($bytes)
    $cts = [System.Threading.CancellationTokenSource]::new(8000)
    $recvBuf = New-Object byte[] 65536
    $recvSeg = [System.ArraySegment[byte]]::new($recvBuf)
    $ms = [System.IO.MemoryStream]::new()
    try {
        $null = $Ws.SendAsync($sendSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
        while ($true) {
            $ms.SetLength(0)
            do {
                $res = $Ws.ReceiveAsync($recvSeg, $cts.Token).GetAwaiter().GetResult()
                if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    throw 'WebSocket closed'
                }
                if ($res.Count -gt 0) {
                    $ms.Write($recvBuf, 0, $res.Count)
                }
            } while (-not $res.EndOfMessage)

            $msgText = [System.Text.Encoding]::UTF8.GetString($ms.GetBuffer(), 0, [int]$ms.Length)
            $msg = $msgText | ConvertFrom-Json
            if ($null -ne $msg -and ($msg.PSObject.Properties.Name -contains 'id') -and [int]$msg.id -eq $cmdId) {
                if ($msg.PSObject.Properties.Name -contains 'error' -and $null -ne $msg.error) {
                    throw "CDP $Method error: $($msg.error.message)"
                }
                if ($null -ne $msg.result -and ($msg.result.PSObject.Properties.Name -contains 'exceptionDetails') -and $null -ne $msg.result.exceptionDetails) {
                    throw "Runtime.evaluate exception: $($msg.result.exceptionDetails.text)"
                }
                return $msg.result
            }
        }
    } finally {
        $ms.Dispose()
        $cts.Dispose()
    }
}

function Invoke-InjectTarget {
    param(
        [object]$Target,
        [int]$Port,
        [string]$OverlaySource,
        [string]$Fingerprint
    )
    if (-not (Test-CdpTargetMatch -Target $Target)) { return $false }
    $tid = [string]$Target.id
    if ([string]::IsNullOrWhiteSpace($tid)) { return $false }
    $wsUrl = if ($Target.webSocketDebuggerUrl) { [string]$Target.webSocketDebuggerUrl } else { "ws://127.0.0.1:$Port/devtools/page/$tid" }
    if (-not (Test-ValidCdpWsUrl -WsUrl $wsUrl -ExpectedPort $Port)) { return $false }

    $u = $null
    try { $u = [Uri]([string]$Target.url) } catch {}
    $isSwarm = ($null -ne $u -and ([string]$Target.type) -eq 'iframe' -and $u.Scheme -eq 'plugin')

    $ws = $null
    try {
        $ws = Connect-LocalWebSocket -WsUrl $wsUrl
        $fpJson = $Fingerprint | ConvertTo-Json -Compress
        $checkExpr = "window.__antigravityZhPatchInstalled === true && window.__observedDocument === document && window.__antigravityZhPatchFingerprint === $fpJson"

        $chk = Invoke-CdpWsCommand -Ws $ws -Method 'Runtime.evaluate' -Params @{ expression = $checkExpr; returnByValue = $true }
        if ($null -ne $chk -and $null -ne $chk.result -and $chk.result.value -eq $true) {
            return $true
        }

        $wrapped = "window.__antigravityZhPatchRequestedFingerprint = $fpJson;`n$OverlaySource"
        if ($isSwarm) {
            $hostJson = $u.Host | ConvertTo-Json -Compress
            $wrapped = "(() => { if (location.protocol !== 'plugin:' || location.hostname !== $hostJson || (location.pathname !== '/' && location.pathname !== '') || !document.querySelector('[data-testid=`"swarm-tabs`"]') || !document.querySelector('[data-testid=`"swarm-empty-state`"]')) return;`n$wrapped`n})()"
        } else {
            try { $null = Invoke-CdpWsCommand -Ws $ws -Method 'Page.enable' -Params @{} } catch {}
            $null = Invoke-CdpWsCommand -Ws $ws -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{ source = $wrapped }
        }

        $null = Invoke-CdpWsCommand -Ws $ws -Method 'Runtime.evaluate' -Params @{ expression = $wrapped; awaitPromise = $false }
        $verify = Invoke-CdpWsCommand -Ws $ws -Method 'Runtime.evaluate' -Params @{ expression = $checkExpr; returnByValue = $true }
        return ($null -ne $verify -and $null -ne $verify.result -and $verify.result.value -eq $true)
    } finally {
        if ($null -ne $ws) {
            try { $ws.Dispose() } catch {}
        }
    }
}

function Start-CdpWatchLoop {
    param(
        [bool]$NoGui = $false
    )
    $overlaySource = [System.IO.File]::ReadAllText($OverlayJs, [System.Text.Encoding]::UTF8)
    $fingerprint = (Get-FileHash -Algorithm SHA256 -Path $OverlayJs).Hash.ToLowerInvariant().Substring(0, 16)

    $port = Get-DebugAntigravityPort
    if ($port -gt 0) {
        Write-Host "$TagInfo $(Resolve-ZhText '\u68c0\u6d4b\u5230 Antigravity \u5df2\u4ee5\u4e2d\u6587\u8c03\u8bd5\u6a21\u5f0f\u8fd0\u884c (\u7aef\u53e3') $port$(Resolve-ZhText ')\uff0c\u76f4\u63a5\u9644\u7740\u76d1\u89c6\u3002')"
    } else {
        $origExe = Find-OriginalExe
        if (-not $origExe) {
            throw (Resolve-ZhText '\u672a\u627e\u5230 Antigravity.exe \u5b89\u88c5\u8def\u5f84\u3002')
        }
        $port = Get-FreeLoopbackPort
        Write-Host "$TagInfo $(Resolve-ZhText '\u6b63\u5728\u542f\u52a8 Antigravity \u4e2d\u6587\u8c03\u8bd5\u4f1a\u8bdd (\u7aef\u53e3') $port)..."
        $null = Start-Process -FilePath $origExe -ArgumentList @("--remote-debugging-port=$port", '--remote-debugging-address=127.0.0.1') -WorkingDirectory (Split-Path -Parent $origExe) -PassThru
        $ready = $false
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($null -ne (Invoke-LocalCdpJson -Port $port -Path '/json/version')) {
                $ready = $true
                break
            }
            Start-Sleep -Milliseconds 300
        }
        if (-not $ready) {
            throw "$(Resolve-ZhText '\u7b49\u5f85 Antigravity \u8c03\u8bd5\u7aef\u53e3\u5c31\u7eea\u8d85\u65f6 (\u7aef\u53e3:') $port)"
        }
    }

    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    [System.IO.File]::WriteAllText($WatcherPidFile, "$PID`n", [System.Text.UTF8Encoding]::new($false))

    $injectedSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $sweepTargets = {
        $targets = Invoke-LocalCdpJson -Port $port -Path '/json/list'
        if ($null -ne $targets) {
            foreach ($t in $targets) {
                $tid = [string]$t.id
                if ([string]::IsNullOrWhiteSpace($tid) -or $injectedSet.Contains($tid)) { continue }
                try {
                    if (Invoke-InjectTarget -Target $t -Port $port -OverlaySource $overlaySource -Fingerprint $fingerprint) {
                        $null = $injectedSet.Add($tid)
                    }
                } catch {}
            }
        }
    }

    $connectBrowser = {
        $ver = Invoke-LocalCdpJson -Port $port -Path '/json/version'
        if ($null -eq $ver -or -not (Test-ValidCdpWsUrl -WsUrl ([string]$ver.webSocketDebuggerUrl) -ExpectedPort $port)) {
            return $null
        }
        $bws = Connect-LocalWebSocket -WsUrl ([string]$ver.webSocketDebuggerUrl)
        $discoverJson = '{"id":1,"method":"Target.setDiscoverTargets","params":{"discover":true}}'
        $dBytes = [System.Text.Encoding]::UTF8.GetBytes($discoverJson)
        $dSeg = [System.ArraySegment[byte]]::new($dBytes)
        $dCts = [System.Threading.CancellationTokenSource]::new(3000)
        try {
            $null = $bws.SendAsync($dSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $dCts.Token).GetAwaiter().GetResult()
        } finally {
            $dCts.Dispose()
        }
        return $bws
    }

    $browserWs = $null
    try {
        & $sweepTargets
        for ($i = 0; $i -lt 15; $i++) {
            try {
                $browserWs = & $connectBrowser
                if ($null -ne $browserWs) { break }
            } catch {}
            Start-Sleep -Milliseconds 300
        }
        if ($null -eq $browserWs) {
            throw "$(Resolve-ZhText '\u65e0\u6cd5\u5efa\u7acb\u672c\u5730 CDP \u4e8b\u4ef6\u8fde\u63a5 (\u7aef\u53e3:') $port)"
        }

        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u8fdb\u5165 Antigravity \u4e2d\u6587\u76d1\u89c6\u72b6\u6001 (\u7aef\u53e3') $port$(Resolve-ZhText ')\u3002')"
        $bBuf = New-Object byte[] 65536
        $bSeg = [System.ArraySegment[byte]]::new($bBuf)
        $msgMs = [System.IO.MemoryStream]::new()
        $loopCts = [System.Threading.CancellationTokenSource]::new()
        $recvTask = $browserWs.ReceiveAsync($bSeg, $loopCts.Token)
        $lastSweep = [DateTime]::UtcNow

        try {
            while ($true) {
                $signaled = $false
                try {
                    $signaled = $recvTask.Wait(1500)
                } catch {
                    $signaled = $true
                }

                if ($signaled) {
                    $wsBroken = $false
                    try {
                        $r = $recvTask.GetAwaiter().GetResult()
                        if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                            $wsBroken = $true
                        } else {
                            if ($r.Count -gt 0) { $msgMs.Write($bBuf, 0, $r.Count) }
                            if ($r.EndOfMessage) {
                                $txt = [System.Text.Encoding]::UTF8.GetString($msgMs.GetBuffer(), 0, [int]$msgMs.Length)
                                $msgMs.SetLength(0)
                                try {
                                    $evt = $txt | ConvertFrom-Json
                                    if ($evt.method -eq 'Target.targetDestroyed') {
                                        $null = $injectedSet.Remove([string]$evt.params.targetId)
                                    } elseif ($evt.method -eq 'Target.targetCreated' -or $evt.method -eq 'Target.targetInfoChanged') {
                                        $info = $evt.params.targetInfo
                                        $tid = [string]$info.targetId
                                        if ($tid -and -not $injectedSet.Contains($tid)) {
                                            $tObj = [PSCustomObject]@{
                                                id                   = $tid
                                                type                 = [string]$info.type
                                                url                  = [string]$info.url
                                                webSocketDebuggerUrl = "ws://127.0.0.1:$port/devtools/page/$tid"
                                            }
                                            try {
                                                if (Invoke-InjectTarget -Target $tObj -Port $port -OverlaySource $overlaySource -Fingerprint $fingerprint) {
                                                    $null = $injectedSet.Add($tid)
                                                }
                                            } catch {}
                                        }
                                    }
                                } catch {}
                            }
                            $recvTask = $browserWs.ReceiveAsync($bSeg, $loopCts.Token)
                        }
                    } catch {
                        $wsBroken = $true
                    }

                    if ($wsBroken) {
                        try { $loopCts.Cancel() } catch {}
                        try { $browserWs.Dispose() } catch {}
                        $loopCts.Dispose()
                        $msgMs.SetLength(0)
                        $browserWs = $null

                        $reconnected = $false
                        $backoffMs = 500
                        $rcDeadline = [DateTime]::UtcNow.AddSeconds(30)
                        while ([DateTime]::UtcNow -lt $rcDeadline) {
                            if (@(Get-SameSessionAntigravityPids).Count -eq 0 -and $null -eq (Invoke-LocalCdpJson -Port $port -Path '/json/version')) {
                                break
                            }
                            Start-Sleep -Milliseconds $backoffMs
                            try {
                                $browserWs = & $connectBrowser
                                if ($null -ne $browserWs) {
                                    $reconnected = $true
                                    break
                                }
                            } catch {}
                            $backoffMs = [Math]::Min($backoffMs * 2, 5000)
                        }
                        if (-not $reconnected) { break }
                        $loopCts = [System.Threading.CancellationTokenSource]::new()
                        $recvTask = $browserWs.ReceiveAsync($bSeg, $loopCts.Token)
                        & $sweepTargets
                    }
                }

                if (([DateTime]::UtcNow - $lastSweep).TotalSeconds -ge 2) {
                    $lastSweep = [DateTime]::UtcNow
                    & $sweepTargets
                    if (@(Get-SameSessionAntigravityPids).Count -eq 0 -and $null -eq (Invoke-LocalCdpJson -Port $port -Path '/json/version')) {
                        break
                    }
                }
            }
        } finally {
            try { $loopCts.Cancel() } catch {}
            try { $loopCts.Dispose() } catch {}
            $msgMs.Dispose()
        }
    } finally {
        if ($null -ne $browserWs) {
            try { $browserWs.Dispose() } catch {}
        }
        try {
            if ((Test-Path $WatcherPidFile) -and ((Get-Content -Raw -Path $WatcherPidFile -ErrorAction SilentlyContinue).Trim() -eq "$PID")) {
                Remove-Item -Force -Path $WatcherPidFile -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function New-ZhShortcut {
    $targets = @(
        ([Environment]::GetFolderPath('Desktop')),
        ([Environment]::GetFolderPath('Programs'))
    )
    $wsh = New-Object -ComObject WScript.Shell
    $vbsName = if ($Lang -eq 'zh-CN') { 'agy-zh-launch.vbs' } else { $meta.command + '-launch.vbs' }
    $vbsPath = Join-Path $PSScriptRoot $vbsName
    $vbsText = @(
        'Option Explicit',
        'Dim fso, shell, dir, psExe, scriptPath, cmd',
        'Set fso = CreateObject("Scripting.FileSystemObject")',
        'Set shell = CreateObject("WScript.Shell")',
        'dir = fso.GetParentFolderName(WScript.ScriptFullName)',
        'psExe = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")',
        'scriptPath = fso.BuildPath(dir, "agy-zh.ps1")',
        ('cmd = """" & psExe & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & scriptPath & """ start --lang ' + $Lang + ' --nogui"'),
        'shell.Run cmd, 0, False'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($vbsPath, $vbsText, [System.Text.Encoding]::ASCII)
    $origExe = Find-OriginalExe
    $desc = $meta.appName + ' (' + $Lang + ')'
    $wscriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'

    foreach ($dir in $targets) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $lnkPath = Join-Path $dir $ShortcutName
        $sc = $wsh.CreateShortcut($lnkPath)
        $sc.TargetPath = $wscriptExe
        $sc.Arguments = "//B //NoLogo `"$vbsPath`""
        $sc.WorkingDirectory = $PSScriptRoot
        $sc.WindowStyle = 7
        if ($origExe) {
            $sc.IconLocation = "$origExe,0"
        }
        $sc.Description = $desc
        $sc.Save()
        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u521b\u5efa\u300cAntigravity \u4e2d\u6587\u300d\u5feb\u6377\u65b9\u5f0f:') $lnkPath"
    }
}

$allowed = switch ($SubCommand.ToLowerInvariant()) {
    'start' { @('--nogui') }
    'build-overlay' { @('--force') }
    'prompt' { @('on','off','status') }
    { $_ -in @('stop','status','shortcut','help') } { @() }
    default { throw "Unknown command: $SubCommand. Use agy-zh help." }
}
foreach ($arg in $RestArgs) { if ($arg -notin $allowed) { throw "Unsupported argument: $arg" } }
if ($SubCommand -eq 'prompt' -and $RestArgs.Count -gt 1) { throw 'Usage: agy-zh prompt <on|off|status>' }
if ($SubCommand -eq 'help') {
    Write-Host 'agy-zh [start|stop|status|prompt <on|off|status>|build-overlay [--force]|shortcut] [--lang <code>]'
    Write-Host 'Languages: zh-CN zh-TW ja ko es fr de ru pt-BR (default: zh-CN)'
    return
}
switch ($SubCommand.ToLowerInvariant()) {
    'start' {
        $isNoGui = ($RestArgs -contains '--nogui')
        try {
            if (-not (Prepare-AntigravityForZhLaunch -NoGui $isNoGui)) {
                break
            }
            Build-AgyOverlay -Force $false
            Stop-PreviousLanguageWatchers
            if (Test-Path (Join-Path $PluginDir 'plugin.json')) {
                Set-ZhPluginEnabled -Enabled $true
            }
            Start-CdpWatchLoop -NoGui $isNoGui
        } catch {
            $errMsg = $_.Exception.Message
            if ($isNoGui) {
                $popTitle = $meta.appName
                $popMsg = $meta.appName + ": " + $errMsg
                $null = (New-Object -ComObject WScript.Shell).Popup($popMsg, 0, $popTitle, 0x1010)
            }
            throw
        } finally {
            Start-Sleep -Milliseconds 300
            if (-not (Test-ActiveWatcher)) {
                Set-ZhPluginEnabled -Enabled $false
            }
        }
    }
    'build-overlay' {
        $forceFlag = ($RestArgs -contains '--force')
        Build-AgyOverlay -Force $forceFlag
        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u751f\u6210\u589e\u5f3a\u6c49\u5316\u8986\u76d6\u811a\u672c:') $OverlayJs"
    }
    'stop' {
        foreach ($wpid in @(Get-ActiveWatcherPids)) {
            Stop-Process -Id $wpid -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $WatcherPidFile) {
            Remove-Item -Force -Path $WatcherPidFile -ErrorAction SilentlyContinue
        }
        Set-ZhPluginEnabled -Enabled $false
        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u505c\u6b62\u4e2d\u6587\u6c49\u5316\u76d1\u89c6\u5668\uff0c\u5e76\u5173\u95ed\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6\u3002')"
    }
    'prompt' {
        $act = if ($RestArgs.Count -gt 0) { $RestArgs[0].ToLowerInvariant() } else { 'status' }
        switch ($act) {
            'on' {
                Set-ZhPluginEnabled -Enabled $true
                Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u5f00\u542f\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt)\u3002')"
            }
            'off' {
                Set-ZhPluginEnabled -Enabled $false
                Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u5173\u95ed\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt)\u3002')"
            }
            'status' {
                $st = Get-ZhPluginEnabled
                if ($st) {
                    Write-Host (Resolve-ZhText '\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt): \u5df2\u5f00\u542f (enabled: true)')
                } else {
                    Write-Host (Resolve-ZhText '\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt): \u5df2\u5173\u95ed (enabled: false)')
                }
            }
            default {
                throw (Resolve-ZhText '\u7528\u6cd5: agy-zh prompt <on|off|status>')
            }
        }
    }
    'shortcut' {
        New-ZhShortcut
    }
    'status' {
        $orig = Find-OriginalExe
        $st = Get-ZhPluginEnabled
        $activePids = @(Get-ActiveWatcherPids)
        $desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName
        $programsLnk = Join-Path ([Environment]::GetFolderPath('Programs')) $ShortcutName
        $lnkList = @()
        if (Test-Path $desktopLnk) { $lnkList += $desktopLnk }
        if (Test-Path $programsLnk) { $lnkList += $programsLnk }

        Write-Host "Language: $Lang / $($meta.appName)"
        Write-Host (Resolve-ZhText '=== Antigravity \u53cc\u5165\u53e3\u6c49\u5316\u72b6\u6001 ===')
        Write-Host "$(Resolve-ZhText '\u539f\u7248\u5165\u53e3 (\u7eaf\u51c0\u82f1\u6587): ') $(if ($orig) { $orig } else { Resolve-ZhText '\u672a\u68c0\u6d4b\u5230 Antigravity.exe' })"
        Write-Host "$(Resolve-ZhText '\u4e2d\u6587\u5165\u53e3 (\u53cc\u6548\u8054\u52a8): ') $(if ($lnkList.Count -gt 0) { $lnkList -join '; ' } else { Resolve-ZhText '\u672a\u521b\u5efa\uff08\u53ef\u8fd0\u884c agy-zh shortcut \u751f\u6210\uff09' })"
        Write-Host (Resolve-ZhText '\u672c\u5730 CDP \u6ce8\u5165\u5f15\u64ce  : \u5185\u7f6e\u7eaf PowerShell \u811a\u672c\u5f15\u64ce\uff08\u65e0 .exe \u4e8c\u8fdb\u5236\uff0c\u96f6\u8bef\u62a5\uff09')
        Write-Host "$(Resolve-ZhText '\u589e\u5f3a\u6c49\u5316\u8986\u76d6\u811a\u672c   : ') $(if (Test-Path $OverlayJs) { "$(Resolve-ZhText '\u5df2\u5c31\u7eea ')($OverlayJs)" } else { Resolve-ZhText '\u672a\u751f\u6210\uff08\u53ef\u8fd0\u884c agy-zh build-overlay \u751f\u6210\uff09' })"
        Write-Host "$(Resolve-ZhText '\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6 : ') $(if (Test-Path (Join-Path $PluginDir 'plugin.json')) { "$(Resolve-ZhText '\u5df2\u5b89\u88c5 ')($PluginDir)" } else { Resolve-ZhText '\u672a\u5b89\u88c5' })"
        Write-Host "$(Resolve-ZhText '\u63d0\u793a\u8bcd\u5f53\u524d\u5f00\u5173\u72b6\u6001 : ') $(if ($st) { Resolve-ZhText '\u5df2\u5f00\u542f (enabled: true)' } else { Resolve-ZhText '\u5df2\u5173\u95ed (enabled: false\uff0c\u539f\u7248\u5165\u53e3\u7eaf\u51c0)' })"
        Write-Host "$(Resolve-ZhText '\u540e\u53f0\u6c49\u5316\u76d1\u89c6\u5668\u8fdb\u7a0b : ') $(if ($activePids.Count -gt 0) { "$(Resolve-ZhText '\u8fd0\u884c\u4e2d') (PID: $($activePids -join ', '))" } else { Resolve-ZhText '\u672a\u8fd0\u884c' })"
    }
    default {
        Write-Host (Resolve-ZhText 'agy-zh - Antigravity \u53cc\u5165\u53e3\u65e0\u635f\u6c49\u5316\u4e0e\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u8054\u52a8\u542f\u52a8\u5668 (Windows)')
        Write-Host (Resolve-ZhText '\u7528\u6cd5: agy-zh <start|stop|status|prompt <on|off|status>|build-overlay|shortcut>')
    }
}