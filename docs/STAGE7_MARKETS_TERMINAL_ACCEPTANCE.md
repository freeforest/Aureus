# Stage 7 Markets Terminal Acceptance

**Status:** Stage 7AA Native Chart Accessibility Gate Closure Candidate — Awaiting Reviewer Gate  
**Implementation date:** 2026-08-26  
**Authority:** This document records implementation and synthetic verification evidence. It does not decide the Stage 7 Gate or extend live Provider acceptance.

## 1. Evidence boundary

Stage 7 inherits, without expansion, the Stage 6NBC evidence that `AAPL/USD/XNGS` Search identity and the precise `1day`/`.all` Historical operation succeeded for the then-current credential at the observed instant. Actual Plan, Quote, Split, Dividend, actual freshness, other symbols and MICs, and `XHKG`/`XSHG`/`XSHE`/`XJPX` remain `NOT VERIFIED`.

No real Twelve Data or Frankfurter request was made by Stage 7 implementation or automated verification. Production does not request data on App launch or merely on entering Markets. Search and daily Historical refresh require explicit user action and continue through `MarketDataService` and the actor-owned `TransientMarketSessionStore`.

## 2. Product surface

- A four-market capability overview always shows US, Hong Kong, Mainland China, and Japan with honest verified-scope or Not Verified states.
- Symbol Search preserves Provider relevance order and raw MIC identity.
- Watchlist persistence stores only normalized symbol, normalized raw MIC, order, selected daily range, enabled indicator kinds, and presentation preference. Provider descriptions, currency, values, freshness, fetch times, observations, and chart payloads are excluded.
- Session Watchlist Heatmap uses equal-area tiles and current in-memory daily bars only. Unknown data is shown as Unknown and direction is expressed with text/symbols in addition to color.
- Stock Detail uses daily `.all` semantics, says `Latest Daily Close`, exposes Unknown freshness honestly, and does not claim market cap or intraday data.
- The native accessible surface contains a visible-range summary and a daily O/H/L/C/Volume/freshness table; the WebView is not the only information source.

## 3. Indicator contract

Swift computes all authoritative values with checked `Decimal` arithmetic before the display bridge:

| Indicator | Frozen calculation |
|---|---|
| SMA | Window mean; first point at the Nth valid close |
| EMA | `alpha = 2 / (N + 1)` with SMA seed |
| RSI | Period 14, Wilder smoothing; rising 100, flat 50 |
| MACD | EMA12 − EMA26; signal EMA9; histogram difference |
| Bollinger Bands | SMA20 ± 2 population standard deviations |

Input dates must be strictly ascending and unique. Invalid OHLCV, overflow, and invalid division produce typed failures; insufficient history produces empty series rather than zero-filled data. Only checked finite `Double` values cross into the renderer.

## 4. Chart renderer

TradingView Lightweight Charts 5.2.0 is bundled from the official npm distribution. The upstream JavaScript is byte-for-byte pinned; provenance and hashes are in [`PROVENANCE.md`](../Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/PROVENANCE.md). License and notice information is in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

The `WKWebView` uses `WKWebsiteDataStore.nonPersistent()`, loads only bundle resources, applies a Content Security Policy with `connect-src 'none'`, rejects remote navigation and new windows, and removes its message handler during teardown. The versioned Codable bridge carries bounded chart data and finite display values only. It never receives a credential, account, wealth, ledger, snapshot, authenticated URL, or raw Provider payload.

## 5. Persistence and capability matrix

| Area | Stage 7 state |
|---|---|
| Twelve Data Session Store | Enabled, actor-owned, 64 MiB, lifecycle-cleared |
| Twelve Data persistent reads/writes | Disabled by product policy |
| Retention rights | BLOCKED |
| Identifier-only watchlist/UI preferences | Enabled through isolated typed preferences store |
| US observed scope | AAPL/XNGS Search + precise daily Historical at prior observation instant only |
| Actual Plan | NOT VERIFIED |
| Quote / Split / Dividend | NOT VERIFIED |
| Actual freshness | NOT VERIFIED |
| International MICs | NOT VERIFIED |
| Synthetic Demo | Automated implementation evidence only; never live proof |

