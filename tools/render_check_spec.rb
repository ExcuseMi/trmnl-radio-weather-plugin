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
      clip = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part], [data-sw-part] > svg, [data-sw-unit] img, [data-sw-unit] span').forEach(function(e){var b=e.getBoundingClientRect();if(!b.width||!b.height)return;var p=e.closest('.rounded.bg--white');if(!p)return;var q=p.getBoundingClientRect(),cs=getComputedStyle(p),k=q.width/(p.offsetWidth||q.width);q={left:q.left+parseFloat(cs.paddingLeft)*k,right:q.right-parseFloat(cs.paddingRight)*k,top:q.top+parseFloat(cs.paddingTop)*k,bottom:q.bottom-parseFloat(cs.paddingBottom)*k};var un=e.closest('[data-sw-unit]');if(un){var cb=un.parentElement.getBoundingClientRect();q={left:Math.max(q.left,cb.left),right:Math.min(q.right,cb.right),top:Math.max(q.top,cb.top),bottom:Math.min(q.bottom,cb.bottom)}}if(b.left<q.left-1||b.right>q.right+1||b.top<q.top-1||b.bottom>q.bottom+1)bad.push((e.getAttribute('data-sw-part')||e.tagName)+'@'+[b.left,b.right,b.top,b.bottom].map(function(v){return v.toFixed(0)}).join(':')+'/'+[q.left,q.right,q.top,q.bottom].map(function(v){return v.toFixed(0)}).join(':'))});return bad.join(' ')})()})
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
      # Bleed margin (owner 2026-11-12): every panel (and its shadow/frame) and the title bar keep the framework's
      # screen padding from the screen edge.
      edge = s.evaluate(%q{(function(){var sc=document.querySelector('.screen')||document.body,S=sc.getBoundingClientRect(),k=S.width/(sc.offsetWidth||S.width),bad=[],m=8*k;
document.querySelectorAll('.rounded--large, .title_bar').forEach(function(e){var b=e.getBoundingClientRect();if(!b.width||!b.height)return;
var d=Math.min(b.left-S.left,b.top-S.top,S.right-b.right,S.bottom-b.bottom);if(d<m)bad.push((e.className.baseVal||e.className||e.tagName).toString().slice(0,30)+' '+d.toFixed(1));});return bad.join('; ');})()})
      puts "EDGE #{c['name']}: #{edge}" unless edge.empty?
      expect(edge).to eq('')
      # Days strip (owner 2026-11-12): every grid line through the centre of its label's digits (one x mapping for the
      # header and the rows); the now line continuous from the header down through all rows.
      ds = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e.getBoundingClientRect();return b.width>0||b.height>0};
var sc=[].filter.call(document.querySelectorAll('[data-sw-part="scale"]'),vis)[0],d0=[].filter.call(document.querySelectorAll('[data-sw-part="day"]'),vis)[0];if(!sc||!d0)return '';
sc.querySelectorAll('text[data-sw-tick]').forEach(function(t){var b=t.getBoundingClientRect(),r=d0.querySelector('rect[data-sw-tick="'+t.getAttribute('data-sw-tick')+'"]');if(!r){bad.push('no line '+t.textContent);return;}var q=r.getBoundingClientRect(),dx=(b.left+b.right)/2-(q.left+q.right)/2;if(Math.abs(dx)>1)bad.push('label '+t.textContent+' off '+dx.toFixed(1));});
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
      # Weather icon (owner 2026-11-12): one-line condition: icon as tall as the capitals, centred on them; two lines: the block.
      ci = s.evaluate(%q{(function(){var bad=[],cx=document.createElement('canvas').getContext('2d');document.querySelectorAll('[data-sw-cond]').forEach(function(sp){var sb=sp.getBoundingClientRect();if(!sb.height)return;
var ic=sp.parentElement.firstElementChild,ib=ic.getBoundingClientRect(),k=sb.width/(sp.offsetWidth||sb.width),cs=getComputedStyle(sp);cx.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;var m=cx.measureText('H'),fa=m.fontBoundingBoxAscent*k,fd=m.fontBoundingBoxDescent*k,cap=m.actualBoundingBoxAscent*k;
var rg=document.createRange();rg.selectNodeContents(sp);var lr=[].filter.call(rg.getClientRects(),function(q){return q.width>0}),bl=function(q){return q.top+(q.height-fa-fd)/2+fa},t0=bl(lr[0])-cap,t1=bl(lr[lr.length-1]),n=lr.filter(function(q,i){return i===0||Math.abs(q.top-lr[i-1].top)>2}).length;
var h=n>1?t1-t0:cap,mid=n>1?(t0+t1)/2:t0+cap/2;if(Math.abs(ib.height-h)>2)bad.push('icon h '+ib.height.toFixed(1)+' want '+h.toFixed(1)+' ('+n+' lines)');if(Math.abs(ib.top+ib.height/2-mid)>1.5)bad.push('icon centre off '+(ib.top+ib.height/2-mid).toFixed(1));});return bad.join('; ');})()})
      puts "CONDICON #{c['name']}: #{ci}" unless ci.empty?
      expect(ci).to eq('')
      puts "GEO #{c['name']}: unequal day rows #{geo}"
      expect(geo).to start_with('0/')
      puts "#{c['name']}: #{s.evaluate("document.querySelector('[data-sw-debug]').getAttribute('data-sw-debug')")[0, 300]}"
    end
  end
end
