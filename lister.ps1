Param(
  [string]$CsvPath = "./master.csv",
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

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
  Install-Module -Name powershell-yaml -Scope CurrentUser -Force | Out-Null
}
Import-Module powershell-yaml

$itemSpecPath = Join-Path $PSScriptRoot 'specs_item_specifics.yaml'
$textSpecPath = Join-Path $PSScriptRoot 'specs_text_formats.yaml'
$itemSpecs = ConvertFrom-Yaml (Get-Content $itemSpecPath -Raw)
$textSpecs = ConvertFrom-Yaml (Get-Content $textSpecPath -Raw)

function Fill-Template([string]$template, [hashtable]$data) {
  $result = $template
  foreach ($k in $data.Keys) {
    $result = $result.Replace('{'+$k+'}', $data[$k])
    $result = $result.Replace('<'+$k+'>', $data[$k])
  }
  return $result
}

function Invoke-EbayApi {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    [string]$Body,
    [string]$Tag
  )
  if (-not $IsLive) {
    $outDir = Join-Path $PSScriptRoot '_out/payloads'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $ts = Get-Date -Format 'yyyyMMddHHmmssfff'
    $file = Join-Path $outDir "$ts.$Tag.$Method.json"
    $Body | Out-File -Encoding utf8 -FilePath $file
    Write-Host "DryRun: wrote payload $file"
    return $null
  }
  return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers -Body $Body
}

if (-not (Test-Path $CsvPath)) { throw "CSV file not found: $CsvPath" }

$epsMapPath = Join-Path (Split-Path $CsvPath) 'eps_image_map.json'
$epsUrls = @{}
if (Test-Path $epsMapPath) { $epsUrls = Get-Content $epsMapPath | ConvertFrom-Json -AsHashtable }

$rows = Import-Csv -Path $CsvPath
foreach ($row in $rows) {
  $calc = [double]$row.calculated_price
  $startPrice = [math]::Floor($calc * 0.75 - 1) + 0.99

  $images = @()
  foreach ($fname in @($row.Image_Front,$row.Image_Back,$row.TopFrontImage,$row.TopBackImage)) {
    if ($fname -and $epsUrls.ContainsKey($fname)) { $images += $epsUrls[$fname] }
  }

  $grader = $itemSpecs.grader_map[$row.Grader]
  $language = $itemSpecs.language_map[$row.Language]
  $titleTemplate = if ($row.Specialty) { $textSpecs.with_specialty } else { $textSpecs.without_specialty }
  $title = Fill-Template $titleTemplate @{
    card_name = $row.CardName
    specialty = $row.Specialty
    card_number = $row.CardNumber
    set_name = $row.SetName
    grade = $row.Grade
    language = $language
  }
  $desc = Fill-Template $textSpecs.desc @{
    'Card Name' = $row.CardName
    'Card Number' = $row.CardNumber
    'Set Name' = $row.SetName
    'Grader' = $grader
    'Grade' = $row.Grade
    'CertNumber' = $row.CertNumber
  }

  $aspects = @{
    Brand = $itemSpecs.brand
    Graded = 'Yes'
    Grade = $row.Grade
    'Certification Number' = $row.CertNumber
    Set = $row.SetName
    'Card Name' = $row.CardName
    'Card Number' = $row.CardNumber
    Language = $language
    'Trading Card Type' = 'Pokémon TCG'
  }

  $payload = @{
    sku = if ([string]::IsNullOrWhiteSpace($row.SKU)) { "$($row.Grader)-$($row.CertNumber)" } else { $row.SKU }
    marketplaceId = 'EBAY_US'
    format = 'AUCTION'
    listingType = 'AUCTION'
    listingDuration = 'P7D'
    availableQuantity = $itemSpecs.quantity_default
    categoryId = $itemSpecs.categoryId
    listingDescription = $desc
    pricingSummary = @{ startPrice = @{ value = [math]::Round($startPrice,2); currency = 'USD' } }
    listingPolicies = @{
      paymentPolicyId = $env:EBAY_PAYMENT_POLICY_ID
      returnPolicyId = $env:EBAY_RETURN_POLICY_ID
      fulfillmentPolicyId = $env:EBAY_FULFILLMENT_POLICY_ID
    }
    merchantLocationKey = $env:EBAY_LOCATION_ID
    item = @{
      title = $title
      description = $desc
      brand = $itemSpecs.brand
      imageUrls = $images
      aspects = $aspects
      condition = $itemSpecs.condition_default
    }
  }

  $bodyJson = $payload | ConvertTo-Json -Depth 8
  Invoke-EbayApi -Method Post -Url 'https://api.ebay.com/sell/inventory/v1/offer' -Headers @{ 'Content-Type'='application/json'; Authorization="Bearer $env:ACCESS_TOKEN" } -Body $bodyJson -Tag 'Offer'
}
