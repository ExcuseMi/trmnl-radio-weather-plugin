#!/usr/bin/env python3
"""Regenerate tools/render_check_devices.json: every TRMNL model with a screen class x full/hh/hv/quadrant,
a portrait full + hv for landscape models, and one dark full for models whose default palette is gray.
Source: https://trmnl.com/api/models and /api/palettes (what trmnlp itself reads)."""
import json, sys, urllib.request

def get(p):
    return json.load(urllib.request.urlopen(urllib.request.Request('https://trmnl.com/api/' + p, headers={'User-Agent': 'curl/8'}), timeout=30))['data']

models, palettes = get('models'), get('palettes')
VIEWS = [('full', 'full'), ('hh', 'half_horizontal'), ('hv', 'half_vertical'), ('q', 'quadrant')]
cases = []
for m in sorted(models, key=lambda m: m['name']):
    if not (m.get('css') or {}).get('classes'):
        continue   # Tidbyt, Vestaboard: no screen class
    if m['name'] == 'playdate':
        continue   # pending an owner decision (400x240)
    ids = m.get('palette_ids') or []
    cand = [p for p in palettes if p['id'] in ids]
    pal = next((p for p in cand if p['grays'] == 2 ** m['bit_depth']), cand[0] if cand else None)
    base = {'device': m['name'], 'locale': 'en-US', 'past_press': 1016, 'fields': {'bottom': 'days'}}
    if pal:
        base['palette'] = pal['id']
    grey = bool(pal) and not pal['id'].startswith('color-')
    def add(tag, view, **kw):
        cases.append({'name': f"{m['name']}__{tag}", 'view': view, **base, **kw})
    for tag, view in VIEWS:
        add(tag, view)
    if m['width'] >= m['height']:   # native portrait models already run as portrait above
        add('full-port', 'full', orientation='portrait')
        add('hv-port', 'half_vertical', orientation='portrait')
    if grey:
        add('full-dark', 'full', dark=True)
json.dump(cases, open(sys.argv[1] if len(sys.argv) > 1 else 'tools/render_check_devices.json', 'w'), separators=(',', ':'))
print(len(cases), 'cases', len({c['device'] for c in cases}), 'models')
