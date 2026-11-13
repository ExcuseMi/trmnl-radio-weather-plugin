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
      # A custom screen (the markup editor previews a layout in a frame of the layout's own size, owner 2026-11-13):
      # device {model, width, height, bit_depth, screen_classes}; the checks then read the model name.
      dev = c['device'].is_a?(Hash) ? c['device'].transform_keys(&:to_sym) : (c['device'] || 'v2')
      c = c.merge('device' => dev[:model]) if dev.is_a?(Hash)
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
      fields = { 'lat_lon' => '52.52,13.41', 'unit' => 'celsius', 'days_shown' => 'auto', 'dial_span' => '24h', 'hide_title_bar' => 'false' }.merge(c['fields'] || {})
      opts = { view: c['view'] || 'full', device: dev, mocks:, custom_fields: fields, now:, wait_for: "document.querySelector('[data-sw-drawn],[data-sw-error]') !== null" }
      opts[:variables] = { 'trmnl' => { 'user' => { 'locale' => c['locale'] } } } if c['locale']
      opts[:variables] = (opts[:variables] || {}).merge(c['vars']) if c['vars']
      opts[:theme] = c['theme'] if c['theme']
      opts[:palette] = c['palette'] if c['palette']
      opts[:orientation] = c['orientation'].to_sym if c['orientation']
      opts[:dark_mode] = true if c['dark']
      opts[:text_scale] = c['text_scale'] if c['text_scale']
      opts[:state] = c['state'] if c['state']   # saved state (indoor trend cases)
      if c['offline_h']   # saved state (owner 2026-11-13): a good run writes the copy, then Open-Meteo is down offline_h hours later
        pre = trmnl.transform(**{ device: dev, mocks:, custom_fields: fields, now:, variables: opts[:variables] }.compact)
        opts[:state] = pre.state
        opts[:mocks] = { 'https://api.open-meteo.com/*' => { status: 503, json: { error: true, reason: 'Service unavailable' } } }
        opts[:now] = (Time.iso8601(now) + c['offline_h'] * 3600).iso8601
      end
      s = trmnl.render(**opts)
      puts "SCREEN #{c['name']}: #{s.evaluate("document.querySelector('.screen').className+' '+innerWidth")}" if ENV['SW_SCREEN']
      FileUtils.mkdir_p(out)
      FileUtils.cp(s.png_path, File.join(out, "#{c['name']}.png"))
      # Title bar icon (owner 2026-11-13, live OG 1-bit: gone): wherever the title bar shows, its icon has dark ink in the screenshot.
      tb = s.evaluate(%q{(function(){var e=document.querySelector('.title_bar img');if(!e)return '';var b=e.getBoundingClientRect(),sc=document.querySelector('.screen')||document.body;return [b.left,b.top,b.width,b.height,sc.getBoundingClientRect().left,innerWidth].join(',')})()})
      unless tb.to_s.empty?
        require 'chunky_png'
        bx, by, bw, bh, _sx, iw = tb.split(',').map(&:to_f)
        png = ChunkyPNG::Image.from_file(s.png_path)
        k = png.width / iw
        ink = 0
        (by * k).floor.upto(((by + bh) * k).ceil - 1) { |y| (bx * k).floor.upto(((bx + bw) * k).ceil - 1) { |x| next if x >= png.width || y >= png.height; v = png[x, y]; ink += 1 if ChunkyPNG::Color.r(v) + ChunkyPNG::Color.g(v) + ChunkyPNG::Color.b(v) < 300 } }
        puts "TBAR #{c['name']}: icon #{bw.round}x#{bh.round} ink #{ink}" if ink < 12
        expect(ink).to be >= 12
      end
      err = s.evaluate("(document.querySelector('[data-sw-error]')||{getAttribute:function(){return null}}).getAttribute('data-sw-error')")
      puts "ERR #{c['name']}: #{err}" if err
      expect(err).to be_nil
      # Offline (saved state, owner 2026-11-13): a stale view shows its "as of" once, inside the view, clear of every other ink box.
      sl = s.evaluate(%q{(function(){var st=SW.stale||null,ls=[].filter.call(document.querySelectorAll('[data-sw-stale]'),function(e){var b=e.getBoundingClientRect();return b.width>0&&b.height>0});if(!st)return ls.length?'label without stale data':'';if(ls.length!==1)return 'labels '+ls.length;var L=ls[0].getBoundingClientRect(),V=(document.querySelector('.view')||document.body).getBoundingClientRect(),bad=[];if(ls[0].textContent.trim()!==st)bad.push('text '+ls[0].textContent);if(L.left<V.left||L.right>V.right||L.top<V.top||L.bottom>V.bottom)bad.push('outside the view');var cx=(L.left+L.right)/2,cy=(L.top+L.bottom)/2,F=[].map.call(document.querySelectorAll('[data-sw-part="face"]'),function(e){return e.getBoundingClientRect()}).filter(function(f){return f.width>0&&cx>f.left&&cx<f.right&&cy>f.top&&cy<f.bottom})[0];if(ls[0].closest('.title_bar')){}else if(!F)bad.push('not on a panel');else{var r=Math.min(24,Math.min(F.width,F.height)*0.08),I=2;if(L.left<F.left+I||L.right>F.right-I||L.top<F.top+I||L.bottom>F.bottom-I)bad.push('over the panel edge');[[L.left,L.top],[L.right,L.top],[L.left,L.bottom],[L.right,L.bottom]].forEach(function(q){var ox=q[0]<F.left+r?F.left+r:(q[0]>F.right-r?F.right-r:null),oy=q[1]<F.top+r?F.top+r:(q[1]>F.bottom-r?F.bottom-r:null);if(ox!==null&&oy!==null&&Math.hypot(q[0]-ox,q[1]-oy)>r-I)bad.push('over the rounded corner')});}[].forEach.call(document.querySelectorAll('img,svg,.value,.title,.label,.instance,[data-sw-rule]'),function(e){if(e===ls[0]||ls[0].contains(e)||e.contains(ls[0])||e.closest('[data-sw-part="face"]'))return;var b=e.getBoundingClientRect();if(b.width>0&&b.height>0&&b.left<L.right-1&&b.right>L.left+1&&b.top<L.bottom-1&&b.bottom>L.top+1)bad.push('overlaps '+((e.closest('[data-sw-part]')||e).getAttribute('data-sw-part')||e.tagName+' '+(e.textContent||'').trim().slice(0,12)))});return bad.join('; ');})()})
      puts "STALE #{c['name']}: #{sl}" unless sl.empty?
      expect(sl).to eq('')
      # Indoor trend (saved state, owner 2026-11-13): an up/down arrow behind the indoor unit, inside its twin column; today's low/high fully inside the column.
      it3 = s.evaluate(%q{(function(){var I=SW.inn;if(!I)return '';var bad=[],col=document.querySelector('[data-sw-twin="in"]');if(!col||!col.getBoundingClientRect().width)return '';var C=col.getBoundingClientRect(),a=[].filter.call(col.querySelectorAll('[data-sw-inarrow]'),function(e){return e.getBoundingClientRect().width>0}),want=(I.arrow==='up'||I.arrow==='down')&&document.querySelector('.screen--lg')?1:0;if(a.length!==want)bad.push('arrows '+a.length+'/'+want+' '+[].map.call(col.querySelectorAll('[data-sw-inarrow]'),function(e){var b=e.getBoundingClientRect();return b.width+'x'+b.height+' '+e.innerHTML.length}).join(','));if(a.length){var p=a[0].querySelector('[data-sw-arrowpoly]'),u=col.querySelector('[data-sw-unit="in"]').getBoundingClientRect(),A=a[0].getBoundingClientRect();if(!p||p.getAttribute('data-sw-arrowpoly')!==I.arrow)bad.push('arrow shape');var dg=col.querySelector('[data-sw-part="itemp"]').getBoundingClientRect();if(A.right>dg.left+1)bad.push('arrow not in front of the digits');if(A.left<C.left-1)bad.push('arrow outside the column')}var l=col.querySelector('[data-sw-inlohi]');if(I.lohi&&l){var rg=document.createRange();rg.selectNodeContents(l);var L=rg.getBoundingClientRect();if(L.width>0&&l.querySelectorAll('[data-sw-part="tri"] svg polygon').length!==2)bad.push('low/high marks not two triangles');if(/[LH] \d/.test(l.textContent))bad.push('low/high as letters');if(L.width>0&&(L.left<C.left-1||L.right>C.right+1))bad.push('low/high outside the column');var pe=l.parentElement,ro=document.querySelector('[data-sw-twin="out"]'),rl=ro&&ro.lastElementChild,lh=rl?rl.getBoundingClientRect().height:0;if(L.width>0&&lh>0&&pe.getBoundingClientRect().height>1.3*lh)bad.push('humidity line wraps')}return bad.join('; ');})()})
      puts "INTREND #{c['name']}: #{it3}" unless it3.empty?
      expect(it3).to eq('')
      tf = s.evaluate(%q{(function(){var v=function(q){var e=document.querySelector(q);if(!e)return 0;var r=e.getBoundingClientRect();return r.width>0?r.height:0};var t=v('[data-sw-part="temp"] svg'),f=v('[data-sw-part="feels"] svg');return f&&!(t>f)?'temp '+t.toFixed(0)+' felt '+f.toFixed(0):''})()})   # owner step 12: the main temperature is the largest number in the console
      arc = s.evaluate(%q{(function(){var a=[].filter.call(document.querySelectorAll('g[data-sw-arc]'),function(g){return g.ownerSVGElement.getBoundingClientRect().width>0}),bad=[],rs=[];a.forEach(function(g){var sv=g.ownerSVGElement,k=sv.getBoundingClientRect().width/+sv.getAttribute('width'),v=g.getAttribute('data-sw-arc').split(',').map(Number),r=v[0]*k,w=v[1]*k;rs.push(r);var SB=sv.getBoundingClientRect(),T=1e9;[].forEach.call(sv.querySelectorAll('path,polygon,circle,line,text'),function(e){var b=e.getBoundingClientRect();if(b.width||b.height)T=Math.min(T,b.top)});var hb=sv.querySelector('[data-sw-hub]').getBoundingClientRect();if((T-SB.top)/SB.height>0.2||(SB.bottom-hb.bottom)/SB.height>0.2)bad.push('dial not filling its panel: top '+((T-SB.top)/SB.height*100).toFixed(0)+'% hub '+((SB.bottom-hb.bottom)/SB.height*100).toFixed(0)+'%');var d=sv.closest('[data-sw-part]').getAttribute('data-sw-part'),D=d==='baro'?SW.baro:SW.tdial;if(D&&D.lo!=null&&D.hi!=null&&sv.querySelectorAll('[data-sw-markt]').length!==2)bad.push(d+' marks '+sv.querySelectorAll('[data-sw-markt]').length);});if(rs.length===2&&Math.abs(rs[0]-rs[1])>2)bad.push('radius '+rs.map(function(x){return x.toFixed(1)}).join('/'));return a.length+'|'+bad.join('; ');})()})   # owner step 13: both dials one radius, filling the panel height (ink within 20 % of the top: 3-digit low/high numbers and the twin needle shrink both; hub within 5 % of the bottom), low/high marks on both
      puts "ARC #{c['name']}: #{arc}"
      # Dial clearance (owner 2026-11-13, live X full): no dial ink (arc, ticks, numbers, zone icons, band, marks, labels;
      # not the needle) within the gap (3 % of the dial height, at least 3 px) of the caption text boxes or the panel edges.
      dc = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part="baro"],[data-sw-part="tdial"]').forEach(function(d){var B=d.getBoundingClientRect();if(!B.width)return;var k=d.getAttribute('data-sw-part'),g=Math.max(3,B.height*0.03)-1,P=(d.closest('[data-sw-panel]')||d).getBoundingClientRect(),caps=[].map.call(d.parentElement.querySelectorAll('[data-sw-cap]'),function(c){var rg=document.createRange();rg.selectNodeContents(c);return rg.getBoundingClientRect()}).filter(function(q){return q.width>0});
