param(
  [Parameter(Mandatory=$true)][string]$CsvPath,
  [Parameter(Mandatory=$true)][string]$AccessToken,
  [ValidateSet('AUCTION','FIXED')][string]$ListingFormat = 'AUCTION',
  [string]$ImageMap = 'eps_image_map.json',
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CsvPath)) { throw "CSV file not found: $CsvPath" }
$mapPath = if ([System.IO.Path]::IsPathRooted($ImageMap)) { $ImageMap } else { Join-Path (Split-Path $CsvPath) $ImageMap }
if (-not (Test-Path $mapPath)) { throw "Image map not found: $mapPath" }
$epsUrls = Get-Content $mapPath | ConvertFrom-Json -AsHashtable
foreach ($v in $epsUrls.Values) { if (-not ($v -like 'https://*')) { throw "Non-HTTPS URL in map: $v" } }

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
  Install-Module -Name powershell-yaml -Scope CurrentUser -Force | Out-Null
}
Import-Module powershell-yaml

$itemSpecPath = Join-Path $PSScriptRoot 'specs_item_specifics.yaml'
$textSpecPath = Join-Path $PSScriptRoot 'specs_text_formats.yaml'
$itemSpecs = ConvertFrom-Yaml (Get-Content $itemSpecPath -Raw)
$textSpecs = ConvertFrom-Yaml (Get-Content $textSpecPath -Raw)

$requiredCols = @('CardName','CardNumber','SetName','Language','Grader','Grade','CertNumber','calculated_price','Image_Front','Image_Back','TopFrontImage','TopBackImage')
$rows = Import-Csv -Path $CsvPath
foreach ($col in $requiredCols) {
  if (-not ($rows[0].PSObject.Properties.Name -contains $col)) { throw "Missing required column: $col" }
}

foreach ($row in $rows) {
  if (-not $itemSpecs.grader_map.ContainsKey($row.Grader)) { throw "Unmapped grader: $($row.Grader)" }
  if ($itemSpecs.grade_map -and -not $itemSpecs.grade_map.ContainsKey($row.Grade)) { throw "Unmapped grade: $($row.Grade)" }
  if (-not $itemSpecs.language_map.ContainsKey($row.Language)) { throw "Unmapped language: $($row.Language)" }
  if ($row.Rarity -and -not $itemSpecs.rarity_map.ContainsKey($row.Rarity)) { throw "Unmapped rarity: $($row.Rarity)" }
}

function Fill-Template([string]$template, [hashtable]$data) {
  $result = $template
  foreach ($k in $data.Keys) {
    $result = $result.Replace('{'+$k+'}', $data[$k])
    $result = $result.Replace('<'+$k+'>', $data[$k])
  }
  return $result
}

function Invoke-EbayApi {
  param([string]$Method,[string]$Url,[string]$Body,[string]$Tag)
  if ($DryRun) {
    $outDir = Join-Path $PSScriptRoot '_out/payloads'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $ts = Get-Date -Format 'yyyyMMddHHmmssfff'
    $file = Join-Path $outDir "$ts.$Tag.$Method.json"
    $Body | Out-File -Encoding utf8 -FilePath $file
    Write-Host "DryRun: wrote payload $file"
    return
  }
  $headers = @{ 'Authorization' = "Bearer $AccessToken"; 'Content-Type'='application/json' }
  $attempt = 0
  while ($true) {
    try {
      return Invoke-RestMethod -Method $Method -Uri $Url -Headers $headers -Body $Body
    } catch {
      $resp = $_.Exception.Response
      if ($resp -and ($resp.StatusCode.value__ -eq 429 -or $resp.StatusCode.value__ -ge 500) -and $attempt -lt 5) {
        $delay = [math]::Pow(2,$attempt)
        Start-Sleep -Seconds $delay
        $attempt++
      } else {
        if ($resp) {
          $reader = [System.IO.StreamReader]::new($resp.GetResponseStream())
          $body = $reader.ReadToEnd()
          Write-Error "$Tag failed HTTP $($resp.StatusCode.value__): $body"
        } else {
          Write-Error "$Tag failed: $_"
        }
        throw
      }
    }
  }
}

