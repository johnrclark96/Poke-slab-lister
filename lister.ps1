[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CsvPath,
  [string]$PolicyPaymentId = "272036644014",
  [string]$PolicyReturnId = "272036672014",
  [string]$PolicyFulfillmentId = "272036663014",
  [string]$MarketplaceId = "EBAY_US",
  [switch]$Live,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# YAML module bootstrap
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
  try { Install-Module powershell-yaml -Scope CurrentUser -Force -ErrorAction Stop }
  catch { Write-Error "powershell-yaml not installed; install manually: Install-Module powershell-yaml -Scope CurrentUser" }
}
Import-Module powershell-yaml

# Resolve DryRun vs Live
$sentinel = Join-Path $PSScriptRoot '.ebay-live.ok'
$isProdEnv = ($env:EBAY_ENV -eq 'prod')
$liveRequested = $Live.IsPresent -and -not $DryRun.IsPresent
if (-not $liveRequested) {
  $DryRun = $true
} else {
  if (-not (Test-Path $sentinel)) { throw "Live publishing blocked: missing $sentinel" }
  if (-not $isProdEnv) { throw "Live publishing blocked: EBAY_ENV must be 'prod' (got '$($env:EBAY_ENV)')" }
}

# Output directories
$outDir = Join-Path $PSScriptRoot "_out/payloads"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

function Invoke-EbayApi {
  param(
    [Parameter(Mandatory=$true)][string]$Method,
    [Parameter(Mandatory=$true)][string]$Url,
    [hashtable]$Headers,
    [object]$Body,
    [string]$Tag
  )
  $json = $null
  if ($null -ne $Body) { $json = ($Body | ConvertTo-Json -Depth 10) }

  if ($DryRun) {
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
    $safeTag = ($Tag -replace '[^a-zA-Z0-9_.-]','_')
    $file = Join-Path $outDir "$stamp.$safeTag.$Method.json"
    $obj = [ordered]@{ method=$Method; url=$Url; headers=$Headers; body=($json | ConvertFrom-Json) }
    ($obj | ConvertTo-Json -Depth 10) | Out-File -Encoding UTF8 $file
    return @{ status="DRYRUN"; file=$file }
  }

  $irmParams = @{ Method=$Method; Uri=$Url; Headers=$Headers; ErrorAction='Stop' }
  if ($null -ne $json) { $irmParams['Body']=$json; $irmParams['ContentType']='application/json' }
  return Invoke-RestMethod @irmParams
}

# Load item specifics and text templates
$itemSpecs   = Get-Content (Join-Path $PSScriptRoot 'specs_item_specifics.yaml') | ConvertFrom-Yaml
$textFormats = Get-Content (Join-Path $PSScriptRoot 'specs_text_formats.yaml')  | ConvertFrom-Yaml

# Load EPS image URL map if present
$epsMapPath = Join-Path $PSScriptRoot "eps_image_map.json"
$epsUrls = @{}
if (Test-Path $epsMapPath) { $epsUrls = Get-Content $epsMapPath | ConvertFrom-Json }

$rows = Import-Csv -Path $CsvPath
foreach ($row in $rows) {
  $sku = if ([string]::IsNullOrWhiteSpace($row.sku)) { "$($row.Grader)-$($row.CertNumber)" } else { $row.sku }

  # Title & Description from templates
  $languageTag = if ($textFormats.language_tags.ContainsKey($row.Language)) { $textFormats.language_tags[$row.Language] } else { $row.Language }
  $titleTemplate = if ([string]::IsNullOrWhiteSpace($row.specialty)) { $textFormats.title_without_specialty } else { $textFormats.title_with_specialty }
  $title = $titleTemplate.Replace('{card_name}', $row.CardName).
                         Replace('{language_tag}', $languageTag).
                         Replace('{specialty}', $row.specialty).
                         Replace('{card_number}', $row.CardNumber).
                         Replace('{set_name}', $row.SetName).
                         Replace('{grade}', $row.Grade)
  $desc = $textFormats.description.Replace('<Card Name>', $row.CardName).
                                   Replace('<Card Number>', $row.CardNumber).
                                   Replace('<Set Name>', $row.SetName).
                                   Replace('<Grader>', $row.Grader).
                                   Replace('<Grade>', $row.Grade).
                                   Replace('<CertNumber>', $row.CertNumber)

  # Aspects via mapping
  $aspects = @{}
  foreach ($key in $itemSpecs.ebay_aspect_mapping.Keys) {
    if ($key.StartsWith('aspects.')) {
      $aspectName = $key.Substring(8)
      $expr = $itemSpecs.ebay_aspect_mapping[$key]
      if ($expr -match "^'(.*)'$") { $val = $matches[1] } else { $val = $row.$expr }
      $aspects[$aspectName] = $val
    }
  }

  # Defaults
  $quantity  = if ($row.quantity) { [int]$row.quantity } else { [int]$itemSpecs.defaults.quantity }
  $condition = if ($row.condition) { $row.condition } else { $itemSpecs.defaults.condition }

  # Images via EPS map
  $imageUrls = @()
  foreach ($fname in @($row.Image_Front, $row.Image_Back, $row.TopFrontImage, $row.TopBackImage)) {
    if ($fname -and $epsUrls.ContainsKey($fname)) { $imageUrls += $epsUrls[$fname] }
  }

  # Start price policy
  $calc = [double]$row.calculated_price
  if (-not $calc -or $calc -le 0) { throw "Missing calculated_price for $($row.CardName) $($row.CardNumber)" }
  $start = [math]::Floor($calc * 0.75) + 0.99

  $authHeaders = @{}
  if ($env:ACCESS_TOKEN) { $authHeaders['Authorization'] = "Bearer $env:ACCESS_TOKEN" }

  # Inventory item body
  $inventoryBody = @{
    sku = $sku
    condition = $condition
    product = @{
      title = $title
      description = $desc
      brand = "The Pokémon Company"
      imageUrls = $imageUrls
      aspects = $aspects
    }
  }
  $invUrl = "https://api.ebay.com/sell/inventory/v1/inventory_item/$sku"
  Invoke-EbayApi -Method 'PUT' -Url $invUrl -Headers $authHeaders -Body $inventoryBody -Tag "inventory-item:$sku" | Out-Null

  # Offer payload
  $offerBody = @{
    sku = $sku
    marketplaceId = $MarketplaceId
    format = 'AUCTION'
    listingDuration = 'P7D'
    availableQuantity = $quantity
    categoryId = '183454'
    listingDescription = $desc
    pricingSummary = @{ startPrice = @{ value = $start; currency = 'USD' } }
    listingPolicies = @{
      paymentPolicyId = $PolicyPaymentId
      returnPolicyId = $PolicyReturnId
      fulfillmentPolicyId = $PolicyFulfillmentId
    }
  }
  Invoke-EbayApi -Method 'POST' -Url 'https://api.ebay.com/sell/inventory/v1/offer' -Headers $authHeaders -Body $offerBody -Tag "offer:$sku" | Out-Null
}
