# frozen_string_literal: true

require 'fileutils'
require 'json'

# Renders of the hybrid concept: `trmnlp test tests/review_spec.rb` writes the PNGs into renders/.
# Cases: the mixed sample day (1.6 C) and the widest readings: 104.5 F, 112 F, -40 F, -23.5 C.
RSpec.describe 'Stereo Weather hybrid renders' do
  base = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'mixed.json')))
  t = base.dig('current', 'time')
  now = (Time.utc(*t.split(/[-T:]/).map(&:to_i)) - base['utc_offset_seconds'].to_i + 600).iso8601
  # the mixed day's shape, moved to another range: 1.4..13.1 maps to lo..hi, the current reading set
  shift = lambda do |cur, lo, hi|
    a = JSON.parse(JSON.generate(base))
    m = ->(v) { v.nil? ? nil : (lo + (v - 1.4) * (hi - lo) / 11.7).round(1) }
    a['hourly']['temperature_2m'] = a['hourly']['temperature_2m'].map(&m)
    a['daily']['temperature_2m_max'] = a['daily']['temperature_2m_max'].map(&m)
    a['daily']['temperature_2m_min'] = a['daily']['temperature_2m_min'].map(&m)
    a['current']['temperature_2m'] = cur
    a
  end
  cases = {
    'c1.6' => [base, 'celsius'], 'f104.5' => [shift.call(104.5, 84, 108), 'fahrenheit'],
    'f112' => [shift.call(112, 92, 115), 'fahrenheit'], 'f-40' => [shift.call(-40, -45, -28), 'fahrenheit'],
    'c-23.5' => [shift.call(-23.5, -28, -17), 'celsius'],
    'c1.6-notitle' => [base, 'celsius', { 'hide_title_bar' => 'true' }]
  }
  all_views = %w[full half_horizontal half_vertical quadrant]
  screens = { 'x' => { device: 'v2' }, 'og' => { device: 'og_png' },
              'x-portrait' => { device: 'v2', orientation: :portrait }, 'x-large-text' => { device: 'v2', text_scale: 'large' },
              'x-dark' => { device: 'v2', dark_mode: true }, 'x-gray4' => { device: 'v2', palette: 'gray-4' },
              'og-bwry' => { device: 'og_bwry', palette: 'color-4bwry' }, 'six-colour' => { device: 'seeed_e1002', palette: 'color-6a' } }
  colour_screens = %w[x-dark x-gray4 og-bwry six-colour]
  only_screens = ENV['REVIEW_SCREENS']&.split(',')
  only = ENV['REVIEW_CASES']&.split(',')
  cases.each do |case_name, (answer, unit, extra)|
    next if only && !only.include?(case_name)

    # the sample day on every screen and view; the extremes on the X and OG, full and quadrant
    shots = screens.flat_map do |sn, sc|
      next [] if case_name != 'c1.6' && !%w[x og].include?(sn)
      next(sn == 'x' ? [["#{sn}_full", 'full', sc]] : [["#{sn}_full", 'full', sc], ["#{sn}_quadrant", 'quadrant', sc]]) if extra
      next [] if only_screens && !only_screens.include?(sn)

      views = if colour_screens.include?(sn) then %w[full half_horizontal quadrant]
              elsif case_name == 'c1.6' then all_views
              else %w[full quadrant]
              end
      views.map { |v| ["#{sn}_#{v}", v, sc] }
    end
    shots.each do |name, view, screen|
      it "#{case_name} #{name}" do
        fields = { 'lat_lon' => '52.52,13.41', 'unit' => unit,
                   'days_shown' => 'auto', 'dial_span' => '24h', 'hide_title_bar' => 'false' }.merge(extra || {})
        s = trmnl.render(view:, **screen, mocks: { 'https://api.open-meteo.com/*' => { json: answer } },
                         custom_fields: fields, now:,
                         wait_for: "document.querySelector('[data-sw-debug],[data-sw-error]') !== null")
        dir = File.join(TRMNLP::Testing.plugin_dir, 'renders')
        FileUtils.mkdir_p(dir)
        FileUtils.cp(s.png_path, File.join(dir, "#{case_name}_#{name}.png"))
        err = s.evaluate("(document.querySelector('[data-sw-error]')||{getAttribute:function(){return null}}).getAttribute('data-sw-error')")
        expect(err).to be_nil
        # every icon is TRMNL's own weather icon, none fell back to the drawn glyphs
        icons = JSON.parse(s.evaluate("document.querySelector('[data-sw-debug]').getAttribute('data-sw-debug')"))['icons']
        expect(icons['drawn']).to eq(0)
        expect(icons['wi']).to be > 0
      end
    end
  end
end
