# frozen_string_literal: true

require 'json'
require 'time'

# `trmnlp test` (add `--report report` for a page of every screen drawn). The hybrid receiver: two needle
# meters, the smoked-glass display, the day keys.
RSpec.describe 'Stereo Weather' do
  FIXTURES = File.join(__dir__, 'fixtures')
  VIEWS = %w[full half_horizontal half_vertical quadrant].freeze
  def self.fixture(name) = JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")))
  def fixture(name) = self.class.fixture(name)
  def meteo(answer) = { 'https://api.open-meteo.com/*' => answer }
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
  EXTREMES = { '104.5 F' => [104.5, 84, 108, 'fahrenheit', '104.5'], '112 F' => [112, 92, 115, 'fahrenheit', '112.0'],
               '-40 F' => [-40, -45, -28, 'fahrenheit', '-40.0'], '-23.5 C' => [-23.5, -28, -17, 'celsius', '-23.5'],
               '1.6 C' => [1.6, 1.4, 13.1, 'celsius', '1.6'] }.freeze

  let(:mocks) { meteo(json: fixture('mixed')) }
  let(:custom_fields) do
    { 'lat_lon' => '52.52,13.41', 'unit' => 'celsius',
      'days_shown' => 'auto', 'dial_span' => '24h', 'hide_title_bar' => 'false' }
  end
  let(:drawn) { "document.querySelector('[data-sw-debug],[data-sw-error]') !== null" }

  def draw(view: 'full', device: 'og_png', fields: {}, answer: nil, now: :fresh, **)
    data = answer || { json: fixture('mixed') }
    now = data[:json] && data[:json]['current'] ? fresh_now(data[:json]) : nil if now == :fresh
    trmnl.render(view:, device:, mocks: meteo(data), custom_fields: custom_fields.merge(fields), now:,
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
          expect(s).to have_text('OPEN-METEO')
          expect(d['needles'].size).to be >= 1 unless device == 'og_png' && view == 'quadrant'   # the OG quadrant is the glass alone
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
          it "keeps every label inside and apart for #{name} on #{device} #{view}" do
            s = draw(view:, device:, fields: { 'unit' => unit }, answer: { json: shifted(cur, lo, hi) })
            expect(label_problems(s)).to be_empty
          end
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
          expect(seen.map { it['dh'] }.uniq.size).to eq(1)
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

  describe 'meter names' do
    # Every meter says what it shows: the name printed on every face.
    [['full', 'og_png', :landscape, nil], ['half_vertical', 'v2', :portrait, nil], ['half_vertical', 'v2', :landscape, nil],
     ['quadrant', 'v2', :landscape, nil], ['full', 'v2', :portrait, 'large']].each do |view, device, orientation, text_scale|
      it "prints the meters' names on their faces (#{device} #{view} #{orientation} #{text_scale})" do
        s = draw(view:, device:, orientation:, text_scale:)
        names = debug(s)['names']
        expect(names).not_to be_empty
        expect(names.first).to match(/TEMP/) unless view == 'quadrant'
        expect(names.last).to match(/RAIN|PRECIPITATION/)
        expect(label_problems(s)).to be_empty
      end
    end

    # Owner: the small views showed the temperature twice (digits on the glass, the needle on a lone temperature meter).
    # The glass always shows the temperature; a temperature meter only stands as the stereo pair's L, with the rain R.
    [['og_png', :landscape], ['og_png', :portrait], ['v2', :landscape], ['v2', :portrait]].each do |device, orientation|
      it "never shows the temperature twice without the rain beside it (#{device} #{orientation})" do
        chans = VIEWS.to_h { |view| [view, (debug(draw(view:, device:, orientation:))['needles'] || []).map { it['chan'] }] }
        chans.each { |view, c| expect([view, c]).to satisfy("#{view} #{c}: a temperature meter has the rain meter beside it") { !c.include?('T') || c.include?('R') } }
      end
    end
  end

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

  describe 'glass group, OG scales, short caption' do
    # Seen on the OG snow / BWRY hail renders: the icon floated left of a lone minus; the OG scale numbers crowded
    # the needle; the long precipitation caption ran nearly the full meter width.
    it 'stands the icon right before the first lit digit, a tight group (-1.4, OG and X)' do
      %w[og_png v2].each do |device|
        answer = fixture('mixed')
        answer['current']['temperature_2m'] = -1.4
        d = debug(draw(device:, answer: { json: answer }))['digits']
        first = d['boxes'].find { it['l'] }
        expect(first['l'] - d['iconRight']).to be_between(d['dh'] * 0.05, d['dh'] * 0.3)   # a clear gap, not a far one
      end
    end

    # the ends always, the exact middle unless the needle stands on it (live: the needle crossed a 4)
    it 'labels only the ends and the middle of the OG scales' do
      s = draw(device: 'og_png', answer: { json: fixture('snow') })
      debug(s)
      counts = s.evaluate("[0,1].map(function(n){return document.querySelectorAll('.sw-stage [data-sw-scale=\"'+n+'\"]').length})")
      expect(counts).to all(be_between(2, 3))
    end

    it 'says RAIN CHANCE in English, and keeps TRMNL\'s German word, short where the long one fills the OG meter' do
      expect(debug(draw(device: 'og_png'))['rainCaption']).to eq('RAIN CHANCE')
      expect(debug(draw(device: 'v2'))['rainCaption']).to eq('RAIN CHANCE')
      expect(debug(draw(device: 'og_png', fields: { 'language' => 'de' }))['rainCaption']).to eq('NIEDERSCHLAG')
      expect(debug(draw(device: 'v2', fields: { 'language' => 'de' }))['rainCaption']).to start_with('NIEDERSCHLAG')
    end
  end

  describe 'channel badges' do
    # L and R as small labels in the faces' outer top corners, not in the captions (owner decision).
    %w[full half_horizontal half_vertical].each do |view|
      it "marks the meters L and R inside their faces on the #{view} view" do
        s = draw(view:, device: 'v2')
        expect(debug(s)['badges']).to eq(%w[L R])
        expect(debug(s)['names'].join(' ')).to match(/TEMP.*(RAIN|PRECIPITATION)/)
        expect(s).to have_no_text('L  TEMPERATURE')
      end
    end

    it 'leaves the badge out where only one meter shows (quadrant)' do
      expect(debug(draw(view: 'quadrant', device: 'v2'))['badges']).to be_nil
    end
  end

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

    it 'looks as far ahead for rain as the span setting' do
      r24 = debug(draw(device: 'v2'))['needles'].find { it['chan'] == 'R' }
      r12 = debug(draw(device: 'v2', fields: { 'dial_span' => '12h' }))['needles'].find { it['chan'] == 'R' }
      expect(r24['v']).to eq(0.9)
      expect(r12['v']).to eq(0.55)
    end
  end

  describe 'no overlap or clipping' do
    %w[og_png v2].each do |device|
      VIEWS.each do |view|
        it "keeps every label inside its view and apart from the others (#{device} #{view}, extreme day)" do
          expect(label_problems(draw(view:, device:, answer: { json: fixture('extreme') }))).to be_empty
        end
      end
    end

    VIEWS.each do |view|
      it "keeps every label inside and apart on the X in portrait with large text (#{view})" do
        expect(label_problems(draw(view:, device: 'v2', orientation: :portrait, text_scale: 'large'))).to be_empty
      end

      it "does not overflow the #{view} view on the TRMNL X in portrait with large text" do
        expect(draw(view:, device: 'v2', orientation: :portrait, text_scale: 'large')).to have_no_overflow
      end
    end
  end

  describe 'needle and numbers' do
    # The needle never crosses a scale number: the numbers are printed over it, knocked out in the face colour.
    %w[og_png v2].each do |device|
      it "draws the scale numbers after the needle with a face-coloured knockout (#{device})" do
        s = draw(device:)
        debug(s)
        order = s.evaluate("(function(){var all=[].slice.call(document.querySelectorAll('.sw-stage [data-sw-needle], .sw-stage [data-sw-scale]'));return all.map(function(e){return e.hasAttribute('data-sw-needle')?'N':'S'}).join('')})()")
        expect(order).to match(/\AN+S+N+S+\z/)
        knocked = s.evaluate("[].slice.call(document.querySelectorAll('.sw-stage [data-sw-scale]')).every(function(e){return e.getAttribute('paint-order') === 'stroke' && !!e.getAttribute('stroke')})")
        expect(knocked).to be(true)
      end
    end
  end

  describe 'corner print' do
    # TEMP °C / RAIN % once ran under the pivot on the X half_horizontal.
    [%w[v2 half_horizontal], %w[v2 full], %w[og_png half_vertical], %w[v2 quadrant]].each do |device, view|
      it "keeps the corner print clear of the pivot (#{device} #{view})" do
        d = debug(draw(device:, view:))
        expect(d['cornerPrint']).not_to be_empty
        d['cornerPrint'].each { |c| expect(c['hubLeft'] - c['right']).to be >= c['gap'] }   # two hub radii of air
      end
    end
  end

  describe 'meter words and day labels in every view' do
    # Seen live (nl, dark, X half_vertical and X quadrant on 4 greys): MIN on the face's top edge with the arc's end under
    # it, the needle through a scale number, uneven numbers (0, 4, 10), VANDAAG run off the screen's left edge.
    # Measured in the browser: every LO / HI / NOW word fully inside its face clear of the bevel and the arc, the scale
    # numbers evenly spaced and clear of the needle (the ends may be crossed, knocked out), each day's name in its column.
    METER_PARTS = <<~JS
      (function(){var out=[];function box(e){var b=e.getBBox();return {l:b.x,r:b.x+b.width,t:b.y,b:b.y+b.height};}
        document.querySelectorAll('.sw-stage [data-sw-face]').forEach(function(f){
          var n=f.getAttribute('data-sw-face'),fb=box(f),ins=+f.getAttribute('data-sw-inset')+1,pv=f.getAttribute('data-sw-pivot').split(' ').map(Number);
          var st=f.closest('.sw-stage');
          st.querySelectorAll('[data-sw-mark="'+n+'"]').forEach(function(m){var b=box(m);
            if(b.l<fb.l+ins||b.r>fb.r-ins||b.t<fb.t+ins||b.b>fb.b-ins)out.push('mark on the frame: '+m.textContent);
            var qx=Math.max(b.l,Math.min(pv[0],b.r)),qy=Math.max(b.t,Math.min(pv[1],b.b));
            if(Math.hypot(qx-pv[0],qy-pv[1])<pv[2]+1)out.push('mark on the arc: '+m.textContent);});
          var sc=[].slice.call(st.querySelectorAll('[data-sw-scale="'+n+'"]')),vals=sc.map(function(e){return parseFloat(e.textContent)}).sort(function(a,b){return a-b});
          if(vals.length<2)out.push('meter '+n+' has '+vals.length+' scale numbers');
          for(var i=2;i<vals.length;i++)if(Math.abs((vals[i]-vals[i-1])-(vals[1]-vals[0]))>1e-6)out.push('uneven scale: '+vals.join(','));
          var nd=st.querySelector('[data-sw-meter="'+n+'"]');
          if(nd){var pts=nd.getAttribute('points').split(' ').map(function(p){return p.split(',').map(Number)}),tip=pts[0];
            sc.forEach(function(e){var v=parseFloat(e.textContent);if(v===vals[0]||v===vals[vals.length-1])return;var b=box(e);
              for(var k=0;k<=200;k++){var x=pv[0]+(tip[0]-pv[0])*k/200,y=pv[1]+(tip[1]-pv[1])*k/200;
                if(x>b.l&&x<b.r&&y>b.t&&y<b.b){out.push('needle through '+e.textContent);break;}}});}
        });
        document.querySelectorAll('.sw-stage [data-sw-day]').forEach(function(t){var c=t.getAttribute('data-sw-day').split(' ').map(Number),b=box(t);
          if(b.l<c[0]-1||b.r>c[1]+1)out.push('day name out of its column: '+t.textContent);});
        return out;})()
    JS
    # the today band in the scale's middle (the marks near the arc's top), and a cool day on 0..10 with the needle at 4
    def marks_top = shifted(7.0, 1.4, 13.1).tap { it['daily']['temperature_2m_min'][0] = 6.4; it['daily']['temperature_2m_max'][0] = 8.1 }
    def cool_day = shifted(4.2, 0.2, 9.4).tap { it['daily']['temperature_2m_min'][0] = 3.8; it['daily']['temperature_2m_max'][0] = 5.0 }
    screens = [['og_png', :landscape, nil, nil], ['og_png', :portrait, nil, nil], ['v2', :landscape, nil, nil], ['v2', :portrait, nil, nil],
               ['v2', :landscape, 'large', nil], ['v2', :landscape, nil, 'gray-4'], ['og_plus', :landscape, nil, 'gray-4'],
               ['og_bwry', :landscape, nil, 'color-4bwry'], ['seeed_e1002', :landscape, nil, 'color-6a']]
    runs = screens.flat_map { |sc| [[*sc, 'nl', true], [*sc, 'de', true]] } + [['v2', :landscape, nil, nil, 'nl', false], ['og_png', :landscape, nil, nil, 'de', false]]
    runs.each do |device, orientation, text_scale, palette, lang, dark|
      it "keeps the meter words inside the faces and the day names in their columns (#{device} #{orientation} #{text_scale} #{palette} #{lang}#{' dark' if dark})" do
        problems = VIEWS.product([fixture('mixed'), marks_top, cool_day]).flat_map do |view, answer|
          s = draw(view:, device:, orientation:, text_scale:, palette:, dark_mode: dark, fields: { 'language' => lang }, answer: { json: answer })
          debug(s)
          (s.evaluate(METER_PARTS) + label_problems(s)).map { "#{view} #{answer['current']['temperature_2m']}: #{it}" }
        end
        expect(problems.uniq).to be_empty
      end
    end
  end

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

  describe 'languages' do
    # i18n: the labels follow the language (TRMNL's own texts first, then ours, then English), an unknown
    # locale falls back to English instead of breaking the render, and long words never cut or overlap.
    def texts(screen) = screen.evaluate("[].slice.call(document.querySelectorAll('.sw-stage svg text')).map(function(t){return t.textContent}).join(' | ')")

    { 'de' => ['TEMPERATUR', 'HEUTE', 'REGEN AB', 'TEILWEISE BEWÖLKT'], 'fr' => ['TEMPÉRATURE', 'PLUIE DÈS'],
      'ja' => ['温度', '今日', '雨の開始', '晴れ時々曇り'], 'nl' => ['REGEN VANAF', 'VANDAAG'] }.each do |lang, words|
      it "prints the #{lang} labels" do
        s = draw(device: 'v2', fields: { 'language' => lang })
        debug(s)
        all = texts(s)
        words.each { |w| expect(all).to include(w) }
        expect(all).not_to include('RAIN FROM')
      end
    end

    it 'follows the TRMNL account language when the setting is Automatic' do
      s = draw(device: 'v2', fields: { 'language' => 'auto' }, trmnl: { user: { locale: 'de' } }) rescue nil
      next skip('this trmnlp cannot set trmnl.user.locale') if s.nil?

      expect(texts(s)).to include('TEMPERATUR')
    end

    # l_word on TRMNL's server has more than trmnlp: a "Translation missing" answer (what trmnlp gives for most
    # keys), the key itself or an empty string must never reach the screen; the embedded copy takes over
    it 'never shows a missing-translation answer from l_word' do
      %w[de ja].each do |lang|
        all = texts(draw(device: 'v2', fields: { 'language' => lang }))
        expect(all).not_to match(/translation missing/i)
        expect(all).not_to match(/\b(precipitation_probability|right_now)\b/i)
      end
    end

    it 'falls back to English for words a language lacks, and for an unknown locale' do
      hu = texts(draw(device: 'v2', fields: { 'language' => 'hu' }))
      expect(hu).to include('RAIN FROM')                 # TRMNL has Hungarian texts, ours has none: English for those
      xx = draw(device: 'v2', fields: { 'language' => 'xx-YY' })
      expect(debug(xx)['digits']['str']).to eq('1.6')     # it drew, in English
      expect(texts(xx)).to include('RAIN FROM')
    end

    %w[de ja fr].each do |lang|
      [%w[v2 full], %w[og_png full], %w[v2 quadrant], %w[og_png quadrant], %w[og_png half_horizontal], %w[v2 half_vertical]].each do |device, view|
        it "keeps every #{lang} label inside and apart on #{device} #{view}" do
          s = draw(device:, view:, fields: { 'language' => lang })
          expect(label_problems(s)).to be_empty
          expect(s).to have_no_overflow
        end
      end
    end
  end

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
      expect(icons(s).grep(/hail/)).not_to be_empty
    end

    it 'says it in the chosen language (SCHNEE AB)' do
      expect(all_text(draw(device: 'v2', answer: { json: fixture('snow') }, fields: { 'language' => 'de' }))).to include('SCHNEE AB')
    end

    %w[snow hail].each do |day|
      %w[og_png v2].product(VIEWS).each do |device, view|
        it "keeps every label inside and apart on a #{day} day (#{device} #{view})" do
          s = draw(device:, view:, answer: { json: fixture(day) })
          expect(label_problems(s)).to be_empty
          expect(s).to have_no_overflow
        end
      end
    end

    # the OG in portrait with German: six lamps do not fit; the unlit ones go (SCHNEE from the middle too), never a lit one
    [['og_png', :portrait, nil], ['v2', :portrait, 'large']].each do |device, orientation, text_scale|
      it "fits the lamp row by dropping only unlit lamps (#{device} #{orientation} #{text_scale}, de, hail day)" do
        s = draw(device:, orientation:, text_scale:, answer: { json: fixture('hail') }, fields: { 'language' => 'de' })
        d = debug(s)
        expect(d['lamps']).to include('+REGEN').and include('+HAGEL').and include('+GEWITTER')
        expect(d['lamps'].size).to be < 6
        expect(label_problems(s)).to be_empty
      end
    end
  end

  describe 'level bars' do
    # Owner: segmented level bars, not pills; clear gaps (at least 2 px on the OG) so they read as LED segments.
    [['og_png', nil], ['og_bwry', 'color-4bwry'], ['v2', nil]].each do |device, palette|
      it "draws each day as LED segments with clear gaps (#{device} #{palette})" do
        s = draw(device:, palette:)
        debug(s)
        gaps = s.evaluate(<<~JS)
          (function(){var rs=[].slice.call(document.querySelectorAll('.sw-stage rect[data-sw-led]')).filter(function(r){return r.getAttribute('width')!=='1'});
          var byX={};rs.forEach(function(r){var k=r.getAttribute('x');(byX[k]=byX[k]||[]).push([+r.getAttribute('y'),+r.getAttribute('height')]);});
          var g=[];Object.keys(byX).forEach(function(k){var c=byX[k].sort(function(a,b){return a[0]-b[0]});for(var i=1;i<c.length;i++)g.push(c[i][0]-(c[i-1][0]+c[i-1][1]));});return g;})()
        JS
        expect(gaps).not_to be_empty
        expect(gaps.min).to be >= (device == 'v2' ? 1 : 2)
        expect(s.evaluate("document.querySelectorAll('.sw-stage [data-sw-led=peak]').length")).to be >= 4
      end
    end
  end

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
      it "draws the days on one shared temperature scale (#{device})" do
        strip = debug(draw(device:))['strip']
        expect(strip.size).to be >= 4
        by_hi = strip.sort_by { -it['hi'] }
        expect(by_hi.map { it['top'] }).to eq(by_hi.map { it['top'] }.sort)          # warmer high, higher top
        by_lo = strip.sort_by { -it['lo'] }
        expect(by_lo.map { it['bottom'] }).to eq(by_lo.map { it['bottom'] }.sort)    # warmer low, higher foot
      end
    end

    it 'shows as many days as set, never more than fit' do
      expect(debug(draw(device: 'v2', fields: { 'days_shown' => '4' }))['days']).to eq(4)
      expect(debug(draw(view: 'half_vertical', fields: { 'days_shown' => '7' }))['days']).to be < 7
    end

    # Step A review: two very tall keys in a tall area; those get list rows.
    it 'lists the days in rows on the X portrait half_vertical' do
      d = debug(draw(view: 'half_vertical', device: 'v2', orientation: :portrait))
      expect(d['rows']).to be(true)
      expect(d['days']).to be >= 4
    end
  end

  describe 'no signal and bad data' do
    it 'shows the no-signal state as a designed screen: meters at rest, no day keys, the reason' do
      s = draw(device: 'v2', answer: { status: 400, json: fixture('error') }, now: nil)
      d = debug(s)
      expect(d['needles'].map { it['shown'] }).to eq([-0.03, -0.03])
      expect(d['days']).to eq(0)
      expect(d['rain']).to eq('NO SIGNAL')
      expect(s).to have_text('NO SIGNAL').and have_text('NEXT DAYS').and have_text('LATITUDE MUST BE')
    end

    VIEWS.each do |view|
      it "shows NO SIGNAL on the #{view} view when the API cannot be reached" do
        expect(draw(view:, answer: { error: :reset }, now: nil)).to have_text('NO SIGNAL')
      end
    end

    it 'still shows the temperature when the forecast arrays are empty' do
      s = draw(answer: { json: fixture('empty') })
      debug(s)
      expect(s).to have_no_text('NO SIGNAL')
      expect(s).to have_text('NO FORECAST')
      expect(segs(s, 'lit')).to be > 5
    end

    it 'keeps drawing with nulls in the arrays' do
      expect(debug(draw(device: 'v2', answer: { json: fixture('nulls') }))['needles'].size).to eq(2)
    end
  end

  describe 'palettes and dark mode' do
    # Step B: red digits, yellow lamps and red rain on BWRY; blue rain on 6 colours; no hue on grey panels.
    def fills(screen)
      screen.evaluate("[].slice.call(document.querySelectorAll('.sw-stage rect, .sw-stage path, .sw-stage circle, .sw-stage polygon'))" \
                      ".map(function(e){return (e.getAttribute('fill')||'')+'|'+(e.getAttribute('stroke')||'')})")
    end

    # Owner decision (option C): no dithered orange on BWRY / 6a / 3bwy: solid yellow faces, solid red digits,
    # red zone and peaks, yellow lamps; orange only on 7a (its own ink) and full colour.
    [%w[og_bwry color-4bwry], %w[seeed_e1002 color-6a]].each do |device, palette|
      it "uses solid yellow faces and solid red digits, nothing dithered (#{device} #{palette})" do
        s = draw(device:, palette:)
        d = debug(s)
        expect(d['orange']['digits']).to eq('null')
        faces = s.evaluate("[].slice.call(document.querySelectorAll('.sw-stage rect')).filter(function(r){return r.getAttribute('fill') === 'rgb(255, 255, 0)'}).length")
        expect(faces).to be >= 2
        red_digits = s.evaluate("[].slice.call(document.querySelectorAll('[data-sw-seg=lit]')).filter(function(e){return /255, 0, 0/.test(e.getAttribute('fill'))}).length")
        expect(red_digits).to be > 10
        expect(fills(s).grep(/url\(#swp/)).to be_empty if palette == 'color-4bwry'
        expect(fills(s).grep(/rgb\(0, 0, 255\)/)).to be_empty if palette == 'color-4bwry'
      end
    end

    # Owner: a warm incandescent backlight only where the palette can show it.
    { %w[generic_16_9 color-24bit] => 'full', %w[inky_impression_7_3 color-7a] => 'orange',
      %w[og_bwry color-4bwry] => 'yellow', %w[seeed_e1002 color-6a] => 'yellow', ['v2', nil] => 'grey',
      ['og_png', nil] => 'none' }.each do |(device, palette), want|
      it "lights the meter faces #{want} on #{device} #{palette || 'default'}" do
        s = draw(device:, palette:)
        d = debug(s)
        expect(d['backlight']).to eq(want)
        gradients = s.evaluate("document.querySelectorAll('.sw-stage radialGradient').length")
        expect(gradients).to(want == 'full' ? be >= 2 : eq(0))
        # the grey lamp on 16 greys: dithered ellipses of the panel's own greys, no gradient to posterize into rings
        ellipses = s.evaluate("document.querySelectorAll('.sw-stage [data-sw-lamp]').length")
        expect(ellipses).to(want == 'grey' ? be >= 4 : eq(0))
      end
    end

    it 'paints the digits in the real orange ink on a 7-colour panel' do
      s = draw(device: 'inky_impression_7_3', palette: 'color-7a')
      expect(debug(s)['orange']['digits']).to eq('rgb(255, 165, 0)')
      lit = s.evaluate("[].slice.call(document.querySelectorAll('[data-sw-seg=lit]')).filter(function(e){return e.getAttribute('fill') === 'rgb(255, 165, 0)'}).length")
      expect(lit).to be > 10
    end

    it 'paints likely rain blue on a 6-colour panel' do
      s = draw(device: 'seeed_e1002', palette: 'color-6a')
      debug(s)
      expect(fills(s).grep(/rgb\(0, 0, 255\)/)).not_to be_empty
    end

    %w[og_png v2].each do |device|
      it "uses no hue at all on the grey #{device}" do
        s = draw(device:)
        debug(s)
        expect(fills(s).grep(/rgb\(255, (0|255), 0\)|rgb\(0, 0, 255\)/)).to be_empty
      end
    end

    # The smoked glass is the darkest part with light digits, by day and (owner decision: the night glass) in dark mode.
    [false, true].each do |dark|
      it "keeps the glass dark with light digits (TRMNL X, dark mode #{dark})" do
        d = debug(draw(device: 'v2', dark_mode: dark))
        lum = ->(c) { c.scan(/\d+/).first(3).map(&:to_i).sum / 3.0 }
        expect(lum.call(d['glass'])).to be < 80
        expect(lum.call(d['glow'])).to be > 180
      end
    end
  end

  it 'asks Open-Meteo for the chosen place and unit' do
    run = trmnl.transform(mocks:, custom_fields: custom_fields.merge('lat_lon' => '48.85, 2.35', 'unit' => 'fahrenheit'))
    url = run.requests.map { it[:url] }.find { it.include?('open-meteo') }
    expect(url).to include('latitude=48.85&longitude=2.35')
    expect(url).to include('temperature_unit=fahrenheit').and include('wind_speed_unit=mph')
    expect(url).to include('is_day')
  end

  describe 'title bar' do
    # No location label; the sync time goes in the title bar's instance slot, on the faceplate only when it is hidden.
    it 'puts the sync time in the title bar instance and never the coordinates' do
      s = draw(device: 'v2')
      expect(s).to have_css('.title_bar .instance', exact_text: '06:00')
      expect(s).to have_no_text('52.52')
    end

    { 'full' => 'og_png' }.each do |view, device|
      it "hides the title bar when asked and shows no time on the faceplate (#{device} #{view})" do
        s = draw(view:, device:, fields: { 'hide_title_bar' => 'true' })
        expect(s).to have_no_css('.title_bar')
        expect(s).to have_no_text('06:00')
        expect(s).to have_no_text('52.52')
        expect(label_problems(s)).to be_empty
      end
    end

    # Owner: no title bar outside the full view, whatever the setting; the credit and the time stay on the glass.
    VIEWS.drop(1).product(%w[og_png v2]).each do |view, device|
      it "never draws the title bar on the #{view} view, and keeps Open-Meteo and the time (#{device})" do
        s = draw(view:, device:)
        expect(s).to have_no_css('.title_bar')
        expect(s).to have_text(/06:00\s+·\s+OPEN-METEO/)
        expect(label_problems(s)).to be_empty
      end
    end
  end

  it 'reads Fahrenheit' do
    s = draw(answer: { json: fixture('extreme_f') }, fields: { 'unit' => 'fahrenheit' })
    expect(debug(s)['unit']).to eq('F')
  end
end
