function Build-AgyOverlay {
    param([bool]$Force = $false)
    $localePath = Join-Path $AssetRoot "locales\$Lang.json"
    $localeJson = [System.IO.File]::ReadAllText($localePath, [System.Text.Encoding]::UTF8)
    $locale = $localeJson | ConvertFrom-Json
    $template = [System.IO.File]::ReadAllText((Join-Path $AssetRoot 'lib\overlay.js'), [System.Text.Encoding]::UTF8)
    $i18nLayer = $template.Replace('/*__AGY_LOCALE__*/', $localeJson)
    if ($Lang -eq 'zh-CN' -and (Ensure-EnhancedOverlay -Force $Force)) {
        $baseScript = [System.IO.File]::ReadAllText($OverlayJs, [System.Text.Encoding]::UTF8)
        $marker = '/*__AGY_ZH_I18N_LAYER__*/'
        $markerIdx = $baseScript.IndexOf($marker, [System.StringComparison]::Ordinal)
        if ($markerIdx -ge 0) {
            $baseScript = $baseScript.Substring(0, $markerIdx)
        }
        $script = $baseScript.TrimEnd() + "`n$marker`n" + $i18nLayer
    } else {
        $script = $i18nLayer
    }
    $overlayDir = Split-Path -Parent $OverlayJs
    if ($overlayDir) {
        New-Item -ItemType Directory -Force -Path $overlayDir | Out-Null
    }
    [System.IO.File]::WriteAllText($OverlayJs, $script, [System.Text.UTF8Encoding]::new($false))
}