var n=0;[].forEach.call(d.querySelectorAll('svg path, svg line, svg text, svg polygon, svg image, svg circle'),function(e){if(e.closest('[data-sw-needle],defs,[data-sw-twin]'))return;var b=e.getBoundingClientRect();if(!b.width&&!b.height)return;var w=(e.getAttribute('stroke-width')||0)/2*(B.width/(+d.querySelector('svg').getAttribute('width')||B.width));
var x0=b.left-w,y0=b.top-w,x1=b.right+w,y1=b.bottom+w,tag=e.tagName+(e.textContent?' '+e.textContent:'');
if(x0<P.left+g||y0<P.top+g||x1>P.right-g||y1>P.bottom-g){if(n++<3)bad.push(k+' '+tag+' at the panel edge');return;}
caps.forEach(function(c){if(x0<c.right+g&&x1>c.left-g&&y0<c.bottom+g&&y1>c.top-g&&n++<3)bad.push(k+' '+tag+' within '+g.toFixed(0)+' of caption');});});});return bad.join('; ');})()})
      puts "DIALCLEAR #{c['name']}: #{dc}" unless dc.empty?
      geo = s.evaluate("(function(){var r=[].slice.call(document.querySelectorAll('[data-sw-part=\\'day\\']')).map(function(e){return e.getBoundingClientRect()}).filter(function(b){return b.width>0});return r.filter(function(b){return Math.abs(b.height-r[0].height)>0.5||Math.abs(b.left-r[0].left)>0.5||Math.abs(b.width-r[0].width)>0.5}).length+'/'+r.length})()")
      div = s.evaluate(%q{(function(){var out=[];document.querySelectorAll('[data-sw-div]').forEach(function(dv){var d=dv.getBoundingClientRect();if(!d.height)return;var row=dv.parentElement,u=row.querySelector('[data-sw-unit=\'\']'),t=row.querySelector('[data-sw-part=\'temp\'] svg'),p=row.querySelector(':scope > [data-sw-part=\'cue\']');function k(e){var r=e.getBoundingClientRect(),v=e.viewBox.baseVal,b=e.getBBox(),x=r.width/v.width,y=r.height/v.height;return{l:r.left+(b.x-v.x)*x,t:r.top+(b.y-v.y)*y,h:b.height*y}}var c=document.createElement('canvas').getContext('2d'),cs=getComputedStyle(u);c.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;var ub=u.getBoundingClientRect(),sc=(u.offsetWidth&&ub.width/u.offsetWidth)||1;var ur=ub.left+c.measureText(u.textContent.trim()).actualBoundingBoxRight*sc,pi={l:p.getBoundingClientRect().left},ti=k(t),mid=(d.left+d.right)/2;out.push([(mid-ur).toFixed(1),(pi.l-mid).toFixed(1),(d.height-ti.h).toFixed(1),(d.top-ti.t).toFixed(1),sc.toFixed(3),ur.toFixed(1),pi.l.toFixed(1),d.left.toFixed(1),d.right.toFixed(1)].join(','))});return out.join(' ')})()})
      puts "DIV #{c['name']}: gapL,gapR,dH,dTop #{div}"
      div.split.each { |q| a = q.split(',').map(&:to_f); expect((a[0] - a[1]).abs).to be <= 1.5; expect(a[2].abs).to be <= 1.5; expect(a[3].abs).to be <= 1.5 }
      if c['og_quadrant_console']
        console = s.evaluate(%q{(function(){function vis(e){var b=e.getBoundingClientRect();return b.width>0&&b.height>0}var labels=[].filter.call(document.querySelectorAll('[data-sw-mlabel]'),vis).map(function(e){return e.textContent.trim()});var moon=[].filter.call(document.querySelectorAll('[data-sw-part="moon"]'),vis)[0];var ring=moon&&moon.querySelector('circle[stroke]');return {labels:labels,ring:!!ring,lit:!!(moon&&moon.querySelector('[data-sw-moon="lit"]'))}})()})
        expect(console['labels']).to eq(['WIND'])
        expect(console['ring']).to eq(true) unless c['hourly'].nil?
        expect(console['lit']).to eq(true) unless c['hourly'].nil?
      end
      clip = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part]:not([data-sw-part="face"]), [data-sw-part]:not([data-sw-part="face"]) > svg, [data-sw-unit] img, [data-sw-unit] span').forEach(function(e){var b=e.getBoundingClientRect();if(!b.width||!b.height)return;var ci=e.closest('[data-sw-condicon]'),ik=ci&&(ci.querySelector('[data-sw-ink]')||{getAttribute:function(){return null}}).getAttribute('data-sw-ink');if(ik){var iy=+ik.split(',')[0],ih=+ik.split(',')[1]||1;b={left:b.left,right:b.right,top:b.top+iy*b.height,bottom:b.top+(iy+ih)*b.height,width:b.width,height:ih*b.height};}var p=e.closest('[data-sw-panel]');if(!p)return;var q=p.getBoundingClientRect(),cs=getComputedStyle(p),k=q.width/(p.offsetWidth||q.width);q={left:q.left+parseFloat(cs.paddingLeft)*k,right:q.right-parseFloat(cs.paddingRight)*k,top:q.top+parseFloat(cs.paddingTop)*k,bottom:q.bottom-parseFloat(cs.paddingBottom)*k};var un=e.closest('[data-sw-unit]');if(un){var cb=un.parentElement.getBoundingClientRect();q={left:Math.max(q.left,cb.left),right:Math.min(q.right,cb.right),top:Math.max(q.top,cb.top),bottom:Math.min(q.bottom,cb.bottom)}}if(b.left<q.left-1||b.right>q.right+1||b.top<q.top-1||b.bottom>q.bottom+1)bad.push((e.getAttribute('data-sw-part')||e.tagName)+'@'+[b.left,b.right,b.top,b.bottom].map(function(v){return v.toFixed(0)}).join(':')+'/'+[q.left,q.right,q.top,q.bottom].map(function(v){return v.toFixed(0)}).join(':'))});return bad.join(' ')})()})
      puts "CLIP #{c['name']}: #{clip}" unless clip.empty?
      expect(clip).to eq('')
      # Rain unit (owner 2026-11-12): calendar cells square-ish and readable (numbers at least the meter label size),
      # rain icon and moon the same size on the same left edge. Dials: caption and value never under the hub or tail.
      ru = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null};
var lab=[].filter.call(document.querySelectorAll('[data-sw-mlabel]'),vis)[0],lp=lab?parseFloat(getComputedStyle(lab).fontSize):14;
[].forEach.call(document.querySelectorAll('[data-sw-part="rain"]'),function(d){var sv=d.querySelector('svg');if(!vis(d)||!sv)return;
var k=d.offsetHeight/+sv.getAttribute('height'),t=sv.querySelector('text'),fs=t?+t.getAttribute('font-size')*k:0,ch=d.offsetHeight/Math.ceil(sv.querySelectorAll('text').length/3),cw=d.offsetWidth/3;
var tb=[].map.call(sv.querySelectorAll('text'),function(t){var r=t.getBoundingClientRect();r.y0=t.getAttribute('y');return r});tb.forEach(function(a,i){tb.slice(i+1).forEach(function(b){if(a.y0===b.y0&&Math.min(a.right,b.right)-Math.max(a.left,b.left)>-1)bad.push('labels overlap '+[a.left,a.right,b.left,b.right].map(Math.round))})});
if(fs<lp*0.95)bad.push('num '+fs.toFixed(1)+'<label '+lp+' cell '+cw.toFixed(0)+'x'+ch.toFixed(0));if(cw/ch<0.8||cw/ch>2)bad.push('cell '+cw.toFixed(0)+'x'+ch.toFixed(0));if(ch<lp*1.05)bad.push('cellH '+ch.toFixed(0));
var ic=[].filter.call(document.querySelectorAll('[data-sw-unit="rain"] img'),vis)[0],mo=[].filter.call(document.querySelectorAll('[data-sw-part="moon"]'),vis)[0];
if(ic&&mo){var a=ic.getBoundingClientRect(),b=mo.getBoundingClientRect();if(Math.abs(a.width-b.width)>2||Math.abs(a.height-b.height)>2||Math.abs(a.left-b.left)>2)bad.push('icon '+[a.left,a.width,a.height].map(Math.round)+' moon '+[b.left,b.width,b.height].map(Math.round));}
var cl=[].filter.call(document.querySelectorAll('[data-sw-unit="rain"] [data-sw-part="rain"]'),vis)[0];if(ic&&cl){var a=ic.getBoundingClientRect(),b=cl.getBoundingClientRect();if(a.right<=b.left+1&&Math.abs((a.top+a.bottom)/2-(b.top+b.bottom)/2)>2)bad.push('rain icon off the calendar centre '+Math.round((a.top+a.bottom)/2-(b.top+b.bottom)/2));}});
document.querySelectorAll('[data-sw-hub]').forEach(function(h){var sv=h.ownerSVGElement,hb=vis(h);if(!hb)return;var k=hb.width/(2*+h.getAttribute('r')),R=+h.getAttribute('data-sw-hub')*k,cx=hb.left+hb.width/2,cy=hb.top+hb.height/2;
sv.closest('.relative').querySelectorAll('[data-sw-cap]').forEach(function(c){var b=vis(c);if(!b)return;var nx=Math.max(b.left,Math.min(cx,b.right)),ny=Math.max(b.top,Math.min(cy,b.bottom));if(Math.hypot(nx-cx,ny-cy)<R)bad.push('dial caption under hub: '+c.textContent.trim());});});
return bad.join('; ');})()})
      puts "RAINUNIT #{c['name']}: #{ru}" unless ru.empty?
      expect(ru).to eq('')
      # Moon beside the sun rows (owner 2026-11-13: moon data is not that important): the disc at most 0.72 of the two
      # rows (first sun icon top to last sun icon bottom) and centred on them.
      mo = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-unit="sun"]').forEach(function(u){var m=[].filter.call(u.querySelectorAll('[data-sw-part="moon"]'),function(e){return e.getBoundingClientRect().height>0})[0],ic=[].filter.call(u.querySelectorAll('img[data-sw-icon]'),function(e){return e.getBoundingClientRect().height>0});if(!m||ic.length<2||!u.getBoundingClientRect().height)return;
