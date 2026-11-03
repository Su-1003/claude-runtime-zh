param([switch]$Restore)
$ErrorActionPreference = 'Stop'
try {
    if ($Restore) {
        $snippet = 'window.__claudeRuntimeZh && window.__claudeRuntimeZh.restore();'
        $operation = 'restore'
    } else {
        $path = Join-Path $PSScriptRoot 'claude-zh.js'
        $snippet = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $operation = 'apply'
    }
    $native = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'native-menu-zh.js'), [System.Text.Encoding]::UTF8)
    $snippet += "`n" + $native + "`nawait window.__claudeNativeMenuZh." + $operation +
        "().then(result => { if (!result.supported) console.warn('Native menu bridge unavailable; page text only.'); });"
    Set-Clipboard -Value $snippet
    Write-Host 'Copied. Paste into the Claude page DevTools Console, then press Enter.'
    Write-Host 'Native menu language persists when supported. Restore reverts the saved locale. Installation files and API settings are unchanged.'
} catch {
    Write-Error $_
    exit 1
}
