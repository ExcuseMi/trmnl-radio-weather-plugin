# trmnl-radio-weather-plugin

## Radio Weather

![Radio Weather on the TRMNL X](assets/screenshot.png)

The weather as the front of an early-80s hi-fi receiver, for [TRMNL](https://trmnl.com) e-paper displays:

- **L meter**: a needle shows the temperature now, between today's low and high.
- **R meter**: a needle shows the chance of rain.
- **Smoked-glass display**: the temperature in segment digits, humidity, UV and the time the rain starts. Warning lamps light for rain, snow, hail, thunder, frost, wind and high UV.
- **Level bars**: one key per coming day with its icon, low and high.

Every element shows data. It is drawn for each view (full, half horizontal, half vertical, quadrant) and each panel: a warm lamp glow on colour screens, solid ink on BWRY, grey on the TRMNL X, and a night glass in dark mode.

### Settings

| Setting | What it does |
|---|---|
| Location | City, postal code or latitude,longitude |
| Temperature Unit | Celsius or Fahrenheit |
| Days Shown | Day keys; Auto fits the screen |
| Dial Span | How far ahead the rain meter looks |
| Hide Title Bar | Hides the title bar on the full view |
| Language | Override the TRMNL account language |

Data comes from [Open-Meteo](https://open-meteo.com); no key is needed.

## Development

Built with [trmnlp](https://github.com/usetrmnl/trmnlp).

```bash
cd plugin
trmnlp serve        # preview
trmnlp test         # RSpec specs in plugin/tests
node ../test/model/run.js   # pure-logic tests of the weather model
(cd .. && npm install && node tools/build.js)   # after editing source/shared.liquid
ruby ../tools/sync_trmnl_i18n.rb   # re-sync TRMNL's translations
```

## Editing

Edit `source/shared.liquid` (all comments live there), then run `node tools/build.js`: it writes `plugin/src/shared.liquid` (Liquid comments stripped, page script minified), which is what trmnlp pushes. Never edit the built file; the model tests fail when it is out of date or over 84 KB.

Two render-check tiers, same spec (`tools/render_check_spec.rb`), run base first, then devices, then ship:

| Tier | Cases | Run |
|---|---|---|
| Base | `tools/render_check_cases.json` (OG, X, colour OG; scope unchanged) | `cd plugin && SW_CASES="$(cat ../tools/render_check_cases.json)" SW_OUT=<dir> trmnlp test ../tools/render_check_spec.rb` |
| Devices | `tools/render_check_devices.json`: every TRMNL model x full/hh/hv/quadrant, portrait full+hv, one dark | `tools/check_devices.sh [out_dir] [model-substring]` prints a pass/fail table per device (about 12 min for all) |

Regenerate the device file after TRMNL adds a model: `python3 tools/make_device_cases.py` (reads trmnl.com/api/models). Playdate is left out until the owner decides on small screens.

## Licence

Copyright (c) 2026 ExcuseMi. All rights reserved. No licence is granted to copy, modify or redistribute this code.

The weather texts (the `sw_i18n` capture in each `plugin/src/<view>.liquid`, the slots between the `I18N_TRMNL` markers in `shared.liquid`) come from
[usetrmnl/trmnl-i18n](https://github.com/usetrmnl/trmnl-i18n) and stay under its MIT licence; see
[third_party/trmnl-i18n-LICENSE](third_party/trmnl-i18n-LICENSE). The weather icons are loaded from trmnl.com and are not part of this repository.