var ci=m.querySelector('circle'),b=ci?ci.getBoundingClientRect():m.getBoundingClientRect(),t=ic[0].getBoundingClientRect().top,bo=ic[ic.length-1].getBoundingClientRect().bottom,r=b.height/(bo-t),dc=(b.top+b.bottom)/2-(t+bo)/2;if(r>0.72||Math.abs(dc)>3)bad.push('moon '+b.height.toFixed(0)+' rows '+(bo-t).toFixed(0)+' dc '+dc.toFixed(1))});return bad.join('; ')})()})
      puts "MOON #{c['name']}: #{mo}" unless mo.empty?
      # 1-bit light (step 18): the moon's lit part sits inside a paper ring, so ring and lit part read apart.
      m1 = s.evaluate(%q{(function(){var sc=document.querySelector('.screen').classList;if(!sc.contains('screen--1bit')||sc.contains('screen--dark-mode'))return '';var bad=[];document.querySelectorAll('[data-sw-moon="lit"]').forEach(function(l){var c=l.ownerSVGElement.querySelector('circle[stroke-width]');if(!c||!l.getBoundingClientRect().width)return;var r=+c.getAttribute('r'),w=+c.getAttribute('stroke-width'),h=l.getBBox().height;if(h>2*(r-w)-1)bad.push('lit '+h.toFixed(1)+' touches the ring r '+r.toFixed(1))});return bad.join('; ')})()})
      puts "MOON1 #{c['name']}: #{m1}" unless m1.empty?
      expect(m1).to eq('')
      expect(mo).to eq('') if c['view'] == 'half_vertical'
      # X quadrant (owner, step 12: big empty bands above and below): the content of each panel (images, drawings,
      # text) leaves no band over 8 % of the panel height at its top or bottom, also none between its rows on X quadrant (step 19: landscape too) and X full portrait, hairlines counting as ink (step 18).
      if (c['view'] == 'quadrant' && (c['device'] || 'v2') == 'v2') || c['portrait_console']
        band = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-panel]').forEach(function(p){var q=p.getBoundingClientRect();if(!q.height)return;var t=1e9,b=-1e9;
