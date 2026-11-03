param([switch]$Restore)
$ErrorActionPreference = 'Stop'
try {
    if ($Restore) {
        $snippet = 'window.__claudeRuntimeZh && window.__claudeRuntimeZh.restore();'
    } else {
        $path = Join-Path $PSScriptRoot 'claude-zh.js'
        $snippet = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    }
    Set-Clipboard -Value $snippet
    Write-Host 'Copied. Paste into the Claude page DevTools Console, then press Enter.'
    Write-Host 'This helper does not modify Claude files or settings.'
} catch {
    Write-Error $_
    exit 1
}
