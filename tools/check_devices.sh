#!/bin/bash
# Device tier of the render check: every TRMNL model x layouts (tools/render_check_devices.json), same spec as the base
# suite (tools/render_check_cases.json). Prints a pass/fail table per device. Run after the base suite, before shipping.
# playdate (400x240) is left out until the owner decides. Models with no framework CSS rules are reported as a known harness gap.
# usage: tools/check_devices.sh [out_dir] [model-substring]   (PNGs land in out_dir, default /tmp/tp-radio-devices)
set -o pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-/tmp/tp-radio-devices}"; only="${2:-}"
cases="$(python3 -c "import json,sys;c=json.load(open('$here/tools/render_check_devices.json'));o='$only';print(json.dumps([x for x in c if o in x['device']]))")"
log="$(mktemp)"
(cd "$here/plugin" && SW_CASES="$cases" SW_OUT="$out" trmnlp test ../tools/render_check_spec.rb) > "$log" 2>&1
python3 - "$log" "$cases" <<'P'
import json, re, sys
log, cases = open(sys.argv[1]).read(), json.loads(sys.argv[2])
bad = set(re.findall(r'# renders (\S+)', log))
# Failures raised in after(:all) hooks (spread checks over several cases of one device) name no case: "<what> differs across ["<device>", ...]"
hook = {}
for what, dev in re.findall(r'(dial radius|condition/temperature ratio) differs across \["([^"]+)"', log):
    hook.setdefault(dev, set()).add({'dial radius': 'DIALR', 'condition/temperature ratio': 'CONDRATIO'}[what])
nhook = sum(len(v) for v in hook.values())
# Known harness gap (B12, coordinator 2026-11-14): these models have no model rules in the framework CSS 3.4.6 that trmnlp loads,
# so trmnlp draws them on the framework's 800x480 default (half views blank); their cases run and show, outside the TOTAL.
KNOWN = {'joan_13', 'joan_6', 'joan_6_pro', 'kobo_clara_2e', 'onyx_boox_go_10_3_lumi', 'seeed_sticky', 'xteink_x3', 'tcl_nxtpaper_14', 'kobo_libra_color'}
rows = {}
for c in cases:
    r = rows.setdefault(c['device'], [0, 0, []])
    r[0] += 1
    if c['name'] in bad: r[1] += 1; r[2].append(c['name'].split('__')[1])
for d, w in hook.items():
    if d in rows: rows[d][2].extend(sorted(w))
print('%-48s %5s %5s  failing' % ('device', 'cases', 'fail'))
for d, (n, f, l) in sorted(rows.items()): print('%-48s %5d %5d  %s%s' % (d, n, f, ' '.join(l), '  [known: no model rules in framework CSS 3.4.6 under trmnlp]' if d in KNOWN else ''))
ok = {d: r for d, r in rows.items() if d not in KNOWN}
nh = sum(len(v) for d, v in hook.items() if d not in KNOWN)
print('TOTAL %d cases, %d failing, %d spread checks failing (after-all hooks: DIALR, CONDRATIO); known harness gap: %d cases, %d failing'
      % (sum(r[0] for r in ok.values()), sum(r[1] for r in ok.values()), nh, sum(r[0] for d, r in rows.items() if d in KNOWN), sum(r[1] for d, r in rows.items() if d in KNOWN)))
sys.exit(1 if sum(r[1] for r in ok.values()) or nh else 0)
P
rc=$?; echo "log: $log"; exit $rc
