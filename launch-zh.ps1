param(
    [switch]$Restore,
    [switch]$Configuration,
    [switch]$AllWindows,
    [switch]$CheckOnly,
    [switch]$Diagnose,
    [switch]$ApplyWorker,
    [switch]$ExecuteWorker,
    [ValidatePattern('^[0-9a-f]{32}$')][string]$ExpectedRequestId,
    [long]$ExpectedDevHandle,
    [long]$ExpectedMainHandle,
    [ValidatePattern('^CLAUDE_ZH_OK_[0-9a-f]{32}$')][string]$ConfirmToken,
    [ValidateRange(5, 120)][int]$TimeoutSeconds = 35
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

if (-not ('ClaudeZhWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class ClaudeZhWindow {
    public class Item { public IntPtr Handle; public int Pid; public string Title; }
    private delegate bool EnumCallback(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumCallback callback, IntPtr param);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int pid);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint first, uint second, bool attach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    public static void UsePhysicalCoordinates() { try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) {} }
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X; public int Y; }
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);
    public static Item[] List() {
        var result = new List<Item>();
        EnumWindows((hwnd, unused) => {
            if (!IsWindowVisible(hwnd)) return true;
            var text = new StringBuilder(2048);
            GetWindowText(hwnd, text, text.Capacity);
            if (text.Length == 0) return true;
            int pid; GetWindowThreadProcessId(hwnd, out pid);
            result.Add(new Item { Handle=hwnd, Pid=pid, Title=text.ToString() });
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }
    public static bool IsClaudePageTitle(string title) {
        if (title == null) return false;
        return title.StartsWith("Developer Tools - app://localhost/", StringComparison.Ordinal) ||
               title == "Developer Tools - app://localhost" ||
               title.StartsWith("Developer Tools - https://claude.ai/", StringComparison.Ordinal) ||
               title == "Developer Tools - https://claude.ai";
    }
    public static void FocusConsole(IntPtr expected) {
        Shortcut(expected, 0xC0, true, false);
    }
    public static bool Activate(IntPtr expected) {
        if (GetForegroundWindow() == expected) return true;
        SetForegroundWindow(expected);
        if (GetForegroundWindow() == expected) return true;
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero) return false;
        int ignored; uint foregroundThread = GetWindowThreadProcessId(foreground, out ignored);
        uint callerThread = GetCurrentThreadId();
        if (foregroundThread == callerThread || !AttachThreadInput(callerThread, foregroundThread, true)) return false;
        try { SetForegroundWindow(expected); return GetForegroundWindow() == expected; }
        finally { AttachThreadInput(callerThread, foregroundThread, false); }
    }
    public static void ClickPrompt(IntPtr expected, int x, int y) {
        if (GetForegroundWindow() != expected || GetAncestor(WindowFromPoint(new Point { X=x, Y=y }), 2) != expected)
            throw new InvalidOperationException("Console input is covered by another window. Stopped.");
        if ((GetAsyncKeyState(0x1B) & 0x8000) != 0) throw new OperationCanceledException("Escape pressed.");
        if (!SetCursorPos(x,y)) throw new InvalidOperationException("Could not focus Console input.");
        mouse_event(0x0002,0,0,0,UIntPtr.Zero);
        mouse_event(0x0004,0,0,0,UIntPtr.Zero);
    }
    public static void ScrollConsoleDown(IntPtr expected, int x, int y) {
        if (GetForegroundWindow() != expected || GetAncestor(WindowFromPoint(new Point { X=x, Y=y }), 2) != expected)
            throw new InvalidOperationException("Console scroll area is covered. Stopped.");
        SetCursorPos(x,y);
        mouse_event(0x0800,0,0,unchecked((uint)-30000),UIntPtr.Zero);
    }
    public static void Shortcut(IntPtr expected, byte key, bool ctrl, bool alt) {
        if (GetForegroundWindow() != expected) throw new InvalidOperationException("Focus changed. Stopped without typing.");
        if ((GetAsyncKeyState(0x1B) & 0x8000) != 0) throw new OperationCanceledException("Escape pressed.");
        try {
            if (ctrl) keybd_event(0x11,0,0,UIntPtr.Zero);
            if (alt) keybd_event(0x12,0,0,UIntPtr.Zero);
            keybd_event(key,0,0,UIntPtr.Zero);
            keybd_event(key,0,2,UIntPtr.Zero);
        } finally {
            if (alt) keybd_event(0x12,0,2,UIntPtr.Zero);
            if (ctrl) keybd_event(0x11,0,2,UIntPtr.Zero);
        }
    }
}
'@
}

[ClaudeZhWindow]::UsePhysicalCoordinates()
$scriptPath = Join-Path $PSScriptRoot 'claude-zh.js'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw 'Missing claude-zh.js beside this launcher.' }
$nativeMenuPath = Join-Path $PSScriptRoot 'native-menu-zh.js'
if (-not (Test-Path -LiteralPath $nativeMenuPath -PathType Leaf)) { throw 'Missing native-menu-zh.js beside this launcher.' }
$automation = [System.Windows.Automation.AutomationElement]
$descendants = [System.Windows.Automation.TreeScope]::Descendants
$signatureCache = @{}
$clipboardRunspace = $null
$ownedDraftDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\claude-zh-owned-drafts'

