# frozen_string_literal: true
require 'json'
require 'fileutils'
# SW_CASES: JSON list of {name, view, device, fields, fixture, patch (json merged into current), mocks_extra, palette, orientation}
RSpec.describe 'renders' do
  cases = JSON.parse(ENV.fetch('SW_CASES'))
  out = ENV.fetch('SW_OUT')
  fx = File.join(TRMNLP::Testing.plugin_dir, 'tests', 'fixtures')
  cases.each do |c|
    it c['name'] do
      answer = JSON.parse(File.read(File.join(fx, "#{c['fixture'] || 'mixed'}.json")))
      (c['current'] || {}).each { |k, v| answer['current'][k] = v }
      (c['hourly'] || {}).each { |k, v| answer['hourly'][k] = v }
      (c['daily'] || {}).each { |k, v| answer['daily'][k] = v }
      if c['past_press']   # 3 past hours before the current one (past_hours=3), the first with this pressure
        h = answer['hourly']; h['pressure_msl'] ||= h['time'].map { answer.dig('current', 'pressure_msl') }; t0 = Time.utc(*h['time'][0].split(/[-T:]/).map(&:to_i))
        h.each_key { |k| next unless h[k].is_a?(Array); 3.times { |j| h[k].unshift(k == 'time' ? (t0 - 3600 * (j + 1)).strftime('%Y-%m-%dT%H:%M') : (k == 'pressure_msl' ? c['past_press'] : h[k][0])) } }
      end
      t = answer.dig('current', 'time')
      now = (Time.utc(*t.split(/[-T:]/).map(&:to_i)) - answer['utc_offset_seconds'].to_i + 600).iso8601
      mocks = { 'https://api.open-meteo.com/*' => { json: answer } }
      mocks['https://air-quality-api.open-meteo.com/*'] = { json: c['aq'] } if c['aq']
      fields = { 'lat_lon' => '52.52,13.41', 'unit' => 'celsius', 'days_shown' => 'auto', 'dial_span' => '24h', 'hide_title_bar' => 'false', 'language' => 'nl' }.merge(c['fields'] || {})
      opts = { view: c['view'] || 'full', device: c['device'] || 'v2', mocks:, custom_fields: fields, now:, wait_for: "document.querySelector('[data-sw-drawn],[data-sw-error]') !== null" }
      opts[:variables] = { 'trmnl' => { 'user' => { 'locale' => c['locale'] } } } if c['locale']
      opts[:variables] = (opts[:variables] || {}).merge(c['vars']) if c['vars']
      opts[:theme] = c['theme'] if c['theme']
      opts[:palette] = c['palette'] if c['palette']
      opts[:orientation] = c['orientation'].to_sym if c['orientation']
      opts[:dark_mode] = true if c['dark']
      opts[:text_scale] = c['text_scale'] if c['text_scale']
      s = trmnl.render(**opts)
      FileUtils.mkdir_p(out)
      FileUtils.cp(s.png_path, File.join(out, "#{c['name']}.png"))
      err = s.evaluate("(document.querySelector('[data-sw-error]')||{getAttribute:function(){return null}}).getAttribute('data-sw-error')")
      puts "ERR #{c['name']}: #{err}" if err
      expect(err).to be_nil
      geo = s.evaluate("(function(){var r=[].slice.call(document.querySelectorAll('[data-sw-part=\\'day\\']')).map(function(e){return e.getBoundingClientRect()}).filter(function(b){return b.width>0});return r.filter(function(b){return Math.abs(b.height-r[0].height)>0.5||Math.abs(b.left-r[0].left)>0.5||Math.abs(b.width-r[0].width)>0.5}).length+'/'+r.length})()")
      div = s.evaluate(%q{(function(){var out=[];document.querySelectorAll('[data-sw-div]').forEach(function(dv){var d=dv.getBoundingClientRect();if(!d.height)return;var row=dv.parentElement,u=row.querySelector('[data-sw-unit=\'\']'),t=row.querySelector('[data-sw-part=\'temp\'] svg'),p=row.querySelector('[data-sw-part=\'person\'] svg');function k(e){var r=e.getBoundingClientRect(),v=e.viewBox.baseVal,b=e.getBBox(),x=r.width/v.width,y=r.height/v.height;return{l:r.left+(b.x-v.x)*x,t:r.top+(b.y-v.y)*y,h:b.height*y}}var c=document.createElement('canvas').getContext('2d'),cs=getComputedStyle(u);c.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;var ub=u.getBoundingClientRect(),sc=(u.offsetWidth&&ub.width/u.offsetWidth)||1;var ur=ub.left+c.measureText(u.textContent.trim()).actualBoundingBoxRight*sc,pi=k(p),ti=k(t),mid=(d.left+d.right)/2;out.push([(mid-ur).toFixed(1),(pi.l-mid).toFixed(1),(d.height-ti.h).toFixed(1),(d.top-ti.t).toFixed(1),sc.toFixed(3),ur.toFixed(1),pi.l.toFixed(1),d.left.toFixed(1),d.right.toFixed(1)].join(','))});return out.join(' ')})()})
      puts "DIV #{c['name']}: gapL,gapR,dH,dTop #{div}"
      div.split.each { |q| a = q.split(',').map(&:to_f); expect((a[0] - a[1]).abs).to be <= 1.5; expect(a[2].abs).to be <= 1.5; expect(a[3].abs).to be <= 1.5 }
      clip = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part]:not([data-sw-part="face"]), [data-sw-part]:not([data-sw-part="face"]) > svg, [data-sw-unit] img, [data-sw-unit] span').forEach(function(e){var b=e.getBoundingClientRect();if(!b.width||!b.height)return;var ci=e.closest('[data-sw-condicon]'),ik=ci&&(ci.querySelector('[data-sw-ink]')||{getAttribute:function(){return null}}).getAttribute('data-sw-ink');if(ik){var iy=+ik.split(',')[0],ih=+ik.split(',')[1]||1;b={left:b.left,right:b.right,top:b.top+iy*b.height,bottom:b.top+(iy+ih)*b.height,width:b.width,height:ih*b.height};}var p=e.closest('[data-sw-panel]');if(!p)return;var q=p.getBoundingClientRect(),cs=getComputedStyle(p),k=q.width/(p.offsetWidth||q.width);q={left:q.left+parseFloat(cs.paddingLeft)*k,right:q.right-parseFloat(cs.paddingRight)*k,top:q.top+parseFloat(cs.paddingTop)*k,bottom:q.bottom-parseFloat(cs.paddingBottom)*k};var un=e.closest('[data-sw-unit]');if(un){var cb=un.parentElement.getBoundingClientRect();q={left:Math.max(q.left,cb.left),right:Math.min(q.right,cb.right),top:Math.max(q.top,cb.top),bottom:Math.min(q.bottom,cb.bottom)}}if(b.left<q.left-1||b.right>q.right+1||b.top<q.top-1||b.bottom>q.bottom+1)bad.push((e.getAttribute('data-sw-part')||e.tagName)+'@'+[b.left,b.right,b.top,b.bottom].map(function(v){return v.toFixed(0)}).join(':')+'/'+[q.left,q.right,q.top,q.bottom].map(function(v){return v.toFixed(0)}).join(':'))});return bad.join(' ')})()})
      puts "CLIP #{c['name']}: #{clip}" unless clip.empty?
      expect(clip).to eq('')
      # Rain unit (owner 2026-11-12): calendar cells square-ish and readable (numbers at least the meter label size),
      # rain icon and moon the same size on the same left edge. Dials: caption and value never under the hub or tail.
      ru = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null};
