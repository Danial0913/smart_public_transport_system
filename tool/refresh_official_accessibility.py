"""Refresh documented MRT facilities from station-specific MRT Corp pages.

Run from the repository root. Only exact station/line matches are imported.
Missing facilities remain unknown; ramps do not prove a complete step-free
route or wheelchair boarding. These records describe facilities, not live uptime.
"""
import json
import hashlib
import re
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import Request, urlopen

BASE = 'https://www.mymrt.com.my'


class Page(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.links = set()
        self.parts = []
        self.hidden = 0
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('script', 'style'):
            self.hidden += 1
        if tag == 'a' and attrs.get('href'):
            self.links.add(attrs['href'])

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)

    def handle_data(self, data):
        if not self.hidden and data.strip():
            self.parts.append(data.strip())


def fetch(url):
    cache = Path('build/official_accessibility')
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / (hashlib.sha256(url.encode()).hexdigest() + '.html')
    # Reuse only today's downloaded pages when retrying an interrupted import.
    if path.exists() and datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).date() == datetime.now(timezone.utc).date():
        return Page(path.read_text(encoding='utf-8'))
    request = Request(url, headers={'User-Agent': 'TransitAccessibilityDataImport/1.0'})
    with urlopen(request, timeout=45) as response:
        html = response.read().decode('utf-8')
    path.write_text(html, encoding='utf-8')
    return Page(html)


def main():
    directory = fetch(BASE + '/projects/kajang-line/stations/')
    links = {url for url in directory.links if re.fullmatch(
        BASE + r'/projects/(kajang|putrajaya)-line/stations/[^/]+/', url)}
    if not links:
        raise RuntimeError('No station links found; the source layout may have changed.')
    stops = json.loads(Path('assets/data/rapid-kl-rail.json').read_text())['stops']
    aliases = {
        'pusat-bandar-damansara': 'pusat-bandar-damansara',
        'batu-11-cheras': 'batu-sebelas-cheras',
        'kentomen': 'kentonmen',
        'muzium-negara': 'muzium-negara-kl-sentral',
        'sri-delima': 'seri-delima',
        'sentul-barat': 'sentul-west',
    }
    rows = []
    checked = datetime.now(timezone.utc).date().isoformat()
    for stop in stops:
        code = stop['id'].split(':')[1]
        if not code.startswith(('KG', 'PY')):
            continue
        slug = stop['name'].lower().replace(' ', '-')
        slug = aliases.get(slug, slug)
        line = 'kajang' if code.startswith('KG') else 'putrajaya'
        if slug == 'kwasa-damansara':
            line = 'putrajaya'
        if code.startswith('PY') and slug == 'tun-razak-exchange':
            slug = 'tun-razak-exchange-trx'
        url = f'{BASE}/projects/{line}-line/stations/{slug}/'
        if url not in links:
            print('Unmatched:', stop['id'], stop['name'], flush=True)
            continue
        page = fetch(url)
        # Restrict extraction to this station's facility section, before the
        # repeated line directory. Avoid footer/navigation keyword matches.
        text = '\n'.join(page.parts)
        match = re.search(r'station\s+faciliti?es(.*?)(?:KAJANG LINE|PUTRAJAYA LINE|Travel With MRT)',
                          text, re.I | re.S)
        if not match:
            raise RuntimeError(f'Facility section missing: {url}')
        section = match.group(1).lower()
        facilities = {}
        evidence = {}
        if re.search(r'(?m)^lift$', section):
            facilities['lift'] = 'available'
            evidence['lift'] = 'Lift'
        if 'disabled-friendly toilets' in section:
            facilities['accessibleToilet'] = 'available'
            evidence['accessibleToilet'] = 'Disabled-friendly toilets'
        if not facilities:
            print('No supported facilities:', stop['id'], flush=True)
            continue
        rows.append({'stopId': stop['id'], 'stopName': stop['name'],
                     'sourceName': 'MRT Corp', 'sourceUrl': url,
                     'checkedOn': checked, 'facilities': facilities,
                     'evidence': evidence})
        print(stop['id'], facilities, flush=True)
    result = {'schemaVersion': 1,
              'notice': 'Documented facilities only. Does not confirm current operation or a complete step-free route.',
              'stations': rows}
    Path('assets/data/official_accessibility.json').write_text(
        json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Imported', len(rows), 'station records.', flush=True)


if __name__ == '__main__':
    main()
