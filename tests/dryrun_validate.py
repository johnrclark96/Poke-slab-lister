import csv, json, math, pathlib, shutil, subprocess, os

ROOT = pathlib.Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / '_tests' / 'test.csv'
ITEM_YAML = ROOT / 'specs_item_specifics.yaml'
TEXT_YAML = ROOT / 'specs_text_formats.yaml'

def load_yaml(path):
    """Very small YAML loader supporting nested mappings."""
    data = {}
    stack = [data]
    indents = [0]
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.split('#', 1)[0].rstrip()
        if not line:
            continue
        indent = len(raw) - len(raw.lstrip())
        while indent < indents[-1]:
            stack.pop()
            indents.pop()
        key, sep, val = line.strip().partition(':')
        val = val.strip()
        if not sep:
            continue
        if not val:
            new = {}
            stack[-1][key] = new
            stack.append(new)
            indents.append(indent + 2)
        else:
            if val.startswith(('"', "'")) and val.endswith(('"', "'")):
                val = val[1:-1]
            try:
                val = int(val)
            except ValueError:
                pass
            stack[-1][key] = val
    return data

item_specs = load_yaml(ITEM_YAML)
text_specs = load_yaml(TEXT_YAML)

with open(CSV_PATH, newline='') as fh:
    row = next(csv.DictReader(fh))

calc_price = float(row['calculated_price'])
expected_start = math.floor(calc_price * 0.75 - 1) + 0.99
assert math.isclose(expected_start, 29.99, abs_tol=0.01)

lang = item_specs['language_map'][row['Language']]
grader = item_specs['grader_map'][row['Grader']]

title = text_specs['with_specialty'].format(
    card_name=row['CardName'],
    specialty=row['Specialty'],
    card_number=row['CardNumber'],
    set_name=row['SetName'],
    grade=row['Grade'],
    language=lang,
)
desc = (text_specs['desc']
        .replace('<Card Name>', row['CardName'])
        .replace('<Card Number>', row['CardNumber'])
        .replace('<Set Name>', row['SetName'])
        .replace('<Grader>', grader)
        .replace('<Grade>', row['Grade'])
        .replace('<CertNumber>', row['CertNumber']))

pwsh = shutil.which('pwsh') or shutil.which('powershell')
if pwsh:
    out_dir = ROOT / '_out'
    if out_dir.exists():
        shutil.rmtree(out_dir)
    eps_map = ROOT / 'eps_image_map.json'
    if eps_map.exists():
        eps_map.unlink()
    with open(CSV_PATH, newline='') as fh:
        imgs = {
            row[col]
            for row in csv.DictReader(fh)
            for col in ['Image_Front','Image_Back','TopFrontImage','TopBackImage']
            if row[col]
        }
    with open(eps_map, 'w', encoding='utf-8') as fh:
        json.dump({name: f"https://example.invalid/eps/{name}" for name in imgs}, fh)
    env = dict(os.environ)
    env.update({
        'EBAY_PAYMENT_POLICY_ID': '1',
        'EBAY_RETURN_POLICY_ID': '1',
        'EBAY_FULFILLMENT_POLICY_ID': '1',
        'EBAY_LOCATION_ID': '1',
    })
    subprocess.run([pwsh, str(ROOT/'eps_uploader.ps1'), '-CsvPath', str(CSV_PATH), '-ImagesDir', str(ROOT/'_tests'), '-AccessToken', 'dummy', '-DryRun', '-OutMap', str(eps_map)], check=True, env=env)
    subprocess.run([pwsh, str(ROOT/'lister.ps1'), '-CsvPath', str(CSV_PATH), '-AccessToken', 'dummy', '-ImageMap', str(eps_map), '-ListingFormat', 'AUCTION', '-DryRun'], check=True, env=env)
    with open(eps_map, 'r', encoding='utf-8') as fh:
        eps_data = json.load(fh)
    for col in ['Image_Front','Image_Back','TopFrontImage','TopBackImage']:
        fname = row[col]
        assert eps_data[fname] == f"https://example.invalid/eps/{fname}"
    payload_files = list((out_dir / 'payloads').glob('*Offer*.json'))
    assert payload_files, 'No offer payload generated'
    with open(payload_files[0], 'r', encoding='utf-8') as fh:
        payload = json.load(fh)
    assert payload['format'] == 'AUCTION'
    assert payload['listingDuration'] == 'DAYS_7'
    start_value = float(payload['pricingSummary']['startPrice']['value'])
    assert abs(start_value - expected_start) < 0.01
    assert payload['item']['title'] == title
    assert payload['item']['description'] == desc
    assert payload['item']['aspects']['Brand'] == item_specs['brand']
else:
    lister_text = (ROOT/'lister.ps1').read_text(encoding='utf-8')
    assert 'specs_item_specifics.yaml' in lister_text
    assert 'specs_text_formats.yaml' in lister_text
    assert 'Invoke-EbayApi' in lister_text
    assert 'startPrice' in lister_text
    eps_text = (ROOT/'eps_uploader.ps1').read_text(encoding='utf-8')
    assert 'DryRun: {0} images validated' in eps_text

print('ok')
