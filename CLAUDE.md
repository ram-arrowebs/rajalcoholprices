# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A single-page static site (PWA) that shows the Rajasthan government approved alcohol price list in a searchable, paginated table. Hosted on GitHub Pages at https://ram-arrowebs.github.io/rajalcoholprices/. There is no build step, package manager, linter, or test suite; everything is plain HTML/CSS/JS with libraries pulled from CDNs.

## Running locally

Open `index.html` directly or serve the directory with any static server, e.g.:

```
python3 -m http.server 8000
```

`data/` is gitignored, so on a fresh clone of `develop` there is no price data. Fetch a copy first:

```
mkdir -p data && curl -sSL "https://iems.rajasthan.gov.in/ApprovedRateList/ApprovedRateList/ApprovedRateGridList?type=0" | jq . > data/prices.json
```

The page uses `fetch()`, so it must be served over HTTP (not opened as a `file://` URL). The "Add to home screen" and manifest behaviour only works over `http://localhost` or HTTPS.

## Branching / deployment

- `main` is what GitHub Pages serves. `develop` is the working branch; changes land on `main` via pull request from `develop`.
- The scheduled workflow only runs on the default branch (`main`) and commits `data/prices.json` and `data/meta.json` there as `github-actions[bot]`. Merging `develop` into `main` will not conflict with those commits because `develop` never tracks `data/`.
- Legacy branches: `v1.0` (old IMPORTHTML-based version) and `holding` (a holding page). Leave them alone.

## Architecture (data flow)

All application logic lives in the inline `<script>` at the bottom of `index.html`.

1. **Source of truth** is the Rajasthan IEMS approved-rate JSON endpoint
   (`https://iems.rajasthan.gov.in/ApprovedRateList/ApprovedRateList/ApprovedRateGridList?type=0`). It has CORS issues, so the browser never calls it directly. Shape: `{"data": [{SerialNo, Type, BrandName, Packing, MSP, MRP}, ...]}`, ~2k rows, `Type` is one of BEER / COUNTRY LIQUOR / IMFL / RML.
2. **Snapshot:** `.github/workflows/fetch-prices.yml` runs daily (and on `workflow_dispatch`), curls the endpoint to a temp file, validates with `jq` that `.data` is a non-empty array, and only then writes `data/prices.json` (pretty-printed) and `data/meta.json` (`{fetchedAt, rows}`) and commits them with `git add -f`. Any failure before the write step leaves the previous commit's data intact and marks the run failed.
3. **Loading:** the inline script fetches `./data/prices.json` with `cache: "no-cache"` and maps each object to `[BrandName, Packing, MRP, Type]` (Packing stays numeric so the column sorts by volume; "ml" is appended in the display render). The `Type` column is `visible: false` and exists only so the Type dropdown can filter on it for `feedDataTable`. `./data/meta.json` is fetched separately to fill `#lastupdate` ("Prices as of <date>"); its absence is tolerated. Note `fetchedAt` is the date the list last *changed*, because the workflow only commits when `prices.json` differs.
4. **Offline:** `sw.js` is registered from the inline script. On install it caches the app shell, the pinned CDN libraries and the fonts their CSS references (discovered by parsing `url(...)`), plus the current `data/*.json`. At runtime, same-origin requests are network-first with cache fallback, CDN hosts are cache-first, and a `data/*.json` fallback carries an `X-Offline-Copy: 1` header that the page turns into an "(offline copy)" suffix on the date label. Bump `CACHE` in `sw.js` when changing the CDN list or shell files so stale entries are purged on activate.
5. **Presentation:** DataTables (Bootstrap 5 theme) renders the table. Column `render` callbacks handle display formatting (proper-casing item names via `toProperCase`, which keeps `KEEP_UPPER` abbreviations, vowel-less tokens, roman numerals and digit-bearing tokens upper-case and lower-cases units via `SPECIAL_CASE`; `en-IN` currency formatting of price for `display` type only so sorting stays numeric).
6. **Loading overlay:** `#overlay` (SVG spinner) is shown on document ready and hidden in DataTables' `fnInitComplete`.

Supporting files: `sw.js` (offline cache), `a2hs.js` (Add-to-Home-Screen prompt handling), `manifest.webmanifest` + `icon/` + `browserconfig.xml` (PWA/favicon assets), `qr-code.png` (share link).

## Current state / gotchas

- The Type filter is a `<select>` built in `addTypeFilter` from the hidden column's unique values and prepended into DataTables' own `#rajprice_filter` container (next to the search input). Option labels are proper-cased except for entries in `TYPE_ACRONYMS`; option values stay raw. It uses an anchored-regex column search so values like `RML` and `IMFL` match exactly.
- The Add-to-Home-Screen button (`a2hs.js`) only shows when Chrome fires `beforeinstallprompt`, which requires the manifest to list both 192px and 512px icons. Chrome decides when to fire it; it is not shown on every visit.
- GitHub disables scheduled workflows after 60 days without repository activity; if the data stops refreshing, re-enable it under the Actions tab or trigger `workflow_dispatch`.
- CDN library versions are pinned in `index.html` (jQuery 3.6.0, DataTables 1.11.0, Bootstrap 5.0.1). Keep the DataTables JS and its Bootstrap 5 integration on the same version when upgrading.
- `.gitignore` excludes `manifest.json` and `spinner.html`; the live manifest is `manifest.webmanifest`.