var iv=[];p.querySelectorAll('img, svg, span').forEach(function(e){if(e.closest('[data-sw-part="face"]'))return;var r=e.getBoundingClientRect();if(!r.width||!r.height||(e.tagName==='SPAN'&&!e.textContent.trim()))return;t=Math.min(t,r.top);b=Math.max(b,r.bottom);iv.push([r.top,r.bottom])});
var a=(t-q.top)/q.height,z=(q.bottom-b)/q.height;if(a>0.08||z>0.08)bad.push('top '+(a*100).toFixed(0)+'% bottom '+(z*100).toFixed(0)+'%');
if(BETWEEN){p.querySelectorAll('[data-sw-rule]').forEach(function(e){var r=e.getBoundingClientRect();if(r.width&&getComputedStyle(e).display!=='none')iv.push([r.top,Math.max(r.bottom,r.top+1)])});iv.sort(function(x,y){return x[0]-y[0]});var e0=t;iv.forEach(function(v){if((v[0]-e0)/q.height>0.08)bad.push('band '+((v[0]-e0)/q.height*100).toFixed(0)+'% at '+Math.round(e0-q.top));e0=Math.max(e0,v[1]);})}});return bad.join('; ')})()}.sub('BETWEEN', ((c['device'] || 'v2') == 'v2' && (c['view'] == 'quadrant' || (c['view'] == 'full' && c['orientation'] == 'portrait'))).to_s))
        puts "BAND #{c['name']}: #{band}" unless band.empty?
        expect(band).to eq('')
      end
      # OG portrait (owner 2026-11-13, "portrait for the OG is still broken"): a well-filled tall layout, not landscape
      # pieces squeezed. Icons (condition, rain, moon, sun, day-row clothing) have drawn ink at least 0.8 x the cap height
      # of the text beside them; the days scale's track at least 45 % of the day row width with its first and last labels
      # at the track's ends (within a cell); no empty band over 12 % of the panel height inside the console, the days
      # panel or the console's right column (ink measured in the screenshot); low/high digits at least 0.85 x the day name size;
      # quadrant: the temperature digits at least 13 % of the console height.
      if c['orientation'] == 'portrait' && (c['device'] || 'v2') != 'v2' && %w[full half_vertical half_horizontal quadrant].include?(c['view'] || 'full')
        require 'chunky_png'
        og = s.evaluate(%q{(function(){var vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null},cx=document.createElement('canvas').getContext('2d'),R=function(b){return [b.left,b.top,b.right,b.bottom]};
function cap(sp){var b=vis(sp);if(!b)return 0;var cs=getComputedStyle(sp);cx.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;return cx.measureText('H').actualBoundingBoxAscent*(b.width/(sp.offsetWidth||b.width));}
function scap(t){var sv=t.ownerSVGElement,k=sv.getBoundingClientRect().height/(+sv.getAttribute('height')||sv.getBoundingClientRect().height);cx.font='bold '+(+t.getAttribute('font-size'))+'px '+getComputedStyle(t).fontFamily;return cx.measureText('H').actualBoundingBoxAscent*k;}
var ic=[],add=function(n,e,c){var b=vis(e);if(b&&c)ic.push([n].concat(R(b)).concat([c]))};
[].filter.call(document.querySelectorAll('[data-sw-cond]'),vis).forEach(function(sp){add('cond',sp.parentElement.firstElementChild,cap(sp))});
var st=[].filter.call(document.querySelectorAll('[data-sw-suntime] span.title'),vis);
[].filter.call(document.querySelectorAll('[data-sw-unit="sun"] img'),vis).forEach(function(e,i){var t=e.parentElement.querySelector('[data-sw-suntime] span.title');add('sun',e,cap(t||st[0]))});
[].filter.call(document.querySelectorAll('[data-sw-part="moon"]'),vis).forEach(function(e){if(st[0])add('moon',e.querySelector('svg')||e,cap(st[0]))});
var ca=[].filter.call(document.querySelectorAll('[data-sw-part="rain"] svg text'),vis)[0];[].filter.call(document.querySelectorAll('[data-sw-unit="rain"] img'),vis).forEach(function(e){if(ca)add('rain',e,scap(ca))});
[].filter.call(document.querySelectorAll('[data-sw-row="day"]'),vis).forEach(function(r,i){var t=[].filter.call(r.querySelectorAll('span.title'),function(s){return vis(s)&&/\d/.test(s.textContent)})[0];if(!t)return;var c=cap(t);var nm=r.querySelector('[data-sw-dname],[data-sw-today]'),nf=nm?parseFloat(getComputedStyle(nm).fontSize):0,tf=parseFloat(getComputedStyle(t).fontSize);if(nf&&tf<0.85*nf)ic.push(['day'+i+' low/high '+tf+'px under 0.85 x the day name '+nf+'px',0,0,0,0,1]);[].filter.call(r.querySelectorAll('img'),vis).forEach(function(e){add('day'+i+' icon',e,c)});var d=r.querySelector('[data-sw-part="dcue"]');if(vis(d))add('day'+i+' clothing',d,c);});
var tr='',sc=[].filter.call(document.querySelectorAll('[data-sw-part="scale"]'),vis)[0],row=[].filter.call(document.querySelectorAll('[data-sw-row="day"]'),vis)[0];
if(sc&&row){var sv=sc.querySelector('svg'),sb=sv.getBoundingClientRect(),k=sb.width/(+sv.getAttribute('width')||sb.width),g=sv.querySelector('[data-sw-track]'),cw=0;
[].forEach.call(document.querySelectorAll('[data-sw-cells] rect'),function(q){var w=q.getBoundingClientRect().width;if(vis(q))cw=Math.max(cw,w+2)});
var x0,x1;if(g){var v=g.getAttribute('data-sw-track').split(',').map(Number);x0=sb.left+v[0]*k;x1=sb.left+v[1]*k}else{var L=1e9,Rr=-1e9;[].forEach.call(document.querySelectorAll('[data-sw-cells] rect'),function(q){var b=vis(q);if(b){L=Math.min(L,b.left);Rr=Math.max(Rr,b.right)}});x0=L;x1=Rr}
var lb=[].map.call(sv.querySelectorAll('text[data-sw-tick]'),function(t){var b=t.getBoundingClientRect();return (b.left+b.right)/2});
tr=[(x1-x0)/row.getBoundingClientRect().width,lb.length?lb[0]-x0:1e9,lb.length?lb[lb.length-1]-x1:1e9,cw].map(function(v){return v.toFixed(3)}).join(',')}
var pn=[];[].filter.call(document.querySelectorAll('[data-sw-panel]'),vis).forEach(function(p){var q=p.getBoundingClientRect(),t=1e9,b=-1e9;p.querySelectorAll('img, svg, span').forEach(function(e){if(e.closest('[data-sw-part="face"]'))return;var r=vis(e);if(!r||(e.tagName==='SPAN'&&!e.textContent.trim()))return;t=Math.min(t,r.top);b=Math.max(b,r.bottom)});if(b>t)pn.push([p.closest('[data-sw-console]')?'console':'days',q.left+10,t,q.right-10,b,q.height]);
var rt=p.querySelector('[data-sw-right]'),rb=vis(rt);if(rb&&rb.left>q.left+q.width*0.25){var tp=rt.parentElement.getBoundingClientRect();pn.push(['right column',rb.left,tp.top,rb.right,tp.bottom,q.height,1])}});
var tq=vis(document.querySelector('[data-sw-part="temp"] svg')),pq=vis(document.querySelector('[data-sw-console] [data-sw-panel]'));if(QUAD&&tq&&pq&&tq.height<0.13*pq.height)ic.push(['temperature '+tq.height.toFixed(0)+' under 13 % of the console '+pq.height.toFixed(0),0,0,0,0,1]);
if([].filter.call(document.querySelectorAll('[data-sw-part="rain"]'),vis).length&&![].filter.call(document.querySelectorAll('[data-sw-unit="rain"] img'),vis).length)ic.push(['rain icon missing beside the calendar',0,0,0,0,1]);
return JSON.stringify({ic:ic,tr:tr,pn:pn,iw:innerWidth});})()}.sub('QUAD', (c['view'] == 'quadrant').to_s))
        og = JSON.parse(og)
        png = ChunkyPNG::Image.from_file(s.png_path)
        k = png.width / og['iw'].to_f
        dark = ->(x, y, lim) { v = png[x, y]; ChunkyPNG::Color.r(v) + ChunkyPNG::Color.g(v) + ChunkyPNG::Color.b(v) < lim }
        bad = []
        og['ic'].each do |n, l, t, r, b, capv|
          next bad << n if r.zero?
          ys = ((t * k).floor..((b * k).ceil - 1)).select { |y| y < png.height && ((l * k).floor..[(r * k).ceil - 1, png.width - 1].min).any? { |x| dark.(x, y, 384) } }
          ink = ys.empty? ? 0 : (ys.last - ys.first + 1) / k
          bad << "#{n} ink #{ink.round(1)} < 0.8 x cap #{capv.round(1)}" if ink < 0.8 * capv
        end
        unless og['tr'].empty?
          w, f, z, cw = og['tr'].split(',').map(&:to_f)
          bad << "track #{(w * 100).round}% of the row" if w < 0.45
          bad << "scale labels first #{f.round(1)} last #{z.round(1)} from the track ends (cell #{cw.round(1)})" if f.abs > cw || z.abs > cw
        end
        og['pn'].each do |n, l, t, r, b, ph, edges|
          y0 = (t * k).floor; y1 = [(b * k).ceil - 1, png.height - 1].min; xs = ((l * k).ceil..[(r * k).floor - 1, png.width - 1].min)
          ink = (y0..y1).select { |y| xs.any? { |x| dark.(x, y, 600) } }
          next if ink.empty?
          runs = ink.each_cons(2).map { |a, z2| [z2 - a - 1, a] }
          runs += [[ink.first - y0, y0], [y1 - ink.last, ink.last]] if edges
          mx, at = runs.max_by(&:first) || [0, 0]
          bad << "#{n} empty band #{(mx / k / ph * 100).round}% below y #{(at / k).round}" if mx / k > 0.12 * ph
        end
        puts "OGPORT #{c['name']}: #{bad.join('; ')}" unless bad.empty?
        expect(bad).to eq([])
      end
      # Bleed margin (owner 2026-11-12): every panel (borderless: its lit face) and the title bar keep the framework's
      # screen padding from the screen edge.
      edge = s.evaluate(%q{(function(){var sc=document.querySelector('.screen')||document.body,S=sc.getBoundingClientRect(),k=S.width/(sc.offsetWidth||S.width),bad=[],m=8*k;
document.querySelectorAll('[data-sw-panel], .title_bar').forEach(function(e){var b=e.getBoundingClientRect();if(!b.width||!b.height)return;
var d=Math.min(b.left-S.left,b.top-S.top,S.right-b.right,S.bottom-b.bottom);if(d<m)bad.push((e.className.baseVal||e.className||e.tagName).toString().slice(0,30)+' '+d.toFixed(1));});return bad.join('; ');})()})
      puts "EDGE #{c['name']}: #{edge}" unless edge.empty?
      expect(edge).to eq('')
      # 2-bit (owner 2026-11-12): every grey a native level, no dither tiles in the drawn parts.
      if c['palette'] == 'gray-4'
        pat = s.evaluate("document.querySelectorAll('svg pattern').length")
        puts "PATTERN #{c['name']}: #{pat}" unless pat.zero?
        expect(pat).to eq(0)
      end
      # Weather icon (owner 2026-11-12, revised): drawn ink 2.1 to 2.5 x the cap height (owner, step 12: about 2.3x), one line or two, ink centred on the label.
      ci = s.evaluate(%q{(function(){var bad=[],cx=document.createElement('canvas').getContext('2d');document.querySelectorAll('[data-sw-cond]').forEach(function(sp){var sb=sp.getBoundingClientRect();if(!sb.height)return;
var ic=sp.parentElement.firstElementChild,ib=ic.getBoundingClientRect(),k=sb.width/(sp.offsetWidth||sb.width),cs=getComputedStyle(sp);cx.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;var m=cx.measureText('H'),fa=m.fontBoundingBoxAscent*k,fd=m.fontBoundingBoxDescent*k,cap=m.actualBoundingBoxAscent*k;
var rg=document.createRange();rg.selectNodeContents(sp);var lr=[].filter.call(rg.getClientRects(),function(q){return q.width>0}),bl=function(q){return q.top+(q.height-fa-fd)/2+fa},t0=bl(lr[0])-cap,t1=bl(lr[lr.length-1]),n=lr.filter(function(q,i){return i===0||Math.abs(q.top-lr[i-1].top)>2}).length;
var ik=((ic.querySelector('[data-sw-ink]')||ic).getAttribute('data-sw-ink')||'0,1').split(',').map(Number),it=ib.top+ik[0]*ib.height,ih=ik[1]*ib.height,h=n>1?t1-t0+cap:cap,mid=n>1?(t0+t1)/2:t0+cap/2,q=ih/h;if(n>2)bad.push('label on '+n+' lines');if(n>1&&(q=ih/cap,0))0;if(n>1?(q<(ic.hasAttribute('data-sw-clamped')?1.6:2.1)||q>2.5):(q<(ic.hasAttribute('data-sw-clamped')?1.6:2.1)||q>2.5))bad.push('icon ink '+ih.toFixed(1)+' / cap '+(n>1?cap:h).toFixed(1)+' = '+q.toFixed(2)+' ('+n+' lines)');if(Math.abs(it+ih/2-mid)>1.5)bad.push('icon ink centre off '+(it+ih/2-mid).toFixed(1));});return bad.join('; ');})()})
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
      # Pollen (owner 2026-11-12): a pollen meter row is shown only when it lights at least one cell.
      po = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part="meter"][data-sw-key="pollen"]').forEach(function(m){if(!m.getBoundingClientRect().width)return;var l=m.querySelector('[data-sw-lit]');if(!l||!(+l.getAttribute('data-sw-lit')>0))bad.push('pollen 0 cells');});return bad.join('; ');})()})
      puts "POLLEN #{c['name']}: #{po}" unless po.empty?
      expect(po).to eq('')
      # Indoor sensor (as live): with a reading, BUITEN and BINNEN twin readouts side by side (digits drawn, no overlap,
      # the humidity under BINNEN, no felt line under BUITEN, owner 2026-11-13), and the temperature dial (when shown) carries the twin needle; without one, none of it.
      sn = s.evaluate(%q{(function(){var vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null},bad=[];
var tw=[].filter.call(document.querySelectorAll('[data-sw-twin="out"],[data-sw-twin="in"]'),vis),nd=[].filter.call(document.querySelectorAll('svg [data-sw-twin="1"] polygon'),function(l){return vis(l.ownerSVGElement)&&!l.closest('[data-sw-glow]')});
if(tw.length){if(tw.length!==2)bad.push('twins '+tw.length);else{var a=tw[0].getBoundingClientRect(),b=tw[1].getBoundingClientRect();if(a.right>b.left+1)bad.push('twins overlap');
tw.forEach(function(t){var k=t.getAttribute('data-sw-twin'),d=t.querySelector('[data-sw-part="temp"] svg,[data-sw-part="itemp"] svg'),sp=t.querySelectorAll(':scope > span'),lc=t.querySelector('[data-sw-part="loc"]'),lb=lc&&lc.querySelector('svg path')&&vis(lc);if(!d||!vis(d)||!d.querySelector('path,rect,polygon'))bad.push(k+' no digits');if(!lb)bad.push(k+' no location icon');else{var db=d.getBoundingClientRect(),cb=lc.getBoundingClientRect(),cc=(cb.left+cb.right)/2;if(cc<db.left||cc>db.right)bad.push(k+' icon centre '+cc.toFixed(0)+' outside its digits '+db.left.toFixed(0)+'-'+db.right.toFixed(0));if(Math.abs(cc-(db.left+db.right)/2)>db.width*0.15)bad.push(k+' icon not centred over its digits');}if(k==='out'&&sp[0]&&sp[0].textContent.trim())bad.push('line under BUITEN '+sp[0].textContent.trim());});}}
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
var gk=el.querySelector('[data-sw-k]');if(gk&&+gk.getAttribute('data-sw-r')>=2*+gk.getAttribute('data-sw-k')&&cs.length<2)bad.push('one slab row '+el.getAttribute('data-sw-i'));
[].forEach.call(cs,function(q){var w=q.getBoundingClientRect().width;if(w<4)bad.push('cell under 4 px row '+el.getAttribute('data-sw-i')+' '+w.toFixed(1));});   // step 18: OG half vertical portrait drew 1 px slats
var R=[].map.call(cs,function(q){return[+q.getAttribute('x'),+q.getAttribute('x')+ +q.getAttribute('width')]}),wd=R.map(function(q){return q[1]-q[0]}).sort(function(a,b){return a-b}),md=wd[wd.length>>1];if(R.length>1&&wd[0]<md/2-0.5)bad.push('sliver row '+el.getAttribute('data-sw-i')+' '+wd[0].toFixed(1));
if(nl){var x0=+nl.getAttribute('x'),x1=x0+ +nl.getAttribute('width');R.forEach(function(q){if((Math.abs(q[0]-x1)<0.9||Math.abs(q[1]-x0)<0.9||(q[0]>x0-0.9&&q[0]<x1+0.9)||(q[1]>x0-0.9&&q[1]<x1+0.9)))bad.push('edge at the now line row '+el.getAttribute('data-sw-i'));});}
var r=[].map.call(cs,function(q){return[+q.getAttribute('x'),+q.getAttribute('x')+ +q.getAttribute('width')]}).sort(function(a,b){return a[0]-b[0]});for(var i=1;i<r.length;i++)if(r[i][0]-r[i-1][1]<1.9){bad.push('cells merge row '+el.getAttribute('data-sw-i')+' gap '+(r[i][0]-r[i-1][1]).toFixed(1));break;}});
document.querySelectorAll('[data-sw-part="scale"]').forEach(function(el){if(!vis(el))return;var nl=el.querySelector('[data-sw-now]'),ax=el.querySelector('[data-sw-axis]');if(!nl)return;
if(ax&&(ax.compareDocumentPosition(nl)&Node.DOCUMENT_POSITION_FOLLOWING)===0)bad.push('now line under the labels');var pt=el.querySelector('polygon');var pb=vis(pt);
if(pb)el.querySelectorAll('text').forEach(function(t){var b=t.getBoundingClientRect(),k=el.getBoundingClientRect().height/(+el.querySelector('svg').getAttribute('height')||1),cy=(b.top+b.bottom)/2,hc=+t.getAttribute('font-size')*k*0.36;if(b.width&&pb.left<b.right-1&&pb.right>b.left+1&&pb.bottom>cy-hc+0.5)bad.push('pointer over '+t.textContent);});});
return bad.join('; ');})()})
      puts "DAYS #{c['name']}: #{ds}" unless ds.empty?
      puts "DAYSTRIP #{c['name']}: #{ds}" unless ds.empty?
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
      # no now line, no grid or row lines in the days strip; the clothing cue in the console.
      cm = s.evaluate(%q{(function(){var vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0},n=function(q){return [].filter.call(document.querySelectorAll(q),vis).length};
var dial=n('[data-sw-part="baro"]');return [1,dial,n('[data-sw-part="baro"] ~ .label--inverted, [data-sw-part="tdial"] ~ .label--inverted'),n('[data-sw-trend]'),n('[data-sw-mark]'),document.querySelectorAll('[data-sw-now]').length,document.querySelectorAll('[data-sw-part="day"] rect[data-sw-tick]').length,n('[data-sw-hair="row"]'),n('[data-sw-part="cue"] svg'),SW.cue&&SW.cue.length?1:0,SW.baro.trend?1:0].join(',');})()})
      puts "CALM #{c['name']}: calm,dial,badges,trend,marks,now,grid,hair,cue,wantcue #{cm}"
      q = cm.split(',').map(&:to_i)
      begin
        expect(q[0]).to eq(1)
        expect(q[2]).to eq(0)
        expect(q[3]).to eq(0)   # owner 2026-11-13: no trend word on the dial (the pressure shows; the trend is the arrow)
        expect(q[4]).to eq(q[1] * 2)
        expect(q[5..7]).to eq([0, 0, 0])
        expect(q[8].positive?).to eq(q[9] == 1 && s.evaluate("document.querySelectorAll('[data-sw-cueout]').length").zero? && !(c['view'] == 'half_vertical' && c['device'] != 'v2' && c['orientation'] != 'portrait'))   # step 18 (owner via coordinator): OG half_vertical portrait has room, the badge shows there   # owner 2026-11-13: beside the temperature, X half_vertical too; left out on OG half_vertical (owner 2026-11-13, too narrow) ; X half_vertical portrait shows it again (step 19, coordinator: owner rule, badge beside the temperature in every view; the OG hv portrait layout as the model)
      end
      # Calm (owner): 1-bit and 2-bit panels stay paper (no grey fill); the dial's low/high numbers clear their triangles by 2 px
      # and are at least the size of the dial's scale numbers.
      begin
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
      # Day rows (owner step 17): one name column width, so the icons line up in every row, the name never reaches its icon
      # (the inverted today label included; its text measured too, and never clipped by its box: step 19, x-port-hv) and all rows are the same height.
      al = s.evaluate(%q{(function(){var bad=[],L=[],H=[];[].forEach.call(document.querySelectorAll('[data-sw-row="day"]'),function(e){var q=e.getBoundingClientRect();if(!q.height)return;H.push(q.height);var lo=[].filter.call(e.querySelectorAll('span.title:not([data-sw-dname])'),function(x){return x.getBoundingClientRect().width>0})[0],im=[].filter.call(e.querySelectorAll('img'),function(x){return x.getBoundingClientRect().width>0})[0],nm=e.querySelector('[data-sw-today],[data-sw-dname]');if(nm&&lo&&nm.getBoundingClientRect().right>lo.getBoundingClientRect().left-6)bad.push('name '+nm.textContent.trim()+' reaches its low');if(nm){var r0=document.createRange();r0.selectNodeContents(nm);var tb=r0.getBoundingClientRect(),nb=nm.getBoundingClientRect();if(tb.width&&(tb.right>nb.right+0.5||tb.left<nb.left-0.5))bad.push('name '+nm.textContent.trim()+' runs past its label');}if(!im||!nm)return;var a=im.getBoundingClientRect(),b=nm.getBoundingClientRect(),rg=document.createRange();rg.selectNodeContents(nm);var rr=rg.getBoundingClientRect();if(rr.width&&rr.right>b.right)b=rr;L.push(a.left);if(b.right>a.left-3)bad.push('name '+nm.textContent.trim()+' reaches its icon');});
if(L.length&&Math.max.apply(null,L)-Math.min.apply(null,L)>1)bad.push('icon lefts '+L.map(Math.round));if(H.length&&Math.max.apply(null,H)-Math.min.apply(null,H)>1)bad.push('row heights '+H.map(Math.round));return bad.join('; ')})()})
      # Rain calendar cells are rectangles with the meter cells' corner radius (owner step 17), in rendered pixels.
      rx = s.evaluate(%q{(function(){var cal=[].filter.call(document.querySelectorAll('[data-sw-part="rain"] svg rect[rx]'),function(r){return r.getBoundingClientRect().width>0})[0],mc=[].filter.call(document.querySelectorAll('[data-sw-part="meter"] svg rect[rx]'),function(r){return r.getBoundingClientRect().width>0})[0];if(!cal||!mc)return '';
var px=function(r){var sv=r.ownerSVGElement;return +r.getAttribute('rx')*sv.getBoundingClientRect().height/+sv.getAttribute('height')};var a=px(cal),b=px(mc);return Math.abs(a-b)>0.6?'calendar rx '+a.toFixed(1)+' meter rx '+b.toFixed(1):''})()})
      puts "RAINRX #{c['name']}: #{rx}" unless rx.empty?
      expect(rx).to eq('')
      # Day names on one left edge, and a bar under its name sits closer to that name than to the next day (owner
      # 2026-11-13, OG half vertical portrait: names shifted, bars floating between rows).
      dn = s.evaluate(%q{(function(){var tb=function(n){var g=document.createRange();g.selectNodeContents(n);return n.hasAttribute('data-sw-today')?n.getBoundingClientRect():g.getBoundingClientRect()};var L=[],bad=[],R=[].filter.call(document.querySelectorAll('[data-sw-row="day"]'),function(r){return r.getBoundingClientRect().height>0});R.forEach(function(r){var n=r.querySelector('[data-sw-today],[data-sw-dname]');if(n)L.push(tb(n).left)});if(L.length&&Math.max.apply(null,L)-Math.min.apply(null,L)>2)bad.push('name lefts '+L.map(Math.round));R.forEach(function(r,i){var n=r.querySelector('[data-sw-today],[data-sw-dname]'),b=r.querySelector('[data-sw-part="day"]'),nx=R[i+1]&&R[i+1].querySelector('[data-sw-today],[data-sw-dname]');if(!n||!b||!nx)return;var nb=tb(n),bb=b.getBoundingClientRect(),xb=tb(nx);if(bb.top>=nb.bottom-1&&bb.top-nb.bottom>xb.top-bb.bottom-3)bad.push('bar '+i+' nearer the next day ('+Math.round(bb.top-nb.bottom)+' vs '+Math.round(xb.top-bb.bottom)+')')});return bad.join('; ')})()})
      puts "DAYNAME #{c['name']}: #{dn}" unless dn.empty?
      expect(dn).to eq('')
      # Rain calendar (owner 2026-11-13): a third row only when it holds a wet hour.
      r3 = s.evaluate(%q{(function(){var sv=[].filter.call(document.querySelectorAll('[data-sw-part="rain"] svg'),function(v){return v.getBoundingClientRect().width>0})[0];if(!sv)return '';var ys={};[].forEach.call(sv.querySelectorAll('text'),function(t){var y=t.getAttribute('y');ys[y]=ys[y]||[];ys[y].push(!!t.closest('.text--white'))});var k=Object.keys(ys).sort(function(a,b){return a-b});if(k.length<3)return '';return ys[k[k.length-1]].some(Boolean)?'':k.length+' rows, last dry'})()})
      puts "RAIN3 #{c['name']}: #{r3}" unless r3.empty?
      expect(r3).to eq('')
      puts "DAYALIGN #{c['name']}: #{al}" unless al.empty?
      expect(al).to eq('')
      d = dr.split(',').map(&:to_f)
      expect(d[0]).to eq(0) if c['view'] == 'quadrant'
      expect(d[1]).to be >= (c['device'] == 'v2' ? 53 : 28) if d[0].positive?
      expect([d[3], d[4]]).to eq(d[0].positive? ? [1, 1] : [0, 0])
      expect(d[5]).to eq(1)
      # Felt temperature (owner decision 2026-11-13): no felt readout anywhere (no felt digits, no felt word, no person
      # icon); the felt temperature only drives the clothing badge.
      fi = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null};if(document.querySelector('[data-sw-part="person"]'))bad.push('person icon');
