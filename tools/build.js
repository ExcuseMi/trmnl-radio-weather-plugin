// Build: source/shared.liquid (readable, all comments) -> plugin/src/shared.liquid (what trmnlp pushes).
// Strips Liquid comments, minifies the page script (terser; SW and SWDraw keep their names), nothing else changes.
// Usage: node tools/build.js [outFile]   (default plugin/src/shared.liquid)
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');

async function build(src) {
  const { minify } = require('terser');
  let s = src.replace(/\{%-?\s*comment\s*-?%\}[\s\S]*?\{%-?\s*endcomment\s*-?%\}/g, '');
  const a = s.indexOf('<script'), b = s.indexOf('</script>');
  if (a < 0 || b < a) throw new Error('page script not found in shared.liquid');
  const open = s.slice(a, s.indexOf('>', a) + 1), start = a + open.length;
  let js = s.slice(start, b);
  const lq = [];
  js = js.replace(/\{\{[^}]*\}\}|\{%[^%]*%\}/g, (m) => { lq.push(m); return '__LQ' + (lq.length - 1) + '__'; });
  const r = await minify(js, {
    ecma: 2020, compress: { passes: 3, toplevel: true, pure_getters: true, unsafe_arrows: true },
    mangle: { toplevel: true, reserved: ['SW', 'SWDraw'] },
    format: { comments: /==== (DRAW|I18N)/, max_line_len: false },
  });
  if (r.error) throw r.error;
  let out = r.code.replace(/__LQ(\d+)__/g, (_, i) => lq[+i]);
  if ((out.match(/__LQ/g) || []).length) throw new Error('Liquid placeholder lost');
  return s.slice(0, start) + '\n' + out + '\n' + s.slice(b);
}
module.exports = { build };
if (require.main === module) {
  const out = process.argv[2] || path.join(ROOT, 'plugin/src/shared.liquid');
  build(fs.readFileSync(path.join(ROOT, 'source/shared.liquid'), 'utf8')).then((t) => {
    fs.writeFileSync(out, t); console.log(out + ': ' + Buffer.byteLength(t) + ' bytes');
  }, (e) => { console.error(e); process.exit(1); });
}
