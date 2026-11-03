$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$sourcePath = Join-Path $PSScriptRoot 'launch-zh.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Get-OpenConfigurationWindows', 'Invoke-CombinedTranslation', 'Start-RegisteredClaude')) {
    $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $_.Name -eq $name }
    if (@($definition).Count -ne 1) { throw ('Missing unique function: ' + $name) }
    . ([scriptblock]::Create($definition.Extent.Text))
}

$script:records = New-Object System.Collections.Generic.List[object]
$script:cases = New-Object System.Collections.Generic.List[object]
function Reset-Scenario([int]$Configurations = 0) {
    $script:records.Clear()
    $script:windowReads = 0
    $script:cancelChecks = 0
    $script:cancelAt = 0
    $script:failMain = $false
    $script:failConfiguration = $false
    $script:closeConfigurationAfterMain = $false
    $script:windows = @(
        [pscustomobject]@{Title='Claude';IsConfiguration=$false},
        [pscustomobject]@{Title='Developer Tools - app://localhost/new';IsConfiguration=$true}
    )
    for ($i=0; $i -lt $Configurations; $i++) {
        $script:windows += [pscustomobject]@{Title='Inference';IsConfiguration=$true}
    }
}
function Get-ClaudeWindows { $script:windowReads++; return $script:windows }
function Test-ConfigurationWindow($window) { return $window.IsConfiguration }
function Assert-NotCancelled {
    $script:cancelChecks++
    if ($script:cancelAt -and $script:cancelChecks -eq $script:cancelAt) { throw 'Escape pressed.' }
}
function Invoke-ClaudeWindowLauncher([bool]$ConfigurationTarget, [bool]$RestoreTarget) {
    $script:records.Add([pscustomobject]@{Configuration=$ConfigurationTarget;Restore=$RestoreTarget})
    if ($ConfigurationTarget -and $script:failConfiguration) { throw 'Configuration failed.' }
    if (-not $ConfigurationTarget -and $script:failMain) { throw 'Main failed.' }
    if (-not $ConfigurationTarget -and $script:closeConfigurationAfterMain) {
        $script:windows = @($script:windows | Where-Object { -not $_.IsConfiguration })
    }
}
function Assert-Case([string]$Name, [bool]$Passed) {
    if (-not $Passed) { throw ('FAIL: ' + $Name) }
    $script:cases.Add([pscustomobject]@{name=$Name;passed=$true})
}
function Invoke-ExpectFailure([string]$Pattern) {
    $caught = $null
    try { Invoke-CombinedTranslation -RestoreTarget $false | Out-Null } catch { $caught = $_.Exception.Message }
    if (-not $caught -or $caught -notmatch $Pattern) { throw ('Expected failure matching ' + $Pattern + '; got ' + $caught) }
}

Reset-Scenario
Invoke-CombinedTranslation -RestoreTarget $false | Out-Null
Assert-Case 'No configuration: main only, DevTools excluded' ($script:records.Count -eq 1 -and -not $script:records[0].Configuration)

Reset-Scenario 1
Invoke-CombinedTranslation -RestoreTarget $false | Out-Null
Assert-Case 'One configuration: main then configuration' ($script:records.Count -eq 2 -and -not $script:records[0].Configuration -and $script:records[1].Configuration)

Reset-Scenario 1
Invoke-CombinedTranslation -RestoreTarget $true | Out-Null
Assert-Case 'Restore flag reaches both targets' ($script:records.Count -eq 2 -and $script:records[0].Restore -and $script:records[1].Restore)

Reset-Scenario 2
Invoke-ExpectFailure 'More than one'
Assert-Case 'Ambiguous configuration fails without selecting a target' ($script:records.Count -eq 1)

Reset-Scenario 1
$script:failMain = $true
Invoke-ExpectFailure 'Main failed'
Assert-Case 'Main failure stops before configuration detection' ($script:records.Count -eq 1 -and $script:windowReads -eq 0)

Reset-Scenario 1
$script:failConfiguration = $true
Invoke-ExpectFailure 'Configuration failed'
Assert-Case 'Configuration failure propagates' ($script:records.Count -eq 2)

Reset-Scenario 1
$script:cancelAt = 1
Invoke-ExpectFailure 'Escape'
Assert-Case 'Initial cancellation prevents all execution' ($script:records.Count -eq 0)

Reset-Scenario 1
$script:cancelAt = 2
Invoke-ExpectFailure 'Escape'
Assert-Case 'Cancellation after main prevents configuration execution' ($script:records.Count -eq 1 -and $script:windowReads -eq 0)

Reset-Scenario 1
$script:closeConfigurationAfterMain = $true
Invoke-CombinedTranslation -RestoreTarget $false | Out-Null
Assert-Case 'Configuration is re-detected after main, not held stale' ($script:records.Count -eq 1 -and $script:windowReads -eq 1)

function Get-StartApps { return $script:registeredApps }
function Start-Process($FilePath, $ArgumentList, $WindowStyle) {
    $script:startedApplication = [pscustomobject]@{File=$FilePath;Arguments=$ArgumentList;Style=$WindowStyle}
}
$script:startedApplication = $null
$script:registeredApps = @(
    [pscustomobject]@{AppID='Claude_example!Claude'},
    [pscustomobject]@{AppID='Claude_example!Claude'},
    [pscustomobject]@{AppID='Unrelated_app!App'}
)
Start-RegisteredClaude
Assert-Case 'Duplicate registrations for the same app launch once' ($script:startedApplication.Arguments -ceq 'shell:AppsFolder\Claude_example!Claude')

$script:startedApplication = $null
$script:registeredApps += [pscustomobject]@{AppID='Claude_other!Claude'}
$caught = $false
try { Start-RegisteredClaude } catch { $caught = $true }
Assert-Case 'Distinct registered app IDs remain ambiguous' ($caught -and $null -eq $script:startedApplication)

$script:registeredApps = @()
$caught = $false
try { Start-RegisteredClaude } catch { $caught = $true }
Assert-Case 'Missing registered application fails without launching' ($caught -and $null -eq $script:startedApplication)

[pscustomobject]@{passed=$true;test_count=$script:cases.Count;ui_actions_performed=$false;tests=$script:cases} | ConvertTo-Json -Depth 5