var lab=[].filter.call(document.querySelectorAll('[data-sw-mlabel]'),vis)[0],lp=lab?parseFloat(getComputedStyle(lab).fontSize):14;
[].forEach.call(document.querySelectorAll('[data-sw-part="rain"]'),function(d){var sv=d.querySelector('svg');if(!vis(d)||!sv)return;
var k=d.offsetHeight/+sv.getAttribute('height'),t=sv.querySelector('text'),fs=t?+t.getAttribute('font-size')*k:0,ch=d.offsetHeight/Math.ceil(sv.querySelectorAll('text').length/3),cw=d.offsetWidth/3;
if(fs<lp*0.95)bad.push('num '+fs.toFixed(1)+'<label '+lp+' cell '+cw.toFixed(0)+'x'+ch.toFixed(0));if(cw/ch<0.8||cw/ch>2)bad.push('cell '+cw.toFixed(0)+'x'+ch.toFixed(0));if(ch<lp*1.05)bad.push('cellH '+ch.toFixed(0));
var ic=[].filter.call(document.querySelectorAll('[data-sw-unit="rain"] img'),vis)[0],mo=[].filter.call(document.querySelectorAll('[data-sw-part="moon"]'),vis)[0];
if(ic&&mo){var a=ic.getBoundingClientRect(),b=mo.getBoundingClientRect();if(Math.abs(a.width-b.width)>2||Math.abs(a.height-b.height)>2||Math.abs(a.left-b.left)>2)bad.push('icon '+[a.left,a.width,a.height].map(Math.round)+' moon '+[b.left,b.width,b.height].map(Math.round));}});
document.querySelectorAll('[data-sw-hub]').forEach(function(h){var sv=h.ownerSVGElement,hb=vis(h);if(!hb)return;var k=hb.width/(2*+h.getAttribute('r')),R=+h.getAttribute('data-sw-hub')*k,cx=hb.left+hb.width/2,cy=hb.top+hb.height/2;
sv.closest('.relative').querySelectorAll('[data-sw-cap]').forEach(function(c){var b=vis(c);if(!b)return;var nx=Math.max(b.left,Math.min(cx,b.right)),ny=Math.max(b.top,Math.min(cy,b.bottom));if(Math.hypot(nx-cx,ny-cy)<R)bad.push('dial caption under hub: '+c.textContent.trim());});});
return bad.join('; ');})()})
      puts "RAINUNIT #{c['name']}: #{ru}" unless ru.empty?
      expect(ru).to eq('')
      # Bleed margin (owner 2026-11-12): every panel (borderless: its lit face) and the title bar keep the framework's
      # screen padding from the screen edge.
      edge = s.evaluate(%q{(function(){var sc=document.querySelector('.screen')||document.body,S=sc.getBoundingClientRect(),k=S.width/(sc.offsetWidth||S.width),bad=[],m=8*k;
document.querySelectorAll('[data-sw-panel], .title_bar').forEach(function(e){var b=e.getBoundingClientRect();if(!b.width||!b.height)return;
var d=Math.min(b.left-S.left,b.top-S.top,S.right-b.right,S.bottom-b.bottom);if(d<m)bad.push((e.className.baseVal||e.className||e.tagName).toString().slice(0,30)+' '+d.toFixed(1));});return bad.join('; ');})()})
      puts "EDGE #{c['name']}: #{edge}" unless edge.empty?
      expect(edge).to eq('')
      # Days strip (owner 2026-11-12): every grid line through the centre of its label's digits (one x mapping for the
      # header and the rows); the now line continuous from the header down through all rows.
      ds = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e.getBoundingClientRect();return b.width>0||b.height>0};
