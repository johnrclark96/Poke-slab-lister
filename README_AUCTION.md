
# eBay Pokémon Slab Listing — Auction Package (Full, v2)

This package switches listings to **7‑day AUCTIONS** and ensures the three scripts work together:
1) `Pull-Photos-FromMasterCSV.ps1` → copies your referenced iPhone photos into the Images folder
2) `eps_uploader.ps1` → uploads those photos to eBay Picture Services (EPS) and writes `eps_image_map.json`
3) `lister.ps1` → creates AUCTION offers using the EPS URLs and your CSV data

## Auction defaults
- Listing Type: **AUCTION**
- Duration: **P7D**
- Start Price: **75% of `calculated_price`**, rounded to **.99**
- Best Offer: **Disabled**
- Brand Aspect: **The Pokémon Company**
- Titles: language tag `[EN]`/`[JP]` after card name
- SKU: optional/blank; falls back to `{grader}-{cert_number}` only if required

## YAML configuration
Two YAML files control text and item specifics used by `lister.ps1`:

- `specs_item_specifics.yaml` provides default listing values and maps CSV columns to eBay item specifics. Editing its `defaults` (for example `condition` or `quantity`) or `ebay_aspect_mapping` changes those fields in the generated listing payload.
- `specs_text_formats.yaml` defines the title and description templates plus language tags. Updates to these templates immediately affect the titles and descriptions produced for each listing.

## Environment variables (optional)
- `CSV_PATH` → path to `master.csv` (if not passing `-CsvPath`)
- `IMAGES_SRC` → source root where your iPhone photos live (USB/DCIM path)
- `IMAGES_DIR` → destination Images folder (defaults to `.\Images`)

## Run order (as in your batch file)
1. Pull photos → `PowerShell -File .\Pull-Photos-FromMasterCSV.ps1 -CsvPath .\master.csv`
2. EPS upload → `PowerShell -File .\eps_uploader.ps1 -CsvPath .\master.csv`
3. Listing → `PowerShell -File .\lister.ps1 -CsvPath .\master.csv`
