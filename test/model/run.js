// Pure-logic tests for the SWModel block in plugin/src/transform.js. Run: node test/model/run.js
// The block is cut out between its markers, so the test runs the same bytes the device does.
'use strict';
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '../../plugin/src/transform.js'), 'utf-8');
const a = src.indexOf('// ==== MODEL_BEGIN ====');
const b = src.indexOf('// ==== MODEL_END ====');
if (a < 0 || b < 0) throw new Error('MODEL markers missing in transform.js: move them with the block, never delete them');
const SWModel = new Function(src.slice(a, b) + '\nreturn SWModel;')();
const T = require('../../plugin/src/transform.js');
const fx = (n) => JSON.parse(fs.readFileSync(path.join(__dirname, '../../plugin/tests/fixtures', n + '.json'), 'utf-8'));

let failed = 0, passed = 0;
function test(name, fn) {
  try { fn(); passed++; } catch (e) { failed++; console.log('FAIL ' + name + ': ' + e.message); }
}
function eq(got, want, msg) {
  if (JSON.stringify(got) !== JSON.stringify(want)) throw new Error((msg || '') + ' got ' + JSON.stringify(got) + ', want ' + JSON.stringify(want));
}
function ok(v, msg) { if (!v) throw new Error(msg || 'not true'); }

// removed '3h slots span their hours and the next slot\'s first hour': the interval setting and the 3h slots are gone (owner 2026-11-10, days are the only list)
// removed 'hourly slots take one hour and the next': the interval setting is gone (owner 2026-11-10)
test('the days list: 14 days from today with min, max, rain chance and the weekday', () => {
  const m = SWModel.build(fx('mixed'), {});
  eq(m.days.length, 14);
  eq(m.days[0].label, 'SU', '2026-11-08 is a Sunday');
  eq([m.days[0].lo, m.days[0].hi, m.days[0].rain], [1.4, 13.1, 90]);
});

// removed 'rain is the highest chance inside the slot, not past its end': slots by interval are gone (owner 2026-11-10); the rain window has its own cases below
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
  const m = SWModel.build(fx('empty'), {});
  eq(m.ok, true);
});

test('null temperatures make missing slots, not NaN', () => {
  const m = SWModel.build(fx('nulls'), {});
  ok(m.days.every((s) => s.missing || (Number.isFinite(s.lo) && Number.isFinite(s.hi))));
  eq(m.now.temp, fx('nulls').hourly.temperature_2m[0], 'falls back to the first hour');
});

// removed 'an unknown interval falls back to 3h': the interval setting is gone (owner 2026-11-10)

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
  const m = SWModel.build(fx('mixed'), {});
  eq(m.days[0].icon, 'rain');
  eq(m.now.day, false, '06:00 in November is night');
  eq(m.now.sync, '06:00');
});

test('the rain window: first wet hour to the end of the wet run', () => {
  const m = SWModel.build(fx('mixed'), {});
  eq([m.rain.fromLabel, m.rain.toLabel, m.rain.now], ['17:00', '23:00', false]);
  eq(SWModel.rainWindow([{ h: '06', p: 10, wet: false }], 50), null);
  eq(m.hours.length, 25);
});

test('the wet spell says what falls first: snow, hail, else rain', () => {
  const at = (code) => SWModel.rainWindow([{ h: '17', p: 80, icon: SWModel.kind(code), wet: true }, { h: '18', p: 10, icon: 'cloud', wet: false }], 50);
  eq([at(73).type, at(86).type, at(96).type, at(99).type, at(63).type, at(67).type], ['snow', 'snow', 'hail', 'hail', 'rain', 'rain']);
});