var sc=[].filter.call(document.querySelectorAll('[data-sw-part="scale"]'),vis)[0],d0=[].filter.call(document.querySelectorAll('[data-sw-part="day"]'),vis)[0];if(!sc||!d0)return '';
if(!SW.calm)sc.querySelectorAll('text[data-sw-tick]').forEach(function(t){var b=t.getBoundingClientRect(),r=d0.querySelector('rect[data-sw-tick="'+t.getAttribute('data-sw-tick')+'"]');if(!r){bad.push('no line '+t.textContent);return;}var q=r.getBoundingClientRect(),dx=(b.left+b.right)/2-(q.left+q.right)/2;if(Math.abs(dx)>1)bad.push('label '+t.textContent+' off '+dx.toFixed(1));});
var n=[].map.call(document.querySelectorAll('[data-sw-now]'),function(e){return e.getBoundingClientRect()}).filter(function(b){return b.height>0}).sort(function(a,b){return a.top-b.top});
for(var i=1;i<n.length;i++){if(n[i].top>n[i-1].bottom+0.5)bad.push('now gap '+(n[i].top-n[i-1].bottom).toFixed(1));if(Math.abs(n[i].left-n[0].left)>0.6)bad.push('now x');}
return bad.join('; ');})()})
      puts "DAYS #{c['name']}: #{ds}" unless ds.empty?
      expect(ds).to eq('')
      # 2-bit (owner 2026-11-12): every grey a native level, no dither tiles in the drawn parts.
      if c['palette'] == 'gray-4'
        pat = s.evaluate("document.querySelectorAll('svg pattern').length")
        puts "PATTERN #{c['name']}: #{pat}" unless pat.zero?
        expect(pat).to eq(0)
      end
      # Weather icon (owner 2026-11-12, revised): drawn ink 1.8 to 2.2 x the cap height (two lines: 0.9 to 1.1 x the block), ink centred on the label.
      ci = s.evaluate(%q{(function(){var bad=[],cx=document.createElement('canvas').getContext('2d');document.querySelectorAll('[data-sw-cond]').forEach(function(sp){var sb=sp.getBoundingClientRect();if(!sb.height)return;
var ic=sp.parentElement.firstElementChild,ib=ic.getBoundingClientRect(),k=sb.width/(sp.offsetWidth||sb.width),cs=getComputedStyle(sp);cx.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;var m=cx.measureText('H'),fa=m.fontBoundingBoxAscent*k,fd=m.fontBoundingBoxDescent*k,cap=m.actualBoundingBoxAscent*k;
var rg=document.createRange();rg.selectNodeContents(sp);var lr=[].filter.call(rg.getClientRects(),function(q){return q.width>0}),bl=function(q){return q.top+(q.height-fa-fd)/2+fa},t0=bl(lr[0])-cap,t1=bl(lr[lr.length-1]),n=lr.filter(function(q,i){return i===0||Math.abs(q.top-lr[i-1].top)>2}).length;
var ik=((ic.querySelector('[data-sw-ink]')||ic).getAttribute('data-sw-ink')||'0,1').split(',').map(Number),it=ib.top+ik[0]*ib.height,ih=ik[1]*ib.height,h=n>1?t1-t0+cap:cap,mid=n>1?(t0+t1)/2:t0+cap/2,q=ih/h;if(n>2)bad.push('label on '+n+' lines');if(n>1?(q<(ic.hasAttribute('data-sw-clamped')?0.9:1.05)||q>1.25):(q<(ic.hasAttribute('data-sw-clamped')?1.8:2.25)||q>2.75))bad.push('icon ink '+ih.toFixed(1)+' / '+(n>1?'block ':'cap ')+h.toFixed(1)+' = '+q.toFixed(2)+' ('+n+' lines)');if(Math.abs(it+ih/2-mid)>1.5)bad.push('icon ink centre off '+(it+ih/2-mid).toFixed(1));});return bad.join('; ');})()})
      puts "CONDICON #{c['name']}: #{ci}" unless ci.empty?
      expect(ci).to eq('')
      # Days strip (owner 2026-11-12, later): the strip always starts with today, the one highlighted row.
      hl = s.evaluate(%q{(function(){var r=[].filter.call(document.querySelectorAll('[data-sw-part="day"]'),function(e){return e.getBoundingClientRect().width>0});if(!r.length)return '';var h=r.map(function(e,i){return e.querySelector('[data-sw-hl]')?i:-1}).filter(function(i){return i>=0});var t0=SW.days[+r[0].getAttribute('data-sw-i')];if(!t0||!t0.today)return 'first row not today: '+(t0&&t0.name);var tl=[].filter.call(document.querySelectorAll('[data-sw-today]'),function(e){return e.getBoundingClientRect().width>0})[0];if(!tl||!/label--inverted/.test(tl.className))return 'today name not an inverted label';return h.length===1&&h[0]===0?'':'highlighted rows '+JSON.stringify(h);})()})
      puts "HL #{c['name']}: #{hl}" unless hl.empty?
      expect(hl).to eq('')
      # Days strip axis labels (owner 2026-11-12): at least the meter label size.
      ax = s.evaluate(%q{(function(){var vis=function(e){var b=e.getBoundingClientRect();return b.width>0&&b.height>0};var lab=[].filter.call(document.querySelectorAll('[data-sw-mlabel]'),vis)[0],sc=[].filter.call(document.querySelectorAll('[data-sw-part="scale"] svg'),vis)[0];if(!lab||!sc)return '';
var lp=parseFloat(getComputedStyle(lab).fontSize)*(lab.getBoundingClientRect().width/(lab.offsetWidth||1)),k=sc.getBoundingClientRect().height/+sc.getAttribute('height'),t=sc.querySelector('text[data-sw-tick]');if(!t)return 'no axis label';var fs=+t.getAttribute('font-size')*k;return fs<lp-0.5?'axis '+fs.toFixed(1)+' < label '+lp.toFixed(1):'';})()})
      puts "AXIS #{c['name']}: #{ax}" unless ax.empty?
      expect(ax).to eq('')
      # Colour (owner 2026-11-12, as live): red and yellow only on colour palettes and only on the warning parts
      # (lit lamps, meter warning zones, the days now line and pointer, lit rain cells); none on gray palettes.
      hu = s.evaluate(%q{(function(){var bad=[],n=0,ch=function(v){var m=/(\d+)\D+(\d+)\D+(\d+)/.exec(v||'');if(!m)return false;var a=[+m[1],+m[2],+m[3]];return Math.max.apply(0,a)-Math.min.apply(0,a)>60};
document.querySelectorAll('[data-sw-part] svg *').forEach(function(e){if(!e.getBoundingClientRect().width)return;var cs=getComputedStyle(e);if(!(ch(e.getAttribute('fill'))||ch(cs.fill)&&e.tagName!=='g'))return;n++;
var h=e.closest('[data-sw-hue]'),pt=e.closest('[data-sw-part]').getAttribute('data-sw-part');if(!h)bad.push('stray '+pt+' '+e.tagName);else if(['meter','day','scale','rain'].indexOf(pt)<0)bad.push('part '+pt);});
document.querySelectorAll('.view *').forEach(function(e){if(e.closest('svg'))return;var b=getComputedStyle(e).backgroundColor;if(!ch(b)||!e.getBoundingClientRect().width)return;n++;if(!e.matches('[data-sw-lamp][data-sw-hue]'))bad.push('html '+e.tagName+' '+String(e.className).slice(0,30));});
return n+(bad.length?' '+bad.slice(0,4).join('; '):'');})()})
      colour = (c['palette'] || '').start_with?('color-')
      puts "HUE #{c['name']}: #{hu}"
      expect(hu).to match(/\A\d+\z/)
      expect(hu.to_i.positive?).to eq(colour)
      # Days strip (owner 2026-11-12, item 17): a visible hairline over every shown day row; no edge line left of the graph.
      hr = s.evaluate(%q{(function(){var bad=[];if(SW.calm)return '';[].forEach.call(document.querySelectorAll('[data-sw-row="day"]'),function(r){if(!r.getBoundingClientRect().height)return;var h=r.querySelector('[data-sw-hair="row"]'),hb=h&&h.getBoundingClientRect();var ink=function(st){return st&&(st.backgroundImage!=='none'||!/rgba\(0, 0, 0, 0\)|transparent/.test(st.backgroundColor)||st.borderTopStyle!=='none'||st.borderBottomStyle!=='none'||st.boxShadow!=='none')};if(!h||!hb.width||hb.height<0.9||!(ink(getComputedStyle(h))||ink(getComputedStyle(h,'::before'))||ink(getComputedStyle(h,'::after'))))bad.push('row line '+(hb?hb.width.toFixed(0)+'x'+hb.height.toFixed(1):'none'));});[].forEach.call(document.querySelectorAll('[data-sw-hair="row"]'),function(h){var hb=h.getBoundingClientRect();if(!hb.width)return;var y=hb.top+hb.height/2;[].forEach.call(document.querySelectorAll('[data-sw-part="day"] [data-sw-now], [data-sw-part="scale"] [data-sw-now]'),function(n){var nb=n.getBoundingClientRect();if(!nb.width||nb.top>y||nb.bottom<y||nb.left<hb.left||nb.right>hb.right)return;if(document.elementFromPoint(nb.left+nb.width/2,y)===h)bad.push('row line over the now line');});});var v=document.querySelectorAll('[data-sw-hair="v"]').length;if(v)bad.push(v+' edge lines');return bad.join('; ');})()})
      puts "HAIR #{c['name']}: #{hr}" unless hr.empty?
      expect(hr).to eq('')
      # Pollen (owner 2026-11-12): a pollen meter row is shown only when it lights at least one cell.
      po = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part="meter"][data-sw-key="pollen"]').forEach(function(m){if(!m.getBoundingClientRect().width)return;var l=m.querySelector('[data-sw-lit]');if(!l||!(+l.getAttribute('data-sw-lit')>0))bad.push('pollen 0 cells');});return bad.join('; ');})()})
      puts "POLLEN #{c['name']}: #{po}" unless po.empty?
      expect(po).to eq('')
      # Indoor sensor (as live): with a reading, BUITEN and BINNEN twin readouts side by side (digits drawn, no overlap,
      # a line under each), and the temperature dial (when shown) carries the twin needle; without one, none of it.
      sn = s.evaluate(%q{(function(){var vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null},bad=[];
var tw=[].filter.call(document.querySelectorAll('[data-sw-twin="out"],[data-sw-twin="in"]'),vis),nd=[].filter.call(document.querySelectorAll('svg [data-sw-twin="1"] line'),function(l){return vis(l.ownerSVGElement)&&!l.closest('[data-sw-glow]')});
if(tw.length){if(tw.length!==2)bad.push('twins '+tw.length);else{var a=tw[0].getBoundingClientRect(),b=tw[1].getBoundingClientRect();if(a.right>b.left+1)bad.push('twins overlap');
tw.forEach(function(t){var d=t.querySelector('[data-sw-part] svg'),sp=t.querySelectorAll(':scope > span');if(!d||!vis(d)||!d.querySelector('path,rect,polygon'))bad.push(t.getAttribute('data-sw-twin')+' no digits');if(sp.length<2||!sp[0].textContent.trim()||!sp[1].textContent.trim())bad.push(t.getAttribute('data-sw-twin')+' label/line missing');});}}
var td=[].filter.call(document.querySelectorAll('[data-sw-part="tdial"]'),vis).length;
return tw.length+','+nd.length+','+td+(bad.length?' '+bad.join('; '):'');})()})
      puts "SENSOR #{c['name']}: #{sn}"
      want = c['vars'] && c['vars']['sensor_readings'] ? 2 : 0
      expect(sn.split(' ')[0].split(',')[0].to_i).to eq(want)
      expect(sn).not_to include(' ')
      dials = sn.split(',')[2].to_i
      expect(sn.split(',')[1].to_i).to eq(want.positive? ? dials : 0)
      # Days strip (owner 2026-11-12): a paper channel beside the now line in every row with cells; cells a solid bar or
      # separated by at least 2 px; the now line over the axis labels (continuous) and its pointer clear of every label.
      ds = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null};
