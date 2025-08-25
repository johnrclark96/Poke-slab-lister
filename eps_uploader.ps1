param(
  [Parameter(Mandatory=$true)][string]$CsvPath,
  [Parameter(Mandatory=$true)][string]$ImagesDir,
  [Parameter(Mandatory=$true)][string]$AccessToken,
  [string]$OutMap = 'eps_image_map.json',
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
$uploaded = 0; $cached = 0

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

foreach ($row in $rows) {
  foreach ($col in $cols) {
    if (-not ($row.PSObject.Properties.Name -contains $col)) { continue }
    $fname = $row.$col
    if ([string]::IsNullOrWhiteSpace($fname)) { continue }
    if ($imgMap.ContainsKey($fname)) { $cached++; continue }
    if ($DryRun) {
      $imgMap[$fname] = "https://example.invalid/eps/$fname"
      $uploaded++
      continue
    }
    $path = Join-Path $ImagesDir $fname
    if (-not (Test-Path $path)) { throw "Image file not found: $path" }
    try {
      $url = Invoke-EpsUpload -LocalPath $path -PictureName $fname
    } catch {
      Write-Error "Failed to upload $fname: $_"
      exit 1
    }
    if (-not ($url -like 'https://*')) {
      Write-Error "Non-HTTPS URL returned for $fname: $url"
      exit 1
    }
    $imgMap[$fname] = $url
    $uploaded++
  }
}

$imgMap | ConvertTo-Json | Out-File -Encoding utf8 -FilePath $mapPath
foreach ($v in $imgMap.Values) { if (-not ($v -like 'https://*')) { throw "Non-HTTPS URL in map: $v" } }
Write-Host "uploaded $uploaded new, reused $cached cached"