// removed 'data age from the local data time, the offset and the render time': ageMinutes is gone; the sensor staleness rule is tested below
test('humidity and UV now come through; missing ones are null, never a crash', () => {
  const m = SWModel.build(fx('mixed'), {});
  eq([m.now.hum, m.now.uv], [91, 1.8]);
  // an old cached answer without the uv fields
  const old = fx('mixed');
  delete old.current.uv_index; delete old.current.relative_humidity_2m;
  const o = SWModel.build(old, {});
  eq([o.ok, o.now.hum, o.now.uv], [true, null, null]);
  eq(SWModel.fmt(o.now.uv), '--');
  // a null inside the list
  const nl = fx('mixed'); nl.current.uv_index = null;
  const n = SWModel.build(nl, {});
  eq([n.now.uv, n.now.hum], [null, 91]);
});


test('the rain window: a wet code needs 30 percent, a dry code needs the chosen chance', () => {
  eq(SWModel.rainWindow([{ h: '17', p: 25, wet: true }], 50), null, 'wet code, 25 percent: dry');
  eq(SWModel.rainWindow([{ h: '17', p: 35, wet: true }, { h: '18', p: 5, wet: false }], 50).fromLabel, '17:00');
  eq(SWModel.rainWindow([{ h: '17', p: 55, wet: false }, { h: '18', p: 5, wet: false }], 50).fromLabel, '17:00', 'chance alone starts a window');
  eq(SWModel.rainWindow([{ h: '17', p: 45, wet: false }], 50), null);
});

test('evening mode from 18:00 local: tomorrow in the console data, today untouched before 18:00', () => {
  const day = SWModel.build(fx('mixed'), {});
  eq(day.ev, null);
  const e = fx('mixed'); e.current.time = '2026-11-08T17:59';
  eq(SWModel.build(e, {}).ev, null, '17:59 is still day mode');
  e.current.time = '2026-11-08T18:00';
  const m = SWModel.build(e, {});
  eq([m.ev.hi, m.ev.lo, m.ev.code], [fx('mixed').daily.temperature_2m_max[1], fx('mixed').daily.temperature_2m_min[1], fx('mixed').daily.weather_code[1]]);
  eq(m.hours.length, 24, 'the hours are tomorrow\'s');
  eq([m.today.hi, m.today.uvMax], [m.ev.hi, fx('mixed').daily.uv_index_max[1]], 'the day values are tomorrow\'s');
  eq(m.rain.fromLabel, '17:00');
  eq(m.rain.now, false, 'never "raining now" for tomorrow');
  eq(m.days[0].label, 'SU', 'the days list itself still starts today (the page picks the start)');
});

test('UV relevance inputs: daylight flag and the highest UV of the day', () => {
  const m = SWModel.build(fx('mixed'), {});
  eq([m.now.day, m.today.uvMax], [false, 2.1]);
  const d = fx('mixed'); d.current.is_day = 1; d.daily.uv_index_max[0] = 6;
  const n = SWModel.build(d, {});
  eq([n.now.day, n.today.uvMax], [true, 6]);
});

test('sun times and the moon: today and tomorrow, daylight flag', () => {
  const s = T.sunTimes(fx('mixed'));
  eq([s.riseL, s.setL, s.rise1L, s.set1L, s.day], ['07:21', '16:35', '07:22', '16:34', false]);
  const d = fx('mixed'); d.current.time = '2026-11-08T12:00';
  eq(T.sunTimes(d).day, true);
  ok(/^wi-moon/.test(T.moonIcon('2026-11-08T06:00')));
  eq(T.sunTimes({ daily: {} , current: { time: '2026-11-08T06:00' } }), null, 'no sun data: null');
});

test('pollen level: highest type, 0..1 steps, null without data, only today\'s hours', () => {
  eq(T.pollenLevel({ current: { time: '2026-11-08T06:00', grass_pollen: 5 } }), 0.15);
  eq(Math.round(T.pollenLevel({ current: { time: '2026-11-08T06:00', grass_pollen: 30, birch_pollen: 2 } }) * 100), 45);
  eq(T.pollenLevel({ current: { time: '2026-11-08T06:00' } }), null);
  eq(T.pollenLevel(null), null);
  const aq = { current: { time: '2026-11-08T06:00' }, hourly: { time: ['2026-11-08T07:00', '2026-11-09T07:00'], grass_pollen: [5, 400] } };
  eq(T.pollenLevel(aq), 0.15, 'tomorrow\'s 400 does not count');
});

