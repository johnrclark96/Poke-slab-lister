Param(
  [string]$CsvPath,
  [switch]$Live,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Live -and $DryRun) { throw 'Use -Live or -DryRun, not both' }
if (-not $Live -and -not $DryRun) { $DryRun = $true }

$sentinel = Join-Path $PSScriptRoot '.ebay-live.ok'
$IsLive = $false
if ($Live) {
  if ($env:EBAY_ENV -ne 'prod') { throw 'Refusing Live: EBAY_ENV must be prod' }
  if (-not (Test-Path $sentinel)) { throw 'Refusing Live: .ebay-live.ok missing' }
  $IsLive = $true
}

if (-not $CsvPath) { $CsvPath = $env:CSV_PATH }
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }

$rows = Import-Csv $CsvPath
$cols = @('Image_Front','Image_Back','TopFrontImage','TopBackImage')
$map = @{}

if (-not $IsLive) {
  foreach ($row in $rows) {
    foreach ($col in $cols) {
      if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
      $fname = $row.$col
      if ([string]::IsNullOrWhiteSpace($fname)) { continue }
      $san = [uri]::EscapeDataString($fname)
      $map[$fname] = "https://example.invalid/eps/$san"
    }
  }
} else {
  $ImagesDir = $env:IMAGES_DIR
  if (-not $ImagesDir) { $ImagesDir = Split-Path $CsvPath }
  $EPS_Endpoint = 'https://api.ebay.com/ws/api.dll'
  $Headers = @{
    'X-EBAY-API-CALL-NAME'           = 'UploadSiteHostedPictures'
    'X-EBAY-API-SITEID'              = '0'
    'X-EBAY-API-COMPATIBILITY-LEVEL' = '1249'
    'X-EBAY-API-IAF-TOKEN'           = $env:ACCESS_TOKEN
  }
  function Resolve-LocalPath([string]$maybePath) {
    if ([string]::IsNullOrWhiteSpace($maybePath)) { return $null }
    if (Test-Path $maybePath) { return (Resolve-Path $maybePath).Path }
    $candidate = Join-Path $ImagesDir $maybePath
    if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    return $null
  }
  function Invoke-EpsUpload {
    param([string]$LocalPath,[string]$PictureName)
    $xml = @"
<?xml version='1.0' encoding='utf-8'?>
<UploadSiteHostedPicturesRequest xmlns='urn:ebay:apis:eBLBaseComponents'>
  <RequesterCredentials><eBayAuthToken>$($env:ACCESS_TOKEN)</eBayAuthToken></RequesterCredentials>
  <PictureName>$PictureName</PictureName>
</UploadSiteHostedPicturesRequest>
"@
    $content = [System.Net.Http.MultipartFormDataContent]::new()
    $xmlPart = [System.Net.Http.StringContent]::new($xml,[System.Text.Encoding]::UTF8,'text/xml')
    $content.Add($xmlPart,'XML Payload')
    $bytes = [System.IO.File]::ReadAllBytes($LocalPath)
    $imgPart = [System.Net.Http.ByteArrayContent]::new($bytes)
    $imgPart.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
    $content.Add($imgPart,'file',[System.IO.Path]::GetFileName($LocalPath))
    $client = [System.Net.Http.HttpClient]::new()
    foreach ($k in $Headers.Keys) { $client.DefaultRequestHeaders.Add($k,$Headers[$k]) }
    $resp = $client.PostAsync($EPS_Endpoint,$content).Result
    $raw = $resp.Content.ReadAsStringAsync().Result
    if (-not $resp.IsSuccessStatusCode) { throw "EPS upload failed ($($resp.StatusCode)): $raw" }
    [xml]$xmlResp = $raw
    $ns = [System.Xml.XmlNamespaceManager]::new($xmlResp.NameTable)
    $ns.AddNamespace('e','urn:ebay:apis:eBLBaseComponents')
    return $xmlResp.SelectSingleNode('//e:SiteHostedPictureDetails/e:FullURL',$ns).InnerText
  }
  foreach ($row in $rows) {
    $sku = $row.sku
    foreach ($col in $cols) {
      if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
      $val = $row.$col
      if ([string]::IsNullOrWhiteSpace($val)) { continue }
      $path = Resolve-LocalPath $val
      if (-not $path) { Write-Warning "Missing image file: $val"; continue }
      $picName = if ($sku) { "$sku__$col" } else { $col }
      $url = Invoke-EpsUpload -LocalPath $path -PictureName $picName
      $map[$val] = $url
    }
  }
}

$mapPath = Join-Path (Split-Path $CsvPath) 'eps_image_map.json'
$map | ConvertTo-Json | Out-File -Encoding utf8 -FilePath $mapPath
Write-Host "Wrote EPS image map: $mapPath"