document.querySelectorAll('[data-sw-part="day"]').forEach(function(el){if(!vis(el))return;var nl=el.querySelector('[data-sw-now]'),cs=el.querySelectorAll('[data-sw-cells] rect');if(!cs.length)return;
var R=[].map.call(cs,function(q){return[+q.getAttribute('x'),+q.getAttribute('x')+ +q.getAttribute('width')]}),wd=R.map(function(q){return q[1]-q[0]}).sort(function(a,b){return a-b}),md=wd[wd.length>>1];if(R.length>1&&wd[0]<md/2-0.5)bad.push('sliver row '+el.getAttribute('data-sw-i')+' '+wd[0].toFixed(1));
if(nl){var x0=+nl.getAttribute('x'),x1=x0+ +nl.getAttribute('width');R.forEach(function(q){if((Math.abs(q[0]-x1)<0.9||Math.abs(q[1]-x0)<0.9||(q[0]>x0-0.9&&q[0]<x1+0.9)||(q[1]>x0-0.9&&q[1]<x1+0.9)))bad.push('edge at the now line row '+el.getAttribute('data-sw-i'));});}
var r=[].map.call(cs,function(q){return[+q.getAttribute('x'),+q.getAttribute('x')+ +q.getAttribute('width')]}).sort(function(a,b){return a[0]-b[0]});for(var i=1;i<r.length;i++)if(r[i][0]-r[i-1][1]<1.9){bad.push('cells merge row '+el.getAttribute('data-sw-i')+' gap '+(r[i][0]-r[i-1][1]).toFixed(1));break;}});
document.querySelectorAll('[data-sw-part="scale"]').forEach(function(el){if(!vis(el))return;var nl=el.querySelector('[data-sw-now]'),ax=el.querySelector('[data-sw-axis]');if(!nl)return;
if(ax&&(ax.compareDocumentPosition(nl)&Node.DOCUMENT_POSITION_FOLLOWING)===0)bad.push('now line under the labels');var pt=el.querySelector('polygon');var pb=vis(pt);
if(pb)el.querySelectorAll('text').forEach(function(t){var b=t.getBoundingClientRect(),k=el.getBoundingClientRect().height/(+el.querySelector('svg').getAttribute('height')||1),cy=(b.top+b.bottom)/2,hc=+t.getAttribute('font-size')*k*0.36;if(b.width&&pb.left<b.right-1&&pb.right>b.left+1&&pb.bottom>cy-hc+0.5)bad.push('pointer over '+t.textContent);});});
return bad.join('; ');})()})
      puts "DAYS #{c['name']}: #{ds}" unless ds.empty?
      expect(ds).to eq('')
      # X condition label (owner 2026-11-12): a clearly larger title than the day names, so it fills the middle block.
      if c['device'] == 'v2' && %w[full half_horizontal].include?(c['view'] || 'full') && c['orientation'].nil?
        cr = s.evaluate(%q{(function(){var v=function(q){return [].filter.call(document.querySelectorAll(q),function(e){return e.getBoundingClientRect().width>0})[0]},a=v('[data-sw-cond]'),b=v('[data-sw-dname]')||v('[data-sw-mlabel]');return a&&b?parseFloat(getComputedStyle(a).fontSize)/parseFloat(getComputedStyle(b).fontSize):9;})()})
        puts "CONDSIZE #{c['name']}: #{cr.round(2)}" if cr < 1.2
        expect(cr).to be >= 1.2
      end
      # Dividers between panels (owner 2026-11-12): none between filled panels (light 4-bit), shown where panels are unfilled.
      bt = s.evaluate(%q{(function(){var sc=(document.querySelector('.screen')||document.body).classList,filled=!sc.contains('screen--dark-mode')&&!sc.contains('screen--1bit')&&!sc.contains('screen--2bit')&&!/(^| )screen--color-/.test(sc.value)&&!!document.querySelector('[data-sw-fill]');
var v=[].filter.call(document.querySelectorAll('[data-sw-between]'),function(e){return getComputedStyle(e).display!=='none'&&e.getClientRects().length>0&&(!e.closest('.hidden')||getComputedStyle(e.closest('.hidden')).display!=='none')}).length;return (filled?'filled ':'open ')+v;})()})
      puts "BETWEEN #{c['name']}: #{bt}" if bt.start_with?('filled') && bt != 'filled 0'
      expect(bt).to eq('filled 0') if bt.start_with?('filled')
      # Panel spacing (owner 2026-11-12): with filled panels, every gap (between panels, to the screen edges and the title
      # bar) the same within 2 px.
      pg = s.evaluate(%q{(function(){if(!document.querySelector('[data-sw-fill]'))return '';var sc=document.querySelector('[data-sw-debug]').closest('.view')||document.querySelector('.screen')||document.body,S=sc.getBoundingClientRect(),P=[].map.call(document.querySelectorAll('[data-sw-fill]'),function(e){return e.getBoundingClientRect()}).filter(function(b){return b.width>0&&b.height>0}),tb=document.querySelector('.title_bar'),T=tb&&tb.getBoundingClientRect().height?tb.getBoundingClientRect():null,g=[];
P.forEach(function(a){var Q=(document.querySelector('.screen')||document.body).getBoundingClientRect(),e=function(v,w){return v<1?w:v},L=e(a.left-S.left,a.left-Q.left),R=e(S.right-a.right,Q.right-a.right),U=e(a.top-S.top,a.top-Q.top),D=T?T.top-a.bottom:e(S.bottom-a.bottom,Q.bottom-a.bottom);P.forEach(function(b){if(b===a)return;if(b.right<=a.left+1&&b.bottom>a.top+1&&b.top<a.bottom-1)L=Math.min(L,a.left-b.right);if(b.left>=a.right-1&&b.bottom>a.top+1&&b.top<a.bottom-1)R=Math.min(R,b.left-a.right);if(b.bottom<=a.top+1&&b.right>a.left+1&&b.left<a.right-1)U=Math.min(U,a.top-b.bottom);if(b.top>=a.bottom-1&&b.right>a.left+1&&b.left<a.right-1)D=Math.min(D,b.top-a.bottom);});g.push(L,R,U,D);});
var mn=Math.min.apply(null,g),mx=Math.max.apply(null,g);return mx-mn>2?'gaps '+mn.toFixed(1)+'..'+mx.toFixed(1)+' ['+g.map(function(v){return v.toFixed(0)}).join(',')+']':'';})()})
      puts "GAPS #{c['name']}: #{pg}" unless pg.empty?
      expect(pg).to eq('')
      # Barometer once (owner 2026-11-12): never the dial and the BARO meter both on screen.
      bb = s.evaluate(%q{(function(){var v=function(q){return [].some.call(document.querySelectorAll(q),function(e){var b=e.getBoundingClientRect();return b.width>0&&b.height>0})};return v('[data-sw-part="baro"]')&&v('[data-sw-part="meter"][data-sw-key="baro"]')?'dial and meter':'';})()})
      puts "BARO #{c['name']}: #{bb}" unless bb.empty?
      expect(bb).to eq('')
      # Wind gust (owner 2026-11-12): the fixture's gust (28 km/h over 11 sustained) outlines exactly one WIND cell.
      gu = s.evaluate(%q{[].filter.call(document.querySelectorAll('[data-sw-part="meter"][data-sw-key="wind"]'),function(e){return e.getBoundingClientRect().width>0}).map(function(e){return e.querySelectorAll('[data-sw-gust]').length}).join(',')})
      puts "GUST #{c['name']}: #{gu}" unless gu.empty? || gu.split(',').all? { |v| v == '1' }
      expect(gu.split(',').all? { |v| v == '1' }).to be(true) if (c['fixture'] || 'mixed') == 'mixed' && !c.key?('current')
      # No warning lamps in any view (owner 2026-11-12); the rain unit's icon carries rain, snow or hail.
      lp = s.evaluate("document.querySelectorAll('[data-sw-lamp]').length")
      puts "LAMP #{c['name']}: #{lp}" unless lp.zero?
      expect(lp).to eq(0)
      # Panels (owner 2026-11-12): a plain fill, no backlight lamps (radial grey circles) behind dials, console or days.
      bl = s.evaluate(%q{document.querySelectorAll('[data-sw-backlight], [data-sw-part="face"] ellipse, [data-sw-part="face"] pattern').length})
      puts "BACKLIGHT #{c['name']}: #{bl}" unless bl.zero?
      expect(bl).to eq(0)
      # OG half_vertical (owner 2026-11-12): rain icon left of the calendar at its height, sun times shown, temperature
      # clearly bigger than the felt one, meter labels no bigger than day names, today an inverted lamp, solid dividers.
      if c['view'] == 'half_vertical' && c['device'] != 'v2'
        hv = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null},one=function(q){return [].filter.call(document.querySelectorAll(q),vis)[0]};