[].forEach.call(document.querySelectorAll('[data-sw-part="feels"],[data-sw-feltlabel],[data-sw-felt]'),function(e){if(vis(e))bad.push('felt readout '+(e.getAttribute('data-sw-part')||'label'));});
[].forEach.call(document.querySelectorAll('span,div'),function(e){if(e.children.length||!vis(e))return;var t=e.textContent;if(t.indexOf('GEVOEL')>=0||/(^| )(VOELT|FEELS)( |$)/i.test(t))bad.push('felt text '+t.trim());});
return bad.join('; ');})()})
      puts "FEELS #{c['name']}: #{fi}" unless fi.empty?
      expect(fi).to eq('')
      # Rain gauge (owner 2026-11-13, replaces the REGEN meter row): no REGEN meter anywhere; a visible gauge has as many lit
      # segments as the transform says (of 5) and its amount label; none without a calendar or an amount; on the X full view
      # (room beside the calendar) a wet case with an amount shows it; it stays inside its rain unit.
      rg0 = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e.getBoundingClientRect();return b.width>0&&b.height>0},G=SW.rain&&SW.rain.gauge;
document.querySelectorAll('[data-sw-key="regen"]').forEach(function(e){if(vis(e))bad.push('REGEN meter row');});
var gs=[].filter.call(document.querySelectorAll('[data-sw-part="gauge"]'),vis);
if(gs.length&&!G)bad.push('gauge without data');
gs.forEach(function(e){var m=e.querySelector('[data-sw-gauge]'),lit=Object.keys([].reduce.call(e.querySelectorAll('[data-sw-st="a"] rect'),function(o,r){o[r.getAttribute('data-sw-c')]=1;return o},{})).length,t=e.querySelector('[data-sw-glabel]'),u=e.closest('[data-sw-unit]').getBoundingClientRect(),b=e.getBoundingClientRect();
if(!m||+m.getAttribute('data-sw-gauge')!==G.segs||lit!==G.segs||Object.keys([].reduce.call(e.querySelectorAll('[data-sw-c]'),function(o,r){o[r.getAttribute('data-sw-c')]=1;return o},{})).length!==5)bad.push('gauge segments '+lit+' want '+(G&&G.segs));
if(!t||t.textContent!==G.label)bad.push('gauge label');if(b.right>u.right+0.5||b.left<u.left)bad.push('gauge outside the rain unit');});
if(G&&!gs.length&&INNER_X_FULL)bad.push('no gauge on a wet X full case');
return bad.join('; ')})()}.sub('INNER_X_FULL', (c['device'] == 'v2' && (c['view'] || 'full') == 'full' && !c['orientation'] && !c['fixture']) ? 'true' : 'false'))
      expect(rg0).to eq('')
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
[st,cl.querySelector('[data-sw-htemp]')].filter(Boolean).forEach(function(e){var b=e.getBoundingClientRect();if(Math.abs((b.left+b.right)/2-mid)>2*k)bad.push('off '+i+' '+e.tagName);});});
var L=cols.map(function(cl){return +(cl.querySelector('[data-sw-cells]')||{getAttribute:function(){return 0}}).getAttribute('data-sw-cells')}),T=cols.map(function(cl){return SW.hours[+cl.getAttribute('data-sw-hcol')].tV});
var ib=cols.map(function(cl){var e=[].filter.call(cl.querySelectorAll('img, [data-sw-part="icon"] svg'),vis)[0];return e?e.getBoundingClientRect().top:null}).filter(function(v){return v!==null});
if(ib.length&&Math.max.apply(null,ib)-Math.min.apply(null,ib)>1)bad.push('icon row spread '+(Math.max.apply(null,ib)-Math.min.apply(null,ib)).toFixed(1));
cols.forEach(function(cl){var i=+cl.getAttribute('data-sw-hcol'),q=SW.hours[i],tx=cl.querySelector('[data-sw-htemp]'),rs=cl.querySelectorAll('[data-sw-cells] rect');if(q.tV===null||q.tV===undefined)return;if(!tx||!rs.length){bad.push('no label '+i);return}
var top=Math.min.apply(null,[].map.call(rs,function(r){return r.getBoundingClientRect().top})),tb=tx.getBoundingClientRect(),ic=[].filter.call(cl.querySelectorAll('img'),vis)[0],k=cl.getBoundingClientRect().width/(cl.offsetWidth||1),gap=top-tb.bottom;
if(gap<-1*k||gap>8*k)bad.push('label '+i+' gap '+gap.toFixed(1)+' above its stack');if(ic&&tb.top<ic.getBoundingClientRect().bottom-1)bad.push('label '+i+' into the icon row');});
for(var a=0;a<cols.length;a++)for(var b=0;b<cols.length;b++)if(T[a]!==null&&T[b]!==null&&T[a]>T[b]+1.5&&L[a]<L[b])bad.push('scale '+a+'<'+b);
return cols.length+'|'+bad.join('; ');})()})
      puts "HOURS #{c['name']}: cols|bad #{hs}" if c['hcols'] || hs != '0|'
      expect(hs).to eq("#{c['hcols'] || 0}|")
      # Hours curve (owner 2026-11-13, live OG 1-bit: 4..6 drew one block everywhere): distinct (whole) temperatures of the shown
      # columns get distinct block counts where the strip has room for a block per degree, a warmer column never fewer blocks, and the warmest column's stack fills at
      # least 80 % of the block area.
      hc = s.evaluate(%q{(function(){var bad=[],cs=[].filter.call(document.querySelectorAll('[data-sw-part="hbar"]'),function(e){return e.getBoundingClientRect().height>0});if(!cs.length)return '';
var v=cs.map(function(e){var q=(SW.hours||[])[+e.getAttribute('data-sw-i')]||{},g=e.querySelector('[data-sw-cells]');return {t:q.tV,n:g?+g.getAttribute('data-sw-cells'):0,e:e,g:g}}).filter(function(o){return o.t!==null&&o.t!==undefined});
var C0=Math.min.apply(null,cs.map(function(e){return e.getBoundingClientRect().height})),rt=v.map(function(o){return Math.round(o.t)}),room=Math.max.apply(null,rt)-Math.min.apply(null,rt)+1<=6;   // a block per degree up to 6 blocks high (owner 2026-11-13)
v.forEach(function(a){v.forEach(function(b){if(Math.round(a.t)<Math.round(b.t)&&(a.n>b.n||(room&&a.n>=b.n)))bad.push(a.t+':'+a.n+' vs '+b.t+':'+b.n);});});
v.forEach(function(o){if(o.n<1)bad.push(o.t+': no block');var P=o.e.closest('[data-sw-panel]'),pb=P&&P.getBoundingClientRect();if(pb&&o.g)[].forEach.call(o.g.querySelectorAll('rect'),function(x){if(x.getBoundingClientRect().bottom>pb.bottom+0.5)bad.push(o.t+': block past the panel')});});   // owner 2026-11-13, live X hv dark
var top=v.reduce(function(m,o){return o.t>m.t?o:m},v[0]);if(top&&top.g){var C=+top.g.getAttribute('data-sw-area'),r=[].map.call(top.g.querySelectorAll('rect'),function(x){return x.getBoundingClientRect()}),h=r.length?Math.max.apply(null,r.map(function(x){return x.bottom}))-Math.min.apply(null,r.map(function(x){return x.top})):0;if(h<0.8*C-8)bad.push('warmest stack '+h.toFixed(0)+' of '+C.toFixed(0));}
return bad.slice(0,4).join('; ');})()})
      puts "HCURVE #{c['name']}: #{hc}" unless hc.empty?
      # 1-bit (owner 2026-11-13): block parts (hours and days strip blocks, meter cells) solid ink, no grey (dithered) fill.
      sb = s.evaluate(%q{(function(){if(!(document.querySelector('.screen')||document.body).classList.contains('screen--1bit'))return '';var bad=[];document.querySelectorAll('[data-sw-part="hbar"] g, [data-sw-part="day"] [data-sw-cells] g, [data-sw-part="meter"] g').forEach(function(e){if(!/text--gray-/.test(e.getAttribute('class')||'')||!e.querySelector('rect,path')||e.closest('[data-sw-st="p"]'))return;   // cells reached earlier today: the Framework's lighter grey (owner 2026-11-13)
var b=e.getBoundingClientRect();if(b.width>0&&getComputedStyle(e).display!=='none')bad.push(e.closest('[data-sw-part]').getAttribute('data-sw-part')+' '+e.getAttribute('class'));});return bad.slice(0,3).join('; ');})()})
      puts "SOLID1 #{c['name']}: #{sb}" unless sb.empty?
      # Meter states (owner 2026-11-13): every cell drawn in exactly the state the model gives (a now, p reached earlier
      # today, l expected later today, e empty) and one thick outline at today's peak; active cells in full ink, earlier
      # cells filled grey, later cells a dashed outline.
      mr = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part="meter"]').forEach(function(e){if(!e.getBoundingClientRect().width)return;var m=SW.meters[+e.getAttribute('data-sw-i')||0],lt=e.querySelector('[data-sw-lit]');if(!m||!lt)return;var n=+lt.getAttribute('data-sw-ncell'),W=SWDraw.cellStates(m,n),got=[];
