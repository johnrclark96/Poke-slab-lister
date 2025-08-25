param(
  [Parameter(Mandatory=$true)][string]$CsvPath,
  [Parameter(Mandatory=$true)][string]$DestDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cols = @('Image_Front','Image_Back','TopFrontImage','TopBackImage')
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir | Out-Null }

$sources = $env:PHOTOS_SRC -split ';' | Where-Object { $_ }
if (-not $sources) { throw 'PHOTOS_SRC environment variable not set' }
foreach ($s in $sources) { if (-not (Test-Path $s)) { throw "Source directory not found: $s" } }

$rows = Import-Csv -Path $CsvPath
$missing = New-Object System.Collections.Generic.List[string]
$rowNum = 0
foreach ($row in $rows) {
  $rowNum++
  $label = if ($row.CertNumber) { $row.CertNumber } elseif ($row.SKU) { $row.SKU } else { "Row $rowNum" }
  $rowMissing = @()
  foreach ($col in $cols) {
    if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
    $fname = $row.$col
    if ([string]::IsNullOrWhiteSpace($fname)) { continue }
    $found = $null
    foreach ($root in $sources) {
      $candidate = Join-Path $root $fname
      if (Test-Path $candidate) { $found = $candidate; break }
    }
    if ($found) {
      Copy-Item -LiteralPath $found -Destination (Join-Path $DestDir $fname) -Force
    } else {
      $rowMissing += $fname
      $missing.Add($fname)
    }
  }
  if ($rowMissing.Count -eq 0) {
    Write-Host "$label: OK"
  } else {
    Write-Host "$label: missing $($rowMissing -join ', ')"
  }
}
if ($missing.Count -gt 0) {
  Write-Error ("Missing {0} file(s): {1}" -f $missing.Count, ($missing -join ', '))
  exit 1
}
