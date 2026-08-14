# Renders the templates through Shopify's Ruby Liquid — the engine TRMNL
# actually runs — rather than only liquidjs.
#
# This is not redundant with format.test.mjs. The two engines disagree:
# `divided_by` truncates on integers in Ruby but returns a float in liquidjs,
# and that divergence produced a real formatting bug here. Asserting the same
# case table in both is the point.
#
#   gem install liquid && ruby test/format_test.rb

require 'liquid'
require 'json'

SRC = File.expand_path('../src', __dir__)

# TRMNL concatenates shared.liquid onto each view before rendering rather than
# including it (trmnlp lib/trmnlp/renderer.rb). Modelling that faithfully
# matters: an {% include %}-based harness passes against templates that would
# fail on the real platform, which is exactly what happened here.
SHARED = File.read(File.join(SRC, 'shared.liquid'))

def view_source(name)
  SHARED + File.read(File.join(SRC, "#{name}.liquid"))
end

PROBE = SHARED +
        "\n<<{{ count_text }}|{{ delta_text }}|{{ ok }}|{{ hidden }}|{{ title }}>>"

def google(subs, title: 'Test', hidden: false)
  stats = hidden ? { 'hiddenSubscriberCount' => true }
                 : { 'subscriberCount' => subs.to_s, 'hiddenSubscriberCount' => false }
  { 'items' => [{ 'snippet' => { 'title' => title }, 'statistics' => stats }] }
end

def render(template, assigns)
  Liquid::Template.parse(template).render(assigns)
end

def probe(assigns)
  out = render(PROBE, assigns)
  out[/<<(.*?)>>/m, 1].split('|', -1).map(&:strip)
end

CASES = [
  ['0 subs',            google(0),          '0'],
  ['999 (unrounded)',   google(999),        '999'],
  ['1000 boundary',     google(1000),       '1K'],
  ['1230 -> 1.23K',     google(1230),       '1.23K'],
  ['12.3K',             google(12_300),     '12.3K'],
  ['123K',              google(123_000),    '123K'],
  ['999K',              google(999_000),    '999K'],
  ['1M boundary',       google(1_000_000),  '1M'],
  ['1.02M (pad)',       google(1_020_000),  '1.02M'],
  ['1.2M (trim)',       google(1_200_000),  '1.2M'],
  ['1.23M',             google(1_230_000),  '1.23M'],
  ['exactly 20M',       google(20_000_000), '20M'],
  ['20.2M (mkbhd)',     google(20_200_000), '20.2M'],
  ['202M',              google(202_000_000), '202M'],
  ['1B',                google(1_000_000_000), '1B'],
  # Worker response shape
  ['worker 20.2M', { 'channelId' => 'UC1', 'title' => 'W', 'subscriberCount' => 20_200_000,
                     'hidden' => false, 'delta' => 100_000 }, '20.2M'],
  ['worker small', { 'channelId' => 'UC1', 'title' => 'W', 'subscriberCount' => 842,
                     'hidden' => false, 'delta' => -3 }, '842'],
].freeze

failures = 0

CASES.each do |label, assigns, expected|
  count, delta, ok, = probe(assigns)
  pass = count == expected
  failures += 1 unless pass
  puts format('%-4s %-18s got=%-9s want=%-9s delta=%-8s ok=%s',
              pass ? 'ok' : 'FAIL', label, count.inspect, expected.inspect, delta.inspect, ok)
end

# Delta sign handling, which only the Worker shape exercises.
{ 100_000 => '+100000', -2500 => '-2500' }.each do |delta, expected|
  _, got, = probe({ 'channelId' => 'UC1', 'title' => 'W', 'subscriberCount' => 1000,
                    'hidden' => false, 'delta' => delta })
  pass = got == expected
  failures += 1 unless pass
  puts format('%-4s %-18s got=%s want=%s', pass ? 'ok' : 'FAIL', "delta #{delta}", got.inspect, expected.inspect)
