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
function obeanie(bg, sm) { return { d: "<path d='M" + OP(-5.2, -2.2) + 'C' + OP(-5.4, -7.6) + ' ' + OP(5.4, -7.6) + ' ' + OP(5.2, -2.2) + "' fill='" + bg + "'/><rect x='-6.2' y='-2.6' width='12.4' height='2.6' rx='1' fill='" + bg + "'/><circle cx='0' cy='" + (sm ? -7.25 : -7.15) + "' r='" + (sm ? 1.3 : 1.05) + "' fill='currentColor' " + OW(1) + '/>' + (sm ? '' : "<path d='M-3.4 -2.1v1.6M-1.1 -2.1v1.6M1.1 -2.1v1.6M3.4 -2.1v1.6' " + OW(1) + '/>'), top: sm ? -8.55 : -8.2, half: 6.2 }; }
function oglass(bg, sm) { var y = -2.6, ln = (x) => 'M' + OP(x, y) + 'H' + OF(x + 5) + 'L' + OP(x + 4.6, y + 1.5) + 'A1.2 1.2 0 0 1 ' + OP(x + 3.4, y + 2.6) + 'H' + OF(x + 1.6) + 'A1.2 1.2 0 0 1 ' + OP(x + .4, y + 1.5) + 'Z';
return { d: "<path d='" + ln(-6) + ln(1) + "' fill='currentColor'/><path d='M" + OP(-1, y) + 'H1M' + OP(-6, y) + 'L' + OP(-7.3, y + .5) + 'M' + OP(6, y) + 'L' + OP(7.3, y + .5) + "'/>" + (sm ? '' : "<path d='M" + OP(-4.6, y + 1.5) + 'L' + OP(-3.6, y + .6) + 'M' + OP(2.4, y + 1.5) + 'L' + OP(3.4, y + .6) + "' stroke='" + bg + "' " + OW(.7) + '/>'), top: y, half: 7.3 }; }
// scarf over the collar: loop, a back tail under it, the front tail crossing over to hang on the left
function oscarf(G, bg, sm) {
var y0 = G.neck, w = 3.3, e1 = sm ? y0 + 9.5 : G.hem - 2.8, e2 = e1 - (sm ? 1.6 : 2.2), fl = sm ? 'currentColor' : bg, so = .95 * OSW / 1.8;
var ed = (x) => { var t = (x + 5.5) / 11; return y0 - 1.3 + 7.8 * t * (1 - t); };
var loop = "<path d='M" + OP(-5.5, y0 - 1.3) + 'Q' + OP(0, y0 + 2.6) + ' ' + OP(5.5, y0 - 1.3) + 'A1.5 1.5 0 0 1 ' + OP(5.7, y0 + 1.7) + 'Q' + OP(0, y0 + 7.4) + ' ' + OP(-5.7, y0 + 1.7) + 'A1.5 1.5 0 0 1 ' + OP(-5.5, y0 - 1.3) + "Z' fill='" + fl + "'/>";
var bx = .3, back = "<path d='M" + OP(bx, y0 + 3) + 'V' + OF(e2) + 'H' + OF(bx + w) + 'V' + OF(y0 + 3) + "Z' fill='" + fl + "'/>";
var xl = -4.6, xr = xl + w, yb = y0 + 6.6, sd = 'M' + OP(.2, ed(.2) + so) + 'Q' + OP(xl + .2, y0 + 1.6) + ' ' + OP(xl, yb) + 'V' + OF(e1) + 'H' + OF(xr) + 'V' + OF(yb) + 'Q' + OP(xr + .5, y0 + 2.4) + ' ' + OP(3.5, ed(3.5) + so);
var d = back + loop + "<path d='" + sd + "Z' fill='" + fl + "' stroke='none'/>" + (sm ? "<path d='" + sd + "Z' fill='none' stroke='" + bg + "' " + OW(.9) + '/>' : "<path d='" + sd + "'/>");
if (!sm) { var m = 'M' + OP(xl, e1 - 2.2) + 'H' + OF(xr) + 'M' + OP(bx, e2 - 1.8) + 'H' + OF(bx + w); d += "<path d='" + m + "' " + OW(1.1) + '/>'; }
return { d, top: y0 - 2.2, endY: Math.max(e1, e2), left: -7.2 };
}
function olay(ks, bg, sm, s) {
var k = new Set(ks), t = ['parka', 'jacket', 'sweater', 'tshirt'].find((x) => k.has(x)) || 'tshirt', g = (OCL + OSW) / s + .05, G = ogarm(t, bg, sm, k.has('scarf')), P = [], bb = [-G.half, G.top, G.half, G.hem];
var add = (n, d, b) => { P.push("<g data-sw-item='" + n + "'>" + d + '</g>'); bb[0] = Math.min(bb[0], b[0]); bb[1] = Math.min(bb[1], b[1]); bb[2] = Math.max(bb[2], b[2]); bb[3] = Math.max(bb[3], b[3]); }, tr = (y, d) => "<g transform='translate(0 " + OF(y) + ")'>" + d + '</g>';
add('top', G.d, bb.slice());
var y = G.top - g;
if (k.has('scarf')) { var S = oscarf(G, bg, sm); add('scarf', S.d, [S.left, S.top, -S.left, S.endY]); y = Math.min(y, S.top - g); }
if (k.has('sunglasses')) { var q = oglass(bg, sm); add('glasses', tr(y, q.d), [-q.half, y + q.top, q.half, y]); y += q.top - g; }
if (k.has('beanie')) { var b = obeanie(bg, sm); add('beanie', tr(y, b.d), [-b.half, y + b.top, b.half, y]); }
var low = G.hem, sh = k.has('shorts') && t === 'tshirt', right = G.half;
if (sh) { var y0 = G.hem + g; add('shorts', "<path d='M" + OP(-5.3, y0) + 'L' + OP(-5.7, y0 + 4.8) + 'H-1L' + OP(0, y0 + 2) + 'L' + OP(1, y0 + 4.8) + 'H5.7L' + OP(5.3, y0) + "Z' fill='" + bg + "'/>", [-5.7, y0, 5.7, y0 + 4.8]); low = y0 + 4.8; }
if (k.has('umbrella')) {
var R = 6.7, q = R / 2, by = G.top + 1.2, x = Math.max(right + g, ohalf(G.outline, by - 6 - g, by + g) + g * 1.2 + R), en = Math.max(G.hem, low) - 1.4, sc = (i) => 'Q' + OP(x + R - q * i - q / 2, by - 1.2) + ' ' + OP(x + R - q * (i + 1), by);
add('umbrella', "<path d='M" + OP(x - R, by) + 'A' + R + ' 4.6 0 0 1 ' + OP(x + R, by) + [0, 1, 2, 3].map(sc).join('') + "Z' fill='" + bg + "'/><path d='M" + OP(x, by - 4.6) + 'v-1.1M' + OP(x, by) + 'V' + OF(en) + "a1.4 1.4 0 0 1 -2.8 0'/>", [x - R, by - 5.7, x + R, en + 1.4]);
}
return { P, bb, gh: G.hem - G.top };
}
function ofit(ks, sm) { var s = 1, L, h, w; for (var i = 0; i < 12; i++) { L = olay(ks, '#fff', sm, s); w = L.bb[2] - L.bb[0]; h = L.bb[3] - L.bb[1]; s = Math.min((.92 * 48 - OSW) / h, (.94 * 48 - OSW) / w); } return s; }
// One scale and one spot per box size (owner 2026-11-13): the garment is drawn as in the largest outfit of its type (garment, beanie, glasses, umbrella), extras fill their places.
function outfit(ks, bg, sm) {
var t = ['parka', 'jacket', 'sweater', 'tshirt'].find((x) => ks.indexOf(x) >= 0) || 'tshirt', R = [t, 'beanie', 'umbrella', 'sunglasses'].concat(ks.filter((x) => x == 'scarf' || x == 'shorts'));
var s = ofit(R, sm), M = olay(R, '#fff', sm, s), L = olay(ks, bg, sm, s);
return "<g transform='translate(" + OF(24 - s * (M.bb[0] + M.bb[2]) / 2) + ' ' + OF(24 - s * (M.bb[1] + M.bb[3]) / 2) + ') scale(' + +s.toFixed(4) + ")' fill='none' stroke='currentColor' stroke-width='" + OF(OSW / s) + "' stroke-linecap='round' stroke-linejoin='round'>" + L.P.join('').replace(/stroke-width='([\d.]+)'/g, (_, v) => "stroke-width='" + OF(v / s) + "'") + '</g>';
}