test('air quality: tomorrow\'s maximum in the evening, null (row hidden) when the answer stops today', () => {
  const e = fx('mixed'); e.current.time = '2026-11-08T19:00';
  const aq = { current: { time: '2026-11-08T19:00', european_aqi: 30 }, hourly: { time: ['2026-11-08T20:00', '2026-11-09T09:00', '2026-11-09T10:00'], european_aqi: [30, 55, 75] } };
  eq(SWModel.build(Object.assign({}, e, { aq }), {}).now.aqi, 75);
  const today = { current: aq.current, hourly: { time: ['2026-11-08T20:00'], european_aqi: [30] } };
  eq(SWModel.build(Object.assign({}, e, { aq: today }), {}).now.aqi, null);
  eq(SWModel.build(Object.assign({}, fx('mixed'), { aq }), {}).now.aqi, 30, 'by day: the current index');
});

test('indoor sensor: latest reading, dropped when older than 3 hours', () => {
  const sens = { device_1: { temperature: [{ '2026-11-08 05:00:00 UTC': 21.1 }, { '2026-11-08 05:30:00 UTC': 21.6 }], humidity: [{ '2026-11-08 05:30:00 UTC': 48 }], carbon_dioxide: [], pressure: [] } };
  const base = Date.UTC(2026, 10, 8, 5, 40) / 1000;
  const m = SWModel.build(Object.assign({}, fx('mixed'), { sens, renderedAt: base }), {});
  eq([m.inn.temp, m.inn.hum], [21.6, 48]);
  const old = SWModel.build(Object.assign({}, fx('mixed'), { sens, renderedAt: base + 4 * 3600 }), {});
  eq([old.inn.temp, old.inn.hum], [null, null]);
});

test('sun: the next sunrise and sunset, tomorrow flagged (owner 2026-11-12)', () => {
  const at = (hm) => { const d = JSON.parse(JSON.stringify(fx('mixed'))); d.current.time = '2026-11-08T' + hm; return T.sunTimes(d); };
  const m = at('06:00'), a = at('15:00'), e = at('17:00');
  eq([m.riseL, m.riseTom, m.setL, m.setTom], ['07:21', false, '16:35', false], 'before sunrise: both today');
  eq([a.riseL, a.riseTom, a.setL, a.setTom], ['07:22', true, '16:35', false], 'afternoon: sunrise is tomorrow');
  eq([e.riseL, e.riseTom, e.setL, e.setTom], ['07:22', true, '16:34', true], 'after sunset: both tomorrow');
});

