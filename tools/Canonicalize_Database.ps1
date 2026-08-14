# WoW API Workbench - Canonical API Database Builder
# Windows PowerShell 5.1 compatible. ASCII-only on purpose.
# Reads the raw all_products_api JSON and produces a normalized product-aware database.

[CmdletBinding()]
param(
    [string]$InputFile = '',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'output\canonical'
}

function Normalize-ProductGroup([string]$Product) {
    if ([string]::IsNullOrWhiteSpace($Product)) { return $null }
    switch ($Product) {
        'Retail' { return 'Retail' }
        'Classic' { return 'Classic' }
        'ClassicBeta' { return 'Classic' }
        'ClassicPTR' { return 'Classic' }
        'ClassicEra' { return 'ClassicEra' }
        'ClassicEraPTR' { return 'ClassicEra' }
        'ClassicAnniversary' { return 'ClassicAnniversary' }
        'ClassicTitan' { return 'ClassicAnniversary' }
        default { return $null }
    }
}

function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Get-StringArray($Value) {
    if ($null -eq $Value) { return @() }
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        if ($null -ne $item) { $result.Add([string]$item) }
    }
    return @($result)
}

function Get-FunctionKind($Record) {
    $name = [string](Get-Prop $Record 'Name')
    $namespace = [string](Get-Prop $Record 'Namespace')
    $source = [string](Get-Prop $Record 'Source')

    if ($name -match '^LE_[A-Za-z0-9_]+$' -or $name -match '^[A-Z][A-Z0-9_]+$') {
        if ([string]::IsNullOrWhiteSpace($namespace)) { return 'ConstantOrEnum' }
    }

    if ($source -eq 'documented') { return 'Function' }
    if (-not [string]::IsNullOrWhiteSpace($namespace)) { return 'FunctionCandidate' }
    if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') { return 'FunctionCandidate' }
    return 'Unknown'
}

function Get-ArgumentNames($Arguments) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($arg in @($Arguments)) {
        $name = [string](Get-Prop $arg 'Name')
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = 'arg' + ($result.Count + 1)
        }
        $safe = $name -replace '[^A-Za-z0-9_]', '_'
        if ($safe -match '^[0-9]') { $safe = 'arg_' + $safe }
        $result.Add($safe)
    }
    return @($result)
}

function New-LuaStub($Api) {
    $name = [string]$Api.fullName
    $args = @(Get-ArgumentNames $Api.arguments)
    $argText = $args -join ', '

    if ([string]::IsNullOrWhiteSpace($name)) { return '-- No callable name available' }

    $description = [string]$Api.description
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = 'Description was not present in the harvested API record.'
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('-- API: ' + $name)
    $lines.Add('-- Product: ' + $Api.productGroup)
    $lines.Add('-- Description: ' + ($description -replace '[\r\n]+', ' '))
    $lines.Add('-- This is a generated callable template. Verify runtime restrictions before use.')
    $lines.Add('')
    $lines.Add('local function Example_' + (($name -replace '[^A-Za-z0-9_]', '_')) + '(' + $argText + ')')
    $lines.Add('    return ' + $name + '(' + $argText + ')')
    $lines.Add('end')
    $lines.Add('')
    $lines.Add('return Example_' + (($name -replace '[^A-Za-z0-9_]', '_')))
    return ($lines -join [Environment]::NewLine)
}

function Find-InputFile {
    if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
        if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
            throw 'Input file not found: ' + $InputFile
        }
        return (Get-Item -LiteralPath $InputFile)
    }

    $preferred = @(
        (Join-Path $ProjectRoot 'data\raw\all_products_api.json'),
        (Join-Path $ProjectRoot 'data\all_products_api.json'),
        (Join-Path $ProjectRoot 'all_products_api.json')
    )

    foreach ($candidate in $preferred) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate)
        }
    }

    $hits = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Filter 'all_products_api.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\output\\' -and $_.FullName -notmatch '\\cache\\' } |
        Sort-Object Length -Descending)

    if ($hits.Count -gt 0) { return $hits[0] }
    throw 'Could not locate all_products_api.json. Put it under data\raw\ or pass -InputFile.'
}

$input = Find-InputFile
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Write-Host 'Loading raw API inventory:'
Write-Host ('  ' + $input.FullName)
Write-Host ('  Size: ' + [math]::Round($input.Length / 1MB, 2) + ' MB')

$raw = Get-Content -LiteralPath $input.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
$records = @($raw)

$groups = @('Retail','Classic','ClassicEra','ClassicAnniversary')
$canonical = @{}
$rawCounts = @{}
$branchCounts = @{}
$kindCounts = @{}
$ignored = 0

