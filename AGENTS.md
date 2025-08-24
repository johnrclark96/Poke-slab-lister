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
   - `"format":"AUCTION"`, `"listingDuration":"P7D"`,
   - start price = 75% of `calculated_price` rounded to `.99`,
   - Title/Description from YAML, Brand = "The Pokémon Company".
3) No network calls during validation.

### Validate vs Publish
- **Validate**: run `List_Slabs.bat` with no arguments. Uses DryRun and writes payloads to `_out/`.
- **Publish**: run `List_Slabs.bat live` with required secrets, `EBAY_ENV=prod`, and `.ebay-live.ok`.

## Task-specific notes
- If this folder has its own `AGENTS.md`, follow that in addition to these rules.
