# WoW API Workbench 2.5.0 - canonical inventory builder
# Windows PowerShell 5.1 compatible.
# Reads the raw inventory and writes a derived canonical inventory.
# The raw source dataset is never modified.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DataDir = Join-Path $Root 'data'
$ConfigDir = Join-Path $Root 'config'
$OutputDir = Join-Path $Root 'output'
$DiagDir = Join-Path $Root 'diagnostics'

New-Item -ItemType Directory -Force -Path $OutputDir,$DiagDir | Out-Null

$rawPath = Join-Path $DataDir 'all_products_api.json'
$policyPath = Join-Path $ConfigDir 'product_matrix.json'
$outPath = Join-Path $OutputDir 'canonical_api_inventory.json'
$reportPath = Join-Path $DiagDir 'canonical_inventory_validation.txt'

if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
    throw 'Missing data\all_products_api.json'
}
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    throw 'Missing config\product_matrix.json'
}

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$production = @{}
foreach ($p in @($policy.productionProducts)) {
    $production[[string]$p.product] = $true
}

Write-Host 'Loading all_products_api.json ...'
$records = @(Get-Content -LiteralPath $rawPath -Raw -Encoding UTF8 | ConvertFrom-Json)
Write-Host ('Loaded records: ' + $records.Count)

function Get-Text($Value) {
    if ($null -eq $Value) { return $null }
    return [string]$Value
}

function Get-CanonicalId($Record) {
    $product = Get-Text $Record.Product
    $id = Get-Text $Record.Id
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        return ($product + ':' + $id)
    }

    $full = Get-Text $Record.FullName
    if ([string]::IsNullOrWhiteSpace($full)) {
        $full = Get-Text $Record.Name
    }
    return ($product + ':' + $full)
}

# Build plain PowerShell objects through the pipeline instead of using
# generic List[object].Add(). This avoids a Windows PowerShell 5.1
# ArgumentException seen with mixed dictionary/object values.
$canonical = @(
    foreach ($r in $records) {
        $product = Get-Text $r.Product
        if (-not $production.ContainsKey($product)) {
            continue
        }

        [pscustomobject][ordered]@{
            schemaVersion = '2.5.0'
            canonicalId = Get-CanonicalId $r
            apiId = Get-Text $r.Id
            product = $product
            branch = Get-Text $r.Branch
            production = $true
            environment = Get-Text $r.Environment
            source = [pscustomobject][ordered]@{
                name = Get-Text $r.Source
                file = Get-Text $r.File
                system = Get-Text $r.System
            }
            identity = [pscustomobject][ordered]@{
                name = Get-Text $r.Name
                fullName = Get-Text $r.FullName
                namespace = Get-Text $r.Namespace
            }
            documentation = [pscustomobject][ordered]@{
                description = $r.Description
                arguments = $r.Arguments
                returns = $r.Returns
                flags = $r.Flags
            }
            verification = [pscustomobject][ordered]@{
                availabilityStatus = 'source-present'
                verificationStatus = 'unverified'
                build = $null
                evidence = @()
            }
            examples = [pscustomobject][ordered]@{
                basic = @()
                moderate = @()
                advanced = @()
                advancedMaximum = 20
                dependenciesValidated = $false
            }
        }
    }
)

$productCounts = @{}
$sourceCounts = @{}
$missingIdentityCount = 0
$duplicateKeys = @{}

foreach ($r in $canonical) {
    $product = [string]$r.product
    if (-not $productCounts.ContainsKey($product)) { $productCounts[$product] = 0 }
    $productCounts[$product]++

    $src = [string]$r.source.name
    if ([string]::IsNullOrWhiteSpace($src)) { $src = 'unknown' }
    if (-not $sourceCounts.ContainsKey($src)) { $sourceCounts[$src] = 0 }
    $sourceCounts[$src]++

    if ([string]::IsNullOrWhiteSpace([string]$r.identity.fullName) -and [string]::IsNullOrWhiteSpace([string]$r.identity.name)) {
        $missingIdentityCount++
    }

    $key = $product + '|' + [string]$r.identity.fullName
    if (-not $duplicateKeys.ContainsKey($key)) { $duplicateKeys[$key] = 0 }
    $duplicateKeys[$key]++
}

$duplicateCount = 0
foreach ($key in $duplicateKeys.Keys) {
    if ($duplicateKeys[$key] -gt 1) { $duplicateCount++ }
}

$excludedCount = $records.Count - $canonical.Count

$manifest = [pscustomobject][ordered]@{
    schemaVersion = '2.5.0'
    generated = (Get-Date).ToString('o')
    source = 'data/all_products_api.json'
    sourceRecordCount = $records.Count
    productionRecordCount = $canonical.Count
    excludedReferenceOnlyRecordCount = $excludedCount
    missingIdentityCount = $missingIdentityCount
    duplicateProductFullNameKeys = $duplicateCount
    productCounts = $productCounts
    sourceCounts = $sourceCounts
    rules = [pscustomobject][ordered]@{
        sourcePresenceIsNotVerification = $true
        examplesRequireVerifiedAvailability = $true
        advancedExampleMaximumPerApiProduct = 20
        excludedBranchesRemainReferenceOnly = $true
    }
    excludedProducts = @('ClassicPTR','ClassicEraPTR','ClassicBeta','ClassicTitan')
    validation = [pscustomobject][ordered]@{
        status = if ($missingIdentityCount -eq 0) { 'PASS' } else { 'REVIEW' }
        notes = @(
            'Canonical inventory includes only the four production products.'
            'Availability is intentionally source-present/unverified until independent verification is implemented.'
            'Raw source inventory is never modified by this script.'
        )
    }
}

$payload = [pscustomobject][ordered]@{
    manifest = $manifest
    records = $canonical
}

Write-Host ('Writing canonical inventory: ' + $outPath)
$payload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $outPath -Encoding UTF8

$report = @(
    'WOW API WORKBENCH 2.5.0 - CANONICAL INVENTORY VALIDATION'
    ('Generated: ' + (Get-Date).ToString('o'))
    ('Source records: ' + $records.Count)
    ('Production records: ' + $canonical.Count)
    ('Excluded reference-only records: ' + $excludedCount)
    ('Missing identity records: ' + $missingIdentityCount)
    ('Duplicate Product|FullName keys: ' + $duplicateCount)
    ''
    'PRODUCTION PRODUCT COUNTS'
    ('  Retail: ' + $(if ($productCounts.ContainsKey('Retail')) { $productCounts['Retail'] } else { 0 }))
    ('  Classic: ' + $(if ($productCounts.ContainsKey('Classic')) { $productCounts['Classic'] } else { 0 }))
    ('  ClassicEra: ' + $(if ($productCounts.ContainsKey('ClassicEra')) { $productCounts['ClassicEra'] } else { 0 }))
    ('  ClassicAnniversary: ' + $(if ($productCounts.ContainsKey('ClassicAnniversary')) { $productCounts['ClassicAnniversary'] } else { 0 }))
    ''
    'POLICY'
    '  Source presence = inventory membership only'
    '  Runtime availability = NOT YET VERIFIED'
    '  Example generation = blocked until verification/dependency validation exists'
    '  Advanced examples maximum = 20 per API/product target'
    ''
    ('OUTPUT: ' + $outPath)
)

$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ForEach-Object { Write-Host $_ }
