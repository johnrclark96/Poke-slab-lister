
param(
  [string]$CsvPath = ".\master.csv",
  [string]$SourceRoot = $env:IMAGES_SRC,
  [string]$DestDir = $env:IMAGES_DIR
)

$ErrorActionPreference = "Stop"

if (-not $CsvPath) { $CsvPath = ".\master.csv" }
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  # Default to current folder if IMAGES_SRC not provided
  $SourceRoot = (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($DestDir)) {
  $DestDir = Join-Path (Split-Path $CsvPath) "Images"
}

# Ensure destination exists & is clean
if (Test-Path $DestDir) {
  Get-ChildItem -Path $DestDir -Recurse -File | Remove-Item -Force
} else {
  New-Item -ItemType Directory -Path $DestDir | Out-Null
}

Write-Host "Pulling photos from: $SourceRoot"
Write-Host "Destination Images folder: $DestDir"

# Read CSV and collect distinct filenames from known columns
$rows = Import-Csv -Path $CsvPath
$cols = @("Image_Front","Image_Back","TopFrontImage","TopBackImage","image_front_file","image_back_file","image_topfront_file","image_topback_file")

$want = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($row in $rows) {
  foreach ($c in $cols) {
    if ($row.PSObject.Properties.Name -contains $c) {
      $v = $row.$c
      if ($v -and -not $want.Contains($v)) { $want.Add($v) | Out-Null }
    }
  }
}

if ($want.Count -eq 0) {
  Write-Warning "No image filenames found in CSV."
  exit 0
}

# Build a lookup of filename -> full path by scanning SourceRoot recursively (leafname match, case-insensitive)
$lookup = @{}
Write-Host "Scanning source tree (this may take a moment)..."
Get-ChildItem -Path $SourceRoot -File -Recurse | ForEach-Object {
  $leaf = $_.Name.ToLowerInvariant()
  if (-not $lookup.ContainsKey($leaf)) { $lookup[$leaf] = @() }
  $lookup[$leaf] += $_.FullName
}

$copied = 0
$missing = @()

foreach ($name in $want) {
  $key = [System.IO.Path]::GetFileName($name).ToLowerInvariant()
  if ($lookup.ContainsKey($key)) {
    # choose newest if multiple
    $candidate = $lookup[$key] | Sort-Object { (Get-Item $_).LastWriteTimeUtc } -Descending | Select-Object -First 1
    Copy-Item -Path $candidate -Destination (Join-Path $DestDir ([System.IO.Path]::GetFileName($name))) -Force
    $copied++
    Write-Host ("Copied {0}" -f $name)
  } else {
    $missing += $name
    Write-Warning ("Could not find file: {0}" -f $name)
  }
}

Write-Host ("Copied {0} file(s) to {1}" -f $copied, $DestDir)
if ($missing.Count -gt 0) {
  Write-Warning ("Missing {0} file(s): {1}" -f $missing.Count, ($missing -join ", "))
  exit 2
}
