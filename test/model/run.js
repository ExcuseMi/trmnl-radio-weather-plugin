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

test('no evening mode (owner 2026-11-12): at 19:00 the console shows now and tomorrow is in the days list', () => {
  const e = fx('mixed'); e.current.time = '2026-11-08T19:00';
  const m = SWModel.build(e, {});
  ok(!('ev' in m) || m.ev == null, 'no evening model');
  eq(m.today.hi, SWModel.build(fx('mixed'), {}).today.hi, 'today values stay today\'s');
  const v = T.buildView(m, T.buildI18n('nl'), e.daily);
  eq(v.days[1].name, T.buildView(SWModel.build(fx('mixed'), {}), T.buildI18n('nl'), fx('mixed').daily).days[1].name, 'tomorrow is the second day, as by day');
  ok(v.days.length >= 2, 'tomorrow on screen');
});

test('time format: the setting decides, 24 h when missing, the TIME constant overrides', () => {
  eq([T.timeIs12(null, '12'), T.timeIs12(null, 12), T.timeIs12(null, '24'), T.timeIs12(null, T.field({}, 'time_format', '24'))], [true, true, false, false], 'missing field: 24 h');
  eq([T.timeIs12('24', '12'), T.timeIs12('12', '24')], [false, true], 'constant wins');
  const y = fs.readFileSync(path.join(__dirname, '../../plugin/src/settings.yml'), 'utf-8');
  const fields = y.split(/^- keyname: /m).slice(1).map((part) => ({ key: part.split('\n')[0], group: (/^  group: (.+)$/m.exec(part) || [])[1] || null }));
  eq(fields.map((f) => f.key), ['author_info', 'lat_lon', 'unit', 'time_format', 'bottom', 'hide_title_bar', 'sensor_show', 'sensor_co2'], 'settings in owner order');
  eq(fields.map((f) => f.group), [null, null, 'Display', 'Display', 'Display', 'Display', 'Sensor', 'Sensor'], 'settings groups');
  ok(/- 24 hours \(17:00\): '24'\n  - 12 hours \(5:00 PM\): '12'\n  default: '24'\n/.test(y) && /- Days: days\n  - Hours: hours\n  - Hours, days after 18:00: auto\n  default: auto\n/.test(y), 'time format 24 by default, bottom strip Days by default');
});

test('temperature trend arrow: +3 h against now, 1 degree C or 2 degrees F', () => {
  eq([T.tempTrend(4, 5, false), T.tempTrend(4, 4.9, false), T.tempTrend(4, 3, false), T.tempTrend(4, 3.1, false), T.tempTrend(null, 3, false)], ['up', 'level', 'down', 'level', null]);
  eq([T.tempTrend(40, 42, true), T.tempTrend(40, 41.9, true), T.tempTrend(40, 38, true), T.tempTrend(40, 38.1, true)], ['up', 'level', 'down', 'level']);
  const v = T.buildView(SWModel.build(fx('mixed'), {}), T.buildI18n('nl'), fx('mixed').daily);
  eq(v.tdial.arrow, 'up', 'mixed: 1.6 now, 4.6 at 09:00');
});

test('bottom strip auto: hours until 17:59 local, days from 18:00', () => {
  eq([T.bottomHours('auto', '2026-11-13T17:59'), T.bottomHours('auto', '2026-11-13T18:00'), T.bottomHours('auto', '2026-11-13T00:00'), T.bottomHours('auto', null)], [true, false, true, false]);
  eq([T.bottomHours('hours', '2026-11-13T20:00'), T.bottomHours('days', '2026-11-13T09:00')], [true, false]);
});

test('air quality: the current index at any hour (no evening mode)', () => {
  const e = fx('mixed'); e.current.time = '2026-11-08T19:00';
  const aq = { current: { time: '2026-11-08T19:00', european_aqi: 30 }, hourly: { time: ['2026-11-08T20:00', '2026-11-09T09:00', '2026-11-09T10:00'], european_aqi: [30, 55, 75] } };
  eq(SWModel.build(Object.assign({}, e, { aq }), {}).now.aqi, 30);
});

test('indoor sensor: latest reading, dropped when older than 3 hours', () => {
  const sens = { device_1: { temperature: [{ '2026-11-08 05:00:00 UTC': 21.1 }, { '2026-11-08 05:30:00 UTC': 21.6 }], humidity: [{ '2026-11-08 05:30:00 UTC': 48 }], carbon_dioxide: [], pressure: [] } };
  const base = Date.UTC(2026, 10, 8, 5, 40) / 1000;
  const m = SWModel.build(Object.assign({}, fx('mixed'), { sens, renderedAt: base }), {});
  eq([m.inn.temp, m.inn.hum], [21.6, 48]);
  const old = SWModel.build(Object.assign({}, fx('mixed'), { sens, renderedAt: base + 4 * 3600 }), {});
  eq([old.inn.temp, old.inn.hum], [null, null]);
});

test('indoor sensor in the view: BUITEN/BINNEN twin readout, twin needle, CO2 meter and high CO2 first (as live)', () => {
  const raw = fx('mixed'), view = (inn) => { const M = SWModel.build(raw, {}); M.inn = Object.assign({ temp: null, hum: null, co2: null, press: null }, inn); return T.buildView(M, T.buildI18n('nl'), raw.daily); };
  const none = view({});
  eq([none.inn, none.tdial.twin, none.meters.some((m) => m.key === 'co2')], [null, null, false], 'no sensor: nothing changes');
  const v = view({ temp: 21.6, hum: 48, co2: 900 });
  eq([v.inn.temp, v.inn.out, v.inn.in, v.inn.hum, v.tdial.twin, 'feels' in v, 'felt' in v.inn], ['21.6', 'BUITEN', 'BINNEN', 'VOCHT 48 %', 21.6, false, false], 'owner 2026-11-13: no felt readout, no felt line under BUITEN');
  ok(v.tdial.b >= 21.6, 'dial scale holds the indoor needle');
  const out = view({}), M0 = SWModel.build(raw, {}), cold = Object.assign({}, M0, { now: Object.assign({}, M0.now, { temp: 15, feels: 1 }) });
  eq(['feels' in out, T.buildView(cold, T.buildI18n('nl'), raw.daily).cue[0]], [false, 'parka'], 'owner 2026-11-13: no felt readout without a sensor either; the felt temperature (1) still picks the top layer (parka, not the air temperature 15)');
  const hi = view({ temp: 21.6, co2: 1500 }).meters.map((m) => m.key), lo = view({ temp: 21.6, co2: 900 }).meters.map((m) => m.key);
  eq(hi.slice(0, 2), ['wind', 'co2'], 'CO2 above 1400 ppm moves up');
  ok(lo.indexOf('co2') < 0 || lo.indexOf('co2') === lo.length - 1, 'normal CO2 stays last');
});