var ir=e.querySelector('[data-sw-twrow]');if(!!ir!==!!m.tw)bad.push(m.key+' twin set '+!!ir+'/'+!!m.tw);if(ir){var wi=SWDraw.cellStates(m.tw.m,n).st.filter(function(x){return x==='a'}).length,gi=ir.querySelectorAll('[data-sw-on] rect[data-sw-c]').length;if(wi!==gi)bad.push(m.key+' indoor lit '+gi+'/'+wi);if(!ir.querySelector('[data-sw-on] g.text--gray-50,[data-sw-on] g[fill]'))bad.push(m.key+' indoor set not grey');}
e.querySelectorAll('rect[data-sw-c]').forEach(function(r){if(r.closest('[data-sw-twrow]'))return;var i=+r.getAttribute('data-sw-c'),st=r.closest('[data-sw-st]');var sv=st?st.getAttribute('data-sw-st'):'?';if((got[i]||'').indexOf(sv)<0)got[i]=(got[i]||'')+sv;if(st&&st.getAttribute('data-sw-st')==='l'&&!r.getAttribute('stroke-dasharray')&&r.getAttribute('fill')==='none')bad.push(m.key+' later cell neither filled nor dashed');if(st&&st.getAttribute('data-sw-st')==='p'&&r.getAttribute('fill')==='none')bad.push(m.key+' earlier cell not filled');});
var gs=[];for(var i=0;i<n;i++)gs.push(got[i]||'-');if(gs.join('')!==W.st.join(''))bad.push(m.key+' states '+gs.join('')+'/'+W.st.join(''));
var pk=[].map.call(e.querySelectorAll('[data-sw-gust]'),function(r){return +r.getAttribute('data-sw-gust')});if(pk.join(',')!==(W.peak>=0&&W.st[W.peak]==='e'?String(W.peak):''))bad.push(m.key+' peak '+pk.join(',')+'/'+W.peak);
var on=e.querySelector('[data-sw-on]');var dg=on&&on.querySelector(':scope > [data-sw-dg]');if(!on||(!dg&&(on.hasAttribute('fill')||on.querySelector(':scope > g[fill]'))))bad.push(m.key+' current cells light grey');});return bad.join('; ');})()})
      puts "MRANGE #{c['name']}: #{mr}" unless mr.empty?
      # Every visible meter has the same block left edge, right edge and width (the twin meter's legend icons sit in a reserved right column), and each legend icon is level with its block row.
      ml = s.evaluate(%q{(function(){var bad=[],xs=[],ys=[];document.querySelectorAll('[data-sw-part="meter"]').forEach(function(e){if(!e.getBoundingClientRect().width)return;var l=1e9,rr=-1e9;[].forEach.call(e.querySelectorAll('rect[data-sw-c]'),function(r){var q=r.getBoundingClientRect();l=Math.min(l,q.left);rr=Math.max(rr,q.right)});if(l<1e9){xs.push(l);ys.push(rr)}});var sp=function(a){return Math.max.apply(null,a)-Math.min.apply(null,a)};if(xs.length&&sp(xs)>1.5)bad.push('block left edges '+xs.map(Math.round).join(','));if(ys.length&&sp(ys)>1.5)bad.push('block right edges '+ys.map(Math.round).join(','));if(xs.length&&sp(xs.map(function(x,i){return ys[i]-x}))>1.5)bad.push('block widths '+xs.map(function(x,i){return Math.round(ys[i]-x)}).join(','));
[].filter.call(document.querySelectorAll('[data-sw-for]'),function(e){return e.getBoundingClientRect().width>0}).forEach(function(ic){var m=[].filter.call(document.querySelectorAll('[data-sw-part="meter"][data-sw-key="'+ic.getAttribute('data-sw-for')+'"]'),function(q){return q.getBoundingClientRect().width>0})[0];if(!m){bad.push('icon without meter');return}var ind=ic.getAttribute('data-sw-i')==='1',rs=[].filter.call(m.querySelectorAll('rect[data-sw-c]'),function(r){return !!r.closest('[data-sw-twrow]')===ind});if(!rs.length){bad.push('icon row without blocks');return}var b=rs[0].getBoundingClientRect(),q=ic.getBoundingClientRect();if(Math.abs((b.top+b.bottom)/2-(q.top+q.bottom)/2)>4)bad.push('icon '+(ind?'in':'out')+' not level with its block row '+((q.top+q.bottom)/2-(b.top+b.bottom)/2).toFixed(1));if(!ic.querySelector('svg path'))bad.push('legend icon not drawn')});return bad.join('; ')})()})
      puts "MLEFT #{c['name']}: #{ml}" unless ml.empty?
      expect(ml).to eq('')
      expect(mr).to eq('')
      expect(sb).to eq('')
      expect(hc).to eq('')
      # Clothing badge (owner): the drawn icons are the model's list (top and up to two extras) in order; one fixed box
      # width on every day row (1 px; the console has its own, larger box); the extras sit right of the top icon, never over its box.
      co = s.evaluate(%q{(function(){var vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0},bad=[],ws=[];
var IT={parka:['top'],jacket:['top'],sweater:['top'],tshirt:['top'],umbrella:['umbrella'],mittens:['mittenL','mittenR'],sunglasses:['glasses'],beanie:['beanie'],scarf:['scarf'],shorts:['shorts']};
function chk(e,want,tag){var cl=e.querySelector('g[data-sw-cloth]'),exp=[].concat.apply([],want.map(function(k){return IT[k]||[]})).sort().join('+'),its=[].slice.call(e.querySelectorAll('g[data-sw-item]')),got=its.map(function(g){return g.getAttribute('data-sw-item')}).sort().join('+');if(got!==exp)bad.push(tag+' parts '+got+'/'+exp);
ws.push(e.getBoundingClientRect().width);var E=e.getBoundingClientRect(),sv=cl&&cl.closest('svg'),T=sv&&sv.getBoundingClientRect();its.forEach(function(g){var b=g.getBoundingClientRect();if(!b.width)return;if((tag==='console'&&(b.left<E.left-1||b.right>E.right+1||b.top<E.top-1||b.bottom>E.bottom+1))||b.left<T.left-1||b.right>T.right+1||b.top<T.top-1||b.bottom>T.bottom+1)bad.push(tag+' '+g.getAttribute('data-sw-item')+' overflows its box')});}
var cn=0;[].filter.call(document.querySelectorAll('[data-sw-part="cue"]'),vis).forEach(function(e){cn++;chk(e,SW.cue||[],'console');});ws=[];   // the console badge has its own box (owner); the day rows share one width
var rows=[].filter.call(document.querySelectorAll('[data-sw-row="day"]'),vis),n=0;rows.forEach(function(r){var ds=[].filter.call(r.querySelectorAll('[data-sw-part="dcue"]'),vis);if(!ds.length)return;n++;if(ds.length>1)bad.push('badges '+ds.length);var i=+ds[0].getAttribute('data-sw-i');chk(ds[0],SW.days[i].cue||[],'day '+i);});
if(n&&n!==rows.length)bad.push('rows '+n+'/'+rows.length);if(ws.length&&Math.max.apply(null,ws)-Math.min.apply(null,ws)>1)bad.push('widths '+ws.map(Math.round).join(','));return cn+','+n+'|'+bad.join('; ');})()})
      puts "CLOTH #{c['name']}: console,dayrows|bad #{co}"
      expect(co.split('|', 2)[1]).to eq('')
      expect(co.split(',')[1].to_i).to be_positive if (c['view'] || 'full') == 'full' && (c['fields'] || {})['bottom'] != 'hours'
      # Portrait day rows and console (owner, step 19 on x-port-hv; OG half vertical portrait the model): the console badge
      # beside the temperature, every day row keeps its low and high, the header its two markers, and the scale labels
      # no larger than 1.3 x the low/high digits.
      if c['orientation'] == 'portrait'
        pr = s.evaluate(%q{(function(){var vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0},bad=[],fs=function(e){return parseFloat(getComputedStyle(e).fontSize)*(e.getBoundingClientRect().width/(e.offsetWidth||1))};
if(SW.cue&&SW.cue.length&&![].some.call(document.querySelectorAll('[data-sw-part="cue"]'),vis))bad.push('no console badge');
var rows=[].filter.call(document.querySelectorAll('[data-sw-row="day"]'),vis),lf=0;rows.forEach(function(r){var n=[].filter.call(r.querySelectorAll('span.title:not([data-sw-dname])'),vis);if(n.length<2)bad.push('row '+r.textContent.trim().split(/\s+/)[0]+' without low/high');else lf=fs(n[0]);});
if(rows.length){var tr=[].filter.call(document.querySelectorAll('[data-sw-part="tri"]'),vis).length;if(tr!==2)bad.push('markers '+tr);
var sv=[].filter.call(document.querySelectorAll('[data-sw-part="scale"] svg'),vis)[0];if(sv&&lf){var k=sv.getBoundingClientRect().height/(+sv.getAttribute('height')||1);[].forEach.call(sv.querySelectorAll('text'),function(t){var f=+t.getAttribute('font-size')*k;if(f>lf*1.3)bad.push('scale label '+f.toFixed(0)+' px over low/high '+lf.toFixed(0));});}}
return bad.filter(function(x,i,a){return a.indexOf(x)===i}).join('; ');})()})
        puts "PORT #{c['name']}: #{pr}" unless pr.empty?
        expect(pr).to eq('')
      end
      # Dividers (owner 2026-11-12, step 12): no ink (shapes, icons, glyphs) within 0.75 of the row gap of a vertical
      # divider in a panel; the clothing badge, meters and digits keep the normal gap.
      dg = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e.getBoundingClientRect();return b.height>0?b:null};
