## Mission
- Edit PowerShell/BAT + YAML files.
- **Never** hit live eBay APIs during tests (DryRun only).

## Non-negotiables
- Default to **DryRun**; Live requires: `-Live` flag + `EBAY_ENV=prod` + `.ebay-live.ok`.
- No secrets in git; load from local `C:\Users\johnr\Documents\ebay\secrets.env`.
- Keep all work **offline**. If internet is enabled, use allowlist only (PyPI/PSGallery/GitHub) and **GET** requests.

## How to validate
1) Generate `eps_image_map.json` (DryRun stubs).
2) Produce `_out/payloads/*.json` with:
   - `"format":"AUCTION"`, `"listingDuration":"DAYS_7"`,
   - start price = 75% of `calculated_price` rounded to `.99`,
   - Title/Description from YAML, Brand = "The Pokémon Company".
3) No network calls during validation.

### Validate vs Publish
- **Validate**: run `List_Slabs.bat` with no arguments. Uses DryRun and writes payloads to `_out/`.
- **Publish**: run `List_Slabs.bat live` with required secrets, `EBAY_ENV=prod`, and `.ebay-live.ok`.

## Task-specific notes
- If this folder has its own `AGENTS.md`, follow that in addition to these rules.

## Runbook Quickstart
- **Secrets:** populate `secrets.env` with OAuth keys and policy/location IDs: `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_REFRESH_TOKEN`, `EBAY_LOCATION_ID`, `EBAY_PAYMENT_POLICY_ID`, `EBAY_RETURN_POLICY_ID`, `EBAY_FULFILLMENT_POLICY_ID`.
- **Default BASEDIR:** `C:\Users\johnr\Documents\ebay`. Override with `BASEDIR` in `secrets.env`.
- **DryRun:** run `List_Slabs.bat` with no args. Validates CSV, YAML, and images; writes payloads to `_out/`.
- **Publish:** run `List_Slabs.bat live` (requires secrets, `EBAY_ENV=prod`, and `.ebay-live.ok`).
- **Logs:** see `logs/run_YYYYMMDD_HHmmss.log`; scripts exit non-zero on failure.
- **Common failures:** missing image filenames, unmapped YAML values, inventory location or policy ID mismatches.
- **Photos source resolution:** Step 0 searches `PHOTOS_SRC` (semicolon-separated folders) recursively. If `PHOTOS_SRC` is unset or set to `auto`, it auto-discovers an attached iPhone under `This PC\Apple iPhone\Internal Storage\DCIM` and copies matching filenames. Locked or hidden devices cause a fail-fast message to unlock the phone.
