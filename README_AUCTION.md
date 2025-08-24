# Pokémon Slab Auction Lister

Scripts for creating eBay auctions of graded Pokémon cards. All logic is driven by YAML files in the repo root.

## YAML config
- **specs_item_specifics.yaml** – normalization maps, defaults, and listing policies. Sets `Brand` to "The Pokémon Company" and `categoryId` 183454.
- **specs_text_formats.yaml** – title and description templates.

### Title rules
- With specialty: `{card_name} {specialty} {card_number} – {set_name} – {grade} – {language}`
- Without specialty: `{card_name} {card_number} – {set_name} – {grade} – {language}`

### Description template
```
<Card Name> #<Card Number> from <Set Name>
<Grader> <Grade>
Cert #: <CertNumber>
Shipped quickly and securely in a bubble mailer with ding defender
```

## Auction defaults
- format: `AUCTION`
- listingDuration: `P7D`
- startPrice: 75% of `calculated_price` rounded down to end in `.99` (e.g. `40.00 → 29.99`)
- Brand aspect fixed to "The Pokémon Company"

## Secrets
Not committed. Stored at `C:\Users\johnr\Documents\ebay\secrets.env` with keys:
```
EBAY_CLIENT_ID
EBAY_CLIENT_SECRET
EBAY_REFRESH_TOKEN
EBAY_PAYMENT_POLICY_ID=272036644014
EBAY_RETURN_POLICY_ID=272036672014
EBAY_FULFILLMENT_POLICY_ID=272036663014
EBAY_LOCATION_ID=POKESLABS_US
```

## DryRun vs Live
Scripts default to DryRun and never hit network. Live mode requires **all** of:
1. Pass `-Live` (or `List_Slabs.bat live`).
2. `EBAY_ENV=prod`.
3. Sentinel file `.ebay-live.ok` in repo root.

When DryRun:
- `eps_uploader.ps1` builds `eps_image_map.json` with `https://example.invalid/eps/...` URLs.
- `lister.ps1` writes request bodies to `_out/payloads/` instead of calling eBay.
