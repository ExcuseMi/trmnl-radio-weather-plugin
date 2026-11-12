# frozen_string_literal: true

require 'json'
require 'time'
require 'tmpdir'
require 'fileutils'

# The design of 2026-11-12: barometer left, temperature right, one console (meter rows, BUITEN/BINNEN, rain or
# GEEN REGEN with sun and moon), the days strip from tomorrow, serverless transform, TRMNL's own dark mode.
# Every spec here was seen red once on a deliberately broken copy (see the "red:" note on each).
RSpec.describe 'Radio Weather, design of 2026-11-12' do
  FX = File.join(__dir__, 'fixtures')
  SRC = File.expand_path('../src', __dir__)
  def fx(name) = JSON.parse(File.read(File.join(FX, "#{name}.json")))

  def dry_hours(answer)
    n = answer['hourly']['time'].size
    answer['hourly']['weather_code'] = [3] * n
    answer['hourly']['precipitation_probability'] = [3] * n
    answer['hourly']['precipitation'] = [0] * n
    answer
  end

  # a daylight answer with a given highest UV of the day (the fixture is a night with max UV 2.1)
  def sunny(max_uv = 6.0, day: 1)
    a = fx('mixed')
    a['current']['is_day'] = day
    a['daily']['uv_index_max'][0] = max_uv
    a
  end

  def sensors(extra = {})
    { 'sensor_readings' => { 'device_1' => { 'temperature' => [{ '2026-11-08 04:40:00 UTC' => 21.0 }, { '2026-11-08 05:00:00 UTC' => 21.6 }],
                                             'humidity' => [{ '2026-11-08 05:00:00 UTC' => 48 }],
                                             'carbon_dioxide' => [], 'pressure' => [] }.merge(extra), 'device_2' => {} } }
  end

  # one render; the test's fixture time plus ten minutes is "now"
  def shot(view: 'full', device: 'og_png', palette: nil, dark: false, orientation: :landscape, theme: nil, answer: nil, aq: nil,
           vars: nil, fields: {}, locale: 'nl')
    answer ||= fx('mixed')
    t = answer.dig('current', 'time')
    now = (Time.utc(*t.split(/[-T:]/).map(&:to_i)) - answer['utc_offset_seconds'].to_i + 600).iso8601
    mocks = { 'https://api.open-meteo.com/*' => { json: answer }, 'https://air-quality-api.open-meteo.com/*' => aq || { json: fx('aq') } }
    opts = { view:, device:, mocks:, now:, orientation:, dark_mode: dark,
             custom_fields: { 'lat_lon' => '52.52,13.41', 'unit' => 'celsius', 'hide_title_bar' => 'false' }.merge(fields),
             variables: { 'trmnl' => { 'user' => { 'locale' => locale } } }.merge(vars || {}),
             wait_for: "document.querySelector('[data-sw-debug],[data-sw-error]') !== null" }
    opts[:palette] = palette if palette
    opts[:theme] = theme if theme
    trmnl.render(**opts)
  end

  def dbg(screen)
    err = screen.evaluate("(document.querySelector('[data-sw-error]')||{getAttribute:function(){return null}}).getAttribute('data-sw-error')")
    raise "the drawing threw: #{err}" if err

    JSON.parse(screen.evaluate("document.querySelector('[data-sw-debug]').getAttribute('data-sw-debug')"))
  end

  def texts(screen)
    screen.evaluate("[].slice.call(document.querySelectorAll('.sw-stage svg text')).filter(function(t){return !t.closest('[data-sw-halo]')}).map(function(t){return t.textContent})")
  end

  def count(screen, selector) = screen.evaluate("document.querySelectorAll('.sw-stage #{selector}').length")

  describe 'meter rows and zones' do
    it 'draws the fixed rows and hides rows without data (pollen without data, CO2 without a sensor)' do
      # red: breaking the 'pollen' filter in ROK made the POLLEN row appear without data
      d = dbg(shot(device: 'v2'))
      expect(d['readoutKinds']).to eq(%w[humidity wind aqi])   # night: no UV row
    end

    it 'drops the POLLEN row when the pollen data is null, and shows it with a value' do
      # red: pollenLevel returning 0 for no data kept an empty POLLEN row
      aq = fx('aq')
      aq['current'].merge!('grass_pollen' => nil, 'birch_pollen' => nil, 'alder_pollen' => nil)
      expect(dbg(shot(device: 'v2', answer: sunny, aq: { json: aq }))['readoutKinds']).not_to include('pollen')
      aq['current']['birch_pollen'] = 80.0
      expect(dbg(shot(device: 'v2', answer: sunny, aq: { json: aq }))['readoutKinds']).to include('pollen')
    end

    it 'shows POLLEN with pollen data and CO2 with a sensor reading, in that order' do
      # red: removing 'co2' from RO_ORDER lost the row
      aq = fx('aq')
      aq['current']['grass_pollen'] = 30.0
      d = dbg(shot(device: 'v2', answer: sunny, aq: { json: aq }, vars: sensors('carbon_dioxide' => [{ '2026-11-08 05:00:00 UTC' => 1180 }])))
      expect(d['readoutKinds']).to eq(%w[humidity uv wind aqi pollen co2])
    end

    it 'shows only AQI, UV and WIND with 5 segments on the OG, and VOCHT, POLLEN, CO2 only in a warning or danger zone' do
      # owner 2026-11-12. red: removing the OGD filter on warnRow brought all rows back; NS = 10 gave 10-segment rows
      aq = fx('aq')
      aq['current']['grass_pollen'] = 30.0   # level 0.4: warning
      calm = dbg(shot(device: 'og_png', aq: { json: aq }))
      expect(calm['readoutKinds']).to eq(%w[humidity wind aqi pollen]) # (night, no UV) fixture humidity and pollen are in a warning zone
      a = sunny(6.0)
      a['current']['relative_humidity_2m'] = 50
      aq['current']['grass_pollen'] = 1.0
      quiet = shot(device: 'og_png', answer: a, aq: { json: aq }, vars: sensors('carbon_dioxide' => [{ '2026-11-08 05:00:00 UTC' => 700 }]))
      expect(dbg(quiet)['readoutKinds']).to eq(%w[uv wind aqi])
      segs = quiet.evaluate("new Set([].slice.call(document.querySelectorAll('.sw-stage [data-sw-rcell=\"readouts:0\"] [data-sw-rseg]')).map(function(e){return Math.floor(+e.getAttribute('x'))})).size")
      expect(segs).to eq(5)
      loud = shot(device: 'og_png', answer: a, aq: { json: aq }, vars: sensors('carbon_dioxide' => [{ '2026-11-08 05:00:00 UTC' => 1500 }]))
      expect(dbg(loud)['readoutKinds']).to include('co2')
      v2 = shot(device: 'v2', answer: a, aq: { json: aq })
      expect(v2.evaluate("new Set([].slice.call(document.querySelectorAll('.sw-stage [data-sw-rcell=\"readouts:0\"] [data-sw-rseg]')).map(function(e){return Math.floor(+e.getAttribute('x'))})).size")).to eq(10)
    end

    it 'shows the UV row only in daylight and when the highest UV of the day is 3 or more' do
      # owner 2026-11-12. red: dropping the daylight test showed UV at night; dropping the 3 test showed it with max UV 2
      expect(dbg(shot(device: 'v2', answer: sunny(6.0)))['readoutKinds']).to include('uv')
      expect(dbg(shot(device: 'v2', answer: sunny(6.0, day: 0)))['readoutKinds']).not_to include('uv')
      expect(dbg(shot(device: 'v2', answer: sunny(2.0)))['readoutKinds']).not_to include('uv')
      expect(dbg(shot(device: 'v2', answer: sunny(3.0)))['readoutKinds']).to include('uv')
      expect(dbg(shot(device: 'og_png', answer: sunny(6.0)))['readoutKinds']).to include('uv')
    end

    it 'puts the zone borders where the owner set them (UV 3 and 8, lit segments 1..8)' do
      # red: moving the UV zone to 4/11 changed the zone list
      a = sunny(9.0)
      a['current']['uv_index'] = 9.0
      s = shot(device: 'v2', answer: a)
      zones = s.evaluate("[].slice.call(document.querySelectorAll('.sw-stage [data-sw-rcell=\"readouts:1\"] [data-sw-zone]')).map(function(e){return +e.getAttribute('data-sw-zone')})")
      expect(zones).to eq([0, 0, 0, 1, 1, 1, 1, 2])
    end

    it 'draws no segment when the reading is missing and shows "--"' do
      # red: nodata branch returned lit = 0 but no "--"
      a = fx('mixed')
      a['current']['wind_speed_10m'] = nil
      s = shot(answer: a)
      expect(count(s, '[data-sw-nodata]')).to be >= 1
    end
  end

  describe 'lamps' do
    it 'draws lit lamps only, and never a lamp word the colour of its box (white and red theme)' do
      # red: giving the lamp text the ink colour on the red theme made text and box the same colour
      s = shot(device: 'og_bwry', palette: 'color-4bwry', theme: 'white-and-red')
      expect(dbg(s)['lamps'].all? { |l| l.start_with?('+') }).to be(true)
      pairs = s.evaluate(<<~JS)
        [].slice.call(document.querySelectorAll('.sw-stage rect[data-sw-status]')).filter(function(r){ return r.getAttribute('fill') !== 'none' && r.nextElementSibling && r.nextElementSibling.tagName === 'text'; }).map(function(r){
          return [r.nextElementSibling.getAttribute('fill'), r.getAttribute('fill')]; })
      JS
      expect(pairs).not_to be_empty
      expect(pairs.reject { |a, b| b && a == b }).to eq(pairs)
    end
  end

  describe 'channel badges' do
    # replaces the deleted 'channel badges' describe of the old design: the dials keep their L and R badges
    %w[v2 og_png].each do |device|
      it "marks the barometer L at the left and the temperature dial R at the right (#{device})" do
        # red: placing both badges at the left made R sit left of the middle
        s = shot(device:)
        xs = s.evaluate("(function(){ var o = {}, pv = [].slice.call(document.querySelectorAll('.sw-stage [data-sw-pivot]')).map(function(e){ return +e.getAttribute('data-sw-pivot').split(' ')[0]; }); var st = document.querySelector('.sw-stage').getBoundingClientRect(); var k = st.width / +document.querySelector('.sw-stage svg').getAttribute('viewBox').split(' ')[2]; o.p = pv; o.k = k; [].slice.call(document.querySelectorAll('.sw-stage svg text')).forEach(function(t){ if (t.textContent === 'L' || t.textContent === 'R') o[t.textContent] = (t.getBoundingClientRect().left - st.left) / k; }); return o; })()")
        expect(xs['p'].size).to eq(2)
        expect(xs['L']).to be < xs['p'][0]    # L sits left of the barometer pivot
        expect(xs['R']).to be > xs['p'][1]    # R sits right of the temperature pivot
      end
    end
  end

  describe 'meter labels' do
    it 'sizes the meter labels from the row pitch, so they are not tiny on the OG half_horizontal' do
      # owner 2026-11-12. red: removing the nSz growth left the labels at about 11 px
      aq = fx('aq')
      aq['current']['grass_pollen'] = 30.0   # four rows: humidity, wind, AQI, pollen
      s = shot(device: 'og_png', view: 'half_horizontal', aq: { json: aq })
      r = s.evaluate("(function(){ var k = document.querySelector('.sw-stage').getBoundingClientRect().width / +document.querySelector('.sw-stage svg').getAttribute('viewBox').split(' ')[2]; var t = [].slice.call(document.querySelectorAll('.sw-stage text[data-sw-cell]')); var ys = t.map(function(e){return parseFloat(e.getAttribute('y'))}).sort(function(a,b){return a-b}); return { size: parseFloat(t[0].getAttribute('font-size')), pitch: ys[1] - ys[0], k: k, n: t.length }; })()")
      expect(r['size'] / r['pitch']).to be >= 0.45
    end
  end

  describe 'lamp thresholds' do
    def lamps(answer: nil, aq: nil) = dbg(shot(device: 'og_png', answer:, aq: aq && { json: aq }))['lamps']

    it 'lights SMOG above an air-quality index of 60, not at 60' do
      # red: changing the limit to 40 lit SMOG at 60
      aq = fx('aq')
      aq['current']['european_aqi'] = 60
      expect(lamps(aq:)).not_to include('+SMOG')
      aq['current']['european_aqi'] = 61
      expect(lamps(aq:)).to include('+SMOG')
    end

    it 'lights UV from a UV index of 8, not below' do
      # red: changing the limit to 3 lit UV at 7.9
      a = fx('mixed')
      a['current']['uv_index'] = 7.9
      expect(lamps(answer: a)).not_to include('+UV')
      a['current']['uv_index'] = 8.0
      expect(lamps(answer: a)).to include('+UV')
    end
  end

  describe 'rain window and the dry block' do
    it 'needs a 30 percent chance to start a window (code-only rain is dry)' do
      # red: removing the 30 percent rule made the 5 percent hours a window
      a = dry_hours(fx('mixed'))
      a['hourly']['weather_code'][9] = 61
      expect(dbg(shot(answer: a))['rain']).to start_with('DRY')
      a['hourly']['precipitation_probability'][9] = 60
      expect(dbg(shot(answer: a))['rain']).to start_with('RAIN')
    end

    it 'shows GEEN REGEN with sunrise, sunset and the moon on a dry day, nothing else in the block' do
      # red: dropping the sunT block removed the times
      s = shot(answer: dry_hours(fx('mixed')))
      t = texts(s)
      expect(t).to include('GEEN REGEN', '07:21', '16:35')
      expect(t).not_to include('--:--')
    end
  end

  describe 'dials' do
    it 'draws the barometer left with the value, four zones and a ring identical to the temperature dial' do
      # red: shrinking the barometer's rArc by 2 px changed the pivot radii
      s = shot(device: 'v2')
      piv = s.evaluate("[].slice.call(document.querySelectorAll('.sw-stage [data-sw-pivot]')).map(function(e){return e.getAttribute('data-sw-pivot')})")
      expect(piv.size).to eq(2)
      expect(piv[0].split.last(2)).to eq(piv[1].split.last(2))
      expect(piv[0].split[1]).to eq(piv[1].split[1])
      expect(count(s, '[data-sw-zone4]')).to eq(4)
      expect(texts(s)).to include('BAROMETER', 'TEMPERATUUR', '1013', 'hPa')
    end

    it 'marks the temperature range with a hollow low and a solid high triangle' do
      # red: making both triangles solid
      s = shot(device: 'v2')
      hollow = s.evaluate("document.querySelectorAll('.sw-stage polygon[fill=\"none\"][stroke]').length")
      expect(hollow).to be >= 2   # one per dial
    end

    it 'adds an indoor twin needle only when a sensor reports a temperature' do
      # red: always drawing the twin
      expect(count(shot(device: 'v2'), '[data-sw-twin]')).to eq(0)
      expect(count(shot(device: 'v2', vars: sensors), '[data-sw-twin]')).to eq(1)
    end
  end

  describe 'BUITEN and BINNEN' do
    it 'shows two readouts with GEVOEL under the outdoor one and the indoor humidity under the other' do
      # red: removing the dual flag kept a single readout
      t = texts(shot(device: 'v2', vars: sensors))
      expect(t).to include('BUITEN', 'BINNEN', 'VOCHT 48 %')
      expect(t.grep(/GEVOEL/)).not_to be_empty
      expect(texts(shot(device: 'v2'))).not_to include('BINNEN')
    end

    it 'puts one readout above the other in the single column' do
      # red: skipping the indoor row in colLayout
      s = shot(view: 'half_vertical', orientation: :portrait, vars: sensors)
      expect(texts(s)).to include('BINNEN', 'VOCHT 48 %')
    end
  end

  describe 'days strip' do
    it 'starts with tomorrow, and the pointer triangle is drawn after the knockouts' do
      # red: slice(0) put today first
      s = shot(device: 'v2')
      first = texts(s).find { |x| %w[MA DI WO DO VR ZA ZO].include?(x) }
      expect(first).to eq('MA')   # the fixture's today is a Sunday (ZO)
      # the pointer: exactly one in the strip, and no ground-coloured knockout drawn after it may cross its line
      covered = s.evaluate(<<~JS)
        (function(){
          var g = document.querySelector('.sw-stage g[data-sw-dial] rect[data-sw-pointer]').parentNode, kids = [].slice.call(g.children);
          var ptr = g.querySelector('rect[data-sw-pointer]'), pi = kids.indexOf(ptr), px = +ptr.getAttribute('x'), pw = +ptr.getAttribute('width');
          var bad = kids.slice(pi + 1).filter(function(e){ return e.tagName === 'rect' && !e.getAttribute('stroke') && !e.hasAttribute('data-sw-pointer') &&
            +e.getAttribute('x') < px + pw && +e.getAttribute('x') + +e.getAttribute('width') > px && +e.getAttribute('height') > 4 &&
            +e.getAttribute('y') < +ptr.getAttribute('y') + +ptr.getAttribute('height') && +e.getAttribute('y') + +e.getAttribute('height') > +ptr.getAttribute('y'); });
          var last = kids.filter(function(e){return e.tagName !== 'text'}).pop();
          return { n: g.querySelectorAll('rect[data-sw-pointer]').length, bad: bad.length, last: last.tagName };
        })()
      JS
      expect(covered['n']).to eq(1)
      expect(covered['bad']).to eq(0)
      expect(covered['last']).to eq('polygon')
    end
  end

  describe 'dark mode and glow' do
    it 'never draws a lit segment the colour of the glass (no black on black)' do
      # red: using the non-token gray-80 gave lowContrast rows
      # owner 2026-11-12: 2-bit light lit segments use the darker middle grey (threshold 0.5 on 2-bit); red: back to gray-35 on 2-bit light
      a2 = fx('mixed')
      a2['current']['uv_index'] = 9.0
      a2['current']['wind_speed_10m'] = 35.0
      expect(dbg(shot(device: 'v2', dark: true))['lowContrast']).to be_nil
      expect(dbg(shot(device: 'og_plus', palette: 'gray-4', dark: true))['lowContrast']).to be_nil
      expect(dbg(shot(device: 'v2'))['lowContrast']).to be_nil
      expect(dbg(shot(device: 'og_plus', palette: 'gray-4', answer: a2))['lowContrast']).to be_nil
      expect(dbg(shot(device: 'v2', answer: a2))['lowContrast']).to be_nil
    end

    it 'gives 2-bit dark the same glow ring on the X and on the OG (decided by depth, not width)' do
      # red: re-adding the width test on the ring removed it on the OG
      x = count(shot(device: 'v2', palette: 'gray-4', dark: true), 'g[data-sw-halo][stroke-linejoin]')
      og = count(shot(device: 'og_plus', palette: 'gray-4', dark: true), 'g[data-sw-halo][stroke-linejoin]')
      expect(x).to be > 0
      expect(og).to be > 0
      expect(count(shot(device: 'og_plus', palette: 'gray-4'), 'g[data-sw-halo]')).to eq(0)
    end
  end

  describe 'every text inside its box' do
    cases = [%w[v2 full landscape], %w[v2 half_vertical portrait], %w[v2 quadrant portrait], %w[og_png full landscape],
             %w[og_png half_horizontal portrait], %w[og_png half_vertical portrait], %w[og_png quadrant landscape], %w[og_png quadrant portrait],
             %w[og_bwry full portrait]]
    cases.each do |device, view, orient|
      it "has nothing clipped or overlapping: #{device} #{view} #{orient}" do
        # red: forcing a text outside (x - 400) put it in debug.clip
        d = dbg(shot(device:, view:, orientation: orient.to_sym, vars: sensors, dark: true))
        expect(d['clip']).to eq([])
        expect(d['overlap']).to eq([])
        expect(d['outside'] || []).to eq([])
      end
    end
  end

  describe 'priority on narrow, portrait and quadrant boxes' do
    it 'uses one column under 320 px, with the temperature and no dials' do
      # red: raising the column limit to 100 left the old stacked layout
      s = shot(view: 'half_vertical', orientation: :portrait)
      d = dbg(s)
      expect(d['col']).not_to be_nil
      expect(count(s, '[data-sw-face]')).to eq(0)
      expect(count(s, '[data-sw-seg]')).to be > 0
    end

    it 'shows the console first in a quadrant, and the dial only with room left' do
      # red: swapping the order drew the dial instead of the console
      s = shot(view: 'quadrant', device: 'v2', orientation: :portrait)
      expect(count(s, '[data-sw-rcell]')).to be > 0
    end
  end

  describe 'resize' do
    # trmnlp's page cannot change size or classes after the render (tried: style change, resize event, class change on
    # .screen and html: nothing redraws), so the redraw itself is UNPROVEN here. This only guards that the three triggers
    # are still wired in the source; a person must check a real resize on the device preview.
    it 'still wires the resize listener, the size observer and the class observer to the redraw' do
      # red: deleting the ResizeObserver line made it fail
      src = File.read(File.join(SRC, 'shared.liquid'))
      expect(src).to include("window.addEventListener('resize', sched)")
      expect(src).to include('new ResizeObserver(sched).observe(st)')
      expect(src).to include("attributeFilter: ['class']")
    end
  end

  describe 'no signal' do
    # 2026-11-12 regression: the failure path had no indoor block and the drawing threw (M.inn undefined) after the
    # indoor sensors were added. Guard: every view draws NO SIGNAL (and never throws) when the weather API fails.
    %w[full half_horizontal half_vertical quadrant].each do |view|
      %w[og_png v2].each do |device|
        it "draws a designed no-signal screen on #{device} #{view} when the API fails" do
          # red: removing inn from the empty model made dbg raise "the drawing threw"
          s = trmnl.render(view:, device:, mocks: { 'https://api.open-meteo.com/*' => { status: 500, json: { error: true } },
                                                      'https://air-quality-api.open-meteo.com/*' => { status: 500, json: {} } },
                           custom_fields: { 'lat_lon' => '52.52,13.41', 'unit' => 'celsius' },
                           wait_for: "document.querySelector('[data-sw-debug],[data-sw-error]') !== null")
          d = dbg(s)
          expect(d['clip']).to eq([])
          expect(texts(s).join(' ')).to match(/NO SIGNAL|GEEN SIGNAAL|NO DATA/i)
        end
      end
    end
  end

  describe 'extreme and odd answers' do
    # replaces the old label_problems specs (digits, extremes, snow and hail, past the scale), which measured the
    # dials of the old design; the page's own guards (debug.clip, debug.overlap) now run on every text.
    { 'extreme' => 'celsius', 'extreme_f' => 'fahrenheit', 'snow' => 'celsius', 'hail' => 'celsius', 'nulls' => 'celsius' }.each do |name, unit|
      %w[og_png v2].each do |device|
        %w[full half_horizontal half_vertical quadrant].each do |view|
          it "keeps every text inside and apart: #{name} #{device} #{view}" do
            # red: the same forced offset as in the full matrix spec
            d = dbg(shot(device:, view:, answer: fx(name), fields: { 'unit' => unit }))
            expect(d['clip']).to eq([])
            expect(d['overlap']).to eq([])
          end
        end
      end
    end
  end

  describe 'languages' do
    # replaces the old 'language' field specs (owner 2026-11-10: the TRMNL user's locale decides, LANGUAGE constant forces)
    { 'de' => %w[TEMPERATUR REGEN\ AB TEILWEISE\ BEWÖLKT], 'fr' => %w[BAROMÈTRE TEMPÉRATURE PLUIE\ DÈS], 'ja' => %w[温度 雨の開始 晴れ時々曇り],
      'nl' => %w[BAROMETER TEMPERATUUR REGEN\ VANAF GEVOEL], 'en' => %w[TEMPERATURE RAIN\ FROM UNTIL\ 23:00] }.each do |loc, words|
      it "prints the #{loc} labels from the user's locale" do
        # red: ignoring the locale variable left English
        t = texts(shot(device: 'v2', locale: loc))
        words.each { |w| expect(t).to include(w) }
        expect(t).not_to include('RAIN FROM') unless loc == 'en'
      end
    end
  end

  describe 'serverless transform' do
    def run_node(js, language: nil, unit: nil)
      Dir.mktmpdir do |dir|
        src = File.read(File.join(SRC, 'transform.js'))
        src = src.sub("const LANGUAGE = null;", "const LANGUAGE = #{language.to_json};") if language
        src = src.sub("const UNIT = null;", "const UNIT = #{unit.to_json};") if unit
        File.write(File.join(dir, 'transform.js'), src)
        File.write(File.join(dir, 'run.js'), js)
        out = IO.popen(['node', File.join(dir, 'run.js')], &:read)
        JSON.parse(out)
      end
    end

    STUB = <<~JS
      const t = require('./transform.js');
      const urls = [];
      global.fetch = async (u) => { urls.push(String(u)); if (/air-quality/.test(u)) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => ({ current: { time: '2026-11-08T06:00' }, daily: { sunrise: ['2026-11-08T07:21'], sunset: ['2026-11-08T16:35'] }, hourly: {} }) }; };
      t.run({ trmnl: { user: { locale: 'en' }, plugin_settings: { custom_fields_values: { lat_lon: '52.5,13.4', unit: 'celsius' } } } })
        .then((r) => console.log(JSON.stringify({ weather: !!r.weather.current, aq: r.aq, loc: r.i18n.loc, unit: r.unit, url: urls[0], pollen: r.pollen, sun: r.sun })));
    JS

    it 'keeps the weather when the air quality fails' do
      # red: throwing on the air answer
      r = run_node(STUB, language: nil)
      expect(r['weather']).to be(true)
      expect(r['aq']).to be_nil
      expect(r['pollen']).to be_nil
    end

    it 'forces language and unit from the constants at the top' do
      # red: ignoring the constants
      r = run_node(STUB, language: 'de', unit: 'fahrenheit')
      expect(r['loc']).to eq('de')
      expect(r['unit']).to eq('fahrenheit')
      expect(r['url']).to include('temperature_unit=fahrenheit', 'precipitation_unit=inch')
      expect(run_node(STUB)['loc']).to eq('en')
    end

    it 'falls back to English for an unsupported language' do
      # red: returning the raw code
      expect(run_node(STUB, language: 'xx')['loc']).to eq('en')
    end
  end
end
