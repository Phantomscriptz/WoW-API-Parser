# WoW API Workbench - Canonical Database Validator
# Windows PowerShell 5.1 compatible. ASCII-only.

[CmdletBinding()]
param(
    [string]$DatabaseFile = ''
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptRoot

if ([string]::IsNullOrWhiteSpace($DatabaseFile)) {
    $DatabaseFile = Join-Path $ProjectRoot 'output\canonical\canonical_api_database.json'
}

if (-not (Test-Path -LiteralPath $DatabaseFile -PathType Leaf)) {
    Write-Host ('ERROR: canonical database not found: ' + $DatabaseFile)
    exit 2
}

$db = Get-Content -LiteralPath $DatabaseFile -Raw -Encoding UTF8 | ConvertFrom-Json
$fail = $false
$checks = New-Object System.Collections.Generic.List[string]

function Pass([string]$Message) {
    $checks.Add('[PASS] ' + $Message)
}

function Fail([string]$Message) {
    $script:fail = $true
    $checks.Add('[FAIL] ' + $Message)
}

if ($null -eq $db.metadata) { Fail 'metadata object is missing.' } else { Pass 'metadata object exists.' }
if ($null -eq $db.apis) { Fail 'apis array is missing.' } else { Pass 'apis array exists.' }

$apis = @($db.apis)
if ($apis.Count -le 0) { Fail 'canonical API array is empty.' } else { Pass ('canonical API count is ' + $apis.Count + '.') }

$expected = @('Retail','Classic','ClassicEra','ClassicAnniversary')
foreach ($group in $expected) {
    $count = @($apis | Where-Object { $_.productGroup -eq $group }).Count
    if ($count -le 0) { Fail ($group + ' has no canonical APIs.') } else { Pass ($group + ' has ' + $count + ' canonical APIs.') }
}

$badKeys = @($apis | Where-Object { [string]::IsNullOrWhiteSpace($_.id) -or [string]::IsNullOrWhiteSpace($_.fullName) -or [string]::IsNullOrWhiteSpace($_.productGroup) })
if ($badKeys.Count -gt 0) { Fail ($badKeys.Count + ' APIs have incomplete canonical keys.') } else { Pass 'All canonical APIs have productGroup, id, and fullName.' }

$duplicateIds = @($apis | Group-Object id | Where-Object { $_.Count -gt 1 })
if ($duplicateIds.Count -gt 0) { Fail ($duplicateIds.Count + ' duplicate canonical ids detected.') } else { Pass 'Canonical ids are unique.' }

$missingVariants = @($apis | Where-Object { @($_.variants).Count -le 0 })
if ($missingVariants.Count -gt 0) { Fail ($missingVariants.Count + ' APIs have no source variants.') } else { Pass 'Every canonical API retains source variants.' }

$missingAvailability = @($apis | Where-Object { $null -eq $_.availability })
if ($missingAvailability.Count -gt 0) { Fail ($missingAvailability.Count + ' APIs have no availability object.') } else { Pass 'Every canonical API has availability metadata.' }

$report = New-Object System.Collections.Generic.List[string]
$report.Add('WOW API WORKBENCH - CANONICAL DATABASE VALIDATION')
$report.Add('Database: ' + $DatabaseFile)
$report.Add('')
$checks | ForEach-Object { $report.Add($_) }
$report.Add('')
if ($fail) {
    $report.Add('RESULT: FAILED')
    $report | ForEach-Object { Write-Host $_ }
    $reportPath = Join-Path (Split-Path -Parent $DatabaseFile) 'canonical_validation.txt'
    $report | Set-Content -LiteralPath $reportPath -Encoding UTF8
    exit 1
}
else {
    $report.Add('RESULT: PASSED')
    $report | ForEach-Object { Write-Host $_ }
    $reportPath = Join-Path (Split-Path -Parent $DatabaseFile) 'canonical_validation.txt'
    $report | Set-Content -LiteralPath $reportPath -Encoding UTF8
    exit 0
}
