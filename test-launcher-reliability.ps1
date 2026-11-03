$ErrorActionPreference = 'Stop'
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'launch-zh.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors | Out-String)}
foreach($name in @('Get-ConsolePayloadDigest','Save-OwnedConsolePayload','Get-SavedConsoleRequestId','New-ConsolePayload','Get-OwnPendingRequestId','Open-ClaudeDevTools','Get-DevToolsPageKind','Read-ChildProcessResult','Focus-Window','Get-CopiedConsoleDraft')){
 $definition=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object {$_.Name -eq $name})
 if($definition.Count -ne 1){throw ('Missing unique function: '+$name)}
 . ([scriptblock]::Create($definition[0].Extent.Text))
}
$script:tests=New-Object System.Collections.Generic.List[object]
function Check([string]$Name,[bool]$Passed){if(-not $Passed){throw ('FAIL: '+$Name)};$script:tests.Add([pscustomobject]@{name=$Name;passed=$true})}
$ownedDraftDirectory=Join-Path (Split-Path $PSScriptRoot -Parent) ('logs\draft-tests-'+[Guid]::NewGuid().ToString('N'))
$Restore=$false
$id='0123456789abcdef0123456789abcdef'
$payload=New-ConsolePayload 'oldLocalVersion();' 'checkLocalVersion();' $id
Save-OwnedConsolePayload $payload $id
Check 'Saved old revision recognized by entire payload hash' ((Get-SavedConsoleRequestId $payload) -ceq $id)
Check 'Changed draft rejected' ($null -eq (Get-SavedConsoleRequestId ($payload+';otherCommand();')))
Check 'CRLF and edge whitespace accepted' ((Get-SavedConsoleRequestId ("`n"+$payload.Replace("`n","`r`n")+"`n")) -ceq $id)
Check 'Current exact revision still recognized' ((Get-OwnPendingRequestId $payload 'oldLocalVersion();' 'checkLocalVersion();') -ceq $id)
Check 'Old revision does not match current revision body' ($null -eq (Get-OwnPendingRequestId $payload 'newLocalVersion();' 'checkLocalVersion();'))
$unknown=New-ConsolePayload 'unknown();' 'check();' '11111111111111111111111111111111'
Check 'Unknown request ID rejected' ($null -eq (Get-SavedConsoleRequestId $unknown))
Check 'Multiple request markers rejected' ($null -eq (Get-SavedConsoleRequestId ($payload+"console.info('CLAUDE_ZH_OK_' + '11111111111111111111111111111111');")))
$recordPath=Join-Path $ownedDraftDirectory ($id+'.json')
$record=[System.IO.File]::ReadAllText($recordPath)
Check 'Record contains only metadata, no copied payload' (-not $record.Contains('oldLocalVersion'))
[System.IO.File]::WriteAllText($recordPath,'broken-json')
Check 'Corrupted record rejected' ($null -eq (Get-SavedConsoleRequestId $payload))
$failed=$false
try{Save-OwnedConsolePayload $payload '..\escape'}catch{$failed=$true}
Check 'Invalid record path rejected' $failed

function New-TestProcess([string]$Code){
 $info=New-Object System.Diagnostics.ProcessStartInfo
 $info.FileName=Join-Path $PSHOME 'powershell.exe'
 $info.Arguments='-NoProfile -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 return [Diagnostics.Process]::Start($info)
}
$process=New-TestProcess '[Console]::Out.Write(("x"*200000));[Console]::Error.Write(("y"*200000));exit 0'
try{
 $reply=Read-ChildProcessResult $process 10000
 Check 'Both large redirected streams drain without deadlock' ($reply.ExitCode -eq 0 -and $reply.Output.Length -eq 200000 -and $reply.Error.Length -eq 200000)
}finally{$process.Dispose()}
$process=New-TestProcess 'Start-Sleep -Seconds 10'
try{
 $failed=$false;try{Read-ChildProcessResult $process 100 | Out-Null}catch{$failed=$true}
 [void]$process.WaitForExit(5000)
 Check 'Timed-out local helper is stopped' ($failed -and $process.HasExited)
}finally{$process.Dispose()}

