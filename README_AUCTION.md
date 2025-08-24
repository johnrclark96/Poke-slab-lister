
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

## Credentials
Create a `secrets.env` file in the repository root with your eBay credentials and policy IDs. Each line should follow `KEY=VALUE` format:

```
EBAY_CLIENT_ID=your-app-id
EBAY_CLIENT_SECRET=your-app-secret
EBAY_REFRESH_TOKEN=your-refresh-token
EBAY_PAYMENT_POLICY_ID=your-payment-policy-id
EBAY_FULFILLMENT_POLICY_ID=your-fulfillment-policy-id
EBAY_RETURN_POLICY_ID=your-return-policy-id
EBAY_LOCATION_ID=your-location-id
```

`List_Slabs.bat` loads these values and uses them when invoking the PowerShell scripts. The file is already ignored by git.

## Environment variables (optional)
- `CSV_PATH` → path to `master.csv` (if not passing `-CsvPath`)
- `IMAGES_SRC` → source root where your iPhone photos live (USB/DCIM path)
- `IMAGES_DIR` → destination Images folder (defaults to `.\Images`)

## Run order (as in your batch file)
1. Pull photos → `PowerShell -File .\Pull-Photos-FromMasterCSV.ps1 -CsvPath .\master.csv`
2. EPS upload → `PowerShell -File .\eps_uploader.ps1 -CsvPath .\master.csv`
3. Listing → `PowerShell -File .\lister.ps1 -CsvPath .\master.csv`
