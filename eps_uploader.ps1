param(
  [Parameter(Mandatory)][string]$CsvPath,
  [Parameter(Mandatory)][string]$ImagesDir,
  [Parameter(Mandatory)][string]$AccessToken,
  [string]$OutMap = (Join-Path $env:BASEDIR 'eps_image_map.json'),
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
if (-not (Test-Path $ImagesDir)) { throw "Images directory not found: $ImagesDir" }

$mapPath = if ([System.IO.Path]::IsPathRooted($OutMap)) { $OutMap } else { Join-Path (Split-Path $CsvPath) $OutMap }
$imgMap = @{}
if (Test-Path $mapPath) { $imgMap = Get-Content $mapPath | ConvertFrom-Json -AsHashtable }
foreach ($v in $imgMap.Values) { if (-not ($v -like 'https://*')) { throw "Non-HTTPS URL in map: $v" } }

$cols = @('Image_Front','Image_Back','TopFrontImage','TopBackImage')
$rows = Import-Csv -Path $CsvPath
$filenames = [System.Collections.Generic.HashSet[string]]::new()
foreach ($row in $rows) {
  foreach ($col in $cols) {
    if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
    $fname = $row.$col
    if ([string]::IsNullOrWhiteSpace($fname)) { continue }
    $filenames.Add($fname) | Out-Null
  }
}

if ($DryRun) {
  $missing = @()
  foreach ($name in $filenames) {
    if (-not ($imgMap.ContainsKey($name) -and $imgMap[$name] -like 'https://*')) {
      $missing += $name
    }
  }
  if ($missing.Count -gt 0) {
    Write-Error ("Missing HTTPS URLs for: {0}" -f ($missing -join ', '))
    exit 1
  }
  Write-Host ("DryRun: {0} images validated" -f $filenames.Count)
  exit 0
}

function Invoke-EpsUpload {
  param([string]$LocalPath,[string]$PictureName)
  $endpoint = 'https://api.ebay.com/ws/api.dll'
  $headers = @{
    'X-EBAY-API-CALL-NAME'           = 'UploadSiteHostedPictures'
    'X-EBAY-API-SITEID'              = '0'
    'X-EBAY-API-COMPATIBILITY-LEVEL' = '1249'
    'X-EBAY-API-IAF-TOKEN'           = $AccessToken
  }
  $xml = @"
<?xml version='1.0' encoding='utf-8'?>
<UploadSiteHostedPicturesRequest xmlns='urn:ebay:apis:eBLBaseComponents'>
  <RequesterCredentials><eBayAuthToken>$AccessToken</eBayAuthToken></RequesterCredentials>
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
  foreach ($k in $headers.Keys) { $client.DefaultRequestHeaders.Add($k,$headers[$k]) }
  $resp = $client.PostAsync($endpoint,$content).Result
  $raw = $resp.Content.ReadAsStringAsync().Result
  if (-not $resp.IsSuccessStatusCode) { throw "HTTP $($resp.StatusCode): $raw" }
  [xml]$xmlResp = $raw
  $ns = [System.Xml.XmlNamespaceManager]::new($xmlResp.NameTable)
  $ns.AddNamespace('e','urn:ebay:apis:eBLBaseComponents')
  return $xmlResp.SelectSingleNode('//e:SiteHostedPictureDetails/e:FullURL',$ns).InnerText
}

$uploaded = 0; $cached = 0
foreach ($name in $filenames) {
  if ($imgMap.ContainsKey($name) -and $imgMap[$name] -like 'https://*') { $cached++; continue }
  $path = Join-Path $ImagesDir $name
  if (-not (Test-Path $path)) { throw "Image file not found: $path" }
  try {
    $url = Invoke-EpsUpload -LocalPath $path -PictureName $name
  } catch {
    Write-Error $_
    exit 1
  }
  if (-not ($url -like 'https://*')) {
    Write-Error "Non-HTTPS URL returned for $name: $url"
    exit 1
  }
  $imgMap[$name] = $url
  $uploaded++
}

$tmpPath = "$mapPath.tmp"
$imgMap | ConvertTo-Json | Out-File -Encoding utf8 -FilePath $tmpPath
Move-Item -Force $tmpPath $mapPath
foreach ($v in $imgMap.Values) { if (-not ($v -like 'https://*')) { throw "Non-HTTPS URL in map: $v" } }
Write-Host "uploaded $uploaded, reused $cached"
exit 0
