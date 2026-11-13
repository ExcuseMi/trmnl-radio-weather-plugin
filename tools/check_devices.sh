#!/bin/bash
# Device tier of the render check: every TRMNL model x layouts (tools/render_check_devices.json), same spec as the base
# suite (tools/render_check_cases.json). Prints a pass/fail table per device. Run after the base suite, before shipping.
# playdate (400x240) is left out until the owner decides.
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
rows = {}
for c in cases:
    r = rows.setdefault(c['device'], [0, 0, []])
    r[0] += 1
    if c['name'] in bad: r[1] += 1; r[2].append(c['name'].split('__')[1])
for d, w in hook.items():
    if d in rows: rows[d][2].extend(sorted(w))
print('%-48s %5s %5s  failing' % ('device', 'cases', 'fail'))
for d, (n, f, l) in sorted(rows.items()): print('%-48s %5d %5d  %s' % (d, n, f, ' '.join(l)))
print('TOTAL %d cases, %d failing, %d spread checks failing (after-all hooks: DIALR, CONDRATIO)' % (len(cases), sum(r[1] for r in rows.values()), nhook))
sys.exit(1 if bad or nhook else 0)
P
rc=$?; echo "log: $log"; exit $rc
