param([string]$CsvPath)

if (-not $CsvPath) { $CsvPath = $env:CSV_PATH }
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not $env:ACCESS_TOKEN) { throw "ACCESS_TOKEN missing (the .bat sets this at runtime)." }

$ImagesDir = $env:IMAGES_DIR
if (-not $ImagesDir) { $ImagesDir = Split-Path $CsvPath }

$EPS_Endpoint = "https://api.ebay.com/ws/api.dll"
$Headers = @{
  "X-EBAY-API-CALL-NAME"           = "UploadSiteHostedPictures"
  "X-EBAY-API-SITEID"              = "0"
  "X-EBAY-API-COMPATIBILITY-LEVEL" = "1249"
  "X-EBAY-API-IAF-TOKEN"           = $env:ACCESS_TOKEN
}

function Resolve-LocalPath([string]$maybePath) {
  if ([string]::IsNullOrWhiteSpace($maybePath)) { return $null }
  if (Test-Path $maybePath) { return (Resolve-Path $maybePath).Path }
  $candidate = Join-Path $ImagesDir $maybePath
  if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
  return $null
}

function Invoke-EpsUpload {
  param([Parameter(Mandatory=$true)][string]$LocalPath,
        [Parameter(Mandatory=$true)][string]$PictureName)

  $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<UploadSiteHostedPicturesRequest xmlns="urn:ebay:apis:eBLBaseComponents">
  <RequesterCredentials><eBayAuthToken>$($env:ACCESS_TOKEN)</eBayAuthToken></RequesterCredentials>
  <PictureName>$PictureName</PictureName>
</UploadSiteHostedPicturesRequest>
"@

  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $fileBytes = [System.IO.File]::ReadAllBytes($LocalPath)
  $fileHeader = "--$boundary$LF" +
                "Content-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $LocalPath -Leaf)`"$LF" +
                "Content-Type: application/octet-stream$LF$LF"
  $fileFooter = "$LF--$boundary--$LF"

  $content = ([System.Text.Encoding]::ASCII.GetBytes($fileHeader)) + $fileBytes + ([System.Text.Encoding]::ASCII.GetBytes($fileFooter))

  $resp = Invoke-WebRequest -Uri $EPS_Endpoint -Method Post -Headers $Headers -ContentType "multipart/form-data; boundary=$boundary" -Body $content
  $raw = $resp.Content
  if ($raw -notmatch '<FullURL>([^<]+)</FullURL>') { throw "No FullURL in response: $raw" }
  return $Matches[1]
}

$rows = Import-Csv $CsvPath
$changed = $false

$possibleFileCols = @("Image_Front","Image_Back","TopFrontImage","TopBackImage","image_front_file","image_back_file","image_topfront_file","image_topback_file")

$epsMap = @{}

foreach ($row in $rows) {
  $sku = $row.sku
  foreach ($col in $possibleFileCols) {
    if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
    $val = $row.$col
    if ([string]::IsNullOrWhiteSpace($val)) { continue }

    $path = Resolve-LocalPath $val
    if (-not $path) { Write-Warning "Missing image file: $val"; continue }

    $picName = if ($sku) { "$sku__$col" } else { $col }
    $url = Invoke-EpsUpload -LocalPath $path -PictureName $picName
    Write-Host ("Uploaded {0} -> {1}" -f $val, $url)
    $epsMap[$val] = $url
    $changed = $true
  }
}

$mapPath = Join-Path (Split-Path $CsvPath) "eps_image_map.json"
$epsMap | ConvertTo-Json | Out-File -Encoding utf8 -FilePath $mapPath
Write-Host "Wrote EPS image map: $mapPath"

if ($changed) {
  Write-Host "EPS uploads complete."
} else {
  Write-Host "No new uploads performed."
}
