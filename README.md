# trmnl-radio-weather-plugin

## Radio Weather

![Radio Weather on the TRMNL X](assets/screenshot.png)

A calm weather console in the style of an early-80s hi-fi receiver, for [TRMNL](https://trmnl.com) e-paper displays.

- **Dials** (TRMNL X): a barometer with the weather it points to, and a thermometer between today's low and high. A small arrow shows a rising or falling trend.
- **Console**: the condition, the temperature in segment digits and what to wear (t-shirt, sweater, jacket or parka, plus umbrella, mittens or sunglasses when needed).
- **Meters**: rain, wind, humidity, UV, air quality, pollen and pressure, only when they matter. Each shows the value now and the rest of today's range; a gust gets an outline.
- **Rain calendar**: the coming hours lit when rain is expected; sunrise, sunset and the moon on dry days.
- **Bottom strip**: the coming days (low, high, icon and what to wear) or the next 24 hours in 2-hour steps. Auto shows hours during the day and days after 18:00.

Drawn for each view (full, half horizontal, half vertical, quadrant), for 1-bit, 2-bit and 4-bit screens and dark mode. The language follows your TRMNL account.

### Settings

| Setting | What it does |
|---|---|
| Location | Where the forecast is for |
| Temperature unit | Celsius or Fahrenheit |
| Time format | 24-hour or 12-hour |
| Bottom strip | Days, hours, or auto (hours, days after 18:00) |
| Hide title bar | Hides the title bar |
| Indoor readings | Shows a TRMNL sensor's indoor temperature |
| CO2 meter | Shows the CO2 meter from a TRMNL sensor |

Weather data: [Open-Meteo](https://open-meteo.com).

## Development

Built with [trmnlp](https://github.com/usetrmnl/trmnlp).

```bash
cd plugin
trmnlp serve        # preview
SW_CASES="$(cat ../tools/render_check_cases.json)" SW_OUT=/tmp/rw trmnlp test ../tools/render_check_spec.rb   # render check, PNGs in /tmp/rw
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