function Assert-NotCancelled {
    if (([ClaudeZhWindow]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0) { throw 'Escape pressed. Operation cancelled.' }
}
function Wait-Ui([int]$milliseconds) {
    $until = [DateTime]::UtcNow.AddMilliseconds($milliseconds)
    do {
        Assert-NotCancelled
        Start-Sleep -Milliseconds 20
    } until ([DateTime]::UtcNow -ge $until)
}
function Invoke-ClipboardAction([string]$operation, [string]$value = '') {
    # Clipboard/OLE stays on a dedicated STA thread; UI Automation stays in MTA.
    if (-not $script:clipboardRunspace) {
        $script:clipboardRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $script:clipboardRunspace.ApartmentState = 'STA'
        $script:clipboardRunspace.ThreadOptions = 'ReuseThread'
        $script:clipboardRunspace.Open()
    }
    $pipeline = [System.Management.Automation.PowerShell]::Create()
    try {
        $pipeline.Runspace = $script:clipboardRunspace
        [void]$pipeline.AddScript(@'
param($operation, $value)
Add-Type -AssemblyName System.Windows.Forms
if ($operation -eq 'Set') {
    [System.Windows.Forms.Clipboard]::SetText($value)
} elseif ($operation -eq 'Read') {
    Write-Output ([System.Windows.Forms.Clipboard]::GetText())
} else { throw 'Unknown clipboard operation.' }
'@).AddArgument($operation).AddArgument($value)
        $reply = @($pipeline.Invoke())
        if ($pipeline.HadErrors) { throw $pipeline.Streams.Error[0].Exception }
        if ($operation -eq 'Read') { if ($reply.Count) { return [string]$reply[0] }; return '' }
    } finally { $pipeline.Dispose() }
}
function Get-CopiedConsoleDraft($dev, [string]$sentinel) {
    for ($probe = 0; $probe -lt 20; $probe++) {
        Assert-DevToolsTarget $dev
        $value = Invoke-ClipboardAction 'Read'
        if ($value -cne $sentinel) { return $value }
        Wait-Ui 100
    }
    return $null
}
function Read-ConsoleDraft($dev, $prompt) {
    # Chromium virtualizes long editor lines in UIA. Copy the selected editor
    # text instead; never execute based on a truncated accessibility value.
    $textPattern = $null
    $plainEmpty = $prompt.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$textPattern) -and
        [string]::IsNullOrWhiteSpace($textPattern.DocumentRange.GetText(-1))
    $emptyHint = [string]::IsNullOrWhiteSpace((Get-PromptValue $prompt)) -and $plainEmpty -and
        $prompt.Current.BoundingRectangle.Height -gt 0 -and $prompt.Current.BoundingRectangle.Height -le 96 -and
        -not $prompt.Current.IsOffscreen
    $sentinel = 'CLAUDE_ZH_CLIPBOARD_' + [Guid]::NewGuid().ToString('N')
    Invoke-ClipboardAction 'Set' $sentinel
    Assert-DevToolsTarget $dev
    [ClaudeZhWindow]::Shortcut($dev.Handle, 0x41, $true, $false)
    Wait-Ui 80
    [ClaudeZhWindow]::Shortcut($dev.Handle, 0x43, $true, $false)
    $value = Get-CopiedConsoleDraft $dev $sentinel
    Assert-DevToolsTarget $dev
    [ClaudeZhWindow]::Shortcut($dev.Handle, 0x27, $false, $false)
    if ($null -eq $value) {
        if ($emptyHint) { return '' }
        throw 'The full Console draft could not be read. No command was executed.'
    }
    return $value
}
function Get-TrustedClaudePids {
    $ids = @()
    foreach ($process in @(Get-Process -Name claude -ErrorAction SilentlyContinue)) {
        $exe = $null
        try { $exe = $process.Path } catch { continue }
        if (-not $exe -or $exe -notmatch '(?i)\\WindowsApps\\[^\\]*Claude[^\\]*\\app\\claude\.exe$') { continue }
        if (-not $signatureCache.ContainsKey($exe)) {
            $signature = Get-AuthenticodeSignature -LiteralPath $exe
            $signatureCache[$exe] = ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match 'Anthropic')
        }
        if ($signatureCache[$exe]) { $ids += $process.Id }
    }
    return $ids
}
function Get-ClaudeWindows {
    $ids = @(Get-TrustedClaudePids)
    return @([ClaudeZhWindow]::List() | Where-Object { $ids -contains $_.Pid })
}
function Get-MainClaudeWindow {
    $windows = @(Get-ClaudeWindows | Where-Object { $_.Title -notlike 'Developer Tools*' -and $_.Title -notlike 'DevTools*' })
    $windows = @($windows | Where-Object { -not (Test-ConfigurationWindow $_) })
    $exact = @($windows | Where-Object { $_.Title -eq 'Claude' })
    if ($exact.Count -eq 1) { return $exact[0] }
    if ($windows.Count -eq 1) { return $windows[0] }
    if ($windows.Count -gt 1) { throw 'More than one Claude window is open. Keep only the intended main window, then retry.' }
    return $null
}
function Test-ConfigurationWindow($window) {
    $root = $automation::FromHandle($window.Handle)
    return ($null -ne (Find-ByProperty $root $automation::NameProperty 'Configure third-party inference')) -or
        ($null -ne (Find-ByProperty $root $automation::NameProperty ([string]::Concat([char]0x914d,[char]0x7f6e,[char]0x7b2c,[char]0x4e09,[char]0x65b9,[char]0x63a8,[char]0x7406,[char]0x670d,[char]0x52a1))))
}
function Get-ConfigurationWindow {
    $windows = @(Get-ClaudeWindows | Where-Object { $_.Title -notlike 'Developer Tools*' -and $_.Title -notlike 'DevTools*' -and (Test-ConfigurationWindow $_) })
    if ($windows.Count -eq 1) { return $windows[0] }
    throw 'Open exactly one Inference configuration window in Claude, then use the configuration launcher.'
}
function Get-OpenConfigurationWindows {
    return @(Get-ClaudeWindows | Where-Object {
        $_.Title -notlike 'Developer Tools*' -and $_.Title -notlike 'DevTools*' -and (Test-ConfigurationWindow $_)
    })
}
function Invoke-ClaudeWindowLauncher([bool]$ConfigurationTarget, [bool]$RestoreTarget) {
    $arguments = @('-NoProfile', '-MTA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
        '-TimeoutSeconds', [string]$TimeoutSeconds)
    if ($ConfigurationTarget) { $arguments += '-Configuration' }
    if ($RestoreTarget) { $arguments += '-Restore' }
    & (Join-Path $PSHOME 'powershell.exe') @arguments
    if ($LASTEXITCODE -ne 0) {
        $target = if ($ConfigurationTarget) { 'inference configuration' } else { 'main window' }
        throw ('The ' + $target + ' step failed. See its STOPPED message above.')
    }
}
function Invoke-CombinedTranslation([bool]$RestoreTarget) {
    Assert-NotCancelled
    Write-Host 'Processing Claude main window...'
    Invoke-ClaudeWindowLauncher -ConfigurationTarget $false -RestoreTarget $RestoreTarget
    Assert-NotCancelled
    # Re-detect after the main step: a configuration window can close meanwhile.
    $configurationWindows = @(Get-OpenConfigurationWindows)
    if ($configurationWindows.Count -gt 1) {
        throw 'Main window completed. More than one inference configuration window is open; keep one and run the same launcher again.'
    }
    if ($configurationWindows.Count -eq 1) {
        Assert-NotCancelled
        Write-Host 'Processing the open inference configuration window...'
        Invoke-ClaudeWindowLauncher -ConfigurationTarget $true -RestoreTarget $RestoreTarget
    } else {
        Write-Host 'No inference configuration window is open. If opened later, run this same launcher again.'
    }
    Write-Host 'SUCCESS: all current supported target windows completed.'
}
function Start-RegisteredClaude {
    # Activate the registered application. No EXE switches, repair, or file copies.
    $apps = @(Get-StartApps | Where-Object { $_.AppID -match '^(Claude|AnthropicPBC\.Claude)_[^!]+!Claude$' } |
        Select-Object -ExpandProperty AppID -Unique)
    if ($apps.Count -ne 1) { throw 'Cannot uniquely find the registered Claude app. Open Claude manually, then retry.' }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $apps[0]) -WindowStyle Hidden | Out-Null
}
function Focus-Window($window) {
    Assert-NotCancelled
    [void][ClaudeZhWindow]::ShowWindow($window.Handle, 9)
    [void][ClaudeZhWindow]::Activate($window.Handle)
    Wait-Ui 200
    if ([ClaudeZhWindow]::GetForegroundWindow() -eq $window.Handle) { return }
    Write-Host 'Waiting up to 8 seconds for Claude. Click the target Claude window; Escape cancels.'
    $focusDeadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        Wait-Ui 100
        if ([ClaudeZhWindow]::GetForegroundWindow() -eq $window.Handle) { return }
    } until ([DateTime]::UtcNow -ge $focusDeadline)
    throw 'Could not focus the target Claude window. No input was sent. Click it and retry.'
}
function Find-ByProperty($root, $property, [string]$value) {
    if ($null -eq $root -or $null -eq $property) { throw 'Accessibility target or property is unavailable.' }
    $condition = [System.Windows.Automation.PropertyCondition]::new($property, [object]$value)
    return $root.FindFirst($descendants, $condition)
}
function Get-ForegroundHandle { return [ClaudeZhWindow]::GetForegroundWindow().ToInt64() }
function Get-ClaudeDevWindows { return @(Get-ClaudeWindows | Where-Object { [ClaudeZhWindow]::IsClaudePageTitle($_.Title) }) }
function Send-DevToolsToggle($window) { [ClaudeZhWindow]::Shortcut($window.Handle, 0x49, $true, $true) }
function Get-DevToolsPageKind([string]$title) {
    if (-not $title.StartsWith('Developer Tools - ', [StringComparison]::Ordinal)) { return 'unknown' }
    $address = $null
    if (-not [Uri]::TryCreate($title.Substring('Developer Tools - '.Length), [UriKind]::Absolute, [ref]$address)) { return 'unknown' }
    if (-not (($address.Scheme -ceq 'app' -and $address.Host -ceq 'localhost') -or ($address.Scheme -ceq 'https' -and $address.Host -ceq 'claude.ai'))) { return 'unknown' }
    if ($address.AbsolutePath -ceq '/setup-desktop-3p') { return 'configuration' }
    if ($address.AbsolutePath -eq '/' -or $address.AbsolutePath -match '^/(new|cowork|chat|chats|project|projects|artifacts|recents|customize|scheduled-task)(/|$)') { return 'main' }
    return 'unknown'
}
function Open-ClaudeDevTools($main, [bool]$ConfigurationTarget = $false) {
    Assert-NotCancelled
    $kind = if ($ConfigurationTarget) { 'configuration' } else { 'main' }
    $previous = @(Get-ClaudeDevWindows)
    $matching = @($previous | Where-Object { (Get-DevToolsPageKind $_.Title) -eq $kind })
    if ($matching.Count -gt 1) { throw 'More than one matching Claude DevTools window is open. Keep only the intended page tool.' }
    if ($matching.Count -eq 1) {
        Focus-Window $matching[0]
        return [pscustomobject]@{Window=$matching[0];OpenedNew=$false}
    }
    if (@($previous | Where-Object { (Get-DevToolsPageKind $_.Title) -eq 'unknown' }).Count) {
        throw 'An existing Claude DevTools target cannot be identified. Close it yourself before retrying; its draft was not touched.'
    }
    Focus-Window $main
    Send-DevToolsToggle $main
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Wait-Ui 250
        $current = @(Get-ClaudeDevWindows)
        $front = Get-ForegroundHandle
        $selected = @($current | Where-Object { $_.Handle.ToInt64() -eq $front -and (Get-DevToolsPageKind $_.Title) -eq $kind })
        if ($selected.Count -eq 1) {
            return [pscustomobject]@{Window=$selected[0];OpenedNew=$true}
        }
    } until ([DateTime]::UtcNow -ge $deadline)
    throw 'Claude page DevTools did not become available. Check Developer Mode and target-window focus; no code was pasted.'
}
function Get-ConsolePayloadDigest([string]$payload) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload.Replace("`r`n", "`n").Trim())
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Save-OwnedConsolePayload([string]$payload, [string]$requestId) {
    if ($requestId -notmatch '^[0-9a-f]{32}$') { throw 'Invalid local request record.' }
    [void][System.IO.Directory]::CreateDirectory($ownedDraftDirectory)
    $record = [pscustomobject]@{RequestId=$requestId;SHA256=(Get-ConsolePayloadDigest $payload)} | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText((Join-Path $ownedDraftDirectory ($requestId + '.json')), $record, (New-Object System.Text.UTF8Encoding($false)))
}
function Get-SavedConsoleRequestId([string]$draft) {
    $ids = [regex]::Matches($draft, "console\.info\('CLAUDE_ZH_OK_' \+ '([0-9a-f]{32})'\);")
    if ($ids.Count -ne 1) { return $null }
    $id = $ids[0].Groups[1].Value
    $path = Join-Path $ownedDraftDirectory ($id + '.json')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { $record = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { return $null }
    if ($record.RequestId -cne $id -or $record.SHA256 -cne (Get-ConsolePayloadDigest $draft)) { return $null }
    return $id
}
function Read-ChildProcessResult($process, [int]$timeoutMilliseconds) {
    # Drain both redirected pipes while the process runs; waiting first can
    # deadlock once either pipe fills.
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($timeoutMilliseconds)) {
        $process.Kill()
        throw 'The local helper timed out and was stopped; Claude was not terminated.'
    }
    return [pscustomobject]@{Output=$stdout.GetAwaiter().GetResult();Error=$stderr.GetAwaiter().GetResult();ExitCode=$process.ExitCode}
}
function Assert-DevToolsTarget($window) {
    $fresh = @([ClaudeZhWindow]::List() | Where-Object { $_.Handle -eq $window.Handle })
    if ($fresh.Count -ne 1 -or -not [ClaudeZhWindow]::IsClaudePageTitle($fresh[0].Title) -or
        (@(Get-TrustedClaudePids) -notcontains $fresh[0].Pid)) {
        throw 'The intended Claude page DevTools window is no longer available. Stopped.'
    }
    if ([ClaudeZhWindow]::GetForegroundWindow() -ne $window.Handle) { throw 'Focus changed. Stopped without typing.' }
}
function Get-PromptValue($prompt) {
    $pattern = $null
    if (-not $prompt.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        throw 'Console prompt does not expose its text. Use copy-script.cmd manually.'
    }
    return $pattern.Current.Value
}
function Get-InjectionBody {
    $native = [System.IO.File]::ReadAllText($nativeMenuPath, [System.Text.Encoding]::UTF8)
    if ($Restore) {
        $body = 'window.__claudeRuntimeZh && window.__claudeRuntimeZh.restore();'
        $operation = 'restore'
    } else {
        $body = [System.IO.File]::ReadAllText($scriptPath, [System.Text.Encoding]::UTF8)
        if ($Configuration) { $body = "window.__claudeRuntimeZhOptions = { configuration: true };`n" + $body }
        $operation = 'apply'
    }
    return $body + "`n" + $native + "`nconst nativeMenuResult = await window.__claudeNativeMenuZh." + $operation + '();' +
        "`nconsole.info('CLAUDE_NATIVE_MENU_' + JSON.stringify(typeof window.__claudeNativeMenuZh.inspect === 'function' ? await window.__claudeNativeMenuZh.inspect() : window.__claudeNativeMenuZh.status()));" +
        "`nif (!nativeMenuResult.supported) console.warn('Native menu bridge unavailable; page text only.');"
}
function Focus-ConsolePrompt($dev, $root, $prompt) {
    $window = $root.Current.BoundingRectangle
    for ($attempt=0; $attempt -lt 12; $attempt++) {
        $editor = $prompt.Current.BoundingRectangle
        if ($editor.Bottom -gt ($window.Top+150) -and $editor.Top -lt ($window.Bottom-12)) { break }
        Assert-DevToolsTarget $dev
        [ClaudeZhWindow]::ScrollConsoleDown($dev.Handle, [int]($window.Right-70), [int]($window.Top+$window.Height*0.65))
        Wait-Ui 120
        $prompt = Find-ByProperty $root $automation::NameProperty 'Console prompt'
        if (-not $prompt) { throw 'CONSOLE_LAYOUT_NOT_READY' }
    }
    $point = New-Object System.Windows.Point
    if (-not $prompt.TryGetClickablePoint([ref]$point)) {
        # A multiline Console editor can be taller than the screen. Use the
        # visible bottom of that editor, never its off-screen geometric centre.
        $editor = $prompt.Current.BoundingRectangle
        $window = $root.Current.BoundingRectangle
        $left = [Math]::Max($editor.Left, $window.Left + 4)
        $right = [Math]::Min($editor.Right, $window.Right - 4)
        $top = [Math]::Max($editor.Top, $window.Top + 4)
        $bottom = [Math]::Min($editor.Bottom, $window.Bottom - 12)
        if (($right - $left) -lt 24 -or ($bottom - $top) -lt 8) { throw 'CONSOLE_LAYOUT_NOT_READY' }
        $point = New-Object System.Windows.Point(($left + 18), ($bottom - 5))
    }
    [ClaudeZhWindow]::ClickPrompt($dev.Handle, [int]$point.X, [int]$point.Y)
    Wait-Ui 100
}
function New-ConsolePayload([string]$body, [string]$check, [string]$requestId, [bool]$withMarker = $true) {
    $report = "const report=(failed,message)=>{const n=document.createElement('div'); n.id=(failed?'claude-zh-failed-':'claude-zh-launch-')+'" + $requestId + "'; n.setAttribute('role','status');n.setAttribute('data-claude-zh-ignore','');n.style.cssText='position:fixed;right:18px;bottom:18px;z-index:2147483647;max-width:420px;padding:10px 16px;background:#263c30;color:white;border-radius:8px;font:14px sans-serif;pointer-events:none';n.textContent=message;document.body.append(n);setTimeout(()=>n.remove(),30000);};"
    $successMessage = if ($Restore) { '\u5df2\u6062\u590d\u82f1\u6587' } else { '\u4e2d\u6587\u754c\u9762\u5df2\u542f\u7528' }
    $success = if ($withMarker) { $report + "report(false,'" + $successMessage + "');" } else { '' }
    $failure = if ($withMarker) { $report + "report(true,'Translation failed: '+e.message);" } else { '' }
    return "try {`n" + $body + "`n" + $check + "`n" + $success + "console.info('CLAUDE_ZH_OK_' + '" + $requestId + "'); } catch(e) {" + $failure + "console.error('CLAUDE_ZH_FAILED: ' + e.message); }"
}
function Get-OwnPendingRequestId([string]$draft, [string]$body, [string]$check) {
    $ids = [regex]::Matches($draft, "console\.info\('CLAUDE_ZH_OK_' \+ '([0-9a-f]{32})'\);")
    if ($ids.Count -ne 1) { return $null }
    $requestId = $ids[0].Groups[1].Value
    $expected = New-ConsolePayload $body $check $requestId
    if ($draft.Replace("`r`n", "`n").Trim() -ceq $expected.Replace("`r`n", "`n").Trim()) { return $requestId }
    $legacy = "try {`n" + $body + "`n" + $check + "`nconsole.info('CLAUDE_ZH_OK_' + '" + $requestId + "');`n} catch (e) { console.error('CLAUDE_ZH_FAILED: ' + e.message); }"
    if ($draft.Replace("`r`n", "`n").Trim() -ceq $legacy.Replace("`r`n", "`n").Trim()) { return $requestId }
    return $null
}
function Find-OutputMarker($root, [string]$token) {
    # Chromium's accessibility names can contain directional/zero-width marks.
    $textCondition = New-Object System.Windows.Automation.PropertyCondition($automation::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    foreach ($element in $root.FindAll($descendants, $textCondition)) {
        $name = $element.Current.Name
        if ($name.Length -gt ($token.Length + 20)) { continue }
        if ([regex]::Replace($name, '[\p{Cf}\s]', '') -ceq $token) { return $element }
    }
    return $null
}
function Confirm-InFreshClient([string]$token, [int]$timeoutMilliseconds = 25000, [long]$mainHandle = 0) {
    # Isolate the read-only accessibility client from the client that changed
    # the editor. Chromium can retain a stale accessibility view for that client.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $startInfo.Arguments = '-NoProfile -MTA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -ConfirmToken ' + $token + ' -ExpectedMainHandle ' + $mainHandle
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $verificationProcess = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $reply = Read-ChildProcessResult $verificationProcess $timeoutMilliseconds
        $output = $reply.Output
        $errorText = $reply.Error
        if ($reply.ExitCode -ne 0 -or $output -notmatch '(?m)^CONFIRMED\s*$') {
            if ($errorText) { Write-Host $errorText }
            return $false
        }
        return $true
    } finally { $verificationProcess.Dispose() }
}

