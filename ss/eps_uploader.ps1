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

  $content   = [System.Net.Http.MultipartFormDataContent]::new()
  $xmlPart   = [System.Net.Http.StringContent]::new($xml, [System.Text.Encoding]::UTF8, "text/xml")
  $content.Add($xmlPart, "XML Payload")

  $bytes     = [System.IO.File]::ReadAllBytes($LocalPath)
  $imgPart   = [System.Net.Http.ByteArrayContent]::new($bytes)
  $imgPart.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
  $content.Add($imgPart, "file", [System.IO.Path]::GetFileName($LocalPath))

  $client = [System.Net.Http.HttpClient]::new()
  foreach ($k in $Headers.Keys) { $client.DefaultRequestHeaders.Add($k, $Headers[$k]) }

  try {
    $resp = $client.PostAsync($EPS_Endpoint, $content).Result
  } catch {
    throw "HTTP request failed: $($_.Exception.Message)"
  }
  $raw = $resp.Content.ReadAsStringAsync().Result
  if (-not $resp.IsSuccessStatusCode) { throw "EPS upload failed ($($resp.StatusCode)): $raw" }

  try {
    [xml]$xmlResp = $raw
    $ns = [System.Xml.XmlNamespaceManager]::new($xmlResp.NameTable)
    $ns.AddNamespace("e", "urn:ebay:apis:eBLBaseComponents")
    $fullUrl = $xmlResp.SelectSingleNode("//e:SiteHostedPictureDetails/e:FullURL", $ns).InnerText
  } catch {
    throw "Malformed EPS response: $raw"
  }
  if (-not $fullUrl) { throw "No FullURL in response: $raw" }
  return $fullUrl
}

$rows = Import-Csv $CsvPath
$changed = $false

$map = @{
  "image_front_file"    = "image_front_url"
  "image_back_file"     = "image_back_url"
  "image_topfront_file" = "image_topfront_url"
  "image_topback_file"  = "image_topback_url"
}

foreach ($row in $rows) {
  $sku = $row.sku
  foreach ($srcCol in $map.Keys) {
    $dstCol = $map[$srcCol]
    $localName = $row.$srcCol
    if ([string]::IsNullOrWhiteSpace($localName)) { continue }
    if (-not [string]::IsNullOrWhiteSpace($row.$dstCol)) { continue } # already uploaded

    $path = Resolve-LocalPath $localName
    if (-not $path) { Write-Warning "File not found for $sku: $localName"; continue }

    Write-Host "Uploading $localName for $sku ..."
    $epsName = "$($sku)__${srcCol}"
    $url = Invoke-EpsUpload -LocalPath $path -PictureName $epsName
    $row.$dstCol = $url
    Write-Host " -> $url"
    $changed = $true
  }
}

if ($changed) {
  $rows | Export-Csv $CsvPath -NoTypeInformation -Encoding UTF8
  Write-Host "CSV updated with EPS URLs: $CsvPath"
} else {
  Write-Host "No changes (all URLs present or no files found)."
}