foreach ($record in $records) {
    $product = [string](Get-Prop $record 'Product')
    $group = Normalize-ProductGroup $product
    if ($null -eq $group) {
        $ignored++
        continue
    }

    if (-not $rawCounts.ContainsKey($group)) { $rawCounts[$group] = 0 }
    $rawCounts[$group]++

    $branch = [string](Get-Prop $record 'Branch')
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'unknown' }
    $branchKey = $group + '|' + $branch
    if (-not $branchCounts.ContainsKey($branchKey)) { $branchCounts[$branchKey] = 0 }
    $branchCounts[$branchKey]++

    $fullName = [string](Get-Prop $record 'FullName')
    $name = [string](Get-Prop $record 'Name')
    if ([string]::IsNullOrWhiteSpace($fullName)) { $fullName = $name }
    if ([string]::IsNullOrWhiteSpace($fullName)) {
        $ignored++
        continue
    }

    $key = $group + '|' + $fullName
    $kind = Get-FunctionKind $record
    if (-not $kindCounts.ContainsKey($kind)) { $kindCounts[$kind] = 0 }
    $kindCounts[$kind]++

    if (-not $canonical.ContainsKey($key)) {
        $canonical[$key] = [ordered]@{
            id = $key
            productGroup = $group
            fullName = $fullName
            namespace = [string](Get-Prop $record 'Namespace')
            name = $name
            kind = $kind
            system = [string](Get-Prop $record 'System')
            environment = [string](Get-Prop $record 'Environment')
            description = [string](Get-Prop $record 'Description')
            arguments = @((Get-Prop $record 'Arguments'))
            returns = @((Get-Prop $record 'Returns'))
            flags = @(Get-StringArray (Get-Prop $record 'Flags'))
            variants = @()
            sourcePriority = $null
        }
    }

    $entry = $canonical[$key]
    $source = [string](Get-Prop $record 'Source')
    $priority = if ($source -eq 'documented') { 2 } elseif ($source -eq 'source_discovered') { 1 } else { 0 }

    $variant = [ordered]@{
        product = $product
        productGroup = $group
        branch = $branch
        source = $source
        file = [string](Get-Prop $record 'File')
        environment = [string](Get-Prop $record 'Environment')
        description = [string](Get-Prop $record 'Description')
        arguments = @((Get-Prop $record 'Arguments'))
        returns = @((Get-Prop $record 'Returns'))
        flags = @(Get-StringArray (Get-Prop $record 'Flags'))
    }

    $variants = @($entry.variants)
    $variants += ,$variant
    $entry.variants = $variants

    if ($null -eq $entry.sourcePriority -or $priority -gt [int]$entry.sourcePriority) {
        $entry.sourcePriority = $priority
        $entry.system = [string](Get-Prop $record 'System')
        $entry.environment = [string](Get-Prop $record 'Environment')
        $entry.description = [string](Get-Prop $record 'Description')
        $entry.arguments = @((Get-Prop $record 'Arguments'))
        $entry.returns = @((Get-Prop $record 'Returns'))
        $entry.flags = @(Get-StringArray (Get-Prop $record 'Flags'))
    }

    $canonical[$key] = $entry
}

$items = @($canonical.Values | ForEach-Object {
    $api = $_
    $api.availability = [ordered]@{
        Retail = $false
        Classic = $false
        ClassicEra = $false
        ClassicAnniversary = $false
    }

    foreach ($variant in @($api.variants)) {
        $api.availability[$variant.productGroup] = $true
    }

    $api.luaStub = New-LuaStub $api
    $api
}) | Sort-Object productGroup, fullName

$byProduct = [ordered]@{}
foreach ($group in $groups) {
    $byProduct[$group] = @($items | Where-Object { $_.productGroup -eq $group })
}

$metadata = [ordered]@{
    schemaVersion = '2.5.0-canonical-1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    sourceFile = $input.FullName
    sourceSizeBytes = $input.Length
    rawRecordCount = $records.Count
    canonicalApiCount = $items.Count
    ignoredRecordCount = $ignored
    products = $groups
    rawCounts = $rawCounts
    branchCounts = $branchCounts
    classificationCounts = $kindCounts
    descriptionCoverage = [math]::Round((@($items | Where-Object { -not [string]::IsNullOrWhiteSpace($_.description) }).Count / [math]::Max(1,$items.Count)) * 100, 2)
    notes = @(
        'Canonical keys are productGroup plus FullName.',
        'ClassicBeta and ClassicPTR are grouped under Classic.',
        'ClassicEraPTR is grouped under ClassicEra.',
        'ClassicTitan is grouped under ClassicAnniversary.',
        'Source discovered records are retained as evidence and are not allowed to override documented signatures.',
        'No description text is invented when the raw dataset does not contain one.'
    )
}

$database = [ordered]@{
    metadata = $metadata
    apis = $items
}

$globalPath = Join-Path $OutputDir 'canonical_api_database.json'
$database | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $globalPath -Encoding UTF8

foreach ($group in $groups) {
    $path = Join-Path $OutputDir ($group + '.json')
    [ordered]@{
        product = $group
        generatedAt = $metadata.generatedAt
        apiCount = @($byProduct[$group]).Count
        apis = $byProduct[$group]
    } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
}

$reportPath = Join-Path $OutputDir 'canonical_build_report.txt'
$report = New-Object System.Collections.Generic.List[string]
$report.Add('WOW API WORKBENCH 2.5.0 - CANONICAL BUILD')
$report.Add('Generated: ' + $metadata.generatedAt)
$report.Add('Input: ' + $input.FullName)
$report.Add(('Raw records: ' + $records.Count))
$report.Add(('Canonical APIs: ' + $items.Count))
$report.Add(('Ignored records: ' + $ignored))
$report.Add(('Description coverage: ' + $metadata.descriptionCoverage + '%'))
$report.Add('')
$report.Add('PRODUCT API COUNTS')
foreach ($group in $groups) {
    $report.Add(('  {0}: {1}' -f $group, @($byProduct[$group]).Count))
}
$report.Add('')
$report.Add('RAW RECORD COUNTS')
foreach ($group in $groups) {
    $rawValue = if ($rawCounts.ContainsKey($group)) { $rawCounts[$group] } else { 0 }
    $report.Add(('  {0}: {1}' -f $group, $rawValue))
}
$report.Add('')
$report.Add('CLASSIFICATION COUNTS')
foreach ($key in ($kindCounts.Keys | Sort-Object)) {
    $report.Add(('  {0}: {1}' -f $key, $kindCounts[$key]))
}
$report.Add('')
$report.Add('OUTPUT')
$report.Add('  ' + $globalPath)
$report.Add('  ' + $reportPath)
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
$report | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host 'Canonical build completed successfully.'