if ($CheckOnly) {
    $titlesAccepted = [ClaudeZhWindow]::IsClaudePageTitle('Developer Tools - app://localhost/new')
    $titlesRejected = -not [ClaudeZhWindow]::IsClaudePageTitle('Developer Tools - https://claude.ai.example.com/')
    $probeId = '0123456789abcdef0123456789abcdef'
    $probe = New-ConsolePayload 'exampleBody();' 'exampleCheck();' $probeId
    $resumeValid = (Get-OwnPendingRequestId $probe 'exampleBody();' 'exampleCheck();') -ceq $probeId
    $resumeRejectsModified = $null -eq (Get-OwnPendingRequestId ($probe + ';userCommand();') 'exampleBody();' 'exampleCheck();')
    $resumeAllowsBlankLines = (Get-OwnPendingRequestId ("`n`n" + $probe + "`n") 'exampleBody();' 'exampleCheck();') -ceq $probeId
    if (-not $resumeValid -or -not $resumeRejectsModified -or -not $resumeAllowsBlankLines -or $probe.Contains('CLAUDE_ZH_OK_' + $probeId)) { throw 'Payload safety tests failed.' }
    [pscustomobject]@{CheckOnly=$true;MainScriptExists=$true;NativeHelperCompiled=$true;
        ExpectedPageAccepted=$titlesAccepted;OtherPageRejected=$titlesRejected;
        ExactOwnDraftRecognized=$resumeValid;ModifiedDraftRejected=$resumeRejectsModified;
        LeadingBlankLinesAllowed=$resumeAllowsBlankLines;
        TrustedClaudeProcessCount=@(Get-TrustedClaudePids).Count;UIActionsPerformed=$false} | ConvertTo-Json
    exit 0
}
if ($ConfirmToken) {
    if ($ExpectedMainHandle) {
        $mainWindows = @(Get-ClaudeWindows | Where-Object { $_.Handle.ToInt64() -eq $ExpectedMainHandle })
        if ($mainWindows.Count -ne 1) { exit 2 }
        $root = $automation::FromHandle($mainWindows[0].Handle)
        $suffix = $ConfirmToken -replace '^CLAUDE_ZH_OK_', ''
        if (Find-ByProperty $root $automation::AutomationIdProperty ('claude-zh-launch-' + $suffix)) { Write-Output 'CONFIRMED'; exit 0 }
        $failure = Find-ByProperty $root $automation::AutomationIdProperty ('claude-zh-failed-' + $suffix)
        if ($failure) { Write-Output ('FAILED: ' + $failure.Current.Name); exit 3 }
        exit 2
    }
    $devWindows = @(Get-ClaudeWindows | Where-Object { [ClaudeZhWindow]::IsClaudePageTitle($_.Title) })
    if ($devWindows.Count -ne 1) { exit 2 }
    $root = $automation::FromHandle($devWindows[0].Handle)
    if (Find-OutputMarker $root $ConfirmToken) { Write-Output 'CONFIRMED'; exit 0 }
    exit 2
}
if ($Diagnose) {
    $devWindows = @(Get-ClaudeWindows | Where-Object { [ClaudeZhWindow]::IsClaudePageTitle($_.Title) })
    if ($devWindows.Count -ne 1) { throw 'Exactly one Claude page DevTools window is required for diagnostics.' }
    $root = $automation::FromHandle($devWindows[0].Handle)
    Write-Host ('DevTools window bounds: ' + $root.Current.BoundingRectangle.ToString())
    $prompt = Find-ByProperty $root $automation::NameProperty 'Console prompt'
    $draft = if ($prompt) { Get-PromptValue $prompt } else { '' }
    Write-Host ('Console draft length: ' + $draft.Length)
    $textPattern = $null
    if ($prompt -and $prompt.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$textPattern)) {
        $rangeText = $textPattern.DocumentRange.GetText(-1)
        Write-Host ('Console TextPattern length: ' + $rangeText.Length + '; local-header=' + $rangeText.Contains('/* Claude runtime Chinese UI.'))
    }
    $promptCondition = New-Object System.Windows.Automation.PropertyCondition($automation::NameProperty, 'Console prompt')
    foreach ($item in $root.FindAll($descendants, $promptCondition)) {
        Write-Host ('Prompt geometry: ' + $item.Current.BoundingRectangle.ToString() + '; offscreen=' + $item.Current.IsOffscreen)
    }
    $textCondition = New-Object System.Windows.Automation.PropertyCondition($automation::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    $items = $root.FindAll($descendants, $textCondition)
    Write-Host ('Text node count: ' + $items.Count)
    foreach ($element in $items) {
        $name = $element.Current.Name
        if ($name.Length -lt 1000 -and $name -match 'CLAUDE_NATIVE_MENU_|CLAUDE_ZH_OK_|CLAUDE_ZH_FAILED|Uncaught|SyntaxError|ReferenceError|TypeError|Warning: Don.t paste|allow pasting|runtime Chinese|\u8fd0\u884c\u65f6\u6c49\u5316') {
            Write-Host $name
        }
    }
    exit 0
}

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'MTA') { throw 'Use launch-zh.cmd (the UI Automation thread must be MTA).' }
if ($AllWindows) {
    try {
        if ($Configuration -or $ApplyWorker -or $ExecuteWorker) { throw 'Combined mode cannot be used with single-window worker options.' }
        Invoke-CombinedTranslation -RestoreTarget ([bool]$Restore)
        exit 0
    } catch {
        Write-Host ('STOPPED: ' + $_.Exception.Message) -ForegroundColor Yellow
        exit 1
    }
}
if ($ExecuteWorker) {
    try {
        if (-not $ExpectedRequestId -or -not $ExpectedDevHandle) { throw 'Missing execution record.' }
        $windows = @(Get-ClaudeWindows | Where-Object { $_.Handle.ToInt64() -eq $ExpectedDevHandle -and [ClaudeZhWindow]::IsClaudePageTitle($_.Title) })
        if ($windows.Count -ne 1) { throw 'The intended Claude page DevTools window changed.' }
        $dev = $windows[0]
        $root = $automation::FromHandle($dev.Handle)
        $prompt = Find-ByProperty $root $automation::NameProperty 'Console prompt'
        if (-not $prompt) { throw 'Console prompt unavailable.' }
        $body = Get-InjectionBody
        $check = if ($Restore) { 'if (window.__claudeRuntimeZh) throw new Error("Runtime translation still active");' } else { 'if (!window.__claudeRuntimeZh || !window.__claudeRuntimeZh.status().active) throw new Error("Runtime translation not active");' }
        Focus-Window $dev
        [ClaudeZhWindow]::FocusConsole($dev.Handle)
        Wait-Ui 200
        Focus-ConsolePrompt $dev $root $prompt
        $actualId = Get-OwnPendingRequestId (Read-ConsoleDraft $dev $prompt) $body $check
        if ($actualId -cne $ExpectedRequestId) {
            throw 'Paste could not be verified as the exact local script. Handle any paste safety prompt yourself; no command was executed.'
        }
        Assert-DevToolsTarget $dev
        [ClaudeZhWindow]::Shortcut($dev.Handle, 0x0D, $false, $false)
        Write-Output 'EXECUTED'
        exit 0
    } catch { Write-Host ('STOPPED: ' + $_.Exception.Message); exit 1 }
    finally {
        if ($clipboardRunspace) { $clipboardRunspace.Dispose() }
    }
}
if (-not $ApplyWorker) {
    # Never keep the automation client that edited Console alive while reading
    # its output. Ending that client releases Chromium accessibility resources.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $startInfo.Arguments = '-NoProfile -MTA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -ApplyWorker -TimeoutSeconds ' + $TimeoutSeconds
    if ($Restore) { $startInfo.Arguments += ' -Restore' }
    if ($Configuration) { $startInfo.Arguments += ' -Configuration' }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $worker = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $reply = Read-ChildProcessResult $worker (($TimeoutSeconds + 35) * 1000)
        $output = $reply.Output
        $errorText = $reply.Error
        if ($worker.ExitCode -ne 0 -and $output -match 'CONSOLE_LAYOUT_NOT_READY') {
            $worker.Dispose()
            Start-Sleep -Milliseconds 250
            $worker = [System.Diagnostics.Process]::Start($startInfo)
            $reply = Read-ChildProcessResult $worker (($TimeoutSeconds + 35) * 1000)
            $output = $reply.Output
            $errorText = $reply.Error
        }
        foreach ($line in $output -split "`r?`n") {
            if ($line -and -not $line.StartsWith('CLAUDE_ZH_RESULT:')) { Write-Host $line }
        }
        if ($worker.ExitCode -ne 0) { if ($errorText) { Write-Host $errorText }; exit 1 }
        $resultLines = @($output -split "`r?`n" | Where-Object { $_.StartsWith('CLAUDE_ZH_RESULT:') })
        if ($resultLines.Count -ne 1) { throw 'The launcher worker did not return a verification record.' }
        $result = $resultLines[0].Substring('CLAUDE_ZH_RESULT:'.Length) | ConvertFrom-Json
        if ($result.Token -notmatch '^CLAUDE_ZH_OK_[0-9a-f]{32}$') { throw 'Invalid verification token.' }
        Start-Sleep -Milliseconds 800
        $executeInfo = New-Object System.Diagnostics.ProcessStartInfo
        $executeInfo.FileName = Join-Path $PSHOME 'powershell.exe'
        $executeInfo.Arguments = '-NoProfile -MTA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -ExecuteWorker -ExpectedRequestId ' + ($result.Token -replace '^CLAUDE_ZH_OK_', '') + ' -ExpectedDevHandle ' + [long]$result.DevHandle
        if ($Restore) { $executeInfo.Arguments += ' -Restore' }
        if ($Configuration) { $executeInfo.Arguments += ' -Configuration' }
        $executeInfo.UseShellExecute = $false
        $executeInfo.CreateNoWindow = $true
        $executeInfo.RedirectStandardOutput = $true
        $executeInfo.RedirectStandardError = $true
        $executeProcess = [System.Diagnostics.Process]::Start($executeInfo)
        try {
            $executionReply = Read-ChildProcessResult $executeProcess 25000
            $executionOutput = $executionReply.Output
            $executionError = $executionReply.Error
            if ($executionReply.ExitCode -ne 0 -or $executionOutput -notmatch '(?m)^EXECUTED\s*$') {
                Write-Host $executionOutput
                if ($executionError) { Write-Host $executionError }
                throw 'The exact local command could not be executed safely.'
            }
        } finally { $executeProcess.Dispose() }
        Write-Host '[3/5] Exact local script verified and executed.'
        $mainForVerify = @(Get-ClaudeWindows | Where-Object { $_.Handle.ToInt64() -eq $result.MainHandle })
        if ($mainForVerify.Count -eq 1) { Focus-Window $mainForVerify[0] }
        Start-Sleep -Milliseconds 700
        $deadline = [DateTime]::UtcNow.AddSeconds(25)
        $success = $false
        do {
            Assert-NotCancelled
            $remaining = [int][Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
            $success = Confirm-InFreshClient $result.Token $remaining ([long]$result.MainHandle)
            if (-not $success) { Start-Sleep -Milliseconds 400 }
        } until ($success -or [DateTime]::UtcNow -gt $deadline)
        if (-not $success) { throw 'Could not verify success. DevTools was left open for inspection.' }
        Write-Host '[4/5] Runtime translation success verified.'
        $dev = @(Get-ClaudeWindows | Where-Object { $_.Handle.ToInt64() -eq $result.DevHandle -and [ClaudeZhWindow]::IsClaudePageTitle($_.Title) })
        $main = @(Get-ClaudeWindows | Where-Object { $_.Handle.ToInt64() -eq $result.MainHandle })
        if ($dev.Count -eq 1 -and $result.OpenedDevTools) {
            [void][ClaudeZhWindow]::PostMessage($dev[0].Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        }
        if ($main.Count -eq 1) { Focus-Window $main[0] }
        Write-Host '[5/5] Returned to Claude.'
        if ($Restore) { Write-Host 'SUCCESS: English UI restored.' }
        else { Write-Host 'SUCCESS: Chinese UI applied. Native menu language persists when supported; Restore reverts the saved locale. Signed program files and API settings were not changed.' }
        Write-Host 'After restarting Claude, use this launcher again. No startup task or permanent hook was installed.'
        exit 0
    } catch {
        Write-Host ('STOPPED: ' + $_.Exception.Message) -ForegroundColor Yellow
        exit 1
    } finally {
        $worker.Dispose()
        if ($clipboardRunspace) { $clipboardRunspace.Dispose() }
    }
}
$payload = $null
$openedDevTools = $false
try {
    $main = if ($Configuration) { Get-ConfigurationWindow } else { Get-MainClaudeWindow }
    if (-not $main) {
        Write-Host 'Starting registered Claude...'
        Start-RegisteredClaude
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            Assert-NotCancelled
            Start-Sleep -Milliseconds 300
            $main = Get-MainClaudeWindow
        } until ($main -or [DateTime]::UtcNow -gt $deadline)
        if (-not $main) { throw 'Claude did not expose a signed main window before timeout. No code was pasted.' }
    }
    Write-Host '[1/5] Signed Claude window found.'
    $devState = Open-ClaudeDevTools $main ([bool]$Configuration)
    $dev = $devState.Window
    $openedDevTools = $devState.OpenedNew
    Focus-Window $dev
    Assert-DevToolsTarget $dev
    $root = $automation::FromHandle($dev.Handle)
    $consoleTab = Find-ByProperty $root $automation::AutomationIdProperty 'tab-console'
    if (-not $consoleTab) { throw 'Console tab was not found. Stopped without typing.' }
    $selection = $null
    if (-not $consoleTab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) {
        throw 'Console tab cannot be selected automatically. Use copy-script.cmd manually.'
    }
    $selection.Select()
    Write-Host '[2/5] Claude Console selected.'
    Wait-Ui 200
    $prompt = Find-ByProperty $root $automation::NameProperty 'Console prompt'
    if (-not $prompt) { throw 'Console prompt was not found. Stopped without typing.' }
    [ClaudeZhWindow]::FocusConsole($dev.Handle)
    Wait-Ui 250
    $root = $automation::FromHandle($dev.Handle)
    $prompt = Find-ByProperty $root $automation::NameProperty 'Console prompt'
    if (-not $prompt) { throw 'Console prompt is not available.' }
    Focus-ConsolePrompt $dev $root $prompt
    $draft = Read-ConsoleDraft $dev $prompt
    Assert-DevToolsTarget $dev
    if ($Restore) {
        $body = Get-InjectionBody
        $check = 'if (window.__claudeRuntimeZh) throw new Error("Runtime translation still active");'
    } else {
        $body = Get-InjectionBody
        $check = 'if (!window.__claudeRuntimeZh || !window.__claudeRuntimeZh.status().active) throw new Error("Runtime translation not active");'
    }
    if (-not [string]::IsNullOrWhiteSpace($draft)) {
        $requestId = Get-OwnPendingRequestId $draft $body $check
        if ($requestId) {
            Write-Host 'Resuming an exact, unchanged command previously pasted by this launcher.'
        } elseif (Get-SavedConsoleRequestId $draft) {
            Write-Host 'Replacing a previously recorded local translation draft with the current version.'
            $requestId = [Guid]::NewGuid().ToString('N')
        } else {
            throw 'The Console contains an unrecognized unfinished command. Finish or clear it yourself, then retry.'
        }
    } else {
        $requestId = [Guid]::NewGuid().ToString('N')
    }
    $payload = New-ConsolePayload $body $check $requestId
    Save-OwnedConsolePayload $payload $requestId
    if ($draft.Replace("`r`n", "`n").Trim() -cne $payload.Replace("`r`n", "`n").Trim()) {
        Invoke-ClipboardAction 'Set' $payload
        if (-not [string]::IsNullOrWhiteSpace($draft)) { [ClaudeZhWindow]::Shortcut($dev.Handle, 0x41, $true, $false) }
        [ClaudeZhWindow]::Shortcut($dev.Handle, 0x56, $true, $false)
        Wait-Ui 1000
    }
    # Console executes with plain Enter; Ctrl+Enter belongs to Sources snippets.
    $token = 'CLAUDE_ZH_OK_' + $requestId
    Write-Host 'Local script pasted; a separate process will verify the exact text before execution.'
    Assert-DevToolsTarget $dev
    Write-Output ('CLAUDE_ZH_RESULT:' + ([pscustomobject]@{Token=$token;MainHandle=$main.Handle.ToInt64();DevHandle=$dev.Handle.ToInt64();OpenedDevTools=$openedDevTools} | ConvertTo-Json -Compress))
} catch {
    Write-Host ('STOPPED: ' + $_.Exception.Message) -ForegroundColor Yellow
    exit 1
} finally {
    if ($clipboardRunspace) { $clipboardRunspace.Dispose() }
}