test('temperature readout: no decimal once the whole part has 3+ characters (owner, step 12: 104.6 F touched the divider)', () => {
  const raw = fx('mixed'), at = (t) => { const M = SWModel.build(raw, {}); M.now.temp = t; return T.buildView(M, T.buildI18n('nl'), raw.daily); };
  eq([104.6, -13.2, -12, 38.3, -2.5, 99.96, -0.04].map((t) => at(t).tdial.value), ['105', '-13', '-12', '38.3', '-2.5', '100', '0.0']);
});

test('sun: the next sunrise and sunset, tomorrow flagged (owner 2026-11-12)', () => {
  const at = (hm) => { const d = JSON.parse(JSON.stringify(fx('mixed'))); d.current.time = '2026-11-08T' + hm; return T.sunTimes(d); };
  const m = at('06:00'), a = at('15:00'), e = at('17:00');
  eq([m.riseL, m.riseTom, m.setL, m.setTom], ['07:21', false, '16:35', false], 'before sunrise: both today');
  eq([a.riseL, a.riseTom, a.setL, a.setTom], ['07:22', true, '16:35', false], 'afternoon: sunrise is tomorrow');
  eq([e.riseL, e.riseTom, e.setL, e.setTom], ['07:22', true, '16:34', true], 'after sunset: both tomorrow');
});