$script:main=[pscustomobject]@{Handle=[IntPtr]100;Title='Claude'}
function New-Dev([int]$Id){$title=if($Id -eq 201){'Developer Tools - app://localhost/setup-desktop-3p'}elseif($Id -eq 301){'Developer Tools - app://localhost/unrecognized'}else{'Developer Tools - app://localhost/new?coldLaunch=1'};return [pscustomobject]@{Handle=[IntPtr]$Id;Title=$title}}
function Reset-DevScenario([string]$Scenario){$script:scenario=$Scenario;$script:toggles=0;$script:waits=0;$script:cancel=$false}
function Focus-Window($window){}
function Send-DevToolsToggle($window){$script:toggles++}
function Assert-NotCancelled{if($script:cancel){throw 'Cancelled test.'}}
function Wait-Ui([int]$milliseconds){Assert-NotCancelled;$script:waits++;if($script:waits -gt 4){throw 'No foreground target test.'}}
function Get-ClaudeDevWindows{
 switch($script:scenario){
  'new'{if($script:toggles){New-Dev 101}}
  'existing'{New-Dev 101}
  'reopen'{if(-not $script:toggles){New-Dev 101}elseif($script:toggles -gt 1){New-Dev 102}}
  'ambiguous'{New-Dev 101;New-Dev 102}
  'unknown'{New-Dev 301}
  'other-page'{New-Dev 201;if($script:toggles){New-Dev 101}}
  'lost-focus'{}
 }
}
function Get-ForegroundHandle{
 switch($script:scenario){
  'new'{return 101}
  'existing'{return 101}
  'reopen'{if($script:toggles -gt 1){return 102};return 100}
  'other-page'{return 101}
  'lost-focus'{return 999}
 }
}
Reset-DevScenario 'new'
$result=Open-ClaudeDevTools $script:main
Check 'New DevTools opens once and is marked for closing' ($script:toggles -eq 1 -and $result.OpenedNew)
Reset-DevScenario 'existing'
$result=Open-ClaudeDevTools $script:main
Check 'Existing DevTools reused without toggling or losing its draft' ($script:toggles -eq 0 -and -not $result.OpenedNew)
Reset-DevScenario 'reopen'
$result=Open-ClaudeDevTools $script:main
Check 'Already-open target is never closed by the shortcut' ($script:toggles -eq 0 -and $result.Window.Handle.ToInt64() -eq 101 -and -not $result.OpenedNew)
Reset-DevScenario 'other-page'
$result=Open-ClaudeDevTools $script:main
Check 'Another page DevTools does not become the selected target' ($result.Window.Handle.ToInt64() -eq 101 -and $result.OpenedNew)
Reset-DevScenario 'lost-focus'
$failed=$false;try{Open-ClaudeDevTools $script:main | Out-Null}catch{$failed=$true}
Check 'Unrelated foreground window never becomes a target' ($failed -and $script:toggles -eq 1)
Reset-DevScenario 'new';$script:cancel=$true
$failed=$false;try{Open-ClaudeDevTools $script:main | Out-Null}catch{$failed=$true}
Check 'Cancellation stops DevTools selection' $failed
Reset-DevScenario 'ambiguous'
$failed=$false;try{Open-ClaudeDevTools $script:main | Out-Null}catch{$failed=$true}
Check 'Ambiguous existing targets fail before toggling' ($failed -and $script:toggles -eq 0)
Reset-DevScenario 'unknown'
$failed=$false;try{Open-ClaudeDevTools $script:main | Out-Null}catch{$failed=$true}
Check 'Unidentified existing target is left untouched' ($failed -and $script:toggles -eq 0)
Check 'Configuration route is distinct from main page' ((Get-DevToolsPageKind 'Developer Tools - app://localhost/setup-desktop-3p') -eq 'configuration')
Check 'Lookalike remote host is rejected' ((Get-DevToolsPageKind 'Developer Tools - https://claude.ai.example.com/new') -eq 'unknown')

