# WoW API Workbench 2.5.0 - canonical inventory builder
# Windows PowerShell 5.1 compatible.
# READS raw inventory and writes derived canonical inventory; never modifies source data.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DataDir = Join-Path $Root 'data'
$ConfigDir = Join-Path $Root 'config'
$OutputDir = Join-Path $Root 'output'
$DiagDir = Join-Path $Root 'diagnostics'

foreach ($d in @($OutputDir,$DiagDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

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
    $production[[string]$p.product] = [pscustomobject]$p
}

Write-Host 'Loading all_products_api.json ...'
$records = @(Get-Content -LiteralPath $rawPath -Raw -Encoding UTF8 | ConvertFrom-Json)
Write-Host ('Loaded records: ' + $records.Count)

function Get-Text($v) {
    if ($null -eq $v) { return $null }
    return [string]$v
}

function Get-CanonicalId($r) {
    $id = Get-Text $r.Id
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        return ((Get-Text $r.Product) + ':' + $id)
    }
    $full = Get-Text $r.FullName
    if ([string]::IsNullOrWhiteSpace($full)) { $full = Get-Text $r.Name }
    return ((Get-Text $r.Product) + ':' + $full)
}

$canonical = New-Object System.Collections.Generic.List[object]
$excluded = New-Object System.Collections.Generic.List[object]
$missingIdentity = New-Object System.Collections.Generic.List[object]
$duplicateKeys = @{}
$productCounts = @{}
$sourceCounts = @{}

foreach ($r in $records) {
    $product = Get-Text $r.Product
    if (-not $production.ContainsKey($product)) {
        $excluded.Add([pscustomobject]@{
            Product = $product
            Branch = Get-Text $r.Branch
            Id = Get-Text $r.Id
            FullName = Get-Text $r.FullName
        })
        continue
    }

    $fullName = Get-Text $r.FullName
    $name = Get-Text $r.Name
    if ([string]::IsNullOrWhiteSpace($fullName) -and [string]::IsNullOrWhiteSpace($name)) {
        $missingIdentity.Add([pscustomobject]@{ Product = $product; Id = Get-Text $r.Id; File = Get-Text $r.File })
    }

    $key = $product + '|' + $fullName
    if (-not $duplicateKeys.ContainsKey($key)) { $duplicateKeys[$key] = 0 }
    $duplicateKeys[$key]++

    if (-not $productCounts.ContainsKey($product)) { $productCounts[$product] = 0 }
    $productCounts[$product]++
    $src = Get-Text $r.Source
    if ([string]::IsNullOrWhiteSpace($src)) { $src = 'unknown' }
    if (-not $sourceCounts.ContainsKey($src)) { $sourceCounts[$src] = 0 }
    $sourceCounts[$src]++

    $canonical.Add([ordered]@{
        schemaVersion = '2.5.0'
        canonicalId = Get-CanonicalId $r
        apiId = Get-Text $r.Id
        product = $product
        branch = Get-Text $r.Branch
        production = $true
        environment = Get-Text $r.Environment
        source = [ordered]@{
            name = $src
            file = Get-Text $r.File
            system = Get-Text $r.System
        }
        identity = [ordered]@{
            name = $name
            fullName = $fullName
            namespace = Get-Text $r.Namespace
        }
        documentation = [ordered]@{
            description = $r.Description
            arguments = $r.Arguments
            returns = $r.Returns
            flags = $r.Flags
        }
        verification = [ordered]@{
            availabilityStatus = 'source-present'
            verificationStatus = 'unverified'
            build = $null
            evidence = @()
        }
        examples = [ordered]@{
            basic = @()
            moderate = @()
            advanced = @()
            advancedMaximum = 20
            dependenciesValidated = $false
        }
    })
}

$duplicates = @($duplicateKeys.GetEnumerator() | Where-Object { $_.Value -gt 1 } | ForEach-Object {
    [pscustomobject]@{ Key = $_.Key; Count = $_.Value }
})

$manifest = [ordered]@{
    schemaVersion = '2.5.0'
    generated = (Get-Date).ToString('o')
    source = 'data/all_products_api.json'
    sourceRecordCount = $records.Count
    productionRecordCount = $canonical.Count
    excludedRecordCount = $excluded.Count
    missingIdentityCount = $missingIdentity.Count
    duplicateProductFullNameKeys = $duplicates.Count
    productCounts = $productCounts
    sourceCounts = $sourceCounts
    rules = [ordered]@{
        sourcePresenceIsNotVerification = $true
        examplesRequireVerifiedAvailability = $true
        advancedExampleMaximumPerApiProduct = 20
        excludedBranchesRemainReferenceOnly = $true
    }
    excludedProducts = @('ClassicPTR','ClassicEraPTR','ClassicBeta','ClassicTitan')
    validation = [ordered]@{
        status = if ($missingIdentity.Count -eq 0) { 'PASS' } else { 'REVIEW' }
        notes = @(
            'Canonical inventory includes only the four production products.'
            'Availability is intentionally source-present/unverified until independent verification is implemented.'
            'Raw source inventory is never modified by this script.'
        )
    }
}

$payload = [ordered]@{
    manifest = $manifest
    records = $canonical
}

Write-Host ('Writing canonical inventory: ' + $outPath)
$payload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $outPath -Encoding UTF8

$report = New-Object System.Collections.Generic.List[string]
$report.Add('WOW API WORKBENCH 2.5.0 - CANONICAL INVENTORY VALIDATION')
$report.Add('Generated: ' + (Get-Date).ToString('o'))
$report.Add('Source records: ' + $records.Count)
$report.Add('Production records: ' + $canonical.Count)
$report.Add('Excluded reference-only records: ' + $excluded.Count)
$report.Add('Missing identity records: ' + $missingIdentity.Count)
$report.Add('Duplicate Product|FullName keys: ' + $duplicates.Count)
$report.Add('')
$report.Add('PRODUCTION PRODUCT COUNTS')
foreach ($name in @('Retail','Classic','ClassicEra','ClassicAnniversary')) {
    $count = 0
    if ($productCounts.ContainsKey($name)) { $count = $productCounts[$name] }
    $report.Add(('  {0}: {1}' -f $name,$count))
}
$report.Add('')
$report.Add('POLICY')
$report.Add('  Source presence = inventory membership only')
$report.Add('  Runtime availability = NOT YET VERIFIED')
$report.Add('  Example generation = blocked until verification/dependency validation exists')
$report.Add('  Advanced examples maximum = 20 per API/product target')
$report.Add('')
$report.Add('OUTPUT: ' + $outPath)
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ForEach-Object { Write-Host $_ }