[].forEach.call(document.querySelectorAll('[data-sw-panel] [data-sw-rule], [data-sw-panel] [data-sw-div]'),function(rl){var R=vis(rl);if(!R||R.width>4||R.height<R.width)return;
var pn=rl.closest('[data-sw-panel]'),k=R.height/(rl.offsetHeight||R.height),g=parseFloat(getComputedStyle(rl.parentElement).columnGap)||0;g=(g||16)*k*0.75;var x=(R.left+R.right)/2;
var ink=[].slice.call(pn.querySelectorAll('svg path, svg rect, svg circle, svg ellipse, svg line, svg polyline, svg polygon, svg text, img'));
[].forEach.call(pn.querySelectorAll('span'),function(sp){if(sp.children.length)return;var rg=document.createRange();rg.selectNodeContents(sp);[].forEach.call(rg.getClientRects(),function(q){if(q.width>0)ink.push({q:q,t:'text '+sp.textContent.trim().slice(0,8)})});});
ink.forEach(function(e){if(e.closest&&e.closest('[data-sw-part="face"]'))return;var b=e.q||e.getBoundingClientRect();if(!b.width||!b.height)return;
if(e.getAttribute&&e.tagName!=='IMG'){var cs=getComputedStyle(e);if((cs.fill==='none'||cs.fillOpacity==='0')&&cs.stroke==='none')return;if(cs.visibility==='hidden'||cs.opacity==='0')return;}
if(b.bottom<=R.top||b.top>=R.bottom)return;var d=b.left>x?b.left-x:(b.right<x?x-b.right:-1);
if(d<g){var p=e.t||((e.closest('[data-sw-part]')||{getAttribute:function(){return e.tagName}}).getAttribute('data-sw-part')+'/'+e.tagName);bad.push(p+' '+d.toFixed(1)+'<'+g.toFixed(1)+' @'+x.toFixed(0));}});});
var u=[];bad.forEach(function(s){if(u.indexOf(s)<0)u.push(s)});return u.slice(0,8).join('; ');})()})
      # Mittens (owner 2026-11-13): the two mittens never touch, at least 1 px of paper between them at every size.
      mt = s.evaluate(%q{(function(){var bad=[],R=function(g){return g.getBoundingClientRect()},gap=function(a,b){return Math.max(a.left-b.right,b.left-a.right,a.top-b.bottom,b.top-a.bottom)};document.querySelectorAll('g[data-sw-cloth]').forEach(function(c){var L=c.querySelector('[data-sw-item="mittenL"]'),M=c.querySelector('[data-sw-item="mittenR"]');if(!L||!M||!R(L).width)return;[[L,M,'L/R']].forEach(function(p){var g=gap(R(p[0]),R(p[1]));if(g<0.9)bad.push('paper '+g.toFixed(2)+' px '+p[2]+' at '+R(c).height.toFixed(0)+' px')})});return bad.slice(0,3).join('; ')})()})
      puts "MITTENS #{c['name']}: #{mt}" unless mt.empty?
      expect(mt).to eq('')
      # Console hairline (owner 2026-11-12, step 12): the same gap above (to the lowest ink of the top part) and below
      # (to the meters' first ink), at least half the column gap each.
      hg = s.evaluate(%q{(function(){var h=[].filter.call(document.querySelectorAll('[data-sw-hair="console"]'),function(e){return e.getBoundingClientRect().height>0||e.getBoundingClientRect().width>0})[0];if(!h)return'';
var w=h.parentElement,up=w.previousElementSibling,dn=w.nextElementSibling;if(!up||!dn)return'';var H=h.getBoundingClientRect();
function ink(root,lo){var v=lo?-1e9:1e9;[].forEach.call(root.querySelectorAll('svg path, svg rect, svg circle, svg text, svg polygon, img, span'),function(e){if(e.tagName==='SPAN'&&e.children.length)return;var b=e.getBoundingClientRect();if(!b.width||!b.height)return;v=lo?Math.max(v,b.bottom):Math.min(v,b.top)});return v}
var a=H.top-ink(up,true),b=ink(dn,false)-H.bottom,g=parseFloat(getComputedStyle(w.parentElement).rowGap)||8;return [a.toFixed(1),b.toFixed(1),g.toFixed(1)].join(',')})()})
      unless hg.empty?
        ha, hb, hgap = hg.split(',').map(&:to_f)
        puts "HAIR #{c['name']}: above,below,gap #{hg}"
        expect([(ha - hb).abs <= [3, 0.25 * [ha, hb].max].max, [ha, hb].min >= 0.5 * hgap]).to eq([true, true])
      end
      # Console readouts (owner screenshots 107-109; owner 2026-11-13: the badge took the felt reading's place): the
      # clothing badge beside the big temperature, right of the digits and unit, its top layer's box on the digits' ink
      # (top and bottom within 3 px, owner: anchored, not floating) after a divider (DIV: midway, as tall as the digits); the last day row inside its panel.
      cr2 = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null},all=function(q){return [].map.call(document.querySelectorAll(q),vis).filter(Boolean)},ov=function(a,b){return Math.min(a.right,b.right)-Math.max(a.left,b.left)>0.5&&Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top)>0.5};
