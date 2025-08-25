param(
  [Parameter(Mandatory=$true)][string]$CsvPath,
  [Parameter(Mandatory=$true)][string]$DestDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cols = @('Image_Front','Image_Back','TopFrontImage','TopBackImage')
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir | Out-Null }

# parse sources and MTP auto mode
$sources = @()
$useMtp = $false
if ($env:PHOTOS_SRC) {
  foreach ($part in $env:PHOTOS_SRC -split ';') {
    $p = $part.Trim()
    if (-not $p) { continue }
    if ($p.ToLower() -eq 'auto') { $useMtp = $true } else { $sources += $p }
  }
} else {
  $useMtp = $true
}
foreach ($s in $sources) {
  if (-not (Test-Path $s)) { throw "Source directory not found: $s" }
}

function Find-LocalFile {
  param([string]$Name, [string[]]$Roots)
  foreach ($root in $Roots) {
    $match = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $Name } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    if ($match) { return $match.FullName }
  }
  return $null
}

function Build-MtpIndex {
  param([System.Collections.Generic.HashSet[string]]$Targets)
  $shell = New-Object -ComObject Shell.Application
  $myComputer = $shell.Namespace(0x11)
  $deviceItem = $null
  foreach ($i in @($myComputer.Items())) {
    if ($i.Name -match 'iPhone' -or $i.Name -match 'Apple') { $deviceItem = $i; break }
  }
  if (-not $deviceItem) {
    Write-Error "iPhone not accessible. Unlock the device and confirm 'Internal Storage\\DCIM' is visible in Explorer."
    exit 1
  }
  $device = $deviceItem.GetFolder()
  $internalItem = $device.ParseName('Internal Storage')
  if (-not $internalItem) {
    Write-Error "iPhone not accessible. Unlock the device and confirm 'Internal Storage\\DCIM' is visible in Explorer."
    exit 1
  }
  $dcimItem = $internalItem.GetFolder().ParseName('DCIM')
  if (-not $dcimItem) {
    Write-Error "iPhone not accessible. Unlock the device and confirm 'Internal Storage\\DCIM' is visible in Explorer."
    exit 1
  }
  $dcim = $dcimItem.GetFolder()
  $index = @{}
  foreach ($t in $Targets) { $index[$t.ToLower()] = New-Object System.Collections.ArrayList }
  $queue = New-Object System.Collections.Generic.Queue[Object]
  $queue.Enqueue($dcim)
  $any = $false
  while ($queue.Count -gt 0) {
    $folder = $queue.Dequeue()
    foreach ($item in @($folder.Items())) {
      if ($item.IsFolder) {
        $queue.Enqueue($item.GetFolder())
      } else {
        $any = $true
        $name = $item.Name.ToLower()
        if ($index.ContainsKey($name)) { $index[$name].Add($item) | Out-Null }
      }
    }
  }
  if (-not $any) {
    Write-Error "iPhone not accessible. Unlock the device and confirm 'Internal Storage\\DCIM' is visible in Explorer."
    exit 1
  }
  Write-Host ("MTP mode: device '{0}' detected" -f $deviceItem.Name)
  return @{ Shell = $shell; Index = $index }
}

function Get-BestMtpItem {
  param([string]$Name, $Index)
  $list = $Index[$Name.ToLower()]
  if (-not $list -or $list.Count -eq 0) { return $null }
  $best = $null
  $bestDate = $null
  $bestSize = 0
  foreach ($item in $list) {
    $date = $item.ExtendedProperty('System.DateModified')
    if (-not $date) { $date = $item.ExtendedProperty('System.DateCreated') }
    $size = $item.ExtendedProperty('System.Size')
    if (-not $best) {
      $best = $item; $bestDate = $date; $bestSize = $size; continue
    }
    if ($date -and $bestDate) {
      if ($date -gt $bestDate) { $best = $item; $bestDate = $date; $bestSize = $size }
    } elseif ($date -and -not $bestDate) {
      $best = $item; $bestDate = $date; $bestSize = $size
    } elseif (-not $date -and -not $bestDate) {
      if ($size -gt $bestSize) { $best = $item; $bestSize = $size }
    }
  }
  return $best
}

$rows = Import-Csv -Path $CsvPath
$targets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($row in $rows) {
  foreach ($col in $cols) {
    if ($row.PSObject.Properties.Name -contains $col) {
      $fname = $row.$col
      if (-not [string]::IsNullOrWhiteSpace($fname)) { $targets.Add($fname) | Out-Null }
    }
  }
}
$mtp = $null
if ($useMtp) { $mtp = Build-MtpIndex $targets }
$destNs = $null
if ($mtp) { $destNs = $mtp.Shell.Namespace($DestDir) }

$missing = [System.Collections.Generic.HashSet[string]]::new()
$copied = 0
$already = 0
$rowNum = 0
foreach ($row in $rows) {
  $rowNum++
  $label = if ($row.CertNumber) { $row.CertNumber } elseif ($row.SKU) { $row.SKU } else { "Row $rowNum" }
  $rowMsgs = @()
  foreach ($col in $cols) {
    if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
    $fname = $row.$col
    if ([string]::IsNullOrWhiteSpace($fname)) { continue }
    $destPath = Join-Path $DestDir $fname
    if (Test-Path $destPath) { $already++; $rowMsgs += "already had $fname"; continue }
    $found = Find-LocalFile -Name $fname -Roots $sources
    if ($found) {
      Copy-Item -LiteralPath $found -Destination $destPath -Force
      if (Test-Path $destPath) {
        $copied++
        $rowMsgs += ("copied {0} from {1}" -f $fname, (Split-Path $found -Parent | Split-Path -Leaf))
        continue
      }
    }
    if ($mtp) {
      $item = Get-BestMtpItem -Name $fname -Index $mtp.Index
      if ($item) {
        $destNs.CopyHere($item, 20)
        Start-Sleep -Milliseconds 200
        if (Test-Path $destPath) {
          $copied++
          $parent = (Split-Path $item.Path -Parent | Split-Path -Leaf)
          $rowMsgs += ("copied {0} from {1}" -f $fname, $parent)
          continue
        }
      }
    }
    $missing.Add($fname) | Out-Null
    $rowMsgs += "missing $fname"
  }
  if ($rowMsgs.Count -gt 0) {
    Write-Host ("{0}: {1}" -f $label, ($rowMsgs -join '; '))
  } else {
    Write-Host ("{0}: no images" -f $label)
  }
}
Write-Host ("Summary: copied {0}, already present {1}, missing {2}" -f $copied, $already, $missing.Count)
if ($missing.Count -gt 0) {
  Write-Error ("Missing {0} file(s): {1}" -f $missing.Count, ([string]::Join(', ',$missing)))
  exit 1
}
exit 0