// v2 X full view: the parts the layout places (buildView in transform.js)
test('the X view: meters in owner order, rain calendar on a wet day, five days from tomorrow', () => {
  const raw = fx('mixed'), M = SWModel.build(raw, {}), v = T.buildView(M, T.buildI18n('nl'), raw.daily, 'wi-moon-full');
  eq(v.meters.map((m) => m.key), ['wind', 'humidity', 'baro']);
  ok(v.rain && !v.dry && v.rain.hours.length === 12, 'rain calendar on a wet day');
  eq(v.days.map((d) => d.name), ['MA', 'DI', 'WO', 'DO', 'VR'], 'days start tomorrow');
  ok(!JSON.stringify(v).includes('<svg'), 'the transform builds no SVG (owner 2026-11-12)');
});
test('the X view: a dry day shows sun times and the moon, no calendar', () => {
  const raw = fx('mixed'), n = raw.hourly.time.length;
  raw.hourly.precipitation_probability = Array(n).fill(0); raw.hourly.weather_code = Array(n).fill(1); raw.hourly.precipitation = Array(n).fill(0);
  const v = T.buildView(SWModel.build(raw, {}), T.buildI18n('nl'), raw.daily, 'wi-moon-full');
  ok(!v.rain && v.dry && /wi-moon-full/.test(v.dry.moon), 'dry block with the moon');
});
test('the X view: no data gives no crash and empty parts', () => {
  const M = SWModel.build(fx('error'), {}), v = T.buildView(M, T.buildI18n('en'), null, null);
  eq(v.ok, false); eq(v.days.length, 0);
});
// Page drawings (DRAW block of shared.liquid), cut out like the model so the test runs the page's own bytes.
const sh = fs.readFileSync(path.join(__dirname, '../../plugin/src/shared.liquid'), 'utf-8');
const da = sh.indexOf('// ==== DRAW_BEGIN ===='), db = sh.indexOf('// ==== DRAW_END ====');
if (da < 0 || db < 0) throw new Error('DRAW markers missing in shared.liquid');
const D = new Function(sh.slice(da, db) + '\nreturn SWDraw;')();
test('segment digits: lit segments only, no ghost segments (owner 2026-11-12)', () => {
  eq((D.digits('1', 100).match(/<polygon/g) || []).length, 2, 'a 1 is two segments');
  eq((D.digits('8.8', 100).match(/<polygon/g) || []).length, 14); ok(/<rect/.test(D.digits('8.8', 100)), 'decimal point');
});
test('segment digits: the minus is narrow, no digit-wide gap before the 2', () => {
  const w = (s) => +/viewBox="0 0 ([\d.]+)/.exec(D.digits(s, 100))[1];
  ok(w('-2') < w('22') * 0.9, 'minus width ' + w('-2') + ' vs ' + w('22'));
});
test('block meter: half lit lights five of ten, no data lights none', () => {
  const lit = (s) => ((s.split('text--gray-40')[1] || '').match(/<rect/g) || []).length;
  eq([lit(D.meter(0.5, 300, 40)), lit(D.meter(null, 300, 40)), lit(D.meter(2, 300, 40))], [5, 0, 10]);
});
test('rain calendar: 12 hours from two hours before the rain, rain hours lit', () => {
  const hrs = Array.from({ length: 25 }, (_, i) => ({ h: String(i).padStart(2, '0') }));
  const c = T.rainHours(hrs, { from: 5, to: 7 });
  eq(c.length, 12); eq(c[0].h, '03', 'starts two hours before'); eq(c.filter((q) => q.wet).map((q) => q.h), ['05', '06', '07']);
  eq(T.rainHours(hrs, { from: 1, to: 2 })[0].h, '00', 'never before the first hour');
  const svg = D.rain(c, 600, 120);
  eq((svg.match(/<rect/g) || []).length, 3, 'one lit cell per rain hour'); ok(!/gray/.test(svg), 'dry hours in full text colour');
});
test('dials: needle drawn last, low mark hollow, high mark solid, baro zone icons', () => {
  const t = D.dial({ now: 1.6, lo: 1.4, hi: 13.1, a: 0, b: 15, step: 5 }, 900, 380, false);
  ok(/<circle[^>]*\/><\/g><\/svg>$/.test(t), 'hub (needle group) is the last thing drawn');
  ok(/fill="none" stroke="currentColor"[^>]*stroke-linejoin/.test(t), 'hollow low mark');
  const b = D.dial({ now: 1013, lo: 1008, hi: 1016, a: 970, b: 1050, icons: ['a.svg', 'b.svg', 'c.svg', 'd.svg'] }, 900, 380, true);
  eq((b.match(/<image /g) || []).length, 4, 'four zone icons');
  ok(D.dial({ now: null, lo: null, hi: null, a: 0, b: 15, step: 5 }, 900, 380, false).indexOf('<polygon') < 0, 'no data: no needle, no marks');
});
test('right column: dotted rule between rain and sun/moon, only when rain shows (owner 2026-11-12)', () => {
  const i = sh.indexOf('data-sw-sep="rain-sun"'), open = sh.lastIndexOf('{%- if ui.rain %}', i), close = sh.indexOf('{%- endif %}', open);
  ok(i > 0 && open > 0 && i < close, 'separator inside the rain block');
  ok(sh.indexOf('ui.rain.icon', open) < i && sh.indexOf('ui.sun.rise', i) > i, 'after the calendar, before the sun times');
});
test('days strip: 5-degree lines faint, blocks at least half the row, now line dark', () => {
  const s = D.day({ loV: 2, hiV: 6 }, { a: -5, b: 15, major: 5, now: 1.6 }, 800, 40);
  ok(/^<svg[^>]*>(<defs>.*<\/defs>)?<g class="text--gray-7\d"/.test(s), 'grid lines light grey');
  const h = +/<rect x="[\d.]+" y="[\d.]+" width="[\d.]+" height="([\d.]+)"/.exec(s.split('text--gray-40')[1])[1];
  ok(h >= 20, 'block height ' + h + ' of 40');
});
test('dial light: backlight in light mode (2-bit up), glow in dark (blur 4-bit, halo 2-bit, none 1-bit)', () => {
  const t = (m) => { D.mode = m; const s = D.dial({ now: 5, lo: 1, hi: 9, a: 0, b: 15, step: 5 }, 900, 380, false); D.mode = null; return s; };
  ok(/data-sw-backlight/.test(t({ dark: false, bits: 4 })), 'light 4-bit backlight'); ok(!/data-sw-backlight/.test(t({ dark: false, bits: 1 })), 'no backlight on 1-bit');
  ok(/data-sw-glow="4"[\s\S]*feGaussianBlur|feGaussianBlur[\s\S]*data-sw-glow="4"/.test(t({ dark: true, bits: 4 })), 'dark 4-bit blur glow');
  ok(/feMorphology/.test(t({ dark: true, bits: 2 })) && !/feGaussianBlur/.test(t({ dark: true, bits: 2 })), 'dark 2-bit halo, no blur');
  ok(!/data-sw-glow|data-sw-backlight/.test(t({ dark: true, bits: 1 })), '1-bit dark: nothing');
  ok(/<circle[^>]*\/><\/g><\/svg>$/.test(t({ dark: true, bits: 4 })), 'needle hub still last');
});
test('OG full (md): no dials, 5-segment meters, 4 days; X (lg) keeps dials, 10 segments, 5 days', () => {
  ok(/<div class="hidden lg:block h--\[30cqh\]"><div class="grid grid--cols-2/.test(sh), 'dials only on lg');
  ok(/lg:hidden" data-sw-part="meter" data-sw-n="5"/.test(sh) && /hidden lg:block[^"]*" data-sw-part="meter" data-sw-n="10"/.test(sh), 'meter copies per size');
  ok(/forloop.index > 4 %}<div class="hidden lg:block">/.test(sh), 'fifth day only on lg');
  const cells = (n) => (D.meter(0, 200, 30, n).match(/<rect/g) || []).length;
  eq([cells(5), cells(10)], [5, 10]);
  D.mode = { bits: 2 }; ok(/text--gray-45/.test(D.meter(0, 200, 30, 5)), '2-bit: unlit cells dark enough to show'); D.mode = null;
});
test('rain unit: icon left of the grid at its height on lg, above it on md; separator under the unit', () => {
  const u = sh.indexOf('data-sw-unit="rain"'), end = sh.indexOf('data-sw-part="rain"', u);
  ok(u > 0 && /flex--col lg:flex--row/.test(sh.slice(sh.lastIndexOf('<div', u), u)), 'column on md, row on lg');
  ok(/hidden lg:block h--\[8cqh\][^>]*ui.rain.icon/.test(sh.slice(u, end)) && /lg:h--\[8cqh\][^"]*" data-sw-part="rain"/.test(sh), 'lg icon as tall as the grid');
  ok(sh.indexOf('data-sw-sep="rain-sun"') > end, 'separator after the unit');
});
console.log(passed + ' passed, ' + failed + ' failed');
process.exit(failed ? 1 : 0);
