// Readable source of the outfit icon in plugin/src/shared.liquid (owner 2026-11-13). The page carries it minified:
//   (echo 'var outfit = (function () {'; cat tools/outfit.src.js; echo 'return outfit; })();') | esbuild --minify --target=es2020
// Outfit icon (owner 2026-11-13): composed clothes round the neck line on a 48 box. outfit(keys, bg, small, px) -> inner svg.
var OSW = 1.8, OCL = 1.5, OF = (v) => +v.toFixed(2), OP = (x, y) => OF(x) + ' ' + OF(y), OW = (w) => "stroke-width='" + w + "'";
function ohalf(o, y0, y1) { var m = 0; for (var i = 1; i < o.length; i++) for (var k = 0; k <= 20; k++) { var y = o[i - 1][1] + (o[i][1] - o[i - 1][1]) * k / 20; if (y >= y0 && y <= y1) m = Math.max(m, o[i - 1][0] + (o[i][0] - o[i - 1][0]) * k / 20); } return m; }
function ogarm(t, bg, sm, pl) {
var nr = (y) => 'C' + OP(2.4, y + 1.7) + ' ' + OP(1.3, y + 2.3) + ' ' + OP(0, y + 2.3) + 'C' + OP(-1.3, y + 2.3) + ' ' + OP(-2.4, y + 1.7) + ' ' + OP(-3.2, y);
var sy = (a) => a.map((p) => OP(p[0], p[1])).concat(a.slice().reverse().map((p) => OP(-p[0], p[1])));
if (t === 'tshirt') { var R = [[3.2, 0], [9.2, 3], [7.3, 6.9], [5.5, 5.9], [5.5, 13.5]]; return { d: "<path d='M" + sy(R).reverse().join('L') + nr(0) + "Z' fill='" + bg + "'/>", top: 0, neck: 0, hem: 13.5, half: 9.2, body: 5.5, outline: R }; }
if (t === 'parka') {
var y = 3, cy = y + 9.6, h = y + 14.5, sc = [-3.6, -1.8, 0, 1.8, 3.6];
var d = "<path d='M" + OP(-4.4, y + 2.4) + 'L' + OP(-7.8, y + 3.4) + 'L' + OP(-10.8, cy) + 'H-8.2L' + OP(-5.9, y + 6.4) + 'V' + h + 'H5.9V' + (y + 6.4) + 'L8.2 ' + cy + 'H10.8L' + OP(7.8, y + 3.4) + 'L' + OP(4.4, y + 2.4) + "Z' fill='" + bg + "'/>";
d += "<path d='M" + OP(-4.4, y + 2.4) + 'L' + OP(-3.6, y) + (sm ? 'L' + OP(3.6, y) : sc.slice(1).map((x, i) => 'Q' + OP((sc[i] + x) / 2, y - 1.1) + ' ' + OP(x, y)).join('')) + 'L' + OP(4.4, y + 2.4) + "Z' fill='" + bg + "'/>" + (pl ? '' : "<path d='M" + OP(0, y + 2.4) + 'V' + h + "'/>");
if (!sm) d += "<path d='" + (pl ? '' : 'M' + OP(-4.6, y + 9.4) + 'H-2M2 ' + OF(y + 9.4) + 'H4.6') + 'M' + OP(-10.3, cy - 1.5) + 'H-8M8 ' + OF(cy - 1.5) + "H10.3' " + OW(1.2) + '/>';
return { d, top: y - .55, neck: y + 1.2, hem: h, half: 10.8, body: 5.9, outline: [[3.6, y - .6], [4.4, y + 2.4], [7.8, y + 3.4], [10.8, cy], [8.2, cy], [5.9, y + 6.4], [5.9, h]] }; }
var cy = 11.5, h = 15, B = (n) => "<path d='M" + OP(-3.2, 0) + 'L' + OP(-7.2, 1.5) + 'L' + OP(-10.6, cy) + 'H-8.2L' + OP(-5.5, 5) + 'V' + h + 'H5.5V5L8.2 ' + cy + 'H10.6L' + OP(7.2, 1.5) + 'L' + OP(3.2, 0) + n + "Z' fill='" + bg + "'/>", d;
if (t === 'sweater') { d = B(nr(0)); if (!sm) d += "<path d='" + (pl ? '' : 'M' + OP(-5.4, h - 1.6) + 'H5.4') + 'M' + OP(-10.4, cy - 1.5) + 'H-8.1M8.1 ' + OF(cy - 1.5) + 'H10.4' + (pl ? '' : 'M' + OP(-2.1, .3) + 'Q' + OP(0, 2.5) + ' ' + OP(2.1, .3)) + "' " + OW(1.2) + '/>'; }
else { d = B('L' + OP(0, 5)) + (pl ? '' : "<path d='M0 5V" + h + "'/>") + "<path d='M" + OP(-3.2, 0) + 'V3.4L' + OP(-1.3, 2.8) + 'M' + OP(3.2, 0) + 'V3.4L' + OP(1.3, 2.8) + "'/>"; if (!sm && !pl) d += "<path d='M" + OP(-4.3, 10.5) + 'h2.2M' + OP(2.1, 10.5) + 'h2.2' + "' " + OW(1.3) + '/>'; }
return { d, top: 0, neck: 0, hem: h, half: 10.6, body: 5.5, outline: [[3.2, 0], [7.2, 1.5], [10.6, cy], [8.2, cy], [5.5, 5], [5.5, h]] };
}
function olay(ks, bg, sm, s) {
var k = new Set(ks), t = ['parka', 'jacket', 'sweater', 'tshirt'].find((x) => k.has(x)) || 'tshirt', g = (OCL + OSW) / s + .05, G = ogarm(t, bg, sm, k.has('scarf')), P = [], bb = [-G.half, G.top, G.half, G.hem];
var add = (n, d, b) => { P.push("<g data-sw-item='" + n + "'>" + d + '</g>'); bb[0] = Math.min(bb[0], b[0]); bb[1] = Math.min(bb[1], b[1]); bb[2] = Math.max(bb[2], b[2]); bb[3] = Math.max(bb[3], b[3]); }, tr = (y, d) => "<g transform='translate(0 " + OF(y) + ")'>" + d + '</g>';
add('top', G.d, bb.slice());
var y = G.top - g;
var low = G.hem, right = G.half;
if (k.has('umbrella')) {
var R = 4.6, q = R / 2, by = G.top + 1.2, x = Math.max(ohalf(G.outline, by - 3.6 - g, by + g) + g * 1.2 + R, ohalf(G.outline, by, G.hem) + g + 1.3), en = Math.max(G.hem, low) - 1.4, sc = (i) => 'Q' + OP(x + R - q * i - q / 2, by - 1.2) + ' ' + OP(x + R - q * (i + 1), by);
add('umbrella', "<path d='M" + OP(x - R, by) + 'A' + R + ' 3.4 0 0 1 ' + OP(x + R, by) + [0, 1, 2, 3].map(sc).join('') + "Z' fill='" + bg + "'/><path d='M" + OP(x, by - 3.4) + 'v-1.1M' + OP(x, by) + 'V' + OF(en) + "a1.4 1.4 0 0 1 -2.8 0'/>", [x - R, by - 4.5, x + R, en + 1.4]);
}
return { P, bb, gh: G.hem - G.top };
}
function ofit(ks, sm, ar) { var s = 1, L, h, w; for (var i = 0; i < 12; i++) { L = olay(ks, '#fff', sm, s); w = L.bb[2] - L.bb[0]; h = L.bb[3] - L.bb[1]; s = Math.min((47.4 - OSW) / h, (47.4 * ar - OSW) / w); } return s; }
// One scale, one spot (owner 2026-11-13): the box is 48 high and 48*ar wide. The scale is the smallest fit of the four garments drawn with the umbrella (the reserve is only as big as that item),
// the garments sit on one axis and one top line (parka as the reference), so a column of cues lines up; extras fill their places.
function outfit(ks, bg, sm, ar) {
var t = ['parka', 'jacket', 'sweater', 'tshirt'].find((x) => ks.indexOf(x) >= 0) || 'tshirt', RT = (u) => [u, 'umbrella'];
var s = Math.min.apply(null, ['parka', 'jacket', 'sweater', 'tshirt'].map((u) => ofit(RT(u), sm, ar))), M = olay(RT('parka'), '#fff', sm, s), L = olay(ks, bg, sm, s);
var tp = ogarm('parka', '#fff', sm, false).top, tt = ogarm(t, '#fff', sm, false).top;
return "<g transform='translate(" + OF(24 * ar - s * (M.bb[0] + M.bb[2]) / 2) + ' ' + OF(24 - s * (M.bb[1] + M.bb[3]) / 2 + s * (tp - tt)) + ') scale(' + +s.toFixed(4) + ")' fill='none' stroke='currentColor' stroke-width='" + OF(OSW / s) + "' stroke-linecap='round' stroke-linejoin='round'>" + L.P.join('').replace(/stroke-width='([\d.]+)'/g, (_, v) => "stroke-width='" + OF(v / s) + "'") + '</g>';
}
