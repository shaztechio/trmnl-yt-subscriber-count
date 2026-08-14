import { Liquid } from 'liquidjs'
import { readFileSync } from 'fs'

const SRC = new URL('../src', import.meta.url).pathname
// No `root`/include resolution on purpose: TRMNL concatenates shared.liquid
// onto each view rather than including it, so the harness must do the same.
const engine = new Liquid()
const SHARED = readFileSync(`${SRC}/shared.liquid`, 'utf8')
const viewSource = (name) => SHARED + readFileSync(`${SRC}/${name}.liquid`, 'utf8')

// Render shared.liquid then echo the computed vars so we can assert on them.
const probe = SHARED +
  '\n<<{{ count_text }}|{{ delta_text }}|{{ ok }}|{{ hidden }}|{{ title }}>>'

const google = (subs, title = 'Test', hidden = false) => ({
  items: [{ snippet: { title }, statistics: hidden ? { hiddenSubscriberCount: true } : { subscriberCount: String(subs), hiddenSubscriberCount: false } }]
})
const worker = (o) => o

const cases = [
  // [label, payload, expected count_text]
  ['0 subs',            google(0),          '0'],
  ['1 sub',             google(1),          '1'],
  ['999 (no rounding)', google(999),        '999'],
  ['1000 boundary',     google(1000),       '1K'],
  ['1234 -> 1.23K',     google(1230),       '1.23K'],
  ['12.3K',             google(12300),      '12.3K'],
  ['123K',              google(123000),     '123K'],
  ['999K',              google(999000),     '999K'],
  ['1M boundary',       google(1000000),    '1M'],
  ['1.23M',             google(1230000),    '1.23M'],
  ['20.2M (mkbhd)',     google(20200000),   '20.2M'],
  ['exactly 20M',       google(20000000),   '20M'],
  ['202M',              google(202000000),  '202M'],
  ['1B',                google(1000000000), '1B'],
  // Worker shape
  ['worker 20.2M',      worker({ channelId: 'UC1', title: 'W', subscriberCount: 20200000, hidden: false, delta: 100000 }), '20.2M'],
  ['worker small',      worker({ channelId: 'UC1', title: 'W', subscriberCount: 842, hidden: false, delta: -3 }), '842'],
]

let fail = 0
for (const [label, data, expect] of cases) {
  const out = await engine.parseAndRender(probe, data)
  const m = out.match(/<<(.*?)>>/s)
  const [count, delta, ok, hidden] = m[1].split('|')
  const pass = count.trim() === expect
  if (!pass) fail++
  console.log(`${pass ? 'ok  ' : 'FAIL'} ${label.padEnd(20)} got=${JSON.stringify(count.trim()).padEnd(10)} want=${JSON.stringify(expect).padEnd(10)} delta=${JSON.stringify(delta.trim())} ok=${ok.trim()}`)
}

// Edge states
for (const [label, data] of [
  ['hidden count', google(0, 'H', true)],
  ['empty items',  { items: [] }],
  ['error body',   { error: { code: 403 } }],
]) {
  const out = await engine.parseAndRender(probe, data)
  const m = out.match(/<<(.*?)>>/s)
  const [count, delta, ok, hidden] = m[1].split('|')
  console.log(`     ${label.padEnd(20)} count=${JSON.stringify(count.trim())} ok=${ok.trim()} hidden=${hidden.trim()}`)
}

// Render each layout to prove they parse
for (const v of ['full', 'half_horizontal', 'half_vertical', 'quadrant']) {
  try {
    const html = await engine.parseAndRender(viewSource(v), google(20200000, 'Marques Brownlee'))
    console.log(`ok   layout ${v.padEnd(16)} ${html.replace(/\s+/g, ' ').trim().length} chars`)
  } catch (e) { fail++; console.log(`FAIL layout ${v}: ${e.message}`) }
}

console.log(fail ? `\n${fail} FAILURES` : '\nall passed')
