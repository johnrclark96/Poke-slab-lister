# eBay Listing Package — Auction Overrides (Final)

This set converts your workflow to **7‑day AUCTION listings** with start price = **75% of calculated_price**, rounded to **.99**.
It also fixes Brand to **The Pokémon Company** and adds a language tag to titles.

## What’s included
- `lister.ps1` — builds AUCTION offers (`listingDuration="P7D"`) and uses start price logic
- `specs_item_specifics.yaml` — Brand mapping set to The Pokémon Company
- `specs_text_formats.yaml` — language tag `[EN]/[JP]` etc. added to titles

## How to use
1) Unzip these files.
2) Replace the originals in your listing package with these versions.
3) Run your normal `List_Slabs.bat` flow.

## Defaults this package assumes
- Category: **183454** (CCG Individual Cards)
- Payment Policy: **272036644014**
- Return Policy: **272036672014**
- Fulfillment Policy: **272036663014**
- Best Offer: **Disabled** (auctions)
- SKU: Optional/blank; script will silently fallback to `{grader}-{cert_number}` only if required by the API.