var te=[].filter.call(document.querySelectorAll('[data-sw-part="temp"] svg'),vis)[0];
[].filter.call(document.querySelectorAll('[data-sw-part="cue"]'),vis).forEach(function(e){if(!te){bad.push('badge without temperature');return;}var r=te.getBoundingClientRect(),vb=te.viewBox.baseVal,bb=te.getBBox(),ky=r.height/(vb.height||r.height),kx=r.width/(vb.width||r.width),tt=r.top+(bb.y-vb.y)*ky,th=bb.height*ky,tr=r.left+(bb.x-vb.x+bb.width)*kx;
var u=te.closest('[data-sw-part]').parentElement.querySelector('[data-sw-unit]'),ur=u?vis(u).right:tr,g=e.querySelector('g[data-sw-cloth]'),sv=e.querySelector('svg'),sr=vis(sv);if(!g||!sr){bad.push('badge not drawn');return;}var sb=sv.viewBox.baseVal,sk=(/slice/.test(sv.getAttribute('preserveAspectRatio')||'')?Math.max:Math.min)(sr.width/sb.width,sr.height/sb.height),oy=sr.top+(sr.height-sb.height*sk)/2,bx=g.getAttribute('data-sw-box').split(',').map(Number),gb={left:sr.left+(bx[0]-sb.x)*sk,top:oy+(bx[1]-sb.y)*sk,height:bx[2]*sk};gb.right=gb.left+bx[2]*sk;gb.bottom=gb.top+gb.height;   // the top layer's box (xMinYMid: a T-shirt draws shorter than a parka in the same box)
if(gb.left<Math.max(tr,ur)-0.5)bad.push('badge not right of the temperature '+gb.left.toFixed(0)+'<'+Math.max(tr,ur).toFixed(0));if(ov(gb,{left:r.left,right:tr,top:tt,bottom:tt+th}))bad.push('badge over temp');
if(Math.abs(gb.top-tt)>3||Math.abs(gb.bottom-tt-th)>3)bad.push('badge '+gb.top.toFixed(1)+'-'+gb.bottom.toFixed(1)+' not on the digits '+tt.toFixed(1)+'-'+(tt+th).toFixed(1));var dv=e.previousElementSibling;if(!e.closest('[data-sw-twin]')&&!(dv&&dv.hasAttribute('data-sw-div')&&dv.getBoundingClientRect().height>0))bad.push('no divider before the badge');});
if(te){var ti2=te.getBBox().height*te.getBoundingClientRect().height/(te.viewBox.baseVal.height||1),fz=function(e){return parseFloat(getComputedStyle(e).fontSize)*(e.getBoundingClientRect().width/(e.offsetWidth||1))},mx=0;[].forEach.call(document.querySelectorAll('[data-sw-suntime],[data-sw-cond]'),function(e){if(vis(e))mx=Math.max(mx,fz(e))});if(mx&&ti2<1.2*mx)bad.push('temperature digits '+ti2.toFixed(0)+' not the largest readout (text '+mx.toFixed(0)+')');}   // owner 2026-11-13 (live X hv dark, 4.4 smaller than the sun times)
document.querySelectorAll('[data-sw-panel]').forEach(function(p){var q=vis(p);if(!q)return;var r=[].map.call(p.querySelectorAll('[data-sw-row="day"]'),vis).filter(Boolean);if(r.length&&r[r.length-1].bottom>q.bottom+0.5)bad.push('day row '+r.length+' past the panel '+(r[r.length-1].bottom-q.bottom).toFixed(0))});
return bad.join('; ');})()})
      puts "READOUT #{c['name']}: #{cr2}" unless cr2.empty?
      expect(cr2).to eq('')
      # Condition row (owner 2026-11-13): the badge moved beside the temperature; the condition label at its full size
      # (no step down), no badge in its row.
      cb = s.evaluate(%q{(function(){var bad=[];[].forEach.call(document.querySelectorAll('[data-sw-cond]'),function(sp){if(!sp.getBoundingClientRect().width)return;if(sp.style.fontSize)bad.push('label stepped down to '+sp.style.fontSize);if(sp.parentElement.querySelector(':scope > [data-sw-part="cue"]'))bad.push('badge in the condition row');});return bad.join('; ');})()})
      puts "CUEROW #{c['name']}: #{cb}" unless cb.empty?
      expect(cb).to eq('')
      # Digit spacing (owner 2026-11-13, "4. 1"): in the seven-segment readouts the ink gap between neighbouring digits
      # (a decimal point between them allowed) at most 30 of the 100-unit digit height (normal 14, with a point 20).
      sp = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-part] svg').forEach(function(v){var r=v.getBoundingClientRect();if(!r.height)return;var k=100/r.height,gl=[].filter.call(v.querySelectorAll('g[data-sw-glyph]'),function(g){return /[0-9]/.test(g.getAttribute('data-sw-glyph'))&&g.getBoundingClientRect().width>0});
for(var i=1;i<gl.length;i++){var a=gl[i-1].getBoundingClientRect(),b=gl[i].getBoundingClientRect(),gp=(b.left-a.right)*k;if(gp>30)bad.push(gl[i-1].getAttribute('data-sw-glyph')+gl[i].getAttribute('data-sw-glyph')+' gap '+gp.toFixed(0));}});return bad.join('; ');})()})
      puts "DIGITGAP #{c['name']}: #{sp}" unless sp.empty?
      expect(sp).to eq('')
      # Dial trend arrows (owner 2026-11-13): one trend-line arrow per dial trending up or down (barometer from 3 h ago,
      # temperature +3 h), matching the direction, none when level, in front of the value on its line (owner 2026-11-13; was top right, then behind the unit), its 28-unit box about 1.5 x the name caption's cap height.
      ar = s.evaluate(%q{(function(){var bad=[],vis=function(e){var b=e&&e.getBoundingClientRect();return b&&b.width>0&&b.height>0?b:null},cx=document.createElement('canvas').getContext('2d');
[].filter.call(document.querySelectorAll('[data-sw-part="baro"],[data-sw-part="tdial"]'),vis).forEach(function(d){var k=d.getAttribute('data-sw-part'),aw=(k==='baro'?SW.baro:SW.tdial).arrow,want=aw==='up'||aw==='down'?1:0,box=d.parentElement,B=box.getBoundingClientRect(),a=[].filter.call(box.querySelectorAll('[data-sw-arrowpoly]'),function(e){return vis(e)&&!e.closest('[data-sw-dialin]')}),di=box.querySelector('[data-sw-dialin]');
if(k==='tdial'&&!!SW.inn!==!!(di&&vis(di)))bad.push('stacked indoor value '+!!(di&&vis(di))+'/'+!!SW.inn);if(di&&vis(di)){var q=di.getBoundingClientRect(),ov=q,o2=box.querySelector('[data-sw-cap]').getBoundingClientRect(),sp=di.querySelector('span.value');if(q.left<B.left||q.right>B.right||q.top<B.top||!sp||!sp.textContent.trim())bad.push('indoor value outside the panel or empty');if(!di.querySelector('[data-sw-part="loc"] svg path'))bad.push('indoor icon missing');if(Math.abs(q.right-di.previousElementSibling.getBoundingClientRect().right)>1.5)bad.push('indoor value right edge not level with the outdoor value');var lb=[].filter.call(d.querySelectorAll('svg text'),vis);lb.forEach(function(e){var b=e.getBoundingClientRect();if(Math.min(b.right,q.right)-Math.max(b.left,q.left)>1&&Math.min(b.bottom,q.bottom)-Math.max(b.top,q.top)>1)bad.push('indoor value over dial label '+e.textContent)});if(q.top<o2.bottom&&q.left<o2.right)bad.push('indoor value over the TEMPERATURE label');[].forEach.call(d.querySelectorAll('svg text,svg line,svg polygon'),function(e){if(e.closest('[data-sw-needle],defs')&&e.tagName!=='polygon')return;var b=e.getBoundingClientRect();[q,di.previousElementSibling.getBoundingClientRect()].forEach(function(r){if(b.width&&Math.min(b.right,r.right)-Math.max(b.left,r.left)>1&&Math.min(b.bottom,r.bottom)-Math.max(b.top,r.top)>1)bad.push('indoor or outdoor value over the dial '+e.tagName+' '+[b.left,b.top,b.right,b.bottom].map(Math.round)+' vs '+[r.left,r.top,r.right,r.bottom].map(Math.round))})});}
if(a.length!==want){bad.push(k+' arrows '+a.length+'/'+want);return;}if(!a.length)return;if(a[0].getAttribute('data-sw-arrowpoly')!==aw)bad.push(k+' arrow '+a[0].getAttribute('data-sw-arrowpoly')+' for '+aw);var r=a[0].ownerSVGElement.getBoundingClientRect(),c=box.querySelector('[data-sw-cap]'),cs=getComputedStyle(c);cx.font=cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;var cap=cx.measureText('H').actualBoundingBoxAscent*(c.getBoundingClientRect().height/(c.offsetHeight||1)),h=Math.max(r.width,r.height);
var vv=a[0].ownerSVGElement.closest('[data-sw-part="arrow"]'),vv=vv&&vv.nextElementSibling,V=vv&&vv.getBoundingClientRect();if(!V||!vv.classList.contains('value')||r.right>V.left||V.left-r.right>2.5*cap||r.top>V.bottom||r.bottom<V.top)bad.push(k+' arrow not in front of the value');if(h<1.2*cap||h>1.8*cap)bad.push(k+' arrow '+h.toFixed(0)+' cap '+cap.toFixed(0));});return bad.join('; ');})()})
      puts "ARROW #{c['name']}: #{ar}" unless ar.empty?
      # Barometer low/high (step 18): with a day's pressure range of 5 hPa or more the two marks stand apart.
      bm = s.evaluate(%q{(function(){var b=SW.baro||{};if(b.lo==null||b.hi-b.lo<5)return '';var bad=[];document.querySelectorAll('[data-sw-part="baro"]').forEach(function(d){if(!d.getBoundingClientRect().width)return;var m=[].map.call(d.querySelectorAll('[data-sw-markt]'),function(e){var r=e.getBoundingClientRect();return [r.left+r.width/2,r.top+r.height/2]});if(m.length!==2)bad.push('baro marks '+m.length);else if(Math.hypot(m[0][0]-m[1][0],m[0][1]-m[1][1])<4)bad.push('baro marks overlap')});return bad.join('; ')})()})
      puts "BAROMARK #{c['name']}: #{bm}" unless bm.empty?
      expect(bm).to eq('')
      expect(ar).to eq('')
      # Sun times (owner 2026-11-12, step 12): one line each, 12 h too (the AM/PM smaller, on the same line).
      st = s.evaluate(%q{(function(){var bad=[];document.querySelectorAll('[data-sw-suntime]').forEach(function(e){var rg=document.createRange();rg.selectNodeContents(e);var r=[].filter.call(rg.getClientRects(),function(q){return q.width>0&&q.height>0});if(r.length>1&&r.some(function(q){return q.left<r[0].right-1&&q.top>r[0].top+2}))bad.push(e.textContent.replace(/\s+/g,' ').trim());});return bad.join('; ');})()})
      puts "SUNTIME #{c['name']}: #{st}" unless st.empty?
      expect(st).to eq('')
      puts "DIVGAP #{c['name']}: #{dg}" unless dg.empty?
      expect(dg).to eq('')
      puts "GEO #{c['name']}: unequal day rows #{geo}"
      expect(tf).to eq('')
      expect(arc.split('|', 2)[1]).to eq('')
      expect(dc).to eq('')
      expect(geo).to start_with('0/')
      puts "#{c['name']}: #{s.evaluate("document.querySelector('[data-sw-debug]').getAttribute('data-sw-debug')")[0, 300]}"
    end
  end
end
