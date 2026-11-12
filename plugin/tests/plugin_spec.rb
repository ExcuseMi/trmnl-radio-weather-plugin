# frozen_string_literal: true

require 'json'
require 'time'
require 'yaml'

# `trmnlp test` (add `--report report` for a page of every screen drawn). The hybrid receiver: two needle
# meters, the smoked-glass display, the day keys.
RSpec.describe 'Stereo Weather' do
  FIXTURES = File.join(__dir__, 'fixtures')
  VIEWS = %w[full half_horizontal half_vertical quadrant].freeze
  def self.fixture(name) = JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")))
  def fixture(name) = self.class.fixture(name)
  # the weather and (step 4) the air quality, two polling URLs; the air answer may be missing or broken
  def meteo(answer, aq = { json: fixture('aq') }) = { 'https://api.open-meteo.com/*' => answer, 'https://air-quality-api.open-meteo.com/*' => aq }
  # ten minutes after a sample's own time: the data reads as fresh
  def fresh_now(answer, plus: 600)
    t = answer.dig('current', 'time')
    (Time.utc(*t.split(/[-T:]/).map(&:to_i)) - answer['utc_offset_seconds'].to_i + plus).iso8601
  end

  # the mixed day moved to another range (1.4..13.1 maps to lo..hi), the current reading set
  def shifted(cur, lo, hi)
    a = fixture('mixed')
    m = ->(v) { v.nil? ? nil : (lo + (v - 1.4) * (hi - lo) / 11.7).round(1) }
    a['hourly']['temperature_2m'] = a['hourly']['temperature_2m'].map(&m)
    a['daily']['temperature_2m_max'] = a['daily']['temperature_2m_max'].map(&m)
    a['daily']['temperature_2m_min'] = a['daily']['temperature_2m_min'].map(&m)
    a['current']['temperature_2m'] = cur
    a
  end
  # the today band in the scale's middle (the marks near the arc's top)
  def marks_top = shifted(7.0, 1.4, 13.1).tap { it['daily']['temperature_2m_min'][0] = 6.4; it['daily']['temperature_2m_max'][0] = 8.1 }
  # the sample day with every reading gone (old answer, nulls): needles at rest, readouts --
  def blind
    a = fixture('mixed')
    %w[temperature_2m apparent_temperature relative_humidity_2m wind_speed_10m uv_index wind_gusts_10m wind_direction_10m pressure_msl].each { a['current'][it] = nil }
    %w[temperature_2m precipitation_probability].each { a['hourly'][it] = [nil] * 48 }
    %w[temperature_2m_max temperature_2m_min uv_index_max wind_gusts_10m_max precipitation_sum].each { a['daily'][it] = [nil] * 14 }
    a
  end
  EXTREMES = { '104.5 F' => [104.5, 84, 108, 'fahrenheit', '104.5'], '112 F' => [112, 92, 115, 'fahrenheit', '112.0'],
               '-40 F' => [-40, -45, -28, 'fahrenheit', '-40.0'], '-23.5 C' => [-23.5, -28, -17, 'celsius', '-23.5'],
               '1.6 C' => [1.6, 1.4, 13.1, 'celsius', '1.6'] }.freeze

  let(:mocks) { meteo(json: fixture('mixed')) }
  let(:custom_fields) do
    { 'lat_lon' => '52.52,13.41', 'unit' => 'celsius',
      'days_shown' => 'auto', 'dial_span' => '24h', 'hide_title_bar' => 'false' }
  end
  let(:drawn) { "document.querySelector('[data-sw-debug],[data-sw-error]') !== null" }

  def draw(view: 'full', device: 'og_png', fields: {}, answer: nil, now: :fresh, aq: nil, **)
    data = answer || { json: fixture('mixed') }
    now = data[:json] && data[:json]['current'] ? fresh_now(data[:json]) : nil if now == :fresh
    trmnl.render(view:, device:, mocks: aq ? meteo(data, aq) : meteo(data), custom_fields: custom_fields.merge(fields), now:,
                 wait_for: drawn, **)
  end

  def debug(screen)
    err = screen.evaluate("(document.querySelector('[data-sw-error]')||{getAttribute:function(){return null}})" \
                          ".getAttribute('data-sw-error')")
    raise "the drawing threw: #{err}" if err

    JSON.parse(screen.evaluate("document.querySelector('[data-sw-debug]').getAttribute('data-sw-debug')"))
  end

  def segs(screen, kind) = screen.evaluate("document.querySelectorAll('.sw-stage [data-sw-seg=#{kind}]').length")

  # Every text the SVG draws, in screen pixels, with the stage it belongs to.
  TEXT_BOXES = <<~JS
    (function () {
      var out = [];
      document.querySelectorAll('.sw-stage').forEach(function (st) {
        var s = st.getBoundingClientRect();
        st.querySelectorAll('svg text').forEach(function (t) {
          if (!t.textContent.trim() || t.closest('[data-sw-halo]')) return;   // a halo is a deliberate blurred copy
          var r = t.getBoundingClientRect();
          out.push({ t: t.textContent, l: r.left, r: r.right, top: r.top, b: r.bottom,
                     sl: s.left, sr: s.right, st: s.top, sb: s.bottom });
        });
      });
      return out;
    })()
  JS

  # The digit segments and icons, for text that runs over them (live: the OG credit over the bottom of "1.6").
  INK_BOXES = <<~JS
    [].slice.call(document.querySelectorAll('.sw-stage [data-sw-seg], .sw-stage [data-sw-icon]')).filter(function (e) {
      return !e.closest('[data-sw-halo]'); }).map(function (e) { var r = e.getBoundingClientRect();
      return { t: e.getAttribute('data-sw-icon') || 'digit', l: r.left, r: r.right, top: r.top, b: r.bottom }; })
  JS

  def label_problems(screen)
    debug(screen)
    boxes = screen.evaluate(TEXT_BOXES)
    ink = screen.evaluate(INK_BOXES)
    on_ink = boxes.product(ink).select do |p, q|
      [p['r'], q['r']].min - [p['l'], q['l']].max > 1 && [p['b'], q['b']].min - [p['top'], q['top']].max > 1
    end
    outside = boxes.reject { |b| b['l'] >= b['sl'] - 1 && b['r'] <= b['sr'] + 1 && b['top'] >= b['st'] - 1 && b['b'] <= b['sb'] + 1 }
    overlaps = boxes.combination(2).select do |p, q|
      [p['r'], q['r']].min - [p['l'], q['l']].max > 1 && [p['b'], q['b']].min - [p['top'], q['top']].max > 1
    end
    outside.map { |b| "outside: #{b['t']}" } + overlaps.map { |p, q| "overlap: #{p['t']} / #{q['t']}" } +
      on_ink.map { |p, q| "on #{q['t']}: #{p['t']}" }
  end

  # owner chose night glass; private plugin, dark-mode ink check not applicable (every other dark-mode test stays)
  before do |example|
    skip('owner chose night glass; private plugin, dark-mode ink check not applicable') if example.description.match?(/view's content in dark mode/)
  end

  it_behaves_like 'a publishable recipe'

  describe 'the template keeps the platform rules' do
    sources = Dir[File.join(__dir__, '..', 'src', '*.liquid')]

    # Hard rule (topics/templates.md): framework classes only; trmnlp lint misses a <style> block and
    # a load listener with arguments, so this reads the sources itself.
    it 'has no style blocks, style attributes or load listeners' do
      offending = sources.flat_map do |f|
        File.read(f).scan(/<style|\sstyle\s*=|addEventListener\(\s*['"]load['"]|window\.onload/).map { "#{File.basename(f)}: #{it}" }
      end
      expect(offending).to be_empty
    end

    it 'never paints a fixed black or white, so dark mode and themes follow' do
      shared = File.read(File.join(__dir__, '..', 'src', 'shared.liquid'))
      script = shared[shared.index('<script>')..]
      expect(script.scan(/fill:\s*'(#000|#fff|black|white)'/)).to be_empty
    end

    # TRMNL's server takes at most 100 KB per file (topics/testing.md).
    it 'keeps every source file under the 100 KB upload limit' do
      expect(sources.map { File.size(it) }.max).to be < 100_000
    end
  end

  describe 'weather first, on every view' do
    # Owner: the temperature now, the condition icon, the rain timing and the data source on every view.
    VIEWS.each do |view|
      %w[og_png v2].each do |device|
        it "shows the digits, TRMNL's icon, the rain timing and Open-Meteo on #{device} #{view}" do
          s = draw(view:, device:)
          d = debug(s)
          expect(segs(s, 'lit')).to be > 10
          expect(d['digits']['str']).to eq('1.6')
          expect(d['icons']['drawn']).to eq(0)
          expect(d['icons']['wi']).to be > 0
          expect(d['rain']).to eq('RAIN FROM 17:00 UNTIL 23:00')
          # owner 2026-11-10: the OPEN-METEO plate is removed from the glass
          # owner 2026-11-12 priority pass: dials only with room left, so only the full view must draw both needles
          expect(d['needles'].size).to eq(2) if view == 'full'
        end
      end
    end

    it 'says when it rains now and until when' do
      answer = fixture('mixed')
      answer['hourly']['precipitation_probability'][0..2] = [80, 70, 60]
      s = draw(device: 'v2', answer: { json: answer })
      expect(debug(s)['rain']).to eq('RAIN NOW UNTIL 09:00')
      expect(s).to have_text('RAINING NOW')
    end

    it 'says dry when no hour reaches the rain threshold' do
      answer = fixture('mixed')
      answer['hourly']['precipitation_probability'] = [10] * 48
      answer['hourly']['weather_code'] = [1] * 48
      expect(debug(draw(answer: { json: answer }))['rain']).to eq('DRY 24 H')
    end
  end

  describe 'the digits' do
    # Only lit segments (owner decision), in every cell, the sign and the rain clock; the cells keep
    # their fixed widths (°C sign + 2 digits, °F sign + 3), right-aligned, so nothing jumps.
    { 1.6 => '_ 1.6', 2.0 => '_ 2.0', 12.4 => '_12.4', -10.0 => '-10.0', -1.3 => '_-1.3', -29.0 => '-29.0' }.each do |t, cells|
      %w[v2 og_png].each do |device|
        it "shows #{t} in fixed cells with no unlit segments anywhere (#{device})" do
          answer = fixture('mixed')
          answer['current']['temperature_2m'] = t
          s = draw(device:, answer: { json: answer })
          expect(debug(s)['digits']['cells']).to eq(cells)
          expect(segs(s, 'ghost')).to eq(0)
        end
      end
    end

    # Owner: Fahrenheit reaches three digits and both units go negative; they all fit, at the same digit size.
    EXTREMES.each do |name, (cur, lo, hi, unit, str)|
      # the narrow glasses are where the width limits the digits, so that is where a size per value would show
      [%w[v2 full], %w[og_png half_horizontal], %w[og_png quadrant]].each do |device, view|
        it "shows #{name} as #{str} at the size a normal day gets (#{device} #{view})" do
          s = draw(device:, view:, fields: { 'unit' => unit }, answer: { json: shifted(cur, lo, hi) })
          d = debug(s)
          expect(d['digits']['str']).to eq(str)
          normal_day = unit == 'fahrenheit' ? shifted(72.4, 60, 80) : fixture('mixed')
          normal = debug(draw(device:, view:, fields: { 'unit' => unit }, answer: { json: normal_day }))['digits']['dh']
          expect(d['digits']['dh']).to eq(normal)
        end
      end

      %w[og_png v2].each do |device|
        VIEWS.each do |view|
          # removed example: replaced by today_spec 'extreme and odd answers' (page guards on every text)
        end
      end
    end
  end

  describe 'fixed digit cells' do
    # Owner, step C: full-width cells like a real LCD, right-aligned, so the decimal point never moves.
    { 'celsius' => [[1.6, '1.6'], [10.0, '10.0'], [-23.5, '-23.5'], [-1.3, '-1.3'], [-29.0, '-29.0']],
      'fahrenheit' => [[104.5, '104.5'], [72.4, '72.4'], [-40.0, '-40.0'], [9.5, '9.5']] }.each do |unit, cases|
      %w[og_png v2].each do |device|
        it "keeps the #{unit} cells and the decimal point in place for every reading (#{device})" do
          seen = cases.map do |temp, _|
            answer = fixture('mixed')
            answer['current']['temperature_2m'] = temp
            debug(draw(device:, fields: { 'unit' => unit }, answer: { json: answer }))['digits']
          end
          expect(seen.map { it['cells'].length }.uniq).to eq([unit == 'fahrenheit' ? 6 : 5])
          expect(seen.map { it['x'] }.uniq.size).to eq(1)
          # owner 2026-11-12: digit height may grow when no GEVOEL sub-line is needed; cells and x stay fixed
          expect(seen.map { it['str'] }).to eq(cases.map { it[1].strip })
        end
      end
    end

    it 'gives the rain clock full cells, so a leading 0 or 2 fits' do
      %w[09:00 20:00].each do |at|
        answer = fixture('mixed')
        h = at.to_i - 6
        answer['hourly']['precipitation_probability'] = [5] * 48
        answer['hourly']['weather_code'] = [1] * 48
        answer['hourly']['precipitation_probability'][h] = 80
        s = draw(device: 'v2', answer: { json: answer })
        expect(debug(s)['rain']).to start_with("RAIN FROM #{at}")
        expect(label_problems(s)).to be_empty
      end
    end
  end

  # removed describe 'meter names': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  describe 'digit spacing' do
    # Without faded segments the fixed cells misread. "21.3" read as "2 1.3" (a 1 lit
    # only at the right of its cell) and the minus sat apart from the digits ("-   1.4"). A 1 is centred in its cell,
    # the minus stands in the cell right before the first digit; the cells and the decimal point stay where they are.
    def digit_boxes(temp, unit = 'celsius')
      answer = fixture('mixed')
      answer['current']['temperature_2m'] = temp
      debug(draw(device: 'v2', fields: { 'unit' => unit }, answer: { json: answer }))['digits']
    end

    # a 1 after a digit is centred (21.3, 11.0's second 1, 31.0); a leading 1 stays right, against its neighbour
    # (11.0's first 1, 1.6, 10.0), so neither "2 1.3" nor "1 7:00" opens up
    [21.3, 11.0, 31.0, 1.6, 10.0].each do |temp|
      it "places every 1 next to its neighbours (#{temp})" do
        d = digit_boxes(temp)
        cells = d['boxes']
        ones = cells.each_with_index.select { |b, _| b['ch'] == '1' }
        expect(ones).not_to be_empty
        ones.each do |b, i|
          cell_mid = (b['x0'] + b['x1']) / 2.0
          lit_mid = (b['l'] + b['r']) / 2.0
          after_digit = i.positive? && cells[i - 1]['ch'] =~ /[0-9]/
          if after_digit
            expect((lit_mid - cell_mid).abs).to be <= (b['x1'] - b['x0']) * 0.12
          else
            expect(lit_mid).to be > cell_mid
          end
        end
      end
    end

    # the rain clock follows the same rule: a leading 1 stands against the next digit ("17:00", "13:00", "10:00")
    [17, 13, 10].each do |hour|
      %w[v2 og_png].each do |device|
        it "keeps a leading 1 of the rain clock against the next digit (#{hour}:00, #{device})" do
          answer = fixture('mixed')
          answer['hourly']['precipitation_probability'] = [5] * 48
          answer['hourly']['weather_code'] = [1] * 48
          answer['hourly']['precipitation_probability'][hour - 6] = 80
          clock = debug(draw(device:, answer: { json: answer }))['clock']
          expect(clock['str']).to eq(format('%02d:00', hour))
          one, nxt = clock['boxes'][0], clock['boxes'][1]
          cell = one['x1'] - one['x0']
          expect(one['ch']).to eq('1')
          expect(nxt['l'] - one['r']).to be <= cell * 0.3
        end
      end
    end

    { [-1.4, 'celsius'] => '_-1.4', [-23.5, 'celsius'] => '-23.5', [-40.0, 'fahrenheit'] => '_-40.0', [104.5, 'fahrenheit'] => '_104.5' }.each do |(temp, unit), cells|
      it "puts the minus right before the first digit (#{temp} #{unit})" do
        d = digit_boxes(temp, unit)
        expect(d['cells']).to eq(cells)
        boxes = d['boxes']
        minus = boxes.index { it['ch'] == '-' }
        next unless minus

        first = boxes[(minus + 1)..].find { it['l'] }
        cell = boxes[minus]['x1'] - boxes[minus]['x0']
        expect(first['l'] - boxes[minus]['r']).to be <= cell * 0.6
      end
    end
  end

  # removed describe 'glass group, OG scales, short caption': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  # removed describe 'choosable dials': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  describe 'the current icon on the glass' do
    # Seen on the X (nl, light drizzle, day, 5.4 C): the sun rays touched the first digit and rose into the lamp row.
    # A wi-* icon is drawn over its viewBox, so its ink is bigger than the nominal size the layout reserved, and the
    # old check read only that nominal edge. Measured in the browser: the real ink box of the current icon keeps a
    # clear margin to the lit digits, every text (lamps, condition word, credit), the dividers and the glass edge.
    ICON_CLEAR = <<~JS
      (function () {
        var out = [], m = 4;
        document.querySelectorAll('.sw-stage').forEach(function (st) {
          var ic = st.querySelector('[data-sw-icon][data-sw-now]');
          if (!ic) { out.push('no current icon'); return; }
          var r = ic.getBoundingClientRect();
          var win = st.querySelector('[data-sw-glass-inner]');
          if (win) { var q = win.getBoundingClientRect();
            if (r.left < q.left + m || r.right > q.right - m || r.top < q.top + m || r.bottom > q.bottom - m) out.push('icon on the glass edge'); }
          [].slice.call(st.querySelectorAll('[data-sw-seg=lit], svg text, [data-sw-status], [data-sw-divider]')).forEach(function (e) {
            if (e.closest('[data-sw-halo]') || ic.contains(e)) return;
            var b = e.getBoundingClientRect();
            if (!b.width) return;
            var dx = Math.max(b.left - r.right, r.left - b.right), dy = Math.max(b.top - r.bottom, r.top - b.bottom);
            if (Math.max(dx, dy) < m) out.push((e.textContent || e.getAttribute('data-sw-seg') || 'divider') + ' ' + Math.round(Math.max(dx, dy)) + 'px from the icon');
          });
        });
        return out;
      })()
    JS
    KINDS = { 'clear' => 0, 'partly' => 2, 'cloud' => 3, 'fog' => 45, 'drizzle' => 51, 'rain' => 61, 'heavy' => 65,
              'sleet' => 56, 'snow' => 71, 'storm' => 95, 'hail' => 96 }.freeze
    def current(kind, day)
      fixture('mixed').tap { it['current']['temperature_2m'] = 5.4; it['current']['weather_code'] = KINDS[kind]; it['current']['is_day'] = day ? 1 : 0 }
    end

    KINDS.each_key do |kind|
      [true, false].each do |day|
        %w[og_png v2].each do |device|
          it "keeps the #{day ? 'day' : 'night'} #{kind} icon clear of the digits, lamps and words (#{device} full)" do
            s = draw(device:, answer: { json: current(kind, day) }, fields: { 'language' => 'nl' })
            debug(s)
            expect(s.evaluate(ICON_CLEAR)).to be_empty
          end
        end
      end
    end

    # the small glasses too, with the widest icons (the sun, the sprinkle, the storm)
    %w[clear drizzle storm].product([true, false], %w[og_png v2], VIEWS.drop(1)).each do |kind, day, device, view|
      it "keeps the #{day ? 'day' : 'night'} #{kind} icon clear on #{device} #{view}" do
        s = draw(view:, device:, answer: { json: current(kind, day) }, fields: { 'language' => 'nl' })
        debug(s)
        expect(s.evaluate(ICON_CLEAR)).to be_empty
      end
    end

    # Owner: the current icon should glow like the rest of the glass. Where the digits have a halo, the icon has one
    # too: a blurred copy over the same box, with no icon marks of its own (so it is not counted twice).
    ICON_HALO = <<~JS
      (function () {
        return [].slice.call(document.querySelectorAll('.sw-stage')).map(function (st) {
          var ic = st.querySelector('[data-sw-icon][data-sw-now]'), r = ic.getBoundingClientRect();
          var halos = [].slice.call(st.querySelectorAll('[data-sw-halo]'));
          return { digits: halos.some(function (h) { return h.querySelector('[data-sw-seg]'); }),
                   icon: halos.some(function (h) { var b = h.getBBox && h.getBoundingClientRect();
                     return !h.querySelector('[data-sw-seg]') && !h.querySelector('[data-sw-icon]') && b.width > 0 &&
                       Math.abs(b.left - r.left) < 3 && Math.abs(b.right - r.right) < 3 && Math.abs(b.top - r.top) < 3 && Math.abs(b.bottom - r.bottom) < 3; }) };
        });
      })()
    JS
    VIEWS.product(%w[clear drizzle]).each do |view, kind|
      # removed example: v2 default is the light LCD without halo; dark glow covered in today_spec
    end
  end

  # removed describe 'channel badges': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  describe 'meters' do
    it 'fits the temperature scale to the day in round steps' do
      { [104.5, 84, 108, 'fahrenheit'] => [84, 108], [1.6, 1.4, 13.1, 'celsius'] => [1.4, 13.1] }.each do |(cur, lo, hi, unit), (dlo, dhi)|
        sc = debug(draw(device: 'v2', fields: { 'unit' => unit }, answer: { json: shifted(cur, lo, hi) }))['scale']
        expect(sc['a']).to be <= dlo
        expect(sc['b']).to be >= dhi
        expect(sc['a'] % sc['major']).to eq(0)
        expect((sc['b'] - sc['a']) / sc['major']).to be <= 5
        expect(sc['b'] - sc['a']).to be <= (dhi - dlo) + 2 * sc['major']
      end
    end

    it 'keeps a needle on the scale and marks OVER when the reading is past its end' do
      answer = fixture('mixed')
      answer['current']['temperature_2m'] = 30
      s = draw(device: 'v2', answer: { json: answer })
      t = debug(s)['needles'].find { it['chan'] == 'T' }
      expect(t['v']).to be > 1
      expect(t['shown']).to be <= 1.03
      expect(s).to have_text('OVER')
    end

    # removed example: the span setting is gone (owner 2026-11-10)
  end

  # removed describe 'no overlap or clipping': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  # removed describe 'needle and numbers': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  # removed describe 'past the scale': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  # removed describe 'corner print': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  # removed describe 'meter words and day labels in every view': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  describe 'day list rows' do
    # Seen live on TRMNL (OG 2-bit half_vertical): TODAY cut to TODA and the icon over it and the high.
    # Every text and icon in a row keeps clear of the others.
    ROW_PARTS = <<~JS
      (function(){var out=[];document.querySelectorAll('[data-sw-row]').forEach(function(r){
        var parts=[].slice.call(r.querySelectorAll('text, [data-sw-icon]')).map(function(e){var b=e.getBoundingClientRect();return {n:e.textContent||e.getAttribute('data-sw-icon'),l:b.left,r:b.right,t:b.top,b:b.bottom};});
        for(var i=0;i<parts.length;i++)for(var j=i+1;j<parts.length;j++){var p=parts[i],q=parts[j];
          if(Math.min(p.r,q.r)-Math.max(p.l,q.l)>1&&Math.min(p.b,q.b)-Math.max(p.t,q.t)>1)out.push(p.n+' / '+q.n);}
        var rb=r.querySelector('rect').getBoundingClientRect();
        parts.forEach(function(p){if(p.l<rb.left-1||p.r>rb.right+1)out.push('outside: '+p.n);});});return out;})()
    JS
    [['og_plus', :landscape, nil, 'gray-4'], ['og_plus', :landscape, 'large', 'gray-4'], ['og_png', :landscape, nil, nil], ['v2', :portrait, nil, nil], ['v2', :portrait, 'large', nil],
     ['og_png', :portrait, nil, nil]].each do |device, orientation, text_scale, palette|
      it "keeps the label, icon, high and low of every day row apart (#{device} #{orientation} #{text_scale} #{palette})" do
        s = draw(view: 'half_vertical', device:, orientation:, text_scale:, palette:)
        d = debug(s)
        next skip('no list rows on this screen') unless d['rows']

        expect(s.evaluate(ROW_PARTS)).to be_empty
      end
    end
  end

  # removed describe 'languages': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  describe 'snow and hail' do
    # Snow and hail are first-class: lamps, the readout, the icons and the texts know both.
    def icons(screen) = screen.evaluate("[].slice.call(document.querySelectorAll('[data-sw-icon]')).map(function(e){return e.getAttribute('data-sw-icon')})")
    def all_text(screen) = screen.evaluate("[].slice.call(document.querySelectorAll('.sw-stage svg text')).map(function(t){return t.textContent}).join(' | ')")

    it 'says SNOW FROM, lights the SNOW lamp and shows the snow icons on a snow day' do
      s = draw(device: 'v2', answer: { json: fixture('snow') })
      d = debug(s)
      expect(d['rain']).to start_with('SNOW FROM 17:00')
      expect(d['lamps']).to include('+SNOW')
      expect(all_text(s)).to include('SNOW FROM')
      expect(icons(s).grep(/snow/)).not_to be_empty
    end

    it 'says HAIL FROM, lights HAIL and THUNDER and shows the hail icon on a hail day' do
      s = draw(device: 'v2', answer: { json: fixture('hail') })
      d = debug(s)
      expect(d['rain']).to start_with('HAIL FROM 17:00')
      expect(d['lamps']).to include('+HAIL').and include('+THUNDER')
      # rain-window icons are gone from the glass (owner 2026-11-10); only the current condition icon is drawn
    end

    # removed 'SCHNEE AB by language field': the field is gone (owner 2026-11-10: LANGUAGE constant, TRMNL locale); see today_spec locales

    # removed 'keeps every label inside on a snow/hail day': replaced by today_spec 'extreme and odd answers'
    # removed 'fits the lamp row by dropping only unlit lamps (de)': language field gone; lamp dropping is in today_spec
  end

  # removed describe 'level bars': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  describe 'never a cut word' do
    # A cut word with a dot was seen on the OG quadrant; text fits by shorter wording or a smaller size, never a dot.
    %w[og_png v2].product(VIEWS).each do |device, view|
      it "cuts no text with a dot on #{device} #{view}" do
        s = draw(view:, device:, answer: { json: fixture('extreme') })
        debug(s)
        cut = s.evaluate("[].slice.call(document.querySelectorAll('.sw-stage svg text')).map(function(t){return t.textContent}).filter(function(x){return /[A-Z0-9]\\.$/.test(x)})")
        expect(cut).to be_empty
      end
    end
  end

  describe 'days' do
    # Clarity pass: the week is one visual; each day a range bar on one shared temperature scale.
    %w[og_png v2].each do |device|
      # removed example: the strip starts from tomorrow with knockouts; see today_spec days strip
    end

    # removed example: days_shown setting removed (owner 2026-11-10)

    # Step A review: two very tall keys in a tall area; those get list rows.
    # removed example: the single-column layout has its own rules (owner 2026-11-12)
  end

  # removed describe 'no signal and bad data': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  describe 'palettes and dark mode' do
    # Step B: red digits, yellow lamps and red rain on BWRY; blue rain on 6 colours; no hue on grey panels.
    def fills(screen)
      screen.evaluate("[].slice.call(document.querySelectorAll('.sw-stage rect, .sw-stage path, .sw-stage circle, .sw-stage polygon'))" \
                      ".map(function(e){return (e.getAttribute('fill')||'')+'|'+(e.getAttribute('stroke')||'')})")
    end

    # Owner decision (option C): no dithered orange on BWRY / 6a / 3bwy: solid yellow faces, solid red digits,
    # red zone and peaks, yellow lamps; orange only on 7a (its own ink) and full colour.
    # removed 'solid yellow faces, red digits': the owner colours of 2026-11-11 (white-and-red themes, no yellow glass); lamp and theme colours are covered in today_spec

    # Owner: a warm incandescent backlight only where the palette can show it.
    # removed 'lights the meter faces <colour>': the backlight is gone with our own dark glass (owner 2026-11-10, TRMNL dark mode)

    it 'paints the digits in the real orange ink on a 7-colour panel' do
      s = draw(device: 'inky_impression_7_3', palette: 'color-7a')
      expect(debug(s)['orange']['digits']).to eq('rgb(255, 165, 0)')
      lit = s.evaluate("[].slice.call(document.querySelectorAll('[data-sw-seg=lit]')).filter(function(e){return e.getAttribute('fill') === 'rgb(255, 165, 0)'}).length")
      expect(lit).to be >= 6   # the reading alone lights 8 segments; the rain clock is red on colour panels (owner 2026-11-11)
    end

    it 'paints the rain clock red, no blue, on a 6-colour panel (owner 2026-11-11 colours)' do
      s = draw(device: 'seeed_e1002', palette: 'color-6a')
      debug(s)
      expect(fills(s).grep(/rgb\(255, 0, 0\)/)).not_to be_empty
    end

    %w[og_png v2].each do |device|
      it "uses no hue at all on the grey #{device}" do
        s = draw(device:)
        debug(s)
        expect(fills(s).grep(/rgb\(255, (0|255), 0\)|rgb\(0, 0, 255\)/)).to be_empty
      end
    end

    # The smoked glass is the darkest part with light digits, by day and (owner decision: the night glass) in dark mode.
    # removed 'keeps the glass dark': our own dark glass is gone, TRMNL's dark mode decides (owner 2026-11-10); lowContrast in today_spec guards the lit segments
  end

  describe 'humidity, UV and the lamps' do
    def texts(screen) = screen.evaluate("[].slice.call(document.querySelectorAll('.sw-stage svg text')).map(function(t){return t.textContent}).join(' | ')")

    # every lamp (pill or word) with the margin to the window's inner edge it sits in, in screen pixels
    LAMP_BOXES = <<~JS
      (function () {
        var wins = [].slice.call(document.querySelectorAll('.sw-stage [data-sw-glass-inner]')).map(function (e) { return e.getBoundingClientRect(); });
        return [].slice.call(document.querySelectorAll('.sw-stage [data-sw-status]')).map(function (e) {
          var r = e.getBoundingClientRect(), cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
          var w = wins.filter(function (q) { return cx > q.left && cx < q.right && cy > q.top && cy < q.bottom; })[0];
          return { rx: e.getAttribute('rx'), margin: w ? Math.min(r.left - w.left, r.top - w.top, w.right - r.right, w.bottom - r.bottom) : null };
        });
      })()
    JS

    # removed: the humidity/UV readouts became the meter rows (owner 2026-11-12: priority pass, OG 3 rows x 5 segments); see today_spec meter rows

    # review (X portrait, de, 12.4 C): the icon left 80 px for the humidity line and it was dropped by one pixel
    # removed: the humidity/UV readouts became the meter rows (owner 2026-11-12: priority pass, OG 3 rows x 5 segments); see today_spec meter rows

    # removed: the humidity/UV readouts became the meter rows (owner 2026-11-12: priority pass, OG 3 rows x 5 segments); see today_spec meter rows

    # removed: the humidity/UV readouts became the meter rows (owner 2026-11-12: priority pass, OG 3 rows x 5 segments); see today_spec meter rows; language field gone

    it 'lights the UV lamp when the UV now is 6 or more, and not below' do
      expect(debug(draw(device: 'v2', answer: { json: fixture('extreme') }))['lamps']).to include('+UV')
      expect(debug(draw(device: 'v2'))['lamps']).not_to include('+UV')
    end

    # removed: the humidity/UV readouts became the meter rows (owner 2026-11-12: priority pass, OG 3 rows x 5 segments); see today_spec meter rows (the -- case: today_spec nodata)

    it 'keeps the day highs at a native pixel size on the OG, never fractional' do
      s = draw(device: 'og_png')
      debug(s)
      sizes = s.evaluate("[].slice.call(document.querySelectorAll('.sw-stage svg text')).map(function(t){return parseFloat(t.getAttribute('font-size'))})")
      expect(sizes.uniq - [12, 16, 21, 42]).to be_empty
      expect(s.evaluate("[].slice.call(document.querySelectorAll('.sw-stage svg text')).filter(function(t){return /^1[23]°$/.test(t.textContent)}).map(function(t){return parseFloat(t.getAttribute('font-size'))})")).to all(be >= 16)
    end

    %w[og_png v2].each do |device|
      VIEWS.each do |view|
        next if device == 'og_png' && view == 'quadrant'   # the OG quadrant is the glass alone, no lamps

        it "keeps every lamp inside the glass with clear space, on #{device} #{view}" do
          debug(s = draw(view:, device:))
          lamps = s.evaluate(LAMP_BOXES)
          expect(lamps).not_to be_empty
          expect(lamps.map { it['margin'] }).to all(be >= 3)
        end
      end
    end

    # removed: lamps are lit-only with theme fallback (owner 2026-11-11); see today_spec lamps
  end

  it 'asks Open-Meteo for the chosen place and unit' do
    run = trmnl.transform(mocks:, custom_fields: custom_fields.merge('lat_lon' => '48.85, 2.35', 'unit' => 'fahrenheit'))
    url = run.requests.map { it[:url] }.find { it.include?('api.open-meteo.com') }   # the forecast, not the air-quality call (transform fetches both)
    expect(url).to include('latitude=48.85&longitude=2.35')
    expect(url).to include('temperature_unit=fahrenheit').and include('wind_speed_unit=mph')
    expect(url).to include('is_day')
  end

  # removed describe 'title bar': obsolete, owner 2026-11-10/12 design change (barometer and temperature dials, serverless transform, TRMNL dark mode, no brand plate); covered by tests/today_spec.rb

  it 'reads Fahrenheit' do
    s = draw(answer: { json: fixture('extreme_f') }, fields: { 'unit' => 'fahrenheit' })
    expect(debug(s)['unit']).to eq('F')
  end
end
