# WoW API Workbench - database schema inspection
# Windows PowerShell 5.1 compatible. Read-only: does not modify the API datasets.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DataDir = Join-Path $Root 'data'
$DiagDir = Join-Path $Root 'diagnostics'
New-Item -ItemType Directory -Force -Path $DiagDir | Out-Null

$reportPath = Join-Path $DiagDir 'database_schema_report.txt'
$lines = New-Object System.Collections.Generic.List[string]

function Add-Line([string]$s = '') { $lines.Add($s) }
function Add-PropertySummary($record, [string]$prefix = '') {
    if ($null -eq $record) { return }
    foreach ($p in $record.PSObject.Properties) {
        $name = $prefix + $p.Name
        $value = $p.Value
        $type = if ($null -eq $value) { 'null' } else { $value.GetType().FullName }
        $preview = ''
        if ($null -ne $value -and $value -isnot [System.Collections.IEnumerable]) {
            $preview = [string]$value
            if ($preview.Length -gt 180) { $preview = $preview.Substring(0,180) + '...' }
        }
        Add-Line ('  {0} | type={1} | preview={2}' -f $name,$type,$preview)
    }
}

Add-Line 'WOW API WORKBENCH - DATABASE SCHEMA INSPECTION'
Add-Line ('Generated: ' + (Get-Date).ToString('o'))
Add-Line ('Root: ' + $Root)
Add-Line ''

foreach ($name in @('all_products_api.json','all_products_api.csv','product_diffs.json','master_manifest.json')) {
    $path = Join-Path $DataDir $name
    Add-Line ('=== ' + $name + ' ===')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Line 'MISSING'
        Add-Line ''
        continue
    }
    $file = Get-Item -LiteralPath $path
    Add-Line ('SizeBytes: ' + $file.Length)

    if ($file.Extension -ieq '.csv') {
        $rows = @(Import-Csv -LiteralPath $path)
        Add-Line ('Rows: ' + $rows.Count)
        if ($rows.Count -gt 0) {
            Add-Line 'Columns:'
            foreach ($h in $rows[0].PSObject.Properties.Name) { Add-Line ('  ' + $h) }
            Add-Line 'First record:'
            Add-PropertySummary $rows[0]
            Add-Line 'Distinct Product values:'
            if ($rows[0].PSObject.Properties.Name -contains 'Product') {
                $rows | Group-Object Product | Sort-Object Name | ForEach-Object { Add-Line ('  {0}: {1}' -f $_.Name,$_.Count) }
            }
        }
    }
    else {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        try {
            $parsed = $raw | ConvertFrom-Json
            Add-Line ('Root JSON type: ' + $parsed.GetType().FullName)
            Add-Line 'Root properties:'
            if ($parsed -is [pscustomobject]) {
                foreach ($p in $parsed.PSObject.Properties) {
                    $kind = if ($p.Value -is [System.Array]) { 'array(count=' + @($p.Value).Count + ')' } else { $p.Value.GetType().FullName }
                    Add-Line ('  {0} | {1}' -f $p.Name,$kind)
                }
            }
            Add-Line 'Candidate record collections:'
            foreach ($candidate in @('records','items','entries','data','apis','products')) {
                if ($parsed -is [pscustomobject] -and $parsed.PSObject.Properties.Name -contains $candidate) {
                    $arr = @($parsed.$candidate)
                    Add-Line ('  ' + $candidate + ': ' + $arr.Count)
                    if ($arr.Count -gt 0) {
                        Add-Line ('  First ' + $candidate + ' record:')
                        Add-PropertySummary $arr[0] '    '
                    }
                }
            }
            if ($parsed -is [System.Array] -and @($parsed).Count -gt 0) {
                Add-Line 'First array record:'
                Add-PropertySummary @($parsed)[0]
            }
        }
        catch {
            Add-Line ('JSON parse ERROR: ' + $_.Exception.Message)
        }
    }
    Add-Line ''
}

Add-Line '=== READ-ONLY INTERPRETATION ==='
Add-Line 'This report is an architecture-discovery artifact. It does not rewrite, normalize, or delete any source data.'
Add-Line 'The next implementation step is to use the observed schema to define canonical product/build-aware API records.'
Add-Line 'Do not generate the large example corpus until product/build availability validation is implemented.'

$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host ('Report written to: ' + $reportPath)
