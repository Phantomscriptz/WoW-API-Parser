# WoW API Workbench 2.4.5
# Windows PowerShell 5.1 compatible.
# This source is intentionally ASCII-only.

[CmdletBinding()]
param(
    [ValidateSet('SelfTest','Analyze','DownloadKetho','UI','Help')]
    [string]$Action = 'Help'
)

$ErrorActionPreference = 'Stop'
$Version = '2.4.5'

# PSScriptRoot is reliable for a .ps1 launched from a .bat file in Windows PowerShell 5.1.
$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ([string]::IsNullOrWhiteSpace($Root)) {
    throw 'Unable to determine the Workbench root directory.'
}

$DataDir = Join-Path $Root 'data'
$DiagDir = Join-Path $Root 'diagnostics'
$ConfigDir = Join-Path $Root 'config'
$CacheDir = Join-Path $Root 'cache'
$RefDir = Join-Path $Root 'references'
$OutputDir = Join-Path $Root 'output'
$UiDir = Join-Path $Root 'ui'
$LogPath = Join-Path $DiagDir 'workbench.log'

function Ensure-Dirs {
    foreach ($d in @($DataDir,$DiagDir,$ConfigDir,$CacheDir,$RefDir,$OutputDir,$UiDir)) {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}

function Log([string]$Message) {
    Ensure-Dirs
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-PropertyValue($Object, [string[]]$Names) {
    foreach ($name in $Names) {
        if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }
    return $null
}

function Normalize-Product([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $s = $Value.ToLowerInvariant().Replace('_','').Replace('-','').Replace(' ','')
    switch -Regex ($s) {
        '^retail$' { return 'Retail' }
        '^classic$' { return 'Classic' }
        '^classicer(a|ptr)$' { return 'ClassicEra' }
        '^classicanniversary$' { return 'ClassicAnniversary' }
        default { return $null }
    }
}

function Get-JsonRecords($Parsed) {
    if ($Parsed -is [System.Array]) { return @($Parsed) }

    if ($Parsed -is [pscustomobject]) {
        foreach ($name in @('records','items','entries','data','apis','products')) {
            if ($Parsed.PSObject.Properties.Name -contains $name) {
                $candidate = $Parsed.$name
                if ($candidate -is [System.Array]) {
                    return @($candidate)
                }
            }
        }
    }

    return @()
}

function Find-ApiDatabase {
    Ensure-Dirs

    # Explicitly do NOT consider master_manifest.json to be an API database.
    $priority = @(
        'all_products_api.json',
        'all_products_api.csv',
        'canonical_api_database.json',
        'canonical_api_database.csv',
        'normalized_api_database.json',
        'normalized_api_database.csv'
    )

    foreach ($name in $priority) {
        $hits = @(
            Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.FullName -notmatch '\\diagnostics\\' -and
                    $_.FullName -notmatch '\\output\\'
                } |
                Sort-Object @{Expression={$_.Length};Descending=$true}
        )

        foreach ($file in $hits) {
            try {
                if ($file.Extension -ieq '.json') {
                    $parsed = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    $records = @(Get-JsonRecords $parsed)
                    if ($records.Count -gt 0) {
                        $productHit = $records | Where-Object {
                            $p = Get-PropertyValue $_ @('Product','product')
                            $null -ne (Normalize-Product ([string]$p))
                        } | Select-Object -First 1
                        if ($null -ne $productHit) {
                            return [pscustomobject]@{
                                File = $file
                                Format = 'JSON'
                                Records = $records
                            }
                        }
                    }
                }
                else {
                    $rows = @(Import-Csv -LiteralPath $file.FullName)
                    if ($rows.Count -gt 0) {
                        $productHit = $rows | Where-Object {
                            $p = Get-PropertyValue $_ @('Product','product')
                            $null -ne (Normalize-Product ([string]$p))
                        } | Select-Object -First 1
                        if ($null -ne $productHit) {
                            return [pscustomobject]@{
                                File = $file
                                Format = 'CSV'
                                Records = $rows
                            }
                        }
                    }
                }
            }
            catch {
                Log ('Database candidate rejected: ' + $file.FullName + ' - ' + $_.Exception.Message)
            }
        }
    }

    return $null
}

function Get-DatabaseSummary($Db) {
    $byProduct = [ordered]@{
        Retail = 0
        Classic = 0
        ClassicEra = 0
        ClassicAnniversary = 0
    }

    $sourceCounts = [ordered]@{}
    $classCounts = [ordered]@{}
    $usable = 0

    foreach ($record in @($Db.Records)) {
        $productRaw = Get-PropertyValue $record @('Product','product')
        $product = Normalize-Product ([string]$productRaw)
        if ($null -eq $product) { continue }

        $usable++
        $byProduct[$product]++

        $source = [string](Get-PropertyValue $record @('Source','source'))
        if ([string]::IsNullOrWhiteSpace($source)) { $source = 'unknown' }
        if (-not $sourceCounts.Contains($source)) { $sourceCounts[$source] = 0 }
        $sourceCounts[$source]++

        $namespace = [string](Get-PropertyValue $record @('Namespace','namespace'))
        $name = [string](Get-PropertyValue $record @('Name','name'))

        $class = 'BLIZZARD_INTERNAL_OR_UNKNOWN'
        if ($source -eq 'documented') {
            if ($namespace -like 'C_*') {
                $class = 'C_API'
            }
            elseif ($name -match '^LE_|^(Enum|Constants)$') {
                $class = 'ENUM_CONSTANT'
            }
            else {
                $class = 'DOCUMENTED_API'
            }
        }
        elseif ($namespace -like 'C_*' -or $name -match '^C_') {
            $class = 'C_API_CANDIDATE'
        }
        elseif ($name -match '^LE_|^[A-Z][A-Z0-9_]+$') {
            $class = 'ENUM_CONSTANT_CANDIDATE'
        }
        elseif ($name -match '^(Get|Set|Is|Has|Can|Unit|Create|Update|Apply|Remove|Handle|On|Init|Initialize|Setup|Build|Check|Validate)[A-Z]') {
            $class = 'SOURCE_FUNCTION_CANDIDATE'
        }

        if (-not $classCounts.Contains($class)) { $classCounts[$class] = 0 }
        $classCounts[$class]++
    }

    [pscustomobject]@{
        TotalLoaded = @($Db.Records).Count
        UsableProductRecords = $usable
        ByProduct = $byProduct
        BySource = $sourceCounts
        ByClass = $classCounts
    }
}

function Write-DiscoveryReport($Db, $Summary) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('WOW API WORKBENCH 2.4.5 - DATABASE DISCOVERY')
    $lines.Add('Generated: ' + (Get-Date).ToString('o'))
    $lines.Add('Database found: TRUE')
    $lines.Add('File: ' + $Db.File.FullName)
    $lines.Add('Format: ' + $Db.Format)
    $lines.Add('Records loaded: ' + $Summary.TotalLoaded)
    $lines.Add('Usable product records: ' + $Summary.UsableProductRecords)
    $lines.Add('')
    $lines.Add('PRODUCTION PRODUCTS')
    $lines.Add(('Retail              {0} records' -f $Summary.ByProduct.Retail))
    $lines.Add(('Classic             {0} records' -f $Summary.ByProduct.Classic))
    $lines.Add(('Classic Era         {0} records' -f $Summary.ByProduct.ClassicEra))
    $lines.Add(('Classic Anniversary {0} records' -f $Summary.ByProduct.ClassicAnniversary))
    $lines.Add('')
    $lines.Add('DATABASE VALIDATION: PASSED')
    $lines.Add('master_manifest.json: METADATA ONLY / NOT USED AS PRIMARY DATASET')

    $txtPath = Join-Path $DiagDir 'api_database_discovery.txt'
    $lines | Set-Content -LiteralPath $txtPath -Encoding UTF8

    $json = [ordered]@{
        WorkbenchVersion = $Version
        Generated = (Get-Date).ToString('o')
        Database = @{
            Path = $Db.File.FullName
            Format = $Db.Format
            TotalLoaded = $Summary.TotalLoaded
            UsableProductRecords = $Summary.UsableProductRecords
        }
        Products = $Summary.ByProduct
        Sources = $Summary.BySource
        Classes = $Summary.ByClass
        MasterManifestPolicy = 'metadata-only'
        NextStage = 'Canonical per-product availability normalization and API-specific real-world example generation.'
    }

    $jsonPath = Join-Path $DiagDir 'api_database_discovery.json'
    $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $lines | ForEach-Object { Write-Host $_ }
}

function Analyze {
    Ensure-Dirs
    Log 'Running database analysis...'

    $db = Find-ApiDatabase
    if (-not $db) {
        $lines = @(
            'API DATABASE FOUND: FALSE',
            '',
            'Expected primary dataset, in priority order:',
            '1. all_products_api.json',
            '2. all_products_api.csv',
            '3. canonical_api_database.*',
            '4. normalized_api_database.*',
            '',
            'master_manifest.json is never used as the primary API dataset.'
        )
        $lines | Set-Content -LiteralPath (Join-Path $DiagDir 'api_database_discovery.txt') -Encoding UTF8
        $lines | ForEach-Object { Write-Host $_ }
        Log 'No usable API database found.'
        return 2
    }

    $summary = Get-DatabaseSummary $db

    if ($summary.UsableProductRecords -le 0) {
        throw 'Database was parsed, but no records contained a recognized production Product value.'
    }

    Write-DiscoveryReport $db $summary
    Log ('Database analysis complete: ' + $db.File.FullName)
    return 0
}

function Download-Ketho {
    Ensure-Dirs
    $target = Join-Path $CacheDir 'ketho'
    $zip = Join-Path $CacheDir 'ketho-vscode-wow-api.zip'
    $url = 'https://github.com/Ketho/vscode-wow-api/archive/refs/heads/master.zip'

    New-Item -ItemType Directory -Force -Path $target | Out-Null

    Log 'Downloading Ketho/vscode-wow-api master branch.'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

    $extract = Join-Path $target 'source'
    if (Test-Path -LiteralPath $extract) {
        Remove-Item -LiteralPath $extract -Recurse -Force
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force

    $marker = Join-Path $target 'DOWNLOAD_INFO.txt'
    @(
        'Ketho source cache',
        'Repository: Ketho/vscode-wow-api',
        'URL: ' + $url,
        'Downloaded: ' + (Get-Date).ToString('o')
    ) | Set-Content -LiteralPath $marker -Encoding UTF8

    Log 'Ketho source cached successfully.'
    return 0
}

function SelfTest {
    Ensure-Dirs
    Log 'Running self-test...'

    $fail = $false
    $lines = New-Object System.Collections.Generic.List[string]

    function Check([string]$Name, [scriptblock]$Test) {
        try {
            & $Test
            $lines.Add('[PASS] ' + $Name)
        }
        catch {
            $script:fail = $true
            $lines.Add('[FAIL] ' + $Name + ': ' + $_.Exception.Message)
        }
    }

    Check 'PowerShell 5+ available' {
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            throw 'PowerShell 5.0 or newer is required.'
        }
    }

    Check 'Workbench root detected' {
        if ([string]::IsNullOrWhiteSpace($Root)) {
            throw 'Root directory is empty.'
        }
    }

    Check 'Workbench script path' {
        if (-not (Test-Path -LiteralPath $PSCommandPath -PathType Leaf)) {
            throw 'The running workbench script could not be located.'
        }
    }

    Check 'Required directories' {
        foreach ($d in @($DataDir,$DiagDir,$ConfigDir,$CacheDir,$RefDir,$OutputDir,$UiDir)) {
            if (-not (Test-Path -LiteralPath $d -PathType Container)) {
                throw 'Missing directory: ' + $d
            }
        }
    }

    Check 'Diagnostics write access' {
        $probe = Join-Path $DiagDir 'selftest_write_test.tmp'
        Set-Content -LiteralPath $probe -Value 'ok' -Encoding ASCII
        Remove-Item -LiteralPath $probe -Force
    }

    Check 'Launcher scripts present' {
        foreach ($f in @('SelfTest.bat','Analyze_Database.bat','Download_Ketho.bat','UI.bat','Launch_WoW_API_Workbench.bat')) {
            if (-not (Test-Path -LiteralPath (Join-Path $Root $f) -PathType Leaf)) {
                throw 'Missing launcher: ' + $f
            }
        }
    }

    Check 'API database discovery engine' {
        $null = Find-ApiDatabase
    }

    $db = Find-ApiDatabase
    if ($null -eq $db) {
        $lines.Add('[INFO] No API database found. Fresh installation state is valid.')
    }
    else {
        Check 'API database validation' {
            $summary = Get-DatabaseSummary $db
            if ($summary.TotalLoaded -le 0) {
                throw 'Database contains zero loaded records.'
            }
            if ($summary.UsableProductRecords -le 0) {
                throw 'No recognized production Product records found.'
            }
        }
    }

    $lines.Add('')
    $lines.Add('Workbench version: ' + $Version)
    $lines.Add('Root: ' + $Root)
    $lines.Add('Script: ' + $PSCommandPath)
    $lines.Add('Database: ' + ($(if ($db) { $db.File.FullName } else { 'NOT FOUND' })))

    $lines | Set-Content -LiteralPath (Join-Path $DiagDir 'selftest.txt') -Encoding UTF8

    if ($fail) {
        Log 'Self-test FAILED.'
        $lines | ForEach-Object { Write-Host $_ }
        return 1
    }

    Log 'SELF-TEST PASSED.'
    $lines | ForEach-Object { Write-Host $_ }
    return 0
}

function Launch-UI {
    Ensure-Dirs
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'WoW API Workbench ' + $Version
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1150, 740)
    $form.MinimumSize = New-Object System.Drawing.Size(1000, 650)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'WOW API WORKBENCH'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(20, 15)
    $form.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Retail | Classic | Classic Era | Classic Anniversary'
    $subtitle.AutoSize = $true
    $subtitle.Location = New-Object System.Drawing.Point(22, 45)
    $form.Controls.Add($subtitle)

    $status = New-Object System.Windows.Forms.TextBox
    $status.Multiline = $true
    $status.ReadOnly = $true
    $status.ScrollBars = 'Both'
    $status.Font = New-Object System.Drawing.Font('Consolas', 10)
    $status.Location = New-Object System.Drawing.Point(20, 80)
    $status.Size = New-Object System.Drawing.Size(1090, 500)
    $form.Controls.Add($status)

    $discover = New-Object System.Windows.Forms.Button
    $discover.Text = 'Discover Database'
    $discover.Location = New-Object System.Drawing.Point(20, 605)
    $discover.Size = New-Object System.Drawing.Size(175, 38)
    $form.Controls.Add($discover)

    $selftest = New-Object System.Windows.Forms.Button
    $selftest.Text = 'Run Self-Test'
    $selftest.Location = New-Object System.Drawing.Point(205, 605)
    $selftest.Size = New-Object System.Drawing.Size(145, 38)
    $form.Controls.Add($selftest)

    $ketho = New-Object System.Windows.Forms.Button
    $ketho.Text = 'Download Ketho'
    $ketho.Location = New-Object System.Drawing.Point(360, 605)
    $ketho.Size = New-Object System.Drawing.Size(155, 38)
    $form.Controls.Add($ketho)

    $diag = New-Object System.Windows.Forms.Button
    $diag.Text = 'Open Diagnostics'
    $diag.Location = New-Object System.Drawing.Point(525, 605)
    $diag.Size = New-Object System.Drawing.Size(155, 38)
    $form.Controls.Add($diag)

    $data = New-Object System.Windows.Forms.Button
    $data.Text = 'Open Data'
    $data.Location = New-Object System.Drawing.Point(690, 605)
    $data.Size = New-Object System.Drawing.Size(120, 38)
    $form.Controls.Add($data)

    $discover.Add_Click({
        try {
            & $PSCommandPath -Action Analyze | Out-Null
            $report = Join-Path $DiagDir 'api_database_discovery.txt'
            if (Test-Path -LiteralPath $report) {
                $status.Text = Get-Content -LiteralPath $report -Raw -Encoding UTF8
            }
        }
        catch {
            $status.Text = $_.Exception.ToString()
        }
    })

    $selftest.Add_Click({
        try {
            & $PSCommandPath -Action SelfTest | Out-Null
            $report = Join-Path $DiagDir 'selftest.txt'
            if (Test-Path -LiteralPath $report) {
                $status.Text = Get-Content -LiteralPath $report -Raw -Encoding UTF8
            }
        }
        catch {
            $status.Text = $_.Exception.ToString()
        }
    })

    $ketho.Add_Click({
        try {
            & $PSCommandPath -Action DownloadKetho | Out-Null
            $status.Text = 'Ketho download complete.' + [Environment]::NewLine + (Join-Path $CacheDir 'ketho')
        }
        catch {
            $status.Text = $_.Exception.ToString()
        }
    })

    $diag.Add_Click({
        Start-Process explorer.exe $DiagDir
    })

    $data.Add_Click({
        Start-Process explorer.exe $DataDir
    })

    $status.Text = @(
        'WoW API Workbench ' + $Version,
        '',
        'This is the Windows UI foundation for the API inventory and normalization pipeline.',
        '',
        'Current workflow:',
        '1. Discover all_products_api.json / all_products_api.csv',
        '2. Validate production-product records',
        '3. Cache Ketho source',
        '4. Normalize API availability by product',
        '5. Generate API-specific, real-world Lua examples'
    ) -join [Environment]::NewLine

    [void]$form.ShowDialog()
    return 0
}

switch ($Action) {
    'SelfTest' { exit (SelfTest) }
    'Analyze' { exit (Analyze) }
    'DownloadKetho' { exit (Download-Ketho) }
    'UI' { exit (Launch-UI) }
    default {
        Write-Host 'WoW API Workbench ' + $Version
        Write-Host ''
        Write-Host 'Use:'
        Write-Host '  SelfTest.bat'
        Write-Host '  Analyze_Database.bat'
        Write-Host '  Download_Ketho.bat'
        Write-Host '  UI.bat'
        Write-Host ''
        exit 0
    }
}
