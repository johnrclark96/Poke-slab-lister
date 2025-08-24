param(
  [Parameter(Mandatory=$true)][string]$CsvPath,
  [Parameter(Mandatory=$true)][string]$DestDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRoot = $env:PHOTOS_SRC
if ([string]::IsNullOrWhiteSpace($sourceRoot)) { throw 'PHOTOS_SRC environment variable not set' }
if (-not (Test-Path $sourceRoot)) { throw "Source directory not found: $sourceRoot" }
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir | Out-Null }

$cols = @('Image_Front','Image_Back','TopFrontImage','TopBackImage')
$rows = Import-Csv -Path $CsvPath
$missing = New-Object System.Collections.Generic.List[string]
$copied = 0
foreach ($row in $rows) {
  foreach ($col in $cols) {
    if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
    $fname = $row.$col
    if ([string]::IsNullOrWhiteSpace($fname)) { continue }
    $src = Get-ChildItem -Path $sourceRoot -Recurse -Filter $fname | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($src) {
      Copy-Item -Path $src.FullName -Destination (Join-Path $DestDir $src.Name) -Force
      Write-Host "Copied $($src.Name)"
      $copied++
    } else {
      $missing.Add($fname)
      Write-Warning "Missing source file: $fname"
    }
  }
}
Write-Host "Copied $copied file(s) to $DestDir"
if ($missing.Count -gt 0) {
  Write-Error ("Missing {0} file(s): {1}" -f $missing.Count, ($missing -join ', '))
  exit 1
}
