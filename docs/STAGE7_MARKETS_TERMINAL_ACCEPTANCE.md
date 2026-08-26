# Stage 7 Markets Terminal Acceptance

**Status:** Stage 7 Markets Terminal Implementation Candidate — Awaiting Reviewer Gate  
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