$marketplace = if ($env:EBAY_MARKETPLACE_ID) { $env:EBAY_MARKETPLACE_ID } else { 'EBAY_US' }

foreach ($row in $rows) {
  $images = @()
  foreach ($fname in @($row.Image_Front,$row.Image_Back,$row.TopFrontImage,$row.TopBackImage)) {
    if ($fname -and $epsUrls.ContainsKey($fname)) { $images += $epsUrls[$fname] } else { if ($fname) { throw "Missing EPS URL for $fname" } }
  }
  $grader = $itemSpecs.grader_map[$row.Grader]
  $language = $itemSpecs.language_map[$row.Language]
  $titleTemplate = if ($row.Specialty) { $textSpecs.with_specialty } else { $textSpecs.without_specialty }
  $title = Fill-Template $titleTemplate @{ card_name=$row.CardName; specialty=$row.Specialty; card_number=$row.CardNumber; set_name=$row.SetName; grade=$row.Grade; language=$language }
  $desc = Fill-Template $textSpecs.desc @{ 'Card Name'=$row.CardName; 'Card Number'=$row.CardNumber; 'Set Name'=$row.SetName; 'Grader'=$grader; 'Grade'=$row.Grade; 'CertNumber'=$row.CertNumber }
  $sku = if ([string]::IsNullOrWhiteSpace($row.SKU)) { "$($row.Grader)-$($row.CertNumber)" } else { $row.SKU }

  $inventory = @{ sku=$sku; availability=@{shipToLocationAvailability=@{quantity=1}}; condition=$itemSpecs.condition_default; product=@{brand=$itemSpecs.brand; title=$title; description=$desc; imageUrls=$images} }
  $invJson = $inventory | ConvertTo-Json -Depth 8
  Invoke-EbayApi -Method Put -Url ("https://api.ebay.com/sell/inventory/v1/inventory_item/"+$sku) -Body $invJson -Tag 'InventoryItem'

  $calc = [double]$row.calculated_price
  if ($ListingFormat -eq 'AUCTION') {
    $startPrice = [math]::Floor($calc * 0.75 - 1) + 0.99
    $priceObj = @{ startPrice = @{ value = [math]::Round($startPrice,2); currency='USD' } }
    $format = 'AUCTION'
    $duration = 'DAYS_7'
  } else {
    $priceObj = @{ price = @{ value = [math]::Round($calc,2); currency='USD' } }
    $format = 'FIXED_PRICE'
    $duration = 'GTC'
  }
  $aspects = @{ Brand = $itemSpecs.brand }
  $offer = @{
    sku=$sku; marketplaceId=$marketplace; format=$format; listingDuration=$duration; pricingSummary=$priceObj;
    listingPolicies=@{ paymentPolicyId=$env:EBAY_PAYMENT_POLICY_ID; returnPolicyId=$env:EBAY_RETURN_POLICY_ID; fulfillmentPolicyId=$env:EBAY_FULFILLMENT_POLICY_ID };
    inventoryLocationId=$env:EBAY_LOCATION_ID;
    item=@{ title=$title; description=$desc; imageUrls=$images; aspects=$aspects }
  }
  $offerJson = $offer | ConvertTo-Json -Depth 8
  Invoke-EbayApi -Method Post -Url 'https://api.ebay.com/sell/inventory/v1/offer' -Body $offerJson -Tag 'Offer'

  $publish = @{ offerId='DUMMY' } | ConvertTo-Json
  Invoke-EbayApi -Method Post -Url 'https://api.ebay.com/sell/inventory/v1/offer/publish' -Body $publish -Tag 'Publish'
  Write-Host "$sku listed"
}