var ic=one('[data-sw-unit="rain"] img')||one('[data-sw-unit="rain"] [data-sw-part="icon"]'),ca=one('[data-sw-part="rain"]');if(ca&&!ic)bad.push('no rain icon');if(ca&&ic){var a=ic.getBoundingClientRect(),b=ca.getBoundingClientRect();if(a.right>b.left+1||Math.abs(a.height-b.height)>2)bad.push('rain icon '+[a.left,a.right,a.height].map(Math.round)+' cal '+[b.left,b.height].map(Math.round));}
if(!one('[data-sw-unit="sun"]'))bad.push('no sun times');var wi=one('img[data-sw-icon], [data-sw-cond]'),pn=one('[data-sw-panel]');if(wi&&pn){var wb=one('[data-sw-cond]').parentElement.getBoundingClientRect(),pq=pn.getBoundingClientRect();if(wb.left<pq.left+4)bad.push('weather row past the panel '+wb.left.toFixed(0));}
var t=one('[data-sw-part="temp"] svg'),f=one('[data-sw-part="feels"] svg');if(t&&f&&(t.getBoundingClientRect().height<f.getBoundingClientRect().height*1.4||t.getBoundingClientRect().height<innerHeight*0.09))bad.push('temp not bigger '+t.getBoundingClientRect().height.toFixed(0)+'/'+f.getBoundingClientRect().height.toFixed(0));
var ml=one('[data-sw-mlabel]'),dn=one('[data-sw-dname]');if(ml&&dn&&parseFloat(getComputedStyle(ml).fontSize)>parseFloat(getComputedStyle(dn).fontSize)+0.5)bad.push('meter label > day name');
var td=one('[data-sw-today]');if(td&&!/label--inverted/.test(td.className))bad.push('today not lit');
var sc=(document.querySelector('.screen')||document.body).classList;if(sc.contains('screen--1bit')||sc.contains('screen--2bit'))[].filter.call(document.querySelectorAll('[data-sw-rule]'),function(r){return r.getClientRects().length>0;}).forEach(function(r){if(!/-black/.test(r.className))bad.push('dither rule');});
return bad.join('; ');})()})
        puts "OGHV #{c['name']}: #{hv}" unless hv.empty?
        expect(hv).to eq('')
      end
      # Calm style (owner): no L/R badges, the barometer shows a trend word, the temperature dial carries the low/high numbers,
      # no now line, no grid or row lines in the days strip; the cue (umbrella or coat) only in Calm. Receiver: the opposite.
      cm = s.evaluate(%q{(function(){var vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0},n=function(q){return [].filter.call(document.querySelectorAll(q),vis).length};
var dial=n('[data-sw-part="baro"]');return [SW.calm?1:0,dial,n('[data-sw-part="baro"] ~ .label--inverted, [data-sw-part="tdial"] ~ .label--inverted'),n('[data-sw-trend]'),n('[data-sw-mark]'),document.querySelectorAll('[data-sw-now]').length,document.querySelectorAll('[data-sw-part="day"] rect[data-sw-tick]').length,n('[data-sw-hair="row"]'),n('[data-sw-part="cue"] svg'),SW.cue?1:0].join(',');})()})
      puts "CALM #{c['name']}: calm,dial,badges,trend,marks,now,grid,hair,cue,wantcue #{cm}"
      q = cm.split(',').map(&:to_i)
      if (c['fields'] || {})['style'] == 'calm'
        expect(q[0]).to eq(1)
        expect(q[2]).to eq(0)
        expect(q[3]).to eq(q[1])
        expect(q[4]).to eq(q[1] * 2)
        expect(q[5..7]).to eq([0, 0, 0])
        expect(q[8].positive?).to eq(q[9] == 1) unless c['device'] == 'v2' && c['view'] == 'half_vertical'   # X half_vertical: no room beside the felt temperature, the cue is left out there
        expect(q[8]).to eq(0) if c['device'] == 'v2' && c['view'] == 'half_vertical'
      else
        expect(q[0]).to eq(0)
        expect(q[2]).to eq(q[1] * 2)
        expect([q[3], q[4], q[8]]).to eq([0, 0, 0])
      end
      # Calm (owner): 1-bit and 2-bit panels stay paper (no grey fill); the dial's low/high numbers clear their triangles by 2 px
      # and are at least the size of the dial's scale numbers.
      if (c['fields'] || {})['style'] == 'calm'
        cf = s.evaluate(%q{(function(){var sc=(document.querySelector('.screen')||document.body).classList,lo=sc.contains('screen--1bit')||sc.contains('screen--2bit');
var f=lo?[].filter.call(document.querySelectorAll('[data-sw-fill]'),function(e){return e.getBoundingClientRect().width>0}).length:0,bad=[];
document.querySelectorAll('text[data-sw-mark]').forEach(function(t){var k=t.getAttribute('data-sw-mark'),m=t.ownerSVGElement.querySelector('[data-sw-markt="'+k+'"]');if(!m)return bad.push('no mark '+k);var a=t.getBoundingClientRect(),b=m.getBoundingClientRect();
var sf=[].map.call(t.ownerSVGElement.querySelectorAll('text:not([data-sw-mark])'),function(e){return +e.getAttribute('font-size')});if(sf.length&&+t.getAttribute('font-size')<Math.max.apply(null,sf))bad.push(k+' smaller than the scale numbers');var gx=Math.max(b.left-a.right,a.left-b.right),gy=Math.max(b.top-a.bottom,a.top-b.bottom),gp=Math.max(gx,gy);if(gp<2)bad.push(k+' gap '+gp.toFixed(1));});
return (f?'fill '+f+' ':'')+bad.join('; ');})()})
        puts "CALMFIX #{c['name']}: #{cf}" unless cf.empty?
        expect(cf).to eq('')
      end
      # Inner padding (owner, Calm): margins from each panel edge to the drawn ink (SVG shapes, glyph ink of the text, the
      # weather icon's measured ink), per panel L,R,T,B.
      pad = s.evaluate(%q{(function(){var out=[],cx=document.createElement('canvas').getContext('2d'),vis=function(e){var b=e.getBoundingClientRect();return b.width>0&&b.height>0&&getComputedStyle(e).visibility!=='hidden'};
document.querySelectorAll('[data-sw-panel]').forEach(function(p){var q=p.getBoundingClientRect();if(!q.width||!q.height)return;var L=1e9,R=-1e9,T=1e9,B=-1e9,add=function(l,r,t,b){if(r-l<0.5&&b-t<0.5)return;L=Math.min(L,l);R=Math.max(R,r);T=Math.min(T,t);B=Math.max(B,b);};
p.querySelectorAll('[data-sw-part]:not([data-sw-part="face"]) svg').forEach(function(sv){if(!vis(sv))return;sv.querySelectorAll('path,rect,circle,polygon,line,text,image,ellipse').forEach(function(e){if(e.closest('defs,mask,clipPath,filter,[data-sw-glow]'))return;var b=e.getBoundingClientRect();if(!b.width&&!b.height)return;add(b.left,b.right,b.top,b.bottom);});});
p.querySelectorAll('img').forEach(function(im){if(!vis(im)||im.closest('[data-sw-part]'))return;var b=im.getBoundingClientRect(),ik=(im.getAttribute('data-sw-ink')||'0,1').split(',').map(Number);add(b.left,b.right,b.top+ik[0]*b.height,b.top+(ik[0]+ik[1])*b.height);});
p.querySelectorAll('span').forEach(function(sp){if(!vis(sp)||sp.querySelector('span,img,svg'))return;var tx=sp.textContent.trim();if(!tx)return;var cs=getComputedStyle(sp),k=sp.getBoundingClientRect().width/(sp.offsetWidth||1);cx.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;var m=cx.measureText(tx),fa=m.fontBoundingBoxAscent,fd=m.fontBoundingBoxDescent;
var rg=document.createRange();rg.selectNodeContents(sp);[].forEach.call(rg.getClientRects(),function(r){if(!r.width)return;var bl=r.top+(r.height-(fa+fd)*k)/2+fa*k;add(r.left,r.right,bl-m.actualBoundingBoxAscent*k,bl+Math.max(0,m.actualBoundingBoxDescent)*k);});});
if(L<1e9)out.push([L-q.left,q.right-R,T-q.top,q.bottom-B].map(function(v){return v.toFixed(0)}).join(','));});return out.join(' ');})()})
      puts "PAD #{c['name']}: L,R,T,B #{pad}"
      # Small views (owner, Calm round 3): no days strip in a quadrant; Calm day rows at least the floor height (the Calm
      # full view's light row, 34 px on the OG and 63 px on the X, less 15 % for dark mode's divider); Calm: one now pointer, on today's row.
      dr = s.evaluate(%q{(function(){var r=[].filter.call(document.querySelectorAll('[data-sw-row="day"]'),function(e){return e.getBoundingClientRect().height>0}).map(function(e){return e.getBoundingClientRect().height});
var nm=[].filter.call(document.querySelectorAll('[data-sw-nowmark]'),function(e){return e.getBoundingClientRect().width>0}),tod=nm.filter(function(e){var d=e.closest('[data-sw-part="day"]');return d&&SW.days[+d.getAttribute('data-sw-i')].today}).length;
var ax=[].filter.call(document.querySelectorAll('[data-sw-part="scale"] text[data-sw-tick]'),function(e){return e.getBoundingClientRect().width>0})[0],big=1;
nm.forEach(function(e){var b=e.getBoundingClientRect(),k=ax?ax.ownerSVGElement.getBoundingClientRect().height/+ax.ownerSVGElement.getAttribute('height'):1,fs=ax?+ax.getAttribute('font-size')*k:0;if(b.height<fs*0.42*0.9)big=0;
[].forEach.call(e.ownerSVGElement.querySelectorAll('[data-sw-cells] rect'),function(r){var q=r.getBoundingClientRect();if(q.top<b.bottom-0.5&&q.left<b.right&&q.right>b.left)big=0;});});
return [r.length,r.length?Math.min.apply(null,r).toFixed(1):0,innerHeight,nm.length,tod,big].join(',');})()})
      puts "DAYROW #{c['name']}: rows,minH,screenH,ptr,ptrToday,ptrBigAndClear #{dr}"
      d = dr.split(',').map(&:to_f)
      expect(d[0]).to eq(0) if c['view'] == 'quadrant'
      if (c['fields'] || {})['style'] == 'calm'
        expect(d[1]).to be >= (c['device'] == 'v2' ? 53 : 28) if d[0].positive?
        expect([d[3], d[4]]).to eq(d[0].positive? ? [1, 1] : [0, 0])
        expect(d[5]).to eq(1)
      else
        expect(d[3]).to eq(0)
      end
      # Felt temperature icon (owner): the outline figure, its drawn height the felt digits' height (2 px), centred on them.
      fi = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part="person"] svg').forEach(function(p){var b=p.getBoundingClientRect();if(!b.width)return;if(!p.querySelector('[data-sw-feelsicon]')){bad.push('not the outline icon');return;}