Add-Type -TypeDefinition @'
using System;
public static class ClaudeZhWindow {
 public static IntPtr Current = IntPtr.Zero;
 public static bool Grant;
 public static int Activations;
 public static IntPtr GetForegroundWindow() { return Current; }
 public static bool ShowWindow(IntPtr handle, int command) { return true; }
 public static bool Activate(IntPtr handle) { Activations++; if (Grant) Current=handle; return Grant; }
}
'@
$definition=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object {$_.Name -eq 'Focus-Window'}
. ([scriptblock]::Create($definition.Extent.Text))
function Wait-Ui([int]$milliseconds){
 $script:waits++
 if($script:scenario -eq 'manual-focus' -and $script:waits -eq 2){[ClaudeZhWindow]::Current=[IntPtr]100}
 if($script:scenario -eq 'cancel-focus' -and $script:waits -eq 2){$script:cancel=$true}
 Assert-NotCancelled
 if($script:waits -gt 4){throw 'Unexpected focus wait.'}
}
Reset-DevScenario 'focus-granted';[ClaudeZhWindow]::Current=[IntPtr]999;[ClaudeZhWindow]::Grant=$true;[ClaudeZhWindow]::Activations=0
Focus-Window $script:main
Check 'Granted foreground activation returns immediately' ([ClaudeZhWindow]::Current.ToInt64() -eq 100 -and $script:waits -eq 1)
Reset-DevScenario 'manual-focus';[ClaudeZhWindow]::Current=[IntPtr]999;[ClaudeZhWindow]::Grant=$false;[ClaudeZhWindow]::Activations=0
Focus-Window $script:main
Check 'Manual foreground change accepted without repeated focus stealing' ([ClaudeZhWindow]::Current.ToInt64() -eq 100 -and [ClaudeZhWindow]::Activations -eq 1)
Reset-DevScenario 'cancel-focus';[ClaudeZhWindow]::Current=[IntPtr]999;[ClaudeZhWindow]::Grant=$false;[ClaudeZhWindow]::Activations=0
$failed=$false;try{Focus-Window $script:main}catch{$failed=$true}
Check 'Foreground wait respects cancellation and leaves unrelated window untouched' ($failed -and [ClaudeZhWindow]::Current.ToInt64() -eq 999 -and [ClaudeZhWindow]::Activations -eq 1)
Reset-DevScenario 'focus-granted';$script:cancel=$true;[ClaudeZhWindow]::Activations=0
$failed=$false;try{Focus-Window $script:main}catch{$failed=$true}
Check 'Already-cancelled focus never attempts activation' ($failed -and [ClaudeZhWindow]::Activations -eq 0)

function Assert-DevToolsTarget($dev){if($script:clipboardFocusLost){throw 'Focus changed.'}}
function Invoke-ClipboardAction($operation){$script:reads++;if($script:reads -ge $script:readyAt){return 'entire verified draft'};return 'sentinel'}
function Wait-Ui([int]$milliseconds){}
$script:clipboardFocusLost=$false;$script:reads=0;$script:readyAt=6
Check 'Delayed clipboard copy waits for actual changed content' ((Get-CopiedConsoleDraft $null 'sentinel') -ceq 'entire verified draft' -and $script:reads -eq 6)
$script:reads=0;$script:readyAt=100
Check 'Unchanged clipboard times out without accepting sentinel' ($null -eq (Get-CopiedConsoleDraft $null 'sentinel') -and $script:reads -eq 20)
$script:clipboardFocusLost=$true;$script:reads=0
$failed=$false;try{Get-CopiedConsoleDraft $null 'sentinel' | Out-Null}catch{$failed=$true}
Check 'Clipboard confirmation stops immediately if target loses focus' ($failed -and $script:reads -eq 0)

[pscustomobject]@{passed=$true;test_count=$script:tests.Count;ui_actions_performed=$false;tests=$script:tests} | ConvertTo-Json -Depth 5