Frankfurter/ECB cache policy and Permanent Store ownership remain independent. Session clear cannot delete Wealth, Ledger, Dashboard Snapshot, or authorized unrelated Provider cache rows.

## 6. Verification policy

Stage 7 focused tests cover deterministic indicators, 10,000-bar workloads, preferences minimization and isolation, explicit-only requests, generation cancellation, session clear, bridge schema/limits, local asset integrity, CSP/navigation restrictions, synthetic/Production UI separation, and native accessibility. Full Stage 6 and existing Settings/Ledger/CSV regressions remain mandatory.

Build or test success does not decide the Reviewer Gate and does not establish Provider entitlement. Stage 8 is outside this implementation candidate.

## 7. Local implementation evidence — 2026-08-26

- Final Debug arm64 clean build: `PASS`.
- Final build-for-testing: `PASS`.
- Stage 7 focused Unit/Integration: `19/19 PASS`.
- Stage 6 focused regression: `81/81 PASS` (`90` parameterized executions).
- Full Unit/Integration: `203/203 PASS` (`236` parameterized executions), using the stable unsigned Unit host after the signed host was denied access to its isolated `/private/tmp` test workspace.
- Strengthened Markets UI, including exact `Chart ready`, repeat indicator toggles, native accessible table, and Session clear: `1/1 PASS`.
- Settings, Ledger Dynamic, and Native CSV focused UI: `1/1 PASS` each.
- Final full UI suite: `11/11 PASS`.
- Deterministic 10,000-bar indicator calculation: `4.472 s`; 10,000-bar bridge encoding: `3.209 s`; 1,000 repeated visible-range/indicator bridge changes: `14.755 s` on the recorded local Mac/Xcode environment.
- Real Provider requests: `NOT RUN`. These synthetic and local results do not expand the live matrix.

## 8. Reviewer Prompt 7 decision and Stage 7A findings

Reviewer classified Prompt 7 and the Stage 7 Gate as `PARTIAL`. The accepted Lightweight Charts asset/license and Session/Persistent isolation boundaries remain unchanged. Stage 7A addresses eight bounded findings without entering Stage 8:

1. the prior Stage 6NBC acceptance record is separated from a current zero-network `capabilities()` snapshot;
2. chart panes use typed semantic identities and the JavaScript renderer no longer applies a generic offset;
3. ranges use Gregorian UTC civil-date request windows and inclusive presentation filtering rather than describing `outputSize` as a calendar duration;
4. typed visible-range callbacks drive the native visible subset, summary, table, and enabled-indicator accessibility text;
5. heatmap and summary calculations use a typed checked-Decimal presentation boundary;
6. the heatmap retains multiple range-scoped instrument presentations in memory only;
7. Watchlist Move Up/Move Down controls persist identifier order;
8. light/dark appearance and encoded-byte/string/date/line bounds are enforced in Swift and defensively in the local JavaScript integration.

## 9. Stage 7A repaired contracts

| Contract | Stage 7A behavior |
|---|---|
| Historical acceptance record | Read-only Stage 6NBC evidence, explicitly limited to the credential and instant used then. |
| Current Provider state | Loaded with zero-network `capabilities()` on start, explicit refresh, and operation/clear terminals; no current observation means no current `Verified` claim. |
| Chart panes | Candlestick and SMA/EMA/Bollinger `0`; Volume `1`; RSI `2`; MACD/Signal/Histogram `3`. |
| Renderer evidence | Versioned sanitized identifier/type/pane/point-count summary; no market values. |
| Range policy | Latest returned daily bar for `1D`; calendar UTC `1W/1M/3M/YTD/1Y/5Y`; `MAX` has no start date and caps output at 5,000. |
| Native accessibility | Typed and clamped visible range; visible-subset summary/table; enabled SMA/EMA/RSI/MACD/Bollinger values aligned by session date, with `Unavailable` for insufficient history. |
| Presentation arithmetic | Checked Decimal add/subtract/multiply/divide/magnitude/sum; typed failures are unavailable, never zero fallback. |
| Session heatmap | Multiple Watchlist instruments keyed by symbol/raw MIC/range in Feature-owned transient memory; Session Clear removes values. |
| Watchlist order | Native identity-addressed Move Up/Move Down, persisted with identifier-only preferences. |
| Bridge bounds | 10,000 bars, 16 lines, 10,000 points per line, 6 MiB encoded JSON, bounded strings, canonical dates, typed panes, and six-digit colors. |

