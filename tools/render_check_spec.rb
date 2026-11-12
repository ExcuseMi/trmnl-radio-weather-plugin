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
      puts "GEO #{c['name']}: unequal day rows #{geo}"
      expect(geo).to start_with('0/')
      puts "#{c['name']}: #{s.evaluate("document.querySelector('[data-sw-debug]').getAttribute('data-sw-debug')")[0, 300]}"
    end
  end
end
