# trmnl-yt-subscriber-count

A TRMNL plugin that shows one YouTube channel's subscriber count. That's it.

Two-way synced with TRMNL: saving in the plugin editor commits here, and pushing here surfaces an
"import from GitHub" prompt in TRMNL.

## Setup

One credential, supplied by whoever installs the plugin:

1. [console.cloud.google.com](https://console.cloud.google.com) → create a project
2. APIs & Services → Library → enable **YouTube Data API v3**
3. Credentials → Create credentials → **API key**
4. Restrict it: **API restrictions → YouTube Data API v3** only

> Do **not** add an *Application* restriction (HTTP referrer / IP). TRMNL polls server-side with no
> referrer, so an application restriction silently 403s every request. This is the most common setup
> mistake; the plugin surfaces it as a blank screen.

Then set the two plugin fields: **Channel** (`mkbhd`, `@mkbhd`, or `UCBJycsmduvYEL83R_U4JriQ`) and
**YouTube Data API Key**.

## Quota

`channels.list` costs **1 unit** per call no matter how many `part`s you request, against a default
**10,000 units/day**. At the 15-minute refresh interval that is 96 units/day — under 1%.

The polling URL deliberately never touches `search.list`, which costs **100 units**. That is why it
resolves handles and IDs directly rather than accepting a free-text channel name.

## Subscriber counts are rounded — by YouTube, for everyone

Above 1,000 subscribers YouTube rounds `subscriberCount` to **three significant figures**
(1,234,567 → `1230000`). Exact counts exist only in YouTube Studio, for the channel owner. Every
third-party counter shows this same rounded number.

So the display is abbreviated (`99.2K`, `20.2M`) rather than fake-precise, and it will sit unchanged
for days at a time on a large channel — the underlying number only moves when it crosses a rounding
boundary. Channels that hide their count render a "Hidden" state rather than a misleading zero.

## Files

```
src/settings.yml   strategy, polling URL, form fields   (TRMNL owns the schema — edit values, not keys)
src/shared.liquid  parsing + number formatting, no markup
src/full.liquid            }
src/half_horizontal.liquid } the four layouts; all are required for mashups
src/half_vertical.liquid   }
src/quadrant.liquid        }
settings.worker.yml        optional: poll a proxy instead of Google directly (see below)
```

Two things about the layouts that are easy to get wrong:

- **Shared is prepended, not included.** TRMNL concatenates `shared.liquid` onto every view before
  rendering, so a layout must never `{% include "shared" %}`.
- **Layouts do not wrap themselves in `.view`.** TRMNL supplies that wrapper. Each layout starts at
  `<div class="layout ...">` with `<div class="title_bar">` as a *sibling*.

The count uses responsive value classes (`lg:`, `portrait:`) so it does not overflow on TRMNL X in
portrait orientation.

## Tests

```sh
gem install liquid -v 5.3.0 && ruby test/format_test.rb   # Ruby Liquid — what TRMNL runs
npm install && npm test                                    # liquidjs
```

Both render the same case table. They are not redundant: the two engines disagree on `divided_by`
(Ruby truncates integer division, liquidjs returns a float), which once produced `1.23.23M`. Every
division in `shared.liquid` is followed by an explicit `| floor` for that reason.

The suite also renders the **polling URL**, which is Liquid too and is otherwise easy to break — a
missing `{% assign %}` yields a silent `forHandle=` with no value, and plain `{% %}` tags leave blank
lines that TRMNL reads as additional URLs.

## Optional: proxy instead of direct polling

`settings.worker.yml` points the plugin at a small proxy that holds the API key server-side. Copy it
over `src/settings.yml` and set your endpoint. This buys three things a direct poll cannot give you:

- no API key in the plugin config, so the plugin is installable with **one** field
- a subscriber **delta** — TRMNL's polling strategy is stateless and retains no previous value, so a
  change indicator is impossible without something that remembers
- free-text channel names, because a proxy can afford the 100-unit `search` call once and cache the
  resulting channel ID forever

A reference implementation lives in
[shaztechio/youtube-subs-widget](https://github.com/shaztechio/youtube-subs-widget), alongside iOS and
macOS widgets that share the same backend.