end

# Degenerate payloads must not raise and must report ok=false.
[['empty items', { 'items' => [] }], ['error body', { 'error' => { 'code' => 403 } }],
 ['hidden count', google(0, hidden: true)]].each do |label, assigns|
  count, _, ok, hidden = probe(assigns)
  puts format('     %-18s count=%-6s ok=%-6s hidden=%s', label, count.inspect, ok, hidden)
end

# Every layout must parse and render under the real engine.
%w[full half_horizontal half_vertical quadrant].each do |view|
  template = Liquid::Template.parse(view_source(view))
  html = template.render(google(20_200_000, title: 'Marques Brownlee'))
  if template.errors.any?
    failures += 1
    puts "FAIL layout #{view}: #{template.errors.map(&:message).join('; ')}"
  else
    puts format('ok   layout %-16s %d chars', view, html.gsub(/\s+/, ' ').strip.length)
  end
end

# Structural guards. Both of these rendered fine under an {% include %}-based
# harness while being broken on the actual platform, so assert them directly.
%w[full half_horizontal half_vertical quadrant].each do |view|
  # Strip {% comment %} blocks first — the comments in these files describe the
  # very patterns being banned, and would otherwise trip the checks.
  body = File.read(File.join(SRC, "#{view}.liquid"))
          .gsub(/\{%-?\s*comment\s*-?%\}.*?\{%-?\s*endcomment\s*-?%\}/m, '')

  if body.match?(/\{%-?\s*(include|render)\s+["']shared["']/)
    failures += 1
    puts "FAIL #{view}: includes shared, but TRMNL already prepends it"
  end

  if body.match?(/class=["'][^"']*\bview\b/)
    failures += 1
    puts "FAIL #{view}: wraps itself in a .view div, which TRMNL supplies"
  end

  unless body.include?('class="layout')
    failures += 1
    puts "FAIL #{view}: has no .layout container"
  end
end
puts 'ok   layouts: no stray include, no self-supplied .view wrapper'

# The polling URL is Liquid too — TRMNL renders it before splitting the result
# on line breaks. Two things go wrong here and neither shows up in the layouts:
# dropping the {% assign %} lines yields a silent "forHandle=" with no value,
# and plain {% %} tags leave blank lines that TRMNL may read as extra URLs.
require 'yaml'

polling = YAML.load_file(File.join(SRC, 'settings.yml'))['polling_url']

[['bare handle', 'mkbhd',                    'forHandle=mkbhd'],
 ['@handle',     '@mkbhd',                   'forHandle=mkbhd'],
 ['padded',      '  @mkbhd  ',               'forHandle=mkbhd'],
 ['channel ID',  'UCBJycsmduvYEL83R_U4JriQ', 'id=UCBJycsmduvYEL83R_U4JriQ'],
 ['name w/space', 'Marques Brownlee',        'forHandle=Marques+Brownlee']].each do |label, channel, expected|
  rendered = render(polling, 'channel' => channel, 'api_key' => 'AIzaTESTKEY')
  urls = rendered.split("\n").reject { |l| l.strip.empty? }
  ok = rendered.include?(expected) && urls.size == 1 && rendered.split("\n").size == 1
  failures += 1 unless ok
  puts format('%-4s polling %-13s %s', ok ? 'ok' : 'FAIL', label,
              ok ? expected : rendered.inspect)
end

# A missing key must not silently produce a URL that looks valid.
bad = render(polling, 'channel' => '', 'api_key' => 'K')
if bad.include?('forHandle=&')
  puts 'ok   polling empty channel yields forHandle=& (caller must validate)'
else
  puts "FAIL polling empty channel: #{bad.inspect}"
  failures += 1
end

puts failures.zero? ? "\nall passed (Ruby Liquid #{Liquid::VERSION})" : "\n#{failures} FAILURES"
exit(failures.zero? ? 0 : 1)
