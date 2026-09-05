"""Refresh factual paint values and wheel reference screenshots, never runtime downloads.

Tooling only: pip install beautifulsoup4 pillow. Images remain credited to GTA Wiki
contributors / Rockstar; they are game reference screenshots, not Cortex artwork.
"""
import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import urllib.request

sys.path.insert(0, os.path.join(os.environ.get('TEMP', '/tmp'), 'cortex-asset-tools'))
from bs4 import BeautifulSoup
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'ui' / 'vehicle-catalog'
WIKI = 'https://gta.fandom.com/wiki/Vehicle_Customization_in_GTA_V/Wheels'
API = 'https://gta.fandom.com/api.php?action=parse&page=Vehicle_Customization_in_GTA_V/Wheels&prop=text&format=json'
PAINT = 'https://raw.githubusercontent.com/DurtyFree/gta-v-data-dumps/master/vehicleColors.json'
PLATE_SHEET = 'https://s3-attachments.int-cdn.lcpdfrusercontent.com/monthly_2026_03/54tm4parvp1f1.png.468e329245a911b6426d68b63e06d7bf.png'
PLATE_PAGE = 'https://www.lcpdfr.com/forums/topic/155615-gta-online-license-plates/'


def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=30).read()


def key(name):
    return re.sub(r'[^a-z0-9]', '', name.lower())


def main():
    DEST.mkdir(exist_ok=True)
    (DEST / 'wheels').mkdir(exist_ok=True)
    raw_colors = fetch(PAINT)
    colors = json.loads(raw_colors)
    page = json.loads(fetch(API))
    soup = BeautifulSoup(page['parse']['text']['*'], 'html.parser')
    types = [7, 2, 1, 4, 0, 3, 5, 6, 8, 9, 10, 11, 12]
    catalog, jobs = {}, []
    for wheel_type, table in zip(types, soup.select('table')[:13]):
        entries = catalog[str(wheel_type)] = {}
        for row in table.select('tr'):
            cells = row.find_all('td', recursive=False)
            if not cells or not row.select('td img'):
                continue
            for note in cells[0].select('sup'):
                note.decompose()
            name = cells[0].get_text(' ', strip=True)
            image_cells = [cell for cell in cells[1:] if cell.select_one('img')]
            for variant, cell in enumerate(image_cells):
                image = cell.select_one('img')
                url = image.get('data-src') or image.get('src')
                if not url.startswith('https://static.wikia.nocookie.net/'):
                    continue
                label = ('Chrome ' if variant else '') + name
                filename = f'{wheel_type}-{key(label)}.webp'
                item = {'name': label, 'image': f'vehicle-catalog/wheels/{filename}'}
                entries[key(label)] = item
                if variant:
                    entries[key(name + ' Chrome')] = item
                jobs.append((url, DEST / 'wheels' / filename))

    def download(job):
        url, path = job
        if not path.exists():
            with Image.open(io.BytesIO(fetch(url))) as image:
                image.thumbnail((192, 192), Image.Resampling.LANCZOS)
                image.convert('RGBA').save(path, 'WEBP', quality=82, method=6)
        return {'file': str(path.relative_to(DEST)).replace('\\', '/'), 'source': url,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        sources = list(pool.map(download, jobs))
    # The inspected reference sheet contains 256x128 original plate textures:
    # seven down the left column, six down the right. IDs follow Cfx's enum.
    plate_bytes = urllib.request.urlopen(PLATE_SHEET, timeout=30).read()
    plate_sources = []
    (DEST / 'plates').mkdir(exist_ok=True)
    with Image.open(io.BytesIO(plate_bytes)) as sheet:
        if sheet.size != (600, 896):
            raise ValueError('Plate sheet dimensions changed; re-inspect the crop map.')
        for column, ids in [(0, [3, 0, 4, 2, 1, 6, 12]), (344, [5, 7, 8, 9, 10, 11])]:
            for row, plate_id in enumerate(ids):
                box = [column, row * 128, column + 256, (row + 1) * 128]
                path = DEST / 'plates' / f'{plate_id}.webp'
                sheet.crop(box).convert('RGBA').save(path, 'WEBP', quality=90, method=6)
                plate_sources.append({'id': plate_id, 'file': f'plates/{plate_id}.webp', 'crop': box,
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    payload = {
        'colors': [{'id': c['Index'], 'name': c['ColorName'], 'hex': '#' + c['ColorHex'][-6:]} for c in colors['PrimarySecondaryColors']],
        'xenon': {c['Index']: '#' + c['LightColorHex'][-6:] for c in colors['XenonColors']},
        'wheels': catalog,
        'plates': {str(i): f'vehicle-catalog/plates/{i}.webp' for i in range(13)},
        # Source uses AARRGGBB and omits leading zeroes. CSS uses RRGGBBAA.
        'tints': {str(c['Index']): '#' + c['ColorHex'].zfill(8)[2:] + c['ColorHex'].zfill(8)[:2] for c in colors['WindowColors']},
    }
    (DEST / 'catalog.js').write_text('/* Generated by tools/fetch-vehicle-catalog.py. See sources.json. */\nwindow.VehicleCatalogData = ' + json.dumps(payload, ensure_ascii=True, separators=(',', ':')) + ';\n', encoding='utf-8')
    (DEST / 'sources.json').write_text(json.dumps({'paint': {'url': PAINT, 'sha256': hashlib.sha256(raw_colors).hexdigest()},
        'wheels': {'page': WIKI, 'credit': 'GTA Wiki contributors / Rockstar Games. In-game reference screenshots.',
                   'matching': 'Wheel type and exact normalized English name, never table position or guessed mod index.',
                   'images': sources},
        'plates': {'page': PLATE_PAGE, 'image': PLATE_SHEET, 'credit': 'Rockstar Games plate textures; reference sheet shared on LCPDFR.',
            'sourceSha256': hashlib.sha256(plate_bytes).hexdigest(),
            'nativeMapping': 'https://github.com/citizenfx/natives/blob/master/VEHICLE/GetVehicleNumberPlateTextIndex.md',
            'images': plate_sources}}, indent=2), encoding='utf-8')
    print(f'Catalog: {len(payload["colors"])} paints, {len(jobs)} wheel images, {sum(p.stat().st_size for p in (DEST / "wheels").glob("*.webp")):,} bytes')


if __name__ == '__main__':
    main()
