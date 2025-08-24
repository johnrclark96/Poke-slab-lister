Param(
  [string]$CsvPath = ".\master.csv",
  [string]$PolicyPaymentId = "272036644014",
  [string]$PolicyReturnId = "272036672014",
  [string]$PolicyFulfillmentId = "272036663014",
  [string]$MarketplaceId = "EBAY_US"
)

$ErrorActionPreference = "Stop"

function New-OfferBody($row, $epsUrls) {
  $calc = [double]$row.calculated_price
  if (-not $calc -or $calc -le 0) { throw "Missing calculated_price for $($row.card_name) $($row.card_number)" }

  $calc = [math]::Floor($calc) + 0.99
  $startPrice = [math]::Round(($calc * 0.75), 2)
  $startPrice = [math]::Floor($startPrice) + 0.99

  $imageUrls = @()
  foreach($fname in @($row.Image_Front, $row.Image_Back, $row.TopFrontImage, $row.TopBackImage)) {
    if ($fname -and $epsUrls.ContainsKey($fname)) { $imageUrls += $epsUrls[$fname] }
  }

  $aspects = @{
    "Brand" = "The Pokémon Company";
    "Graded" = "Yes";
    "Grade" = $row.grade;
    "Certification Number" = $row.cert_number;
    "Set" = $row.set_name;
    "Card Name" = $row.card_name;
    "Card Number" = $row.card_number;
    "Language" = $row.language;
    "Trading Card Type" = "Pokémon TCG"
  }

  $pricingSummary = @{
    "startPrice" = @{ "value" = $startPrice; "currency" = "USD" }
  }

  $payload = @{
    "sku" = ($row.sku ? $row.sku : "$($row.grader)-$($row.cert_number)")
    "marketplaceId" = $MarketplaceId
    "format" = "AUCTION"
    "listingType" = "AUCTION"
    "listingDuration" = "P7D"
    "availableQuantity" = 1
    "categoryId" = "183454"
    "listingDescription" = $row.description
    "pricingSummary" = $pricingSummary
    "listingPolicies" = @{
      "paymentPolicyId" = $PolicyPaymentId
      "returnPolicyId" = $PolicyReturnId
      "fulfillmentPolicyId" = $PolicyFulfillmentId
    }
    "item" = @{
      "title" = $row.title
      "description" = $row.description
      "brand" = "The Pokémon Company"
      "imageUrls" = $imageUrls
      "aspects" = $aspects
      "condition" = "NEW"
    }
  }

  return ($payload | ConvertTo-Json -Depth 8)
}

$epsMapPath = Join-Path (Split-Path $CsvPath) "eps_image_map.json"
$epsUrls = @{}
if (Test-Path $epsMapPath) {
  $epsUrls = Get-Content $epsMapPath | ConvertFrom-Json
}

$rows = Import-Csv -Path $CsvPath
foreach ($row in $rows) {
  $body = New-OfferBody -row $row -epsUrls $epsUrls
  Write-Host "Creating AUCTION offer for $($row.card_name) #$($row.card_number) (Cert $($row.cert_number))"
  # Invoke-RestMethod -Method Post -Uri "https://api.ebay.com/sell/inventory/v1/offer" `
  #   -Headers @{ Authorization = "Bearer $env:ACCESS_TOKEN"; "Content-Type" = "application/json" } `
  #   -Body $body
}