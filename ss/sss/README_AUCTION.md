# eBay Pokémon Slab Listing — Auction Package (Full, Regenerated)

This package converts your pipeline to **7‑day AUCTION listings** and ensures full compatibility between
photo pull → EPS upload → lister.

## Key Behavior
- **Listing Type:** AUCTION
- **Duration:** P7D (7 days)
- **Start Price:** 75% of `calculated_price`, rounded to `.99`
- **Best Offer:** Disabled (auctions)
- **Brand Aspect:** The Pokémon Company
- **Titles:** Language tag (e.g., [EN], [JP]) right after card name
- **SKU:** Optional/blank; fallback to `{grader}-{cert_number}` only if API requires it
- **Images:** `eps_uploader.ps1` writes `eps_image_map.json` used by lister

## Files Included
- `lister.ps1` — creates AUCTION offers using eBay Sell Inventory APIs
- `specs_item_specifics.yaml` — Brand mapping + aspect mappings
- `specs_text_formats.yaml` — title/description templates with language tags
- `eps_uploader.ps1` — uploads images to EPS, writes `eps_image_map.json`, supports both filename column styles

## Expected CSV columns
- Filenames: `Image_Front`, `Image_Back`, `TopFrontImage`, `TopBackImage` (preferred)
  - Legacy also supported: `image_front_file`, `image_back_file`, `image_topfront_file`, `image_topback_file`
- Pricing: `pricecharting_market`, `recent_sales_avg`, `calculated_price`, `pricecharting_url`
- Core facts: `grader`, `grade`, `cert_number`, `set_name`, `card_name`, `card_number`, `language`, `specialty` (optional), etc.
- Listing copy: `title`, `description`

## How to Use
1) Replace the matching files in your working listing folder with these versions.
2) Run your normal `List_Slabs.bat` flow.
3) Verify `_out\run_YYYYMMDD_HHMMSS.log` for any warnings/errors.