Stage 7A automated evidence is synthetic/local only. Real Provider requests are `NOT RUN`; Actual Plan, Quote, Split, Dividend, actual freshness, other US identities/MICs, and all international MICs remain `NOT VERIFIED`. Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 8 remains `NO-GO` pending Reviewer decision.

## 10. Stage 7A local verification — 2026-08-26

- Final Debug arm64 clean build: `PASS`.
- Final build-for-testing: `PASS`.
- Stage 7A focused Unit/Integration: `26/26 PASS`.
- Stage 6 focused regression: `67/67 PASS`.
- Full Unit/Integration: the signed host first failed because its isolated `/private/tmp` workspace was denied by the test sandbox; the required stable unsigned-host rerun completed `210/210 PASS` (`243` parameterized executions).
- Settings, Ledger Dynamic, and Native CSV focused UI: `1/1 PASS` each.
- Stage 7 focused UI: `FAIL`; the renderer completed, but the native visible-range accessibility state was not exposed through the asserted AX element. The one allowed focused retry also failed.
- Full UI suite, first run: `10/11 PASS`; only the Stage 7 accessibility assertion failed.
- Full UI suite, one allowed bounded retry: `10/11 PASS`; only the Stage 7 chart-status accessibility label assertion failed.
- A final deterministic repair gives the chart status and visible range separate, explicit accessibility elements and labels. Final clean build and build-for-testing pass with that source, but no further UI run was made after the bounded retry budget was exhausted. This final accessibility repair is therefore `NOT VERIFIED` by UI automation in this round.
- Real Provider requests: `NOT RUN`. Live capability evidence is unchanged.

Consequently this remains a Stage 7A implementation candidate with `PARTIAL` UI evidence. This document does not claim Stage 7 Gate `PASS` or authorize Stage 8.

## 11. Stage 7AA native chart accessibility verification — 2026-08-26

Prompt 7AA preserved the four Stage 7A failed xcresults above as historical evidence and tested the final accessibility source without any pre-test Production or Test source change. The final contract exposes `markets.chart.status` and `markets.chart.visible-range` as separate native semantic nodes; the test reads each node's label independently and does not use a combined status value or transient WebView child tree.

- Fresh signed build-for-testing: `PASS`.
- First and final Stage 7 focused UI: `1/1 PASS`; status label was exactly `Chart ready`, visible-range label contained `Visible range`, the sanitized render summary remained accessible, and indicator toggling preserved the ready status.
- AX-only repair: `None`; the first focused run passed, so no source modification or second focused run was authorized or performed.
- Single authorized full UI suite: `11/11 PASS`; no full-suite retry was performed.
- Stage 7A focused Unit/Integration: `26/26 PASS`.
- Stable unsigned full Unit/Integration: `210/210 PASS` (`243` parameterized executions).
- Final Debug arm64 clean build and final build-for-testing: `PASS`.
- Real Provider requests: `NOT RUN`; Provider capability and live acceptance evidence are unchanged.

This is a **Stage 7AA Native Chart Accessibility Gate Closure Candidate — Awaiting Reviewer Gate**. Twelve Data persistent writes remain `Disabled`, retention remains `BLOCKED`, and Stage 8 remains `NO-GO`. This document does not declare the Stage 7 Gate passed.
