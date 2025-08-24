Param(
  [string]$CsvPath = ".\master.csv",
  [string]$PolicyPaymentId = "272036644014",
  [string]$PolicyReturnId = "272036672014",
  [string]$PolicyFulfillmentId = "272036663014",
  [string]$MarketplaceId = "EBAY_US"
)

$ErrorActionPreference = "Stop"

# Ensure YAML cmdlets are available
Import-Module powershell-yaml -ErrorAction Stop

# Load item specifics and text templates
$itemSpecs    = Get-Content (Join-Path $PSScriptRoot 'specs_item_specifics.yaml') | ConvertFrom-Yaml
$textFormats  = Get-Content (Join-Path $PSScriptRoot 'specs_text_formats.yaml')  | ConvertFrom-Yaml

function New-OfferBody($row, $epsUrls) {
  # --- Auction pricing ---
  $calc = [double]$row.calculated_price
  if (-not $calc -or $calc -le 0) { throw "Missing calculated_price for $($row.card_name) $($row.card_number)" }

  # Round calculated price to .99 then derive auction start price = 75% (rounded to .99)
  $calc = [math]::Floor($calc) + 0.99
  $startPrice = [math]::Round(($calc * 0.75), 2)
  $startPrice = [math]::Floor($startPrice) + 0.99

  # --- Images via EPS map ---
  $imageUrls = @()
  foreach($fname in @($row.Image_Front, $row.Image_Back, $row.TopFrontImage, $row.TopBackImage)) {
    if ($fname -and $epsUrls.ContainsKey($fname)) { $imageUrls += $epsUrls[$fname] }
  }

  # --- Title & Description from templates ---
  $languageTag = if ($textFormats.language_tags.ContainsKey($row.language)) {
    $textFormats.language_tags[$row.language]
  } else {
    $row.language
  }
  if ([string]::IsNullOrWhiteSpace($row.specialty)) {
    $titleTemplate = $textFormats.title_without_specialty
  } else {
    $titleTemplate = $textFormats.title_with_specialty
  }
  $title = $titleTemplate.Replace('{card_name}', $row.card_name).
                         Replace('{language_tag}', $languageTag).
                         Replace('{specialty}', $row.specialty).
                         Replace('{card_number}', $row.card_number).
                         Replace('{set_name}', $row.set_name).
                         Replace('{grade}', $row.grade)

  $desc = $textFormats.description.Replace('<Card Name>', $row.card_name).
                                   Replace('<Card Number>', $row.card_number).
                                   Replace('<Set Name>', $row.set_name).
                                   Replace('<Grader>', $row.grader).
                                   Replace('<Grade>', $row.grade).
                                   Replace('<CertNumber>', $row.cert_number)

  # --- Aspects via mapping ---
  $aspects = @{}
  foreach ($key in $itemSpecs.ebay_aspect_mapping.Keys) {
    if ($key.StartsWith('aspects.')) {
      $aspectName = $key.Substring(8)
      $expr = $itemSpecs.ebay_aspect_mapping[$key]
      if ($expr -match "^'(.*)'$") {
        $val = $matches[1]
      } else {
        $val = $row.$expr
      }
      $aspects[$aspectName] = $val
    }
  }

  # --- Defaults ---
  $quantity  = if ($row.quantity) { [int]$row.quantity } else { [int]$itemSpecs.defaults.quantity }
  $condition = if ($row.condition) { $row.condition } else { $itemSpecs.defaults.condition }

  $pricingSummary = @{
    "startPrice" = @{ "value" = $startPrice; "currency" = "USD" }
  }

  # --- Offer payload (Sell Inventory API) ---
  $payload = @{
    "sku" = if ([string]::IsNullOrWhiteSpace($row.sku)) { "$($row.grader)-$($row.cert_number)" } else { $row.sku }
    "marketplaceId" = $MarketplaceId
    "format" = "AUCTION"
    "listingType" = "AUCTION"
    "listingDuration" = "P7D"
    "availableQuantity" = $quantity
    "categoryId" = "183454"
    "listingDescription" = $desc
    "pricingSummary" = $pricingSummary
    "listingPolicies" = @{
      "paymentPolicyId" = $PolicyPaymentId
      "returnPolicyId" = $PolicyReturnId
      "fulfillmentPolicyId" = $PolicyFulfillmentId
    }
    "item" = @{
      "title" = $title
      "description" = $desc
      "brand" = "The Pokémon Company"
      "imageUrls" = $imageUrls
      "aspects" = $aspects
      "condition" = $condition
    }
  }

  return ($payload | ConvertTo-Json -Depth 8)
}

# Load EPS image URL map if present
$epsMapPath = Join-Path (Split-Path $CsvPath) "eps_image_map.json"
$epsUrls = @{}
if (Test-Path $epsMapPath) {
  $epsUrls = Get-Content $epsMapPath | ConvertFrom-Json
}

$rows = Import-Csv -Path $CsvPath
foreach ($row in $rows) {
  $body = New-OfferBody -row $row -epsUrls $epsUrls
  Write-Host "Creating AUCTION offer for $($row.card_name) #$($row.card_number) (Cert $($row.cert_number))"
  # TODO: Post to eBay Sell Inventory API with your ACCESS_TOKEN:
  # Invoke-RestMethod -Method Post -Uri "https://api.ebay.com/sell/inventory/v1/offer" `
  #   -Headers @{ Authorization = "Bearer $env:ACCESS_TOKEN"; "Content-Type" = "application/json" } `
  #   -Body $body
}