// v2 X full view: the parts the layout places (buildView in transform.js)
test('the X view: meters in owner order, rain calendar on a wet day, seven days from today (X half vertical shows 7), today flagged', () => {
  const raw = fx('mixed'), M = SWModel.build(raw, {}), v = T.buildView(M, T.buildI18n('nl'), raw.daily, 'wi-moon-full');
  eq(v.meters.map((m) => m.key), ['wind', 'humidity', 'baro'], 'no REGEN meter row (the rain gauge replaced it)');
  ok(v.rain && !v.dry && v.rain.hours.length === 12, 'rain calendar on a wet day');
  eq(v.days.map((d) => d.name), ['ZO', 'MA', 'DI', 'WO', 'DO', 'VR', 'ZA'], 'seven days from today'); eq(v.days.map((d) => d.today), [true, false, false, false, false, false, false]);
  ok(!JSON.stringify(v).includes('<svg'), 'the transform builds no SVG (owner 2026-11-12)');
});
test('rain gauge (owner 2026-11-13): mm over the calendar hours to 5 segments of 2 mm (0.08 in), label, only with rain in the calendar', () => {
  const raw = fx('mixed'), mk = (f) => { const M = SWModel.build(raw, {}); if (f) f(M); const v = T.buildView(M, T.buildI18n('nl'), raw.daily); ok(!v.meters.some((m) => m.key === 'regen'), 'no REGEN meter'); return v.rain; };
  const amt = (a) => mk((M) => { M.hours.forEach((q) => { q.mm = 0; }); M.hours[M.rain.from].mm = a / 2; M.hours[M.rain.to].mm += a / 2; }).gauge;
  eq([amt(8).segs, amt(8).label], [4, '8 mm'], '8 mm is 4 segments');
  eq([amt(2).segs, amt(4).segs, amt(10).segs, amt(0.3).segs], [1, 2, 5, 1], 'segments from the bottom, one for a trace');
  eq(mk((M) => { M.hours[M.rain.from].mm = 40; }).gauge.segs, 5, 'clamped at 5');
  eq(mk((M) => { M.hours.forEach((q) => { q.mm = null; }); }).gauge, null, 'hidden without an amount');
  eq(mk((M) => { M.hours.forEach((q) => { q.mm = 0; }); }).gauge, null, 'hidden at 0');
  ok(!T.buildView((() => { const M = SWModel.build(raw, {}); M.rain = null; return M; })(), T.buildI18n('nl'), raw.daily).rain, 'no calendar, no gauge');
  const fm = mk((M) => { M.unit = 'F'; M.hours.forEach((q) => { q.mm = 0; }); M.hours[M.rain.from].mm = 0.3; }).gauge; eq([fm.segs, fm.label], [4, '0.3 in'], 'inch scale 0.4');
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
const shRaw = fs.readFileSync(path.join(__dirname, '../../plugin/src/shared.liquid'), 'utf-8');
const sh = shRaw.replace(/\{\{ (\d+) \| times: \w+ \| round \| at_most: 100 \}\}/g, '$1');   // per-view size factors read as the full view's values
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
test('meters (owner 2026-11-12): order wind, uv, aqi, humidity, pollen, baro, co2; pollen only above zero', () => {
  const raw = fx('mixed'), M0 = SWModel.build(raw, {});
  const keys = (pol, extra) => { const M = SWModel.build(raw, {}); M.rain = null; M.now.pollen = pol; Object.assign(M.now, extra || {}); return T.buildView(M, T.buildI18n('nl'), raw.daily).meters.map((m) => m.key); };
  eq([keys(0).includes('pollen'), keys(null).includes('pollen'), keys(undefined).includes('pollen'), keys(0.05).includes('pollen')], [false, false, false, true], 'zero, null, missing hide pollen; low pollen shows');
  const k = keys(0.4, { aqi: 30 }); ok(k.indexOf('humidity') >= 0 && k.indexOf('pollen') > k.indexOf('humidity'), 'humidity before pollen: ' + k);
  ok(M0 && keys(0.4, { aqi: 30 }).slice(0, 3).join() === 'wind,aqi,humidity', 'priority: humidity kept before pollen when rows run short: ' + k);
});
test('block meter: any reading above zero lights one cell', () => {
  const lit = (s) => ((s.split('<g data-sw-on data-sw-st="a">')[1] || '').match(/data-sw-c=/g) || []).length;   // the current cells (owner 2026-11-13: full ink)
  eq([lit(D.meter({ frac: 0.01 }, 300, 40)), lit(D.meter({ frac: 0 }, 300, 40))], [1, 0]);
});
test('block meter: half lit lights five of ten, no data lights none', () => {
  const lit = (s) => ((s.split('<g data-sw-on data-sw-st="a">')[1] || '').match(/data-sw-c=/g) || []).length;
  eq([lit(D.meter({ frac: 0.5 }, 300, 40)), lit(D.meter({ frac: null }, 300, 40)), lit(D.meter({ frac: 2 }, 300, 40))], [5, 0, 10]);
});
test('rain calendar: 12 hours from the first wet hour, rain hours lit', () => {
  const hrs = Array.from({ length: 25 }, (_, i) => ({ h: String(i).padStart(2, '0') }));
  const c = T.rainHours(hrs, { from: 5, to: 7 });
  eq(c.length, 12); eq(c[0].h, '05', 'starts at the first wet hour'); eq(c.filter((q) => q.wet).map((q) => q.h), ['05', '06', '07']);
  eq(T.rainHours(hrs, { from: 0, to: 2 })[0].h, '00', 'raining now: starts now'); eq(T.rainHours(hrs, { from: 20, to: 22 })[0].h, '13', 'always 12 cells');
  const svg = D.rain(c, 600, 120);
  eq((svg.match(/<rect/g) || []).length, 3, 'one lit cell per rain hour'); ok(!/gray/.test(svg), 'dry hours in full text colour');
});
test('dials: needle drawn last, low mark hollow, high mark solid, baro zone icons', () => {
  const t = D.dial({ now: 1.6, lo: 1.4, hi: 13.1, a: 0, b: 15, step: 5 }, 900, 380, false);
  ok(/<circle[^>]*\/><\/g><\/g><\/svg>$/.test(t), 'hub (needle group) is the last thing drawn');
  ok(/fill="none" stroke="currentColor"[^>]*stroke-linejoin/.test(t), 'hollow low mark');
  const b = D.dial({ now: 1013, lo: 1008, hi: 1016, a: 970, b: 1050, icons: ['a.svg', 'b.svg', 'c.svg', 'd.svg'] }, 900, 380, true);
  eq((b.match(/<image /g) || []).length, 4, 'four zone icons');
  ok(D.dial({ now: null, lo: null, hi: null, a: 0, b: 15, step: 5 }, 900, 380, false).indexOf('<polygon') < 0, 'no data: no needle, no marks');
});
test('right column: no rule between the rain calendar and the sun times (owner 2026-11-12, later decision)', () => {
  ok(sh.indexOf('data-sw-sep="rain-sun"') < 0, 'no rain-sun separator');
});
test('days strip: 5-degree lines faint, blocks at least half the row, now line dark', () => {
  const s = D.day({ loV: 2, hiV: 6 }, { a: -5, b: 15, major: 5, now: 1.6 }, 800, 40);
  ok(/^<svg[^>]*>(<defs>.*<\/defs>)?<g class="text--gray-7\d"/.test(s), 'grid lines light grey');
  const h = +/<rect x="[\d.]+" y="[\d.]+" width="[\d.]+" height="([\d.]+)"/.exec(s.split('text--gray-20')[1])[1];
  ok(h >= 20, 'block height ' + h + ' of 40');
});
test('panel face (owner 2026-11-12): a plain fill on 4-bit light, no backlight lamps; none on 2-bit, in dark or 1-bit', () => {
  const f = (m, W, H) => { D.mode = m; const s = D.part({}, 'face', 0, W, H); D.mode = null; return s; };
  ok(/data-sw-fill/.test(f({ dark: false, bits: 4 }, 1200, 400)) && !/ellipse|<pattern|data-sw-backlight/.test(f({ dark: false, bits: 4 }, 1200, 400)), '4-bit light: plain fill only');
  ok(!/ellipse|<pattern/.test(f({ dark: false, bits: 2 }, 1200, 400)), '2-bit: no face (borderless: a single native band leaves grey corner pieces)');
  ok(!/ellipse/.test(f({ dark: true, bits: 4 }, 1200, 400)) && !/ellipse/.test(f({ dark: false, bits: 1 }, 1200, 400)), 'dark and 1-bit: none');
});
test('dial light: backlight in light mode (2-bit up), glow in dark (blur 4-bit, halo 2-bit, none 1-bit)', () => {
  const t = (m) => { D.mode = m; const s = D.dial({ now: 5, lo: 1, hi: 9, a: 0, b: 15, step: 5 }, 900, 380, false); D.mode = null; return s; };
  ok(!/data-sw-backlight/.test(t({ dark: false, bits: 4 })), 'light 4-bit: no backlight lamps (owner 2026-11-12)');
  ok(!/data-sw-fill/.test(t({ dark: false, bits: 4 })), 'the dial draws no fill of its own: the panel face does, edge to edge (owner 2026-11-12)'); ok(!/data-sw-backlight/.test(t({ dark: false, bits: 1 })), 'no backlight on 1-bit');
  ok(/data-sw-glow="4"[\s\S]*feGaussianBlur|feGaussianBlur[\s\S]*data-sw-glow="4"/.test(t({ dark: true, bits: 4 })), 'dark 4-bit blur glow');
  ok(/feMorphology/.test(t({ dark: true, bits: 2 })) && !/feGaussianBlur/.test(t({ dark: true, bits: 2 })), 'dark 2-bit halo, no blur');
  ok(!/data-sw-glow|data-sw-backlight/.test(t({ dark: true, bits: 1 })), '1-bit dark: nothing');
  ok(/<circle[^>]*\/><\/g><\/g><\/svg>$/.test(t({ dark: true, bits: 4 })), 'needle hub still last');
});
test('dark glow on the lit parts: blur halo on 4-bit, crisp halo on 2-bit, none in light mode or 1-bit (owner 2026-11-12)', () => {
  const SWv = { temp: '12', meters: [{ frac: 0.5 }], rain: { hours: [{ h: '14', wet: true }, { h: '15', wet: false }] }, sun: { phase: 0.3 } };
  const parts = (m) => { D.mode = m; D.src = 'x.svg'; const r = ['temp', 'meter', 'rain', 'moon', 'icon'].map((k) => [k, D.part(SWv, k, 0, 200, 60)]); D.mode = null; return r; };
  parts({ dark: true, bits: 4 }).forEach(([k, s]) => ok(/<g filter="url\(#swgl\d+\)" data-sw-glow="4">/.test(s) && /feGaussianBlur stdDeviation/.test(s) && /slope="0.75"/.test(s), k + ': dark 4-bit halo'));
  parts({ dark: true, bits: 2 }).forEach(([k, s]) => ok(/data-sw-glow="2"/.test(s) && /feMorphology/.test(s) && !/feGaussianBlur/.test(s), k + ': dark 2-bit crisp halo'));
  [{ dark: false, bits: 4 }, { dark: false, bits: 2 }, { dark: true, bits: 1 }, { dark: false, bits: 1 }].forEach((m) => parts(m).forEach(([k, s]) => ok(!/data-sw-glow|swgl/.test(s), k + ': no glow ' + JSON.stringify(m))));
  D.mode = { dark: true, bits: 4 }; const r = D.rain([{ h: '14', wet: true }], 120, 40); D.mode = null;
  ok(r.indexOf('data-sw-glow') < r.lastIndexOf('<rect'), 'halo under the lit cell, not over it');
  D.mode = { dark: true, bits: 4 }; ok(!/text--gray-40/.test(D.meter({ frac: 0.5 }, 200, 30, 10)), 'dark: lit meter cells in full ink, as live'); D.mode = null;
  ok((sh.match(/<img [^>]*data-sw-icon>/g) || []).length === 4, 'weather, rain and sun icons marked to glow');
});
test('moon glow outside the disk in dark mode, none in light or 1-bit (owner 2026-11-12)', () => {
  const at = (m) => { D.mode = m; const v = D.moon(0.3, 100); D.mode = null; return v; };
  const d = at({ dark: true, bits: 4 });
  ok(/<mask [^>]*>.*<circle cx="50" cy="50" r="2[7-9][\d.]*" fill="#000"\/><\/mask>/.test(d), 'mask cuts out the disk');
  ok(/<g mask="url\(#swmk\d+\)" data-sw-moonhalo><defs>.*<g filter="url\(#swgl\d+\)" data-sw-glow="4"><circle[^>]*\/><\/g><\/g>/.test(d), 'the halo is the whole disk, under the mask');
  ok(!/data-sw-glow[^>]*><path/.test(d), 'no halo on the lit part itself');
  [{ dark: false, bits: 4 }, { dark: true, bits: 1 }].forEach((m) => ok(!/swmk|swgl/.test(at(m)), 'no halo ' + JSON.stringify(m)));
});
test('days strip in narrow views: X half vertical 7 days without numbers, OG half vertical 5, portrait larger names and icons (owner 2026-11-12)', () => {
  const v3 = /elsif view == 3 %}([^\n]*)/.exec(sh)[1], v1 = /if view == 1 %}([^\n]*)/.exec(sh)[1];
  ok(/nd_md = 4 %}/.test(v3) && /nd_lg = 7 %}/.test(v3), 'half vertical: 4 days on md (owner 2026-11-12: taller rows), 7 on lg');
  ok(/num_cls = ' lg:hidden' %}/.test(v3), 'half vertical: low/high numbers on the OG (owner 2026-11-12), dropped on the X');
  ok(/bar_cls = 'col--span-7 lg:col--span-8' %}/.test(v3) && /name_cls = 'col--span-2' %}{% assign icon_cls = 'col--span-1 lg:col--span-2' %}{% assign pad_cls = 'col--span-3 lg:col--span-4' %}/.test(v3), 'bars keep at least half the strip, header pad matches name + icon');
  ok(/name_t = ' lg:portrait:title--xlarge' %}/.test(v1) && /icon_x = ' lg:portrait:h--\[7cqh\]' %}/.test(v1), 'portrait: names and icons at the live size');
  ok(/<span class="title title--base{{ name_t }} text--bold" data-sw-dname>{{ d.name }}/.test(sh) && /{{ icon_x }}" src="{{ d.icon }}"/.test(sh), 'row markup uses the per-view sizes');
});
test('OG full (md): no dials, 5-segment meters, 4 days; X (lg) keeps dials, 10 segments, 5 days', () => {
  ok(/<div class="hidden lg:block h--\[30cqh\]"><div class="flex flex--row/.test(sh), 'dials only on lg');
  ok(/lg:hidden" data-sw-part="meter" data-sw-n="5"/.test(sh) && /hidden lg:block[^"]*" data-sw-part="meter" data-sw-n="10"/.test(sh), 'meter copies per size');
  ok(/data-sw-row="day"/.test(sh) && !/forloop.index > 4 %}<div class="hidden lg:block">/.test(sh), 'every day row in the same full-width wrapper (no half-width fifth row)');
  ok(/{%- if d.today %}<span class="label label--inverted[^"]*" data-sw-today>/.test(sh), 'OG: today a lit lamp on the day name (owner 2026-11-12)');
  D.mode = { bits: 1 }; ok(/data-sw-st="e"><g><rect/.test(D.meter({ frac: 0 }, 200, 30, 5)), '1-bit: unlit cells drawn in full colour'); D.mode = null;
  const cells = (n) => (D.meter({ frac: 0 }, 200, 30, n).match(/<rect/g) || []).length;
  eq([cells(5), cells(10)], [5, 10]);
  D.mode = { bits: 2 }; ok(/text--gray-30/.test(D.meter({ frac: 0 }, 200, 30, 5)), '2-bit: unlit cells dark enough to show (native dark grey)'); D.mode = null;
});
test('rain unit: icon left of the grid on every size (owner 2026-11-12, later decision)', () => {
  const u = sh.indexOf('data-sw-unit="rain"'), end = sh.indexOf('data-sw-part="rain"', u);
  ok(u > 0 && /\{\{ ru_cls \}\}/.test(sh.slice(sh.lastIndexOf('<div', u), u)) && /assign ru_cls = 'flex--row lg:portrait:flex--col'/.test(sh), 'row on md and lg');
  ok(/{% if stk %}[^\n]*{% assign ru_cls = 'flex--col lg:flex--row' %}/.test(sh), 'narrow stacked md column: icon above the calendar (owner 2026-11-12)');
  ok(/<img class="image image--adaptive \{\{ ib_cls \}\}" src="\{\{ ui.rain.icon \}\}"/.test(sh.slice(u, end)) && /h--\[\{\{ cal_m \}\}cqh\] lg:h--\[\{\{ cal_l \}\}cqh\][^"]*" data-sw-part="rain"/.test(sh) && /capture ib_cls %\}aspect--1\/1 h--\[\{\{ ib_m \}\}cqh\] lg:h--\[\{\{ cal_l \}\}cqh\]/.test(sh), 'icon as tall as the grid on md and lg');
  ok(/assign ib_m = cal_m %}{% if stk and view != 3 %}{% assign ib_m = rc_m/.test(sh) && /{% if view == 3 %}[^\n]*{% assign ru_cls = 'flex--row' %}/.test(sh), 'stacked md: icon above, one row tall; OG half vertical: icon left at the calendar height (owner 2026-11-12)');
  ok(/<div class="\{\{ ib_cls \}\}" data-sw-part="moon">/.test(sh), 'moon box the same as the rain icon box');
  const T3 = (h) => D.rain(Array.from({ length: 12 }, (_, i) => ({ h: String(i), wet: false })), 300, h).match(/<text/g).length;
  eq([T3(150), T3(500)], [6, 9], 'short rain: 2 x 3; a narrow tall box: 3 x 3');
  eq(T3(300), 9, 'a box sized for 3 rows: 3 x 3');
  const R3 = (w, h, lp) => { D.lp = lp || 0; const n = D.rain(Array.from({ length: 12 }, (_, i) => ({ h: String(i), wet: false })), w, h, 3).match(/<text/g).length; D.lp = 0; return n; };
  eq(R3(300, 160), 9, 'long rain: 3 x 3 in a box that holds it');
  eq([R3(300, 120), R3(300, 160, 50)], [6, 6], 'long rain: 2 x 3 when 3 rows only fit too flat or below the label size (owner 2026-11-12)');
  ok(/data-sw-part="rain" data-sw-rows="{{ rr_m }},{{ rr }}"/.test(sh) && /{% if view == 4 or view == 2 %}{% assign rr_m = 2 %}/.test(sh), 'quadrant and half-horizontal md boxes sized for 2 rows; OG half vertical 3 when the rain is long (owner 2026-11-12)');
  const c = Array.from({ length: 12 }, (_, i) => ({ h: String(i), wet: i >= 2 && i <= 6 }));
  eq([T.rainRows(c), T.rainRows(c.map((q, i) => ({ h: q.h, wet: i >= 2 && i <= 5 })))], [3, 2], 'rows: 3 when the rain runs past the sixth hour');
});
test('sun/moon unit: moon left of the sun rows on every size, grey ink (owner 2026-11-12, later decision)', () => {
  const u = sh.indexOf('data-sw-unit="sun"'), rows = sh.indexOf('ui.sun.rise', u);
  ok(u > 0 && /\{\{ su_cls \}\} \{% if ui.rain %\}flex--left[^%]*\{% else %\}flex--center/.test(sh.slice(sh.lastIndexOf('<div', u), u)) && /assign su_cls = 'flex--row'/.test(sh) && !/assign su_cls = '[^']*portrait:flex--col/.test(sh), 'row on md and lg; centred when dry, on the rain icon\'s left edge when it rains');
  const m = sh.indexOf('data-sw-part="moon"', u); ok(m > u && m < rows, 'moon before the sun rows');
  ok(!/<img[^>]*ui.sun.moon/.test(sh), 'no moon icon image');
  eq(D.moon(null, 60), '');
});
// Lit area of a moon path: SVG arcs to polylines by the spec's endpoint-to-centre conversion, then the shoelace area.
function pathArea(d) {
  const n = d.match(/-?[\d.]+/g).map(Number), pts = [[n[0], n[1]]];
  for (let i = 2; i + 7 <= n.length; i += 7) {
    const [x1, y1] = pts[pts.length - 1], [rx, ry, , fa, fs, x2, y2] = n.slice(i, i + 7);
    if (rx < 1e-6) { pts.push([x2, y2]); continue; }
    const xp = (x1 - x2) / 2, yp = (y1 - y2) / 2, lam = (xp * xp) / (rx * rx) + (yp * yp) / (ry * ry), s2 = lam > 1 ? Math.sqrt(lam) : 1, Rx = rx * s2, Ry = ry * s2;
    let k = Math.sqrt(Math.max(0, (Rx * Rx * Ry * Ry - Rx * Rx * yp * yp - Ry * Ry * xp * xp) / (Rx * Rx * yp * yp + Ry * Ry * xp * xp))); if (fa === fs) k = -k;
    const cxp = k * Rx * yp / Ry, cyp = -k * Ry * xp / Rx, cx = cxp + (x1 + x2) / 2, cy = cyp + (y1 + y2) / 2;
    const ang = (ux, uy, vx, vy) => Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    const t1 = ang(1, 0, (xp - cxp) / Rx, (yp - cyp) / Ry); let dt = ang((xp - cxp) / Rx, (yp - cyp) / Ry, (-xp - cxp) / Rx, (-yp - cyp) / Ry);
    if (!fs && dt > 0) dt -= 2 * Math.PI; if (fs && dt < 0) dt += 2 * Math.PI;
    for (let j = 1; j <= 200; j++) { const t = t1 + dt * j / 200; pts.push([cx + Rx * Math.cos(t), cy + Ry * Math.sin(t)]); }
  }
  let A = 0, X = 0; pts.forEach((q, i) => { const r = pts[(i + 1) % pts.length]; A += q[0] * r[1] - r[0] * q[1]; X += q[0]; });
  return { area: Math.abs(A) / 2, mx: X / pts.length };
}
test('day names without full ICU (item 22): own weekday table, not Intl', () => {
  const real = Intl.DateTimeFormat;
  Intl.DateTimeFormat = function () { return new real('en', arguments[1]); };   // TRMNL's serverless Node: English only
  try {
    eq(T.dayNames(['2026-11-09', '2026-11-10', '2026-11-11', '2026-11-15'], 'nl'), ['MA', 'DI', 'WO', 'ZO'], 'nl');
    eq(T.dayNames(['2026-11-13'], 'de-AT'), ['FR'], 'de-AT by its base language');
    eq(T.dayNames(['2026-11-13'], 'en-GB'), ['FRI'], 'en');
  } finally { Intl.DateTimeFormat = real; }
});
test('meter cell states for today (owner 2026-11-13): active, reached earlier, expected later, empty; one peak outline', () => {
  const S = (m, n) => { const r = D.cellStates(m, n); return r.st.join('') + '|' + r.peak; };
  // now, past max, later max, peak (fractions of the scale) -> cell states and the peak cell
  const table = [
    [{ frac: 0.3, past: 0.6, later: 0.9, peak: 0.9 }, 10, 'aaapppllle|8'],
    [{ frac: 0.3, past: 0.9, later: 0.6, peak: 0.9 }, 10, 'aaappppppe|8'],    // later below the past max: no later cells
    [{ frac: 0.7, past: 0.2, later: 0.4, peak: 0.7 }, 10, 'aaaaaaaeee|6'],    // now is the max: the peak on an active cell
    [{ frac: 0.2, past: null, later: 0.5, peak: 0.5 }, 10, 'aallleeeee|4'],   // no past hours (first hour of the day)
    [{ frac: 0.2, past: 0.55, later: 0.35, peak: 0.87 }, 10, 'aappppeeee|8'], // WIND: the max gust past the speeds, on an empty cell
    [{ frac: 0.3, past: 0.55, later: 0.95, peak: 0.95 }, 5, 'aapll|4'],
    [{ frac: null, past: null, later: null, peak: null }, 5, 'eeeee|-1'],
  ];
  table.forEach(([m, n, want]) => eq(S(m, n), want, JSON.stringify(m) + ' on ' + n));
  const svg = D.meter({ frac: 0.3, past: 0.6, later: 0.9, peak: 0.9 }, 300, 30, 10), gsv = D.meter({ frac: 0.2, past: 0.4, later: 0.3, peak: 0.8 }, 300, 30, 10);
  eq([(svg.match(/data-sw-gust/g) || []).length, (gsv.match(/data-sw-gust/g) || []).length], [0, 1], 'peak outline only outside today\'s range (owner): none when the range already reaches it, one for a gust beyond it');
  eq([1, (svg.match(/data-sw-st="p"><g class="([^"]+)"/) || [])[1] === (svg.match(/data-sw-st="l"><g class="([^"]+)"/) || [])[1] && !/stroke-dasharray/.test(svg)], [1, true], 'one peak outline; earlier and later cells share one range grey (owner: now + today\'s range)');
});
test('moon drawn from the phase: lit fraction within 10 % for crescent, quarter, gibbous and full, light and dark, lit side right while waxing', () => {
  const H = 100, r = H * 0.27, disk = Math.PI * r * r;
  [0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9].forEach((p) => {
    const want = (1 - Math.cos(2 * Math.PI * p)) / 2;
    [false, true].forEach((dark) => {
      D.mode = { dark, bits: 4 }; const s = D.moon(p, H); D.mode = null;
      const d = /<path d="([^"]+)" data-sw-moon="lit"/.exec(s)[1], a = pathArea(d);
      ok(Math.abs(a.area / disk - want) <= 0.1, 'p ' + p + (dark ? ' dark' : ' light') + ': lit ' + (a.area / disk).toFixed(3) + ' want ' + want.toFixed(3));
      if (want < 0.99) ok(p < 0.5 ? a.mx > H / 2 : a.mx < H / 2, 'p ' + p + ': lit on the ' + (p < 0.5 ? 'right' : 'left'));
      ok(/<circle[^>]*fill="none"/.test(s) && !/text--gray-45"><circle[^>]*fill="none"/.test(s), 'limb outline in full ink, light and dark (Calm, owner)');
      ok(dark ? !/text--gray-45"><path/.test(s) : /text--gray-45"><path/.test(s), dark ? 'dark: lit part in full (light) ink' : 'light: lit part in grey ink');
    });
  });
  ok(!/<path/.test(D.moon(0, H)) && /<circle/.test(D.moon(0, H)), 'new moon: outline only');
  for (let d = 1; d <= 30; d++) { const t = '2026-11-' + String(d).padStart(2, '0') + 'T12:00', ic = T.moonIcon(t), p = T.moonPhase(t);
    if (ic === 'wi-moon-alt-full') ok(Math.abs(p - 0.5) < 0.03, t + ' full at ' + p); if (ic === 'wi-moon-alt-new') ok(p < 0.03 || p > 0.97, t + ' new at ' + p); }
  eq(T.moonPhase(null), null);
});
test('barometer trend over 3 h with +/-1 hPa thresholds; clothing cues for every rule and limit', () => {
  eq([T.pressTrend(1011, 1010), T.pressTrend(1010.9, 1010), T.pressTrend(1009, 1010), T.pressTrend(1009.1, 1010), T.pressTrend(1010, null), T.pressTrend(null, 1010)], ['rising', 'steady', 'falling', 'steady', null, null]);
  const C = (o, F) => T.cueFor(Object.assign({ rain: false, wind: null, gust: null, lo: null, hi: null, uv: null, day: true }, o), F).join('+');
  eq([C({ rain: true, lo: 15 }), C({ rain: true, lo: 15, wind: 80, gust: 120 }), C({ rain: true, lo: 1 })], ['sweater+umbrella', 'sweater+umbrella', 'parka+umbrella'], 'rain: always the umbrella extra, the top by felt temperature; no raincoat (owner)');
  eq([C({ lo: -2.1, hi: 25 }), C({ lo: -2, hi: 25 }), C({ lo: 2.9, hi: 25 }), C({ lo: 3, hi: 25 })], ['parka+mittens', 'parka', 'parka', 'tshirt'], 'parka under 3 from the coldest, mittens under -2 as an extra');
  eq([C({ lo: 28.3 }, true), C({ lo: 28.4 }, true), C({ lo: 37.3 }, true), C({ lo: 37.4 }, true)], ['parka+mittens', 'parka', 'parka', 'jacket'], 'Fahrenheit: -2 C = 28.4 F, 3 C = 37.4 F');
  eq([C({ lo: 5, hi: 15, uv: 6 }), C({ lo: 5, hi: 15, uv: 5.9 }), C({ lo: 5, hi: 15, uv: 8, day: false }), C({ lo: 1, uv: 9 })], ['sweater+sunglasses', 'sweater', 'sweater', 'parka+sunglasses'], 'sunglasses by day from UV 6, as an extra');
  eq([C({ hi: 11.9 }), C({ hi: 12 }), C({ hi: 17.9 }), C({ hi: 18 }), C({ hi: 53.5 }, true), C({ hi: 53.6 }, true), C({ hi: 64.3 }, true), C({ hi: 64.4 }, true)], ['jacket', 'sweater', 'sweater', 'tshirt', 'jacket', 'sweater', 'sweater', 'tshirt'], 'tops from the warmest: jacket under 12, sweater under 18, t-shirt; F 53.6 and 64.4');
  eq([C({ rain: true, lo: -5, uv: 7 }), C({ rain: true, wind: 40, lo: -5, uv: 7 })], ['parka+umbrella+mittens+sunglasses', 'parka+umbrella+mittens+sunglasses'], 'every extra in order: umbrella, mittens, sunglasses');
  eq([C({}), C({ uv: 8 }), C({ rain: true })], ['', 'sunglasses', 'umbrella'], 'no temperature: no top layer, extras still apply');
  const i = T.buildI18n('nl');
  eq([i.ours.p_steady, i.ours.p_rising, i.ours.p_falling], ['STABIEL', 'STIJGEND', 'DALEND']);
  eq(T.buildI18n('ja').ours.p_rising, 'RISING', 'missing language falls back to English');
  const f = fx('mixed');
  const M = SWModel.build(f, {}), calm = T.buildView(M, i, f.daily, null, 0.3, { pressAgo: 1015 }), none = T.buildView(M, i, f.daily, null, 0.3);
  eq([calm.cue, calm.baro.trend], [['parka', 'umbrella'], 'DALEND'], 'mixed has rain in the window, 1013.2 now against 1015');
  eq(none.baro.trend, null, 'no pressure 3 h ago: no trend');
});
test('past_hours=3: the past hours are cut so every hourly list starts at the current hour; the pressure 3 h ago is kept', () => {
  const f = fx('mixed'), p = JSON.parse(JSON.stringify(f)), H = p.hourly;
  H.pressure_msl = H.time.map((_, k) => 1013 - k);
  ['2026-11-08T03:00', '2026-11-08T04:00', '2026-11-08T05:00'].reverse().forEach((t, j) => Object.keys(H).forEach((k) => H[k].unshift(k === 'time' ? t : (k === 'pressure_msl' ? 1020 + j : H[k][0]))));
  const d = T.dropPast(p);
  eq(d.ago, 1022, 'pressure at 03:00');
  eq(d.weather.hourly.time[0], f.hourly.current_time || f.current.time);
  const a = SWModel.build(f, {}), b = SWModel.build(d.weather, {});
  eq(b.hours.map((q) => [q.h, q.t, q.p]), a.hours.map((q) => [q.h, q.t, q.p]), 'hours unchanged by the cut');
  eq(b.rain, a.rain, 'rain window unchanged');
  eq(T.dropPast(f).ago, null, 'no past hours: no trend');
  eq(T.dropPast(null).weather, null);
});
test('hours strip: 12 hours from now, stamps per time format, rain only on wet hours, one scale holding every hour', () => {
  const f = fx('mixed'), M = SWModel.build(f, {}), i = T.buildI18n('nl');
  const v = T.buildView(M, i, f.daily, null, 0.3, { hours: true }), d = T.buildView(M, i, f.daily, null, 0.3);
  ok(!('hours' in d) && !('hscale' in d), 'Days (default): no hours keys, the page stays as it was');
  eq(v.hours.length, 12);
  eq(v.hours.map((q) => q.hl), M.hours.filter((q, k) => k % 2 === 0).slice(0, 12).map((q) => q.hl), 'stamps every 2 hours from the (even) current hour (owner 2026-11-13)');
  const H = (h, p) => ({ h: h, hl: String(h).padStart(2, '0'), t: 5, p: p, wet: false, icon: 'cloudy', day: true }), hs13 = Array.from({ length: 25 }, (_, k) => H((13 + k) % 24, k === 2 ? 80 : 0));
  const s13 = T.hourStrip(hs13, String, '°', H(12, 0));
  eq(s13.hours.map((q) => q.hl).slice(0, 4), ['12', '14', '16', '18'], 'at 13:30 the slots are 12, 14, 16 (even hours; 12 from the hour before)');
  eq(s13.hours.map((q) => q.wet).slice(0, 3), [false, true, false], 'wet over the pair: 15:00 wet marks the 14 column');
  eq(T.hourStrip(hs13, String, '°', null).hours[0].hl, '13', 'no hour before: start at the current hour');
  eq(v.hours.map((q) => q.now), [true].concat(Array(11).fill(false)), 'only the current hour is now');
  const W1 = (q) => !!q && (q.p !== null ? q.p >= (q.wet ? 30 : 50) : q.wet); eq(v.hours.map((q) => q.wet), Array.from({ length: 12 }, (_, j) => W1(M.hours[2 * j]) || W1(M.hours[2 * j + 1])), 'wet as the rain window counts it, over each pair of hours');
  ok(v.hours.some((q) => q.wet) && v.hours.some((q) => !q.wet), 'mixed has wet and dry hours');
  ok(v.hours.every((q) => q.tV === null || (q.tV > v.hscale.a && q.tV <= v.hscale.b)), 'every hour above the floor, inside the scale');
  const dry = JSON.parse(JSON.stringify(f)); dry.hourly.precipitation_probability = dry.hourly.precipitation_probability.map(() => 0); dry.hourly.weather_code = dry.hourly.weather_code.map(() => 1);
  ok(T.buildView(SWModel.build(dry, {}), i, f.daily, null, 0.3, { hours: true }).hours.every((q) => !q.wet), 'dry: no rain stamps');
  eq(T.hourStrip([], String, '°'), null);
});
test('console cue window (owner 2026-11-13): garment now to +3 h, umbrella to 19:00 today (at least +3 h), sunglasses from today\'s max UV', () => {
  const C = (hourly, hours, now, uv) => T.cueFor(T.nowCueInput(hourly, hours, Object.assign({ temp: 15, feels: 15, day: true }, now || {}), uv === undefined ? 2 : uv), false).join('+');
  const H = (h0, n, wetAt) => Array.from({ length: n }, (_, k) => ({ h: (h0 + k) % 24, p: (h0 + k) % 24 === wetAt ? 80 : 0, wet: false }));
  eq(C({ apparent_temperature: [15, 15, 15, 15, -10] }, H(7, 25)), 'sweater', 'a cold hour at +4 h does not count');
  eq(C({ apparent_temperature: [15, 15, 15, 1, 15] }, H(7, 25)), 'parka', 'the coldest felt hour up to +3 h picks the parka');
  eq(C({ apparent_temperature: [15, 15, 15, -5] }, H(7, 25)), 'parka+mittens', 'mittens from the coldest felt hour in the window');
  eq(C({ apparent_temperature: [20, 20, 20, 20] }, H(7, 25, 15)), 'tshirt+umbrella', 'rain at 15:00 shows the umbrella at 07:30');
  eq(C({ apparent_temperature: [20, 20, 20, 20] }, H(7, 25, 20)), 'tshirt', 'rain at 20:00 is after 19:00: no umbrella in the morning');
  eq([C({ apparent_temperature: [20, 20, 20, 20] }, H(21, 25, 0)), C({ apparent_temperature: [20, 20, 20, 20] }, H(21, 25, 1))], ['tshirt+umbrella', 'tshirt'], 'evening (21:00): the umbrella looks to +3 h (00:00), not +4 h');
  eq(C({ apparent_temperature: [20, 20, 20, 20] }, H(7, 25), { day: true }, 7), 'tshirt+sunglasses', 'sunglasses from today\'s max UV in daytime');
  eq(C({ apparent_temperature: [20, 20, 20, 20] }, H(7, 25), { day: false }, 7), 'tshirt', 'no sunglasses at night');
  const fb = T.nowCueInput(null, [], { temp: 15, feels: 1, day: true }, 2); eq([fb.lo, fb.hi, fb.rain], [1, 1, null], 'no hourly data: the current felt temperature; rain falls back to the rain window');
});
test('meters: today\'s past and later max from today\'s hours, the peak (WIND: max gust) (owner 2026-11-13)', () => {
  const f = fx('mixed'), today = (k) => String(f.hourly.time[k]).slice(0, 10) === '2026-11-08';
  const g = JSON.parse(JSON.stringify(f)); g.current.time = '2026-11-08T13:00'; g.current.relative_humidity_2m = 30; g.current.wind_speed_10m = 12; g.current.wind_gusts_10m = 20; g.current.pressure_msl = 1010;
  g.hourly.relative_humidity_2m = f.hourly.time.map((t, k) => today(k) ? (k === 2 ? 55 : (k === 11 ? 95 : 40)) : 100);   // 08:00 55 (past), 17:00 95 (later), tomorrow 100
  g.hourly.wind_speed_10m = f.hourly.time.map((t, k) => today(k) ? (k === 1 ? 33 : (k === 12 ? 21 : 8)) : 50); g.hourly.wind_gusts_10m = f.hourly.time.map((t, k) => today(k) ? (k === 4 ? 52 : 15) : 99);
  g.hourly.pressure_msl = f.hourly.time.map((t, k) => today(k) ? (k === 3 ? 1031 : (k === 14 ? 1022 : 1005)) : 1049);
  const d = T.dropPast(g), raw = Object.assign({}, d.weather, { todayHourly: d.today });
  eq(d.weather.hourly.time[0], '2026-11-08T13:00', 'every other consumer still sees the hours from the current hour');
  const v = T.buildView(SWModel.build(raw, {}), T.buildI18n('nl'), g.daily), m = (k) => v.meters.find((q) => q.key === k) || {};
  const r2 = (x) => x === null || x === undefined ? x : Math.round(x * 1000) / 1000, P = (k) => [m(k).frac, m(k).past, m(k).later, m(k).peak].map(r2);
  eq(P('humidity'), [0.3, 0.55, 0.95, 0.95], 'humidity: now 30, earlier 55, later 95 (tomorrow\'s 100 not counted)');
  eq(P('wind'), [0.2, 0.55, 0.35, 0.867], 'wind: speeds earlier 33 and later 21, peak today\'s max gust 52 (tomorrow\'s 99 not counted)');
  eq(P('baro'), [0.5, 0.763, 0.65, 0.763], 'baro: earlier 1031, later 1022 on 970..1050; peak the earlier max');
  eq(D.cellStates(m('humidity'), 10).st.join(''), 'aaapppllll', 'humidity on 10 cells');
  const none = T.buildView(SWModel.build(f, {}), T.buildI18n('nl'), f.daily), h = none.meters.find((q) => q.key === 'humidity');
  eq([h.past, h.later], [null, null], 'no hourly humidity: no earlier or later cells');
  eq(v.meters.filter((q) => q.key === 'co2' || q.key === 'pollen').filter((q) => q.past !== null || q.later !== null || q.peak !== null).length, 0, 'CO2 and pollen: no marks');
});
test('per-day clothing cue: daytime hours 07:00 to 19:00 from the hourly data, daily values where the hours are missing', () => {
  const d = { time: ['2026-11-08', '2026-11-09'], temperature_2m_min: [0, 8], temperature_2m_max: [10, 15], apparent_temperature_min: [-5, 6], apparent_temperature_max: [8, 14], precipitation_probability_max: [90, 10], uv_index_max: [1, 7] };
  const ht = [], at = [], pp = [];
  for (let h = 0; h < 24; h++) { ht.push('2026-11-08T' + String(h).padStart(2, '0') + ':00'); at.push(h < 7 || h > 19 ? -9 : (h === 7 ? 4 : 13)); pp.push(h === 20 ? 99 : 20); }
  const H = { time: ht, apparent_temperature: at, precipitation_probability: pp };
  const a = T.dayCueInput(H, d, 0);
  eq([a.lo, a.hi, a.rain, a.uv], [4, 13, false, 1], 'only 07..19: the night cold and the 20:00 rain do not count');
  eq(T.cueFor(a, false), ['sweater']);
  const at7 = at.slice(); at7[19] = 2.5; eq(T.dayCueInput(Object.assign({}, H, { apparent_temperature: at7 }), d, 0).lo, 2.5, '19:00 is in the window');
  const b = T.dayCueInput(H, d, 1);
  eq([b.lo, b.hi, b.rain, b.uv], [6, 14, false, 7], 'no hours for the day: daily fields');
  eq(T.cueFor(b, false), ['sweater', 'sunglasses']);
  const c = T.dayCueInput(null, { time: ['2026-11-08'], temperature_2m_min: [1], temperature_2m_max: [9], precipitation_probability_max: [60] }, 0);
  eq([c.lo, c.hi, c.rain, T.cueFor(c, false)], [1, 9, true, ['parka', 'umbrella']], 'no felt fields: air temperature; rain from the daily value');
  const f = fx('mixed'), M = SWModel.build(f, {}), i = T.buildI18n('nl');
  const v = T.buildView(M, i, f.daily, null, 0.3, { hourly: f.hourly });
  ok(v.days.every((q) => Array.isArray(q.cue) && q.cue.length >= 1 && q.cue.length <= 3), 'top and up to two extras on every day');
  eq(v.days.map((q) => q.cue), v.days.map((q, k) => T.cueFor(T.dayCueInput(f.hourly, f.daily, k), false).slice(0, 3)), 'days: the list capped at 3');
});
test('days axis (owner bug): from the values as shown (rounded, -0 as 0) and only the days a view shows; the current temperature counts', () => {
  const f = JSON.parse(JSON.stringify(fx('mixed'))), D = f.daily;
  D.temperature_2m_min = D.temperature_2m_min.map((v, k) => k < 5 ? -0.4 : (k === 5 ? -3 : 4)); D.temperature_2m_max = D.temperature_2m_max.map(() => 8);
  f.current.temperature_2m = 1.6;
  const v = T.buildView(SWModel.build(f, {}), T.buildI18n('nl'), f.daily, null, 0.3, {});
  eq(v.days.slice(0, 5).map((d) => d.lo), ['0°', '0°', '0°', '0°', '0°'], 'lows -0.4 show as 0');
  ok(v.scales && v.scales[5], 'a scale per shown row count');
  eq([v.scales[5].a, v.scales[6].a], [0, -5], '5 rows: the hidden 6th day at -3 does not widen the axis; 6 rows: it does');
  f.current.temperature_2m = -1; eq(T.buildView(SWModel.build(f, {}), T.buildI18n('nl'), f.daily, null, 0.3, {}).scales[5].a, -5, 'the current temperature still counts');
});
async function sensorSettingsTests() {
  const originalFetch = global.fetch;
  global.fetch = async (url) => ({ ok: true, json: async () => url.includes('air-quality') ? {} : fx('mixed') });
  const sensor = { device_1: { temperature: [{ '2026-11-08 05:30:00 UTC': 21.6 }], humidity: [{ '2026-11-08 05:30:00 UTC': 48 }], carbon_dioxide: [{ '2026-11-08 05:30:00 UTC': 1600 }], pressure: [{ '2026-11-08 05:30:00 UTC': 1010 }] } };
  const run = (values, nested = false, readings = sensor) => T.run({ sensor_readings: nested ? undefined : readings, trmnl: { user: { locale: 'nl' }, sensor_readings: nested ? readings : undefined, plugin_settings: { custom_fields_values: values } } });
  async function check(name, fn) {
    try { await fn(); passed++; } catch (e) { failed++; console.log('FAIL ' + name + ': ' + e.message); }
  }
  try {
    await check('sensor_show: hide removes every sensor part, show and default keep them', async () => {
      const baseline = await run({}, false, null);
      for (const nested of [false, true]) {
        for (const values of [{}, { sensor_show: 'show' }]) {
          const v = (await run(values, nested)).ui;
          eq([v.inn.temp, v.inn.out, v.inn.in, v.tdial.twin, v.meters.some((m) => m.key === 'co2')], ['21.6', 'BUITEN', 'BINNEN', 21.6, true]);
        }
        const hidden = await run({ sensor_show: 'hide', sensor_co2: 'show' }, nested);
        eq(hidden.ui, baseline.ui, 'hide matches the complete no-sensor view');
        eq(hidden.model.inn, baseline.model.inn, 'hide removes all model readings');
      }
    });
    await check('sensor_co2: hide removes only CO2, show and default keep it', async () => {
      const shown = await run({ sensor_co2: 'show' });
      eq(shown.ui, (await run({})).ui, 'show is the default');
      ok(shown.ui.meters.some((m) => m.key === 'co2'), 'show keeps CO2');
      const hidden = await run({ sensor_co2: 'hide' }, true);
      ok(!hidden.ui.meters.some((m) => m.key === 'co2'), 'hide removes CO2');
      eq(hidden.ui.inn, shown.ui.inn, 'indoor readout unchanged');
      eq(hidden.ui.tdial, shown.ui.tdial, 'twin needle unchanged');
      eq(hidden.model.inn, Object.assign({}, shown.model.inn, { co2: null }), 'other readings unchanged');
    });
  } finally { global.fetch = originalFetch; }
}
sensorSettingsTests().then(() => {
  console.log(passed + ' passed, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
});
test('2-bit active cells are the native dark grey, not black; 4-bit gray-20 (owner 2026-11-13)', () => {
  const f = (m) => { D.mode = m; const s = D.day({ loV: 2, hiV: 6 }, { a: -5, b: 15, major: 5, now: 1.6 }, 800, 40); D.mode = null; return s; };
  ok(/gray-30/.test(f({ dark: false, bits: 2 })) && !/<g class="text--black/.test(f({ dark: false, bits: 2 }).split('data-sw-hl')[0].replace(/text--black[^>]*><line/g, '')), '2-bit day blocks gray-30');
  ok(/text--gray-20/.test(f({ dark: false, bits: 4 })), '4-bit day blocks gray-20');
});
