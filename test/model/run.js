// Pure-logic tests for the SWModel block in plugin/src/shared.liquid. Run: node test/model/run.js
// The block is cut out between its markers, so the test runs the same bytes the device does.
'use strict';
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '../../plugin/src/shared.liquid'), 'utf-8');
const a = src.indexOf('// ==== MODEL_BEGIN ====');
const b = src.indexOf('// ==== MODEL_END ====');
if (a < 0 || b < 0) throw new Error('MODEL markers missing in shared.liquid: move them with the block, never delete them');
const SWModel = new Function(src.slice(a, b) + '\nreturn SWModel;')();
const fx = (n) => JSON.parse(fs.readFileSync(path.join(__dirname, '../../plugin/tests/fixtures', n + '.json'), 'utf-8'));

let failed = 0, passed = 0;
function test(name, fn) {
  try { fn(); passed++; } catch (e) { failed++; console.log('FAIL ' + name + ': ' + e.message); }
}
function eq(got, want, msg) {
  if (JSON.stringify(got) !== JSON.stringify(want)) throw new Error((msg || '') + ' got ' + JSON.stringify(got) + ', want ' + JSON.stringify(want));
}
function ok(v, msg) { if (!v) throw new Error(msg || 'not true'); }

test('3h slots span their hours and the next slot\'s first hour', () => {
  const m = SWModel.build(fx('mixed'), { interval: '3h' });
  const t = fx('mixed').hourly.temperature_2m;
  eq(m.slots[0].label, '06');
  eq(m.slots[1].label, '09');
  eq(m.slots[0].lo, Math.min(...t.slice(0, 4)));
  eq(m.slots[0].hi, Math.max(...t.slice(0, 4)));
  eq(m.slots[0].first, true);
  eq(m.slots[1].first, false);
});

test('hourly slots take one hour and the next', () => {
  const m = SWModel.build(fx('mixed'), { interval: '1h' });
  const t = fx('mixed').hourly.temperature_2m;
  eq([m.slots[3].lo, m.slots[3].hi], [Math.min(t[3], t[4]), Math.max(t[3], t[4])]);
  eq(m.slots.length, 24, 'capped at 24 slots');
});

test('daily slots use min/max and the weekday', () => {
  const m = SWModel.build(fx('mixed'), { interval: 'daily' });
  eq(m.slots[0].label, 'SU', '2026-11-08 is a Sunday');
  eq(m.slots[1].label, 'MO');
  eq([m.slots[0].lo, m.slots[0].hi], [1.4, 13.1]);
  eq(m.slots[0].rain, 90);
});

test('rain is the highest chance inside the slot, not past its end', () => {
  const m = SWModel.build(fx('mixed'), { interval: '3h' });
  const p = fx('mixed').hourly.precipitation_probability;
  eq(m.slots[4].rain, Math.max(...p.slice(12, 15)));
});

test('storm beats snow beats rain', () => {
  eq([95, 99, 75, 86, 61, 82, 45, 0, null].map(SWModel.severity), [4, 4, 3, 3, 2, 2, 1, 0, 0]);
});

test('an error answer gives no signal with the reason', () => {
  const m = SWModel.build(fx('error'), {});
  eq(m.ok, false);
  ok(/Latitude/.test(m.reason));
});

test('nothing at all gives no signal', () => {
  eq(SWModel.build(null, {}).ok, false);
  eq(SWModel.build({}, {}).ok, false);
});

test('empty arrays still show the current temperature', () => {
  const m = SWModel.build(fx('empty'), { interval: '3h' });
  eq(m.ok, true);
  eq(m.slots, []);
});

test('null temperatures make missing slots, not NaN', () => {
  const m = SWModel.build(fx('nulls'), { interval: '1h' });
  ok(m.slots.some((s) => s.missing));
  ok(m.slots.every((s) => s.missing || (Number.isFinite(s.lo) && Number.isFinite(s.hi))));
  ok(m.slots.every((s) => s.rain === null), 'all rain chances were null');
  eq(m.now.temp, fx('nulls').hourly.temperature_2m[0], 'falls back to the first hour');
});

test('an unknown interval falls back to 3h', () => {
  eq(SWModel.build(fx('mixed'), { interval: 'weekly' }).interval, '3h');
});


// Fuzz: every scale holds its data with a free segment either side and lights at least one segment.



test('format: rounding, no negative zero', () => {
  eq([SWModel.fmt(-0.3), SWModel.fmt(12.5), SWModel.fmt(null)], ['0', '13', '--']);
});

test('icon kinds follow the WMO code; the worst of a slot wins', () => {
  // owner: hail is its own kind (WMO 96, 99, a thunderstorm with hail), freezing rain is sleet, 71-77 and 85-86 snow
  eq([0, 1, 2, 3, 45, 51, 56, 61, 65, 66, 67, 71, 73, 75, 77, 80, 82, 85, 86, 95, 96, 99, null].map(SWModel.kind),
    ['clear', 'clear', 'partly', 'cloud', 'fog', 'drizzle', 'sleet', 'rain', 'heavy', 'sleet', 'sleet', 'snow', 'snow', 'snow', 'snow',
      'rain', 'heavy', 'snow', 'snow', 'storm', 'hail', 'hail', null]);
  eq(SWModel.worstKind([0, 2, 61, 3]), 'rain');
  const m = SWModel.build(fx('mixed'), { interval: '3h' });
  // 06-08 partly, 09-14 clear, 15-17 ends in rain at 17:00, 18-20 heavy at 20:00, 21-23 rain, then partly
  eq(m.slots.slice(0, 8).map((s) => s.icon), ['partly', 'clear', 'clear', 'rain', 'heavy', 'rain', 'partly', 'partly']);
  eq(m.slots[0].day, false, '06:00 in November is night');
  eq(m.now.sync, '06:00');
});

test('the rain window: first wet hour to the end of the wet run', () => {
  const m = SWModel.build(fx('mixed'), { interval: '3h' });
  eq([m.rain.fromLabel, m.rain.toLabel, m.rain.now], ['17:00', '23:00', false]);
  eq(SWModel.rainWindow([{ h: '06', p: 10, wet: false }], 50), null);
  eq(m.hours.length, 25);
});

test('the wet spell says what falls first: snow, hail, else rain', () => {
  const at = (code) => SWModel.rainWindow([{ h: '17', p: 80, icon: SWModel.kind(code), wet: true }, { h: '18', p: 10, icon: 'cloud', wet: false }], 50);
  eq([at(73).type, at(86).type, at(96).type, at(99).type, at(63).type, at(67).type], ['snow', 'snow', 'hail', 'hail', 'rain', 'rain']);
});

test('data age from the local data time, the offset and the render time', () => {
  // 06:00 local at +1 h is 05:00 UTC; rendered at 05:10 UTC
  eq(SWModel.ageMinutes('2026-11-08T06:00', 3600, Date.UTC(2026, 10, 8, 5, 10) / 1000), 10);
  eq(SWModel.ageMinutes(null, 0, 1), null);
  eq(SWModel.ageMinutes('2026-11-08T06:00', 0, 0), null);
});

console.log(passed + ' passed, ' + failed + ' failed');
process.exit(failed ? 1 : 0);
