<# 
Pull-Photos-FromMasterCSV.ps1
- Reads your master CSV (the one we generate for EPS) 
- Detects all columns that look like image fields (contains "image" or "photo")
- Extracts/normalizes filenames (supports comma/semicolon/pipe separated lists)
- Copies matching files from iPhone DCIM to a local folder using Shell (MTP)
- Writes logs: _copy_ok.log and _copy_missing.log in the destination
#>

param(
    [string]$CsvPath = "C:\Users\johnr\Documents\ebay\master.csv",
    [string]$DestRoot = "C:\Users\johnr\Documents\ebay\Images",
    [string]$DeviceName = "Apple iPhone",     # Change if your device label differs in "This PC"
    [string[]]$IncludeColumns = @()           # Optional: override auto-detect. Example: "Image_Front","Image_Back","TopFrontImage","TopBackImage"
)

# ---------------- Shell/MTP helpers ----------------
function Get-ShellChildFolder {
    param([object]$ParentFolder,[string]$ChildName)
    foreach ($item in @($ParentFolder.Items())) {
        if ($item.IsFolder -and $item.Name -eq $ChildName) { return $item.GetFolder() }
    }
    return $null
}

function Find-DeviceDcimFolder {
    param([string]$DeviceLabel)
    $shell = New-Object -ComObject Shell.Application
    $myComputer = $shell.Namespace(0x11)
    if (-not $myComputer) { return $null }
    $deviceFolder = $null
    foreach ($item in @($myComputer.Items())) {
        if ($item.IsFolder -and $item.Name -eq $DeviceLabel) { $deviceFolder = $item.GetFolder(); break }
    }
    if (-not $deviceFolder) { return $null }
    $internal = Get-ShellChildFolder -ParentFolder $deviceFolder -ChildName "Internal Storage"
    if (-not $internal) { return $null }
    return Get-ShellChildFolder -ParentFolder $internal -ChildName "DCIM"
}

function Get-DcimFilesMap {
    param([object]$DcimFolder)
    $map = @{}
    $q = New-Object System.Collections.Generic.Queue[object]
    $q.Enqueue($DcimFolder)
    while ($q.Count -gt 0) {
        $folder = $q.Dequeue()
        foreach ($item in @($folder.Items())) {
            if ($item.IsFolder) { $q.Enqueue($item.GetFolder()); continue }
            $name = $item.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $key = $name.ToLowerInvariant()
            if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.ArrayList }
            [void]$map[$key].Add($item)
        }
    }
    return $map
}

function Copy-MtpItem {
    param([object]$ShellItem,[string]$DestFolderPath)
    if (-not (Test-Path -LiteralPath $DestFolderPath)) {
        New-Item -ItemType Directory -Path $DestFolderPath -Force | Out-Null
    }
    $shell = New-Object -ComObject Shell.Application
    $dest = $shell.NameSpace($DestFolderPath)
    if (-not $dest) { throw "Could not open destination: $DestFolderPath" }
    $flags = 16 + 512 + 1024   # No UI, No progress, No confirmation
    $dest.CopyHere($ShellItem, $flags)

    $target = Join-Path $DestFolderPath $ShellItem.Name
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $target) { return $target }
        Start-Sleep -Milliseconds 300
    }
    throw "Timed out copying '$($ShellItem.Name)'."
}

# ---------------- Pull from master CSV ----------------
Write-Host ">> Pulling iPhone photos using master CSV..." -ForegroundColor Cyan
Write-Host "CSV:  $CsvPath"
Write-Host "Dest: $DestRoot"
Write-Host ""

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "CSV not found: $CsvPath" }

# Load first to get headers
$sample = Import-Csv -LiteralPath $CsvPath -Delimiter ',' -ErrorAction Stop
if ($sample.Count -eq 0) { throw "CSV appears empty: $CsvPath" }

$headers = ($sample | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
if ($IncludeColumns.Count -eq 0) {
    # Auto-detect image columns: header contains 'image' or 'photo' (case-insensitive)
    $IncludeColumns = $headers | Where-Object { $_ -match '(?i)image|photo' }
}
if ($IncludeColumns.Count -eq 0) {
    throw "No image/photo columns detected. Specify -IncludeColumns or ensure headers contain 'image' or 'photo'."
}

Write-Host "Using image columns:" ($IncludeColumns -join ', ') -ForegroundColor Yellow

# Re-import as stream to reduce memory (still fine for typical sizes)
$rows = Import-Csv -LiteralPath $CsvPath
$wanted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Normalize & collect filenames from those columns
foreach ($row in $rows) {
    foreach ($col in $IncludeColumns) {
        if (-not $row.PSObject.Properties.Name.Contains($col)) { continue }
        $val = [string]$row.$col
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        # Support multiple filenames in one cell, split on common delimiters
        $parts = $val -split '[,;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        foreach ($p in $parts) {
            # Strip any path if present; keep just filename
            $fn = [System.IO.Path]::GetFileName($p)
            if (-not [string]::IsNullOrWhiteSpace($fn)) {
                [void]$wanted.Add($fn)
            }
        }
    }
}

if ($wanted.Count -eq 0) { throw "No filenames found in the specified image/photo columns." }

Write-Host ("Collected {0} unique filenames from CSV." -f $wanted.Count) -ForegroundColor Green

# Locate iPhone DCIM
$dcim = Find-DeviceDcimFolder -DeviceLabel $DeviceName
if (-not $dcim) {
    throw "Could not locate '$DeviceName' → Internal Storage → DCIM. Make sure iPhone is connected, unlocked, and trusted."
}

Write-Host "Indexing DCIM (one-time per run)..." -ForegroundColor Yellow
$map = Get-DcimFilesMap -DcimFolder $dcim
Write-Host ("Indexed {0} unique filenames on device." -f $map.Keys.Count)

# Logs
New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
$okLog = Join-Path $DestRoot "_copy_ok.log"
$missLog = Join-Path $DestRoot "_copy_missing.log"
Remove-Item -LiteralPath $okLog, $missLog -ErrorAction SilentlyContinue

# Copy
$found = 0; $copied = 0; $missing = 0
foreach ($name in $wanted) {
    $key = $name.ToLowerInvariant()
    if ($map.ContainsKey($key)) {
        $found++
        $item = $map[$key][0]
        Write-Host ("Copying {0}..." -f $name)
        try {
            $outPath = Copy-MtpItem -ShellItem $item -DestFolderPath $DestRoot
            $copied++
            Add-Content -LiteralPath $okLog -Value $outPath
        } catch {
            Write-Warning $_.Exception.Message
            $missing++
            Add-Content -LiteralPath $missLog -Value $name
        }
    } else {
        Write-Warning ("Not found on device: {0}" -f $name)
        $missing++
        Add-Content -LiteralPath $missLog -Value $name
    }
}

Write-Host ""
Write-Host ("Found:  {0}" -f $found) -ForegroundColor Green
Write-Host ("Copied: {0}" -f $copied) -ForegroundColor Green
Write-Host ("Missing:{0}" -f $missing) -ForegroundColor Yellow
if ($missing -gt 0) { Write-Host "Missing list:" (Resolve-Path $missLog) }
Write-Host "Success log:" (Resolve-Path $okLog)
Write-Host ">> Done." -ForegroundColor Cyan