var f=p.closest('[data-sw-part="person"]').parentElement.querySelector('[data-sw-part="feels"] svg');if(!f)return;var a=f.getBoundingClientRect();if(Math.abs(a.height-b.height)>2||Math.abs((a.top+a.bottom)/2-(b.top+b.bottom)/2)>2)bad.push('icon '+b.height.toFixed(1)+'@'+b.top.toFixed(0)+' digits '+a.height.toFixed(1)+'@'+a.top.toFixed(0));});return bad.join('; ');})()})
      puts "FEELSICON #{c['name']}: #{fi}" unless fi.empty?
      # Coat cue (owner): an outline parka, stroke only, as the weather icons; never the old solid coat.
      co = s.evaluate(%q{[].map.call(document.querySelectorAll('[data-sw-cue="coat"] svg'),function(v){return v.getBoundingClientRect().width>0?(v.querySelector('g[data-sw-coat][fill="none"]')?'ok':'solid'):''}).join('')})
      puts "COAT #{c['name']}: #{co}" unless co.empty?
      expect(co).not_to include('solid')
      expect(fi).to eq('')
      # Hours strip (owner): column count per view, an inverted stamp exactly on the current and the wet hours, the block
      # curve inside its column and its panel, stamp, temperature and icon ink centred on the column axis (2 px; every
      # icon's ink is centred in its 30x30 box, 0.502 measured 2026-11-12, so the box centre is the ink centre), columns ordered and equal, the temperature's blocks on one scale.
      hs = s.evaluate(%q{(function(){var vis=function(e){var b=e.getBoundingClientRect();return b.width>0&&b.height>0};var bad=[],cols=[].filter.call(document.querySelectorAll('[data-sw-hcol]'),vis);
cols.forEach(function(cl,k){var i=+cl.getAttribute('data-sw-hcol'),q=SW.hours[i],st=cl.querySelector('[data-sw-hstamp]'),inv=st.classList.contains('label--inverted');if(i!==k)bad.push('order '+k+'/'+i);
if(inv!==(q.now||q.wet))bad.push('stamp '+i+' inverted='+inv+' wet='+q.wet);if(st.getAttribute('data-sw-hstamp')==='wet'&&!q.wet)bad.push('rain stamp on dry '+i);
var cb=cl.getBoundingClientRect(),p=cl.closest('[data-sw-panel]').getBoundingClientRect();[].forEach.call(cl.querySelectorAll('[data-sw-cells] rect, img, span'),function(r){var b=r.getBoundingClientRect();if(b.left<cb.left-1||b.right>cb.right+1||b.top<cb.top-1||b.bottom>cb.bottom+1||b.top<p.top||b.bottom>p.bottom)bad.push('out '+i+' '+r.tagName);});
var n=cl.querySelectorAll('[data-sw-cells] rect').length;if(q.tV!==null&&n<1)bad.push('no blocks '+i);if(Math.abs(cb.width-cols[0].getBoundingClientRect().width)>1)bad.push('width '+i);
var sp=st.getBoundingClientRect();if(sp.width>cb.width+1)bad.push('stamp wider '+i);
var ic=[].filter.call(cl.querySelectorAll('img, [data-sw-part="icon"] svg'),vis)[0],k=(cl.offsetWidth&&cb.width/cl.offsetWidth)||1,mid=(cb.left+cb.right)/2;if(ic){var ib=ic.getBoundingClientRect(),ix=ib.left+ib.width*0.502;if(Math.abs(ix-mid)>2*k)bad.push('icon off '+i+' '+(ix-mid).toFixed(1));}
[st,cl.querySelector('[data-sw-htemp]')].forEach(function(e){var b=e.getBoundingClientRect();if(Math.abs((b.left+b.right)/2-mid)>2*k)bad.push('off '+i+' '+e.tagName);});});
var L=cols.map(function(cl){return +(cl.querySelector('[data-sw-cells]')||{getAttribute:function(){return 0}}).getAttribute('data-sw-cells')}),T=cols.map(function(cl){return SW.hours[+cl.getAttribute('data-sw-hcol')].tV});
var tb=cols.map(function(cl){return cl.querySelector('[data-sw-htemp]').getBoundingClientRect().bottom}),ib=cols.map(function(cl){var e=[].filter.call(cl.querySelectorAll('img, [data-sw-part="icon"] svg'),vis)[0];return e?e.getBoundingClientRect().top:null}).filter(function(v){return v!==null});
if(tb.length&&Math.max.apply(null,tb)-Math.min.apply(null,tb)>1)bad.push('temp baseline spread '+(Math.max.apply(null,tb)-Math.min.apply(null,tb)).toFixed(1));if(ib.length&&Math.max.apply(null,ib)-Math.min.apply(null,ib)>1)bad.push('icon row spread '+(Math.max.apply(null,ib)-Math.min.apply(null,ib)).toFixed(1));
for(var a=0;a<cols.length;a++)for(var b=0;b<cols.length;b++)if(T[a]!==null&&T[b]!==null&&T[a]>T[b]+1.5&&L[a]<L[b])bad.push('scale '+a+'<'+b);
return cols.length+'|'+bad.join('; ');})()})
      puts "HOURS #{c['name']}: cols|bad #{hs}" if c['hcols'] || hs != '0|'
      expect(hs).to eq("#{c['hcols'] || 0}|")
      puts "GEO #{c['name']}: unequal day rows #{geo}"
      expect(geo).to start_with('0/')
      puts "#{c['name']}: #{s.evaluate("document.querySelector('[data-sw-debug]').getAttribute('data-sw-debug')")[0, 300]}"
    end
  end
end
