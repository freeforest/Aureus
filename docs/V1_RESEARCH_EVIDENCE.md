# Aureus V1 Research Evidence

## 1. Purpose, Method, and Evidence Labels

**Status:** Stage 1 Frozen / Reviewer Gate PASS — 2026-08-11; original research visited 2026-08-10, Twelve Data decision refresh visited 2026-08-11.  
**Authority:** This file records evidence and comparison; it does not override the frozen [`V1_SCOPE.md`](V1_SCOPE.md) or [`V1_ARCHITECTURE.md`](V1_ARCHITECTURE.md). The Reviewer Gate decision of PASS was recorded on 2026-08-11.

Research used only primary sources as formal evidence: Apple and Swift documentation, official project documentation/repositories/licenses/releases, and provider-owned API/pricing/terms/attribution/status pages. Search results were used only to locate pages and are not cited as evidence. No account was created, no API key was requested, no credentialed endpoint was called, no dependency was installed, and no package was resolved. The user authorized Twelve Data, BYOK, and the tiered Basic/Pro-or-higher product boundary on 2026-08-10; this evidence records that decision but does not claim the Reviewer Gate or Stage 6 real-Provider acceptance.

Comparison notation:

- **[F] Fact:** directly observed in an official source.
- **[I] Inference:** Executor interpretation derived from cited facts; not stated verbatim by the source.
- **[R] Recommendation:** Executor's single proposed V1 choice.
- **[C] Candidate:** marks a recommendation as it stood during research; frozen outcomes are identified by the current status and architecture decision register.
- **VERIFIED:** the stated fact was directly supported by accessible official material.
- **UNVERIFIED:** official material did not establish the fact needed by Aureus.
- **CONFLICTING:** official pages materially disagreed or left incompatible interpretations.

Provider matrix values such as “unsupported” are used only where official material says so. A dash or `UNVERIFIED` is not treated as absence of real-world service capability; it means the capability cannot safely support this decision from current official evidence.

## 2. Local Toolchain Evidence

All commands were run read-only from `/Users/freeforest/Aureus_Wealth_Terminal`. No Git or GitHub command was run.

| Command | Exit | Observed output |
|---|---:|---|
| `sw_vers` | 0 | ProductName `macOS`; ProductVersion `26.5.2`; BuildVersion `25F84`. |
| `uname -m` | 0 | `arm64`. |
| `xcodebuild -version` | 0 | `Xcode 26.6`; Build version `17F113`. |
| `xcode-select -p` | 0 | `/Applications/Xcode.app/Contents/Developer`. |
| `xcrun --show-sdk-version` | 0 | `26.5`. Xcode also emitted warnings that its filesystem event stream did not start and `DARWIN_USER_CACHE_DIR` length could not be read, so it used `NSCachesDirectory`; the SDK query itself completed successfully. |
| `swift --version` | 0 | `swift-driver version: 1.148.6`; `Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)`; target `arm64-apple-macosx26.0`. |

**Finding:** [F] A complete Xcode path, macOS SDK, and arm64 Swift toolchain are present. [I] The warning on the SDK query is a local Xcode environment limitation worth retaining in evidence, but it did not block a version-only read. No build conclusion can be made because this Stage creates no build target.

## 3. Deployment Target Evidence

| Topic | Official observation | Evidence state | Aureus impact |
|---|---|---|---|
| Xcode deployment range | [F] Apple's Xcode 26.6 system-requirements table lists macOS deployment target support from macOS 11 through macOS 26.5. | VERIFIED, P-01 | macOS 14 is supported by the installed Xcode; using SDK 26.5 does not force a macOS 26 minimum. |
| Toolchain | [F] Xcode 26.6 release notes identify the macOS 26.5 SDK and Swift 6.3 toolchain family. Local commands report Swift 6.3.3. | VERIFIED, P-02 + local | Swift 6 language mode is a compatible candidate foundation. |
| Observation | [F] Apple's “Discover Observation in SwiftUI” describes `@Observable` model types and SwiftUI dependency tracking, introduced with the Observation framework generation. | VERIFIED, P-03 | macOS 14 provides a simple native state baseline. |
| SwiftData availability and model | [F] Apple's SwiftData materials introduce it with macOS Sonoma-era platforms and describe schema/model migration plans. | VERIFIED, P-04/P-05 | It is deployable at macOS 14, but availability alone does not make it the chosen finance store. |
| Core Data | [F] Apple documents object-graph persistence, automatic migration, and staged migration. | VERIFIED, P-06/P-07 | Core Data is a viable system alternative and was compared rather than dismissed as unsupported. |
| Swift 6 checking | [F] Swift's official migration guide describes enabling Swift 6 language mode per target and complete concurrency checking. | VERIFIED, P-08 | Starting in Swift 6 mode reduces a later concurrency migration. |
| SwiftUI charts | [F] Apple documents Charts across Apple platforms, accessibility support, selection/scrolling, and vectorized plots for larger datasets. | VERIFIED, P-15/P-16/P-17 | Swift Charts is viable for native wealth statistics and heatmap-like views. |
| Sandbox distribution | [F] Apple documents App Sandbox as required for Mac App Store distribution and describes standard container locations and user-selected file access. | VERIFIED, P-11/P-12 | Sandbox and security-scoped workflows must exist from foundation even though distribution remains user-controlled. |

**[R][C] Deployment candidate:** macOS 14.0 minimum, Xcode 26.6/macOS 26.5 SDK baseline, Swift 6 mode, Apple Silicon arm64 V1. It balances native Observation availability against unnecessary latest-OS exclusion. Universal Binary, signing identity, notarization, and distribution channel are not claimed without explicit user authority.

## 4. Persistence Comparison Matrix

### 4.1 Technical comparison

| Candidate | macOS range / license | Migration | SQLite and transaction control | Concurrency/testability | Money precision fit | Dependency/maintenance | Result |
|---|---|---|---|---|---|---|---|
| SwiftData | [F] Sonoma-generation API; Apple system framework. | [F] `SchemaMigrationPlan`, versioned schemas, custom stages; coexistence material exists. | [I] SQLite is an implementation detail rather than the application contract; SQL schema/check/index/transaction control is less direct. | [F] Model containers/contexts are testable; Apple continues documenting concurrency/model evolution. | [I] Semantic fixed-point wrappers still need application mapping and migration discipline. | No external package; maintained by Apple. | **REJECT** for V1 persistence; supported but less explicit than required. |
| Core Data | [F] Mature Apple system framework across the deployment range. | [F] Lightweight, custom, and staged migrations. | [I] Strong transaction/object-context semantics, but direct relational schema/SQL control is not its primary abstraction. | [F] Background contexts/concurrency APIs; in-memory and temporary persistent stores are testable. | [I] Decimal/fixed-point mapping is possible, but finance constraints remain application work. | No external package; maintained by Apple. | **REJECT**; viable but object-graph/migration complexity does not improve this relational finance design. |
| GRDB | [F] GRDB 7.11.1 requires macOS 10.15+, Swift 6.1+, Xcode 16.3+; MIT. | [F] `DatabaseMigrator` and explicit schema migrations. | [F] Explicit SQL, transactions, savepoints, backup, WAL/pool/queue choices, records and observation. | [F] `DatabaseQueue`, `DatabasePool`, async/concurrency guidance, in-memory/temporary DB support. | [I] INTEGER fixed-point columns, checks, and explicit decoding match the frozen types directly. | One SwiftPM dependency; release 7.11.1 dated 2026-06-18; active official repository. | **ACCEPT — [R][C] V1 primary persistence.** |
| Direct SQLite C API | [F] SQLite is public domain and provides transactions with one writer/multiple readers. | Application-owned version table and scripts. | Maximum SQL/connection control. | [I] Fully testable, but the app must implement safe binding, decoding, statement lifecycle, migration, concurrency, and backup wrappers. | Exact INTEGER fixed-point fit. | No package beyond system SQLite; high internal code cost. | **REJECT**; necessary control without necessary ergonomics. |

### 4.2 Decision reasoning

- **[R][C] Choice:** GRDB 7.11.x over system SQLite, using one actor-owned `DatabaseQueue` for the permanent store and another for the physically separate market cache.
- **[I] Why it wins:** Aureus needs explicit fixed-point columns, schema constraints, migrations, transaction boundaries, backup, and test stores more than object-graph conveniences. GRDB supplies those without reimplementing the SQLite C lifecycle.
- **Tradeoff:** it is the only Stage 2 external dependency and makes SQL/schema ownership explicit application work.
- **Compatibility finding:** VERIFIED. GRDB's stated minimums are below macOS 14 and the local Swift/Xcode versions.
- **License finding:** VERIFIED MIT license; compatible with a permissive open-source application, subject to retaining its license notice.

Official evidence: D-01 through D-05 in the [source register](#10-official-source-register).

## 5. Market Provider Comparison Matrix

“Production Provider” below means a real, supported non-Mock data path; it does not make real-time or high-frequency data a V1 requirement. The minimum acceptable freshness is documented EOD or delayed data suitable for the required screens, with stale state shown explicitly. Open-source Aureus source code, each user supplying a personal key, data cached only on that user's Mac, Provider data excluded from the Repository, and redistribution of Provider data are separate legal/technical facts. No account, key, subscription, or credentialed endpoint was used.

### 5.1 Formal service, plan, quota, and price evidence

Prices and plan observations are point-in-time facts: the original comparison was visited 2026-08-10 and Twelve Data was refreshed 2026-08-11. They do not claim that the user purchased a plan. **U** means the required official fact was not established; **C** means official pages conflicted.

| Candidate | Formal API / own key | Free plan, quota, span | Paid plan evidence | Result |
|---|---|---|---|---|
| Yahoo Finance / yfinance | **U:** yfinance is an unofficial Python wrapper, not a supported Yahoo Finance API contract; no formal client key/SLA was established. | Quota, plan, history entitlement, and status **U**. | No applicable official Yahoo Finance API plan/price established. | **REJECT** — wrapper convenience and its Apache license do not create a supported data contract. |
| Alpha Vantage | **V:** formal REST API; user API key; Symbol Search and time-series endpoints. | **C:** Support said 25 requests/minute and verified open-source/education access; Premium said standard service is 25/day. Free compact daily output is the latest 100 points; full 20+ year daily output and adjusted series are premium. | Premium page exposes selectable monthly/annual plans but did not expose their numeric prices to the research client; current applicable price is **U**. | **REJECT** — quota conflict, premium data dependencies, incomplete four-market and rights evidence. |
| Stooq | Public site/download UI found; supported formal API/key contract **U**. | Plan, quota, batch, span, and rate limit **U**. | Plan names and prices **U**. | **UNVERIFIED / REJECT as Primary** — an undocumented download path is not a production contract. |
| Twelve Data | **V:** formal REST/WebSocket API and user-owned key; no Vendor SDK required. | Basic Free: 8 API credits/minute, 800/day, three markets, batch requests, internal non-display, real-time US equities/ETFs, FX/crypto, reference data, and technical indicators. | Pro starts at $99/month with 610+ API and 500+ WebSocket credits/minute; the current Exchanges page lists `XHKG`, `XSHG`, `XSHE`, and `XJPX` at Pro, subject to actual entitlement and market-specific licensing. | **SELECTED by user authorization — BYOK tiered model.** Basic is the usable US-focused free path; Pro or higher is the permitted four-market entitlement route, with Stage 6 acceptance still required. |
| Marketstack | **V:** formal access-key REST API; ticker/search, exchange and EOD endpoints; no SDK required. | **C:** the directly readable official FAQ contains both 1,000 requests/month and a later “below 100” statement. The official Pricing page timed out in both research clients, so the exact current Free quota and history span are **U**. Each symbol consumes one request even in a multi-symbol request. | Current paid plan names, prices, quotas, and spans are **U** in this execution because the official Pricing page was not directly readable. | **REJECT** — free quota conflicts and official pages do not map all four markets and rights to one plan. |
| Tiingo | **V:** formal REST API and personal Token; official Developer Program explicitly supports software where every user supplies their own Token. | Starter $0: 500 unique symbols/month, 50 requests/hour, 1,000/day, 1 GB/month, 30+ years advertised. | Power $30/month or $300/year; Individual internal use. | **REJECT** — Starter forbids persistent storage and the EOD list verifies US plus Shanghai/Shenzhen but does not establish Hong Kong or Japan. |
| EODHD | **V:** formal keyed REST API; Search, EOD OHLCV, adjusted data and actions; no SDK required. | Free $0: 20 calls/day, 20 requests/minute, past-year range, personal use. One symbol normally costs one call; Search costs one; whole-exchange bulk costs 100. Exact four-market free entitlement is **U**. | EOD Historical Data — All World: $19.99/month or $199/year; 100,000 calls/day, 1,000 requests/minute, 30+ years, personal use. | **REJECT free; paid conditional candidate** — free quota is impractical; its paid plan was not user-selected, and exact HK/Tokyo EOD price coverage remains unresolved. |
| Finnhub | **V:** Finnhub operates a formal API service and publishes official Pricing, API Documentation, and Terms pages. Detailed endpoint/key facts on the dynamic API page were not directly readable in the research client. | Exact current Free quota, rate limit, and historical-OHLC entitlement are **U**: the official dynamic Pricing page returned no readable body. | Current paid plan names, prices, quotas, history spans, and exchange entitlements are **U** for the same direct-access reason. | **UNVERIFIED / REJECT as Primary** — no directly verified current plan/capability/rights chain establishes the four required markets. |
| Financial Modeling Prep (FMP) | **V:** formal keyed REST API; search/reference, EOD OHLCV, adjusted/unadjusted, dividend and split endpoints; no SDK required. | Basic Free: 250 calls/day, EOD, five years, 500 MB trailing 30 days, individual use; official pricing marks it US-limited. | Starter $22/month billed annually (US); Premium $59/month billed annually (US/UK/Canada); Ultimate $149/month billed annually, 3,000/minute, 30+ years, Global Coverage, bulk/batch. | **REJECT free; paid conditional only** — global coverage is paid and exact four-market exchange evidence/application rights remain incomplete. |

### 5.2 Capability, market coverage, and freshness

Legend: **V** official material verified the capability at the stated free or general tier; **P** only paid/premium material verified it; **U** not verified for the required tier/use; **C** official material conflicted. Absence from a published exchange list is recorded as **U**, not invented as technical impossibility.

| Candidate | Search | Historical OHLCV | Raw / adjusted / actions | ETF / indexes | Minimum freshness observed | US | HK | Mainland China | Japan |
|---|---:|---|---|---|---|---:|---:|---:|---:|
| Yahoo/yfinance | U formal | Wrapper function only; formal contract U | U | U | U | U | U | U | U |
| Alpha Vantage | V | V; free 100-point compact, full 20+ years P | Raw V; adjusted/dividend/split P | V/P by endpoint | Daily and premium intraday documented; exact market delay U | V | U | V examples for Shanghai/Shenzhen | U |
| Stooq | U | Download UI only; formal API/span U | U | U | U | U | U | U | U |
| Twelve Data | V; catalog visibility does not prove price entitlement | V/P; daily history documented, depth varies by plan/market | V daily split adjustment and split/dividend endpoints; exact current `adjust` enum requires Stage 6 direct-doc/API verification | V/P | Basic real-time US; `XSHG`/`XSHE` listed EOD; `XHKG`/`XJPX` current EOD status/licensing requires Provider confirmation | V Basic | P `XHKG`, entitlement/licensing check | P `XSHG`/`XSHE` | P `XJPX`, entitlement/licensing check |
| Marketstack | V through ticker/reference surfaces | EOD endpoint V; current plan span U | Splits/dividends V; exact adjustment semantics U | P / exact scope U | EOD/intraday endpoints V; current plan entitlement and delay U | V | U exact plan | U exact plan | U exact plan |
| Tiingo | V through supported-ticker/search utilities | V: 60+ years where available | V raw/adjusted OHLCV, dividends, splits | V ETFs/funds; major-index scope U | EOD equities about 17:30 US Eastern; later corrections documented | V | U / not in EOD list | V Shanghai/Shenzhen A-shares | U / not in EOD list |
| EODHD | V | V: past year Free; 30+ years paid | V adjusted data, splits/dividends | V by endpoint/plan | EOD; delayed/intraday are separate paid products | V | U for EOD; `XHKG` only verified in trading-hours API | V `SHG`/`XSHG`, `SHE`/`XSHE` | U for EOD; `XTKS` only verified in trading-hours API |
| Finnhub | U in directly readable page body | U | U | U | Exact Free/paid freshness and history entitlement U | U | U | U | U |
| FMP | V | V: EOD five years Free; 30+ years higher tiers | V full, non-split-adjusted, dividend-adjusted, dividends/splits | V/P | Basic EOD; higher tiers real-time/intraday | V | P generic Global, exact exchange U | P generic Global, exact exchange U | P generic Global, exact exchange U |

This matrix does not turn generic words such as “global” or an exchange-calendar code into proof that a plan supplies historical prices for that venue. It also does not turn EOD/delayed data into real-time data; real-time and high-frequency infrastructure are not V1 hard requirements.

### 5.3 Personal use, BYOK, cache, deletion, attribution, and redistribution

| Candidate | Personal/internal and each-user-key boundary | Local persistent cache and post-subscription deletion | Attribution / export / redistribution | Aureus consequence |
|---|---|---|---|---|
| Yahoo/yfinance | Personal-use notice exists, but formal production BYOK client permission U. | U. | U; wrapper source license is not a data license. | Cannot select. |
| Alpha Vantage | Formal key and personal/non-commercial terms; exact open-source desktop BYOK interpretation U. | Persistent-cache and termination deletion boundary U. | Exact attribution/export/redistribution obligations U. | Cannot select while material rights are unknown. |
| Stooq | U. | U. | U. | Cannot select. |
| Twelve Data | **Selected BYOK:** Individual Basic/Grow/Pro/Ultra plans are personal/internal; each user supplies a separate credential and may not share it. The key's actual entitlement, not a typed Plan name, controls access. | Terms permit internal storage only within Documentation timeframes and require deletion of all Provider Data upon termination. Historical guidance recommends cache-once plus incremental refresh; the exact retention window must be reverified in Stage 6. | Individual plans prohibit redistribution and commercial third-party display. Public/external display requires applicable rights and attribution; private/internal use is generally attribution-exempt, but Aureus still shows a source label. | Accept for the user-authorized local personal-use model, subject to Stage 6 plan, market, retention, deletion, and attribution acceptance. |
| Marketstack | Individual key exists; exact personal/open-source BYOK boundary U. | Exact persistence and termination deletion rule U. | Agreement exists; precise attribution/export/redistribution duty for this use U. | Cannot select. |
| Tiingo | Developer Program explicitly allows software requiring each user to supply a separate Token, provided the software does not redistribute Tiingo data; internal use only. | Starter/trials may not write, save, archive, back up, or otherwise retain data in persistent storage; eligible paid plans may persist only while active and must delete all Tiingo data on expiry/cancel/downgrade. | Developer rules require clear Tiingo attribution; redistribution requires separate license; qualifying derived output must not reconstruct source data. | BYOK is clear, but Starter is incompatible with Aureus's bounded persistent market cache and EOD markets are incomplete. |
| EODHD | The official personal-vs-commercial page verifies that public pricing is for personal use; exact open-source BYOK display interpretation remains U. | **U in this execution:** the official Terms URL timed out in both direct research clients, so persistent-cache permission and post-subscription deletion timing were not treated as verified. | Exact display, redistribution, export, and attribution duties are U for the intended desktop use. | Paid local use is only a conditional candidate after authorization and written coverage, cache, deletion, and use-rights confirmation; Free quota is not viable. |
| Finnhub | The directly readable Terms page states personal-use restrictions; current plan/key entitlements remain U because the dynamic Pricing/API bodies were not readable. | Terms require deletion when subscription ends. | No redistribution/share/derived-results use without permission; exact attribution presentation U. | No current free or paid four-market capability and rights chain was verified. |
| FMP | Personal license is for one individual's own non-business use; key/account sharing and integration into tools accessible by third parties are prohibited without the applicable agreement. | Terms require all cached data to be deleted on termination. | Sharing/displaying for others and redistribution require rights; exact private-app attribution U. | An open-source BYOK executable model needs provider confirmation even if every user supplies a key. |

The Repository would contain no Provider payload and no credentials. That privacy rule does not relax any Provider's local-display, cache, retention, deletion, attribution, or redistribution restrictions.

### 5.4 Free-tier usability request budget

Budget model: initial history and a daily incremental EOD refresh each assume one history request or credit per symbol unless the official plan says otherwise. A multi-symbol request is not treated as free when the provider counts each symbol. `S` Symbol Search calls and `M` Market Overview/index calls are additional; the table therefore shows the best-case symbol-only floor. The 10/30/100 values are sensitivity cases, **not** product limits. Local caching reduces repeated history loads but cannot fix a plan that forbids persistent storage or lacks a required market.

| Candidate free path | Initial history: 10 / 30 / 100 symbols | Daily increment: 10 / 30 / 100 | Search / Market Overview / batch effect | Usability conclusion |
|---|---|---|---|---|
| Yahoo/yfinance | U / U / U | U / U / U | Formal quota and supported batch contract U. | Not measurable from a supported contract. |
| Alpha Vantage | At 25/day: same day / 2 days / 4 days. At the conflicting 25/min statement: under 1 / about 2 / about 4 minutes. | At 25/day: 10 fits; 30 and 100 do not. | Search and overview consume additional requests; no documented history batch relief. | Official quota conflict alone prevents a dependable budget. |
| Stooq | U / U / U | U / U / U | Formal quota/search/batch contract U. | Not measurable. |
| Twelve Data Basic | `ceil(N/8)`: about 2 / 4 / 13 minutes; all are within 800/day. | Same credit floor; 100 leaves about 700 daily credits before `S + M`. | Batch is supported but each symbol still costs one time-series credit. | Quota is usable for these sensitivities, but Basic lacks HK/CN/JP entitlements. |
| Marketstack Free | Exact budget U because the official FAQ conflicts between 1,000/month and a later “below 100” statement, while Pricing was unreadable. | At 10/30/100 symbols, the floor is about 300/900/3,000 per 30-day month. Under 1,000, only 10 fits with headroom and 30 barely fits; under 100, none sustains daily refresh. | Each symbol counts even when batched; search/overview add usage. | Not dependably budgetable; even the more generous official FAQ figure fails 100-symbol daily refresh. |
| Tiingo Starter | 10 and 30 fit within one hour; 100 requires at least two hourly windows; all fit the 1,000/day limit and 500 unique/month. | Same rate floor; 100/day is within daily quota. | Search/overview use headroom; no EOD batch discount established. | Quota is usable, but persistent cache is contractually prohibited and HK/JP EOD coverage is unverified. |
| EODHD Free | 10 in one day / 30 in at least 2 days / 100 in at least 5 days. | 10 leaves 10 calls; 30 and 100 cannot refresh daily. | Search costs one; each symbol costs one; whole-exchange bulk costs 100 and cannot fit Free. | Only a tiny case fits; 30/100 and market UI headroom are impractical. |
| Finnhub Free | U / U / U. | U / U / U. | The official dynamic Pricing/API pages returned no readable body, so quota, batch, Search, and candle entitlement cannot be budgeted from direct official evidence. | Not measurable and cannot qualify as Primary. |
| FMP Basic Free | 10 / 30 / 100 all fit within 250/day, leaving 240 / 220 / 150 calls. | Same floor; all fit before `S + M`. | Search/overview consume remaining calls; bulk/batch delivery is an Ultimate feature. | Quota is usable, but Basic is US-limited and the four-market requirement fails. |

**Inference:** Twelve Data Basic has a usable request budget for the US-focused entry path, but it is not complete four-market coverage. The user-authorized tiered decision does not require Basic to cover every target market; Pro-or-higher entitlement and Stage 6 validation are the route for `XHKG`, `XSHG`, `XSHE`, and `XJPX`. Caching reduces repeat requests but cannot create an entitlement.

### 5.5 SDK, maintenance, and service-status evidence

| Candidate | SDK necessity | Maintenance / status observation | Evidence state |
|---|---|---|---|
| Yahoo/yfinance | Python wrapper is neither needed nor acceptable for the Swift-only app; a hypothetical formal API could use `URLSession`. | yfinance repository/release activity V; Yahoo production API/SLA/status U. | Wrapper maintenance V; production contract U. |
| Alpha Vantage | Direct REST via `URLSession`; no SDK needed. | Official docs/support current; dedicated public operational status/SLA U. | Docs V; status U. |
| Stooq | Formal client path and SDK requirement U. | Formal API maintenance/status U. | U. |
| Twelve Data | Direct REST via `URLSession`; vendor SDK optional, not needed. | Provider-linked status reported Operational with zero active incidents during the visit. | Docs and point-in-time status V. |
| Marketstack | Direct REST via `URLSession`; no SDK needed. | Docs/pricing current; public status page timed out. | Docs V; point-in-time status U. |
| Tiingo | Direct REST via `URLSession`; no SDK needed. | Official status reported all systems and EOD endpoint operational. Developer Program promises change notice/deprecation communication, not an SLA. | Docs and point-in-time status V. |
| EODHD | Direct REST via `URLSession`; SDKs are optional. | Pricing/docs updated and official API-limits page links a status service; point-in-time status was not independently established. | Docs V; current status U. |
| Finnhub | A REST service would be callable through `URLSession`; no Vendor SDK was shown to be necessary, but detailed API-page content was unreadable. | Official Terms was directly readable; dynamic Pricing/API pages returned no readable body; dedicated current status/SLA U. | Terms V; current plan/API details and status U. |
| FMP | Direct REST via `URLSession`; no SDK needed. | Official docs/changelog/status page accessible, but the status page did not expose a machine-readable current state to this research client. | Docs/maintenance V; point-in-time status U. |

An active wrapper, documentation page, or point-in-time operational dashboard is not an SLA and does not repair coverage, quota, or data-rights gaps.

### 5.6 Required candidate outcome

- Yahoo/yfinance: **REJECT**.
- Alpha Vantage: **REJECT**.
- Stooq: **UNVERIFIED / REJECT as Primary**.
- Twelve Data: **SELECTED — user-authorized Primary Provider candidate; BYOK; Basic US-focused free path; Pro-or-higher plan/entitlement path for full target-market capability**.
- Marketstack: **REJECT**.
- Tiingo: **REJECT**.
- EODHD: **REJECT Free; retain All World as paid conditional candidate with material coverage/right confirmations outstanding**.
- Finnhub: **UNVERIFIED / REJECT as Primary**.
- FMP: **REJECT Free; paid Global remains conditional and incomplete**.
- V1 Primary Market Data Provider: **Twelve Data — SELECTED in the Stage 1 frozen baseline after Reviewer Gate PASS on 2026-08-11**.
- Test/mock direction: **ACCEPT only as a deterministic in-memory synthetic test provider conforming to the minimal contract; it is not Twelve Data acceptance and does not authorize production Provider implementation or Stage 6 acceptance.**

**Selection basis:** [F] Basic Free provides 8 API credits/minute and 800/day with a usable US-focused path. Pro starts at 610 API credits/minute and the official Exchanges page maps the four target exchange codes to Pro as their minimum individual tier. [User decision] The user accepted a tiered model rather than requiring the free tier to cover every market. [Boundary] Actual entitlements, market-specific licensing, cache/deletion duties, and real responses remain Stage 6 acceptance requirements.

### 5.7 User Decision Packet — Resolved

The Stage 1A decision packet was resolved by the user's explicit decision on **2026-08-10**:

1. Select Twelve Data as the V1 Primary Market Data Provider candidate.
2. Use BYOK; every user owns and supplies a separate key.
3. Treat Basic Free as the usable US-focused entry path, not as four-market coverage.
4. Preserve US/HK/mainland-China/Japan scope and allow full capability to depend on a user-selected Pro-or-higher entitlement.
5. Do not purchase a subscription, embed/share a key, or redistribute Provider data on behalf of users.
6. Require explicit Plan/Entitlement, unsupported, stale, delayed, offline, rate-limit, and attribution states.
7. Keep real Provider, terms, retention/deletion, and four-market entitlement acceptance in Stage 6.

The user did not state that Pro has already been purchased, that a real key has been supplied, or that four-market API behavior has passed. The other eight candidates remain in this comparison as decision history rather than being deleted after selection.

Candidate-to-source trace: Yahoo/yfinance M-01–M-03; Alpha Vantage M-04–M-07; Stooq M-08–M-09; Twelve Data M-10–M-15, M-21, and refresh M-50–M-61; Marketstack M-16–M-20; Tiingo M-22–M-29; EODHD M-30–M-37; Finnhub M-38–M-41; FMP M-42–M-49. Each source-register row carries the official URL, page-specific observation, verification state, Aureus impact, and its applicable visit date.

Official evidence: M-01 through M-61 in the [source register](#10-official-source-register).

### 5.8 Twelve Data Freeze Refresh — 2026-08-11

| Topic | Direct official observation | State | Freeze impact |
|---|---|---|---|
| Basic Free | Pricing and Trial show 8 API credits/minute, 800/day, three markets, real-time US equities/ETFs, reference data, indicators, and batch support. | VERIFIED | Usable US-focused free entry path. |
| Pro | Pricing and Trial show Pro starting at $99/month with 610+ API and 500+ WebSocket credits/minute and 70+ markets. No purchase is inferred. | VERIFIED point-in-time | User-authorized optional tier route, not a bundled subscription. |
| Exchange plan mapping | Exchanges lists United States at Basic and `XHKG`, `XSHG`, `XSHE`, `XJPX` at Pro as the minimum individual plan. | VERIFIED listing | Plan-aware capability candidate; catalog listing alone is not actual-key entitlement. |
| EOD market caveat | The current EOD guide lists `XHKG` and `XJPX` among markets requiring license/current-status confirmation, while `XSHG` and `XSHE` appear as EOD on Exchanges. | CONFLICTING / entitlement-dependent | Pro alone is not claimed to prove HK/JP EOD; Stage 6 must verify/additional licensing as applicable. |
| Historical OHLCV | Historical-price guidance documents OHLCV intervals, daily history, maximum output size 5,000, date windows, and recommends initial fetch then cache/incremental updates. | VERIFIED | Supports local bounded cache design subject to Terms. |
| Adjustment/actions | Official Support verifies daily/weekly/monthly split adjustment, unadjusted intraday data, and `/splits` plus `/dividends` for client-side adjustment. The very large main Docs body and focused Docs route were not directly readable in this refresh. | VERIFIED for Support facts; exact `adjust` enum UNVERIFIED in direct Docs refresh | Stage 6 must directly reverify `all`/`splits`/`dividends`/`none`, defaults, and endpoint behavior. |
| Search/reference and entitlement | Official personal-usage guidance states catalog/search endpoints may expose exchanges outside the subscription and that price access depends on Plan. Usage guidance identifies `/api_usage` and credit headers for current Plan/remaining credits. | VERIFIED | Never infer access from catalog visibility or a typed Plan label. |
| EOD/delayed/real-time | Exchanges supplies per-market delay labels; EOD guide defines EOD fields, and delay guidance distinguishes completed REST-candle latency from WebSocket ticks. | VERIFIED with market-specific caveats | Preserve real-time/delayed/EOD and last-update provenance separately. |
| Personal/internal use | Individual Basic/Grow/Pro/Ultra plans are strictly personal/internal and prohibit redistribution and commercial display to third parties. | VERIFIED | Fits local personal BYOK; no Provider payload enters Repository or third-party distribution. |
| Cache and termination | Terms allow internal processing/storage only within Documentation limits, prohibit caching beyond permitted timeframes, and require deletion of all Data upon termination. Exact ordinary cache duration was not directly enumerated. | VERIFIED general rule; exact duration UNVERIFIED | Stage 6 refreshes the applicable retention and implements disconnect/termination deletion. |
| Attribution | Official guidance says public display/redistribution requires attribution and a dofollow link; internal/private use is generally exempt, with market-specific notices possible. | VERIFIED | Aureus still shows a source label and applies stricter current requirements where applicable. |
| BYOK meaning | Terms prohibit credential sharing; the user selected one key per user. This is an Aureus architecture decision, not a claim that keys may be embedded or shared. | VERIFIED Terms + user decision | Production key exists only in that user's Keychain. |

No account, subscription, API key, credentialed endpoint, trial request, or Provider payload was created or used during this refresh. Official source records M-50 through M-61 preserve the URLs, access date, and direct-access limitation.

## 6. FX Provider Comparison Matrix

| Candidate | CNY/USD and direction | History / update semantics | Free / rate / key | Terms, cache, attribution | Result |
|---|---|---|---|---|---|
| Frankfurter v2 with ECB provider filter | [F] API supports base/quote conversion across currencies; ECB dataset includes EUR reference rates for USD and CNY. [I] Aureus derives CNY per USD from the two EUR legs and labels it derived. | [F] Frankfurter exposes historical and time-series endpoints; ECB publishes reference rates on working days around 16:00 CET. Reference date is retained. | [F] No API key or usage quota; official docs request responsible use, recommend caching, and reserve abuse protection. | [F] Frankfurter identifies provider attribution; ECB permits reuse with source attribution and accurate representation, and derived/modified presentation must be clear. Underlying dataset terms still govern. | **ACCEPT — [R][C] V1 FX provider** |
| Alpha Vantage FX | [F] Formal currency-exchange and FX time-series endpoints with explicit from/to symbols; CNY/USD identifiers are supported by generic currency inputs, but exact pair acceptance was not credential-tested. | [F] Digital/realtime exchange-rate and FX intraday/daily/weekly/monthly endpoints are documented; some endpoints are premium. | API key required; current official free quota pages conflict between 25/minute/open-source language and 25/day. | Official service terms apply; exact cache/attribution/export rights for the desktop workflow were not fully established. | **REJECT** for V1 FX because a key/quota/terms dependency is unnecessary and conflicting. |
| Direct ECB Data Portal API | [F] ECB source dataset and publication timing/attribution are official; USD and CNY reference rates are present. | Working-day reference rates; historical portal exists. | Public data; direct API overview returned HTTP 503 during this research. | ECB disclaimer provides reuse/attribution conditions. | **UNVERIFIED as direct V1 adapter**; Frankfurter/ECB is the bounded choice. |

**[R][C] Choice:** Frankfurter v2 with `providers=ECB`, no SDK. The app stores `source=USD`, `target=CNY`, `cnyPerSource`, ECB reference date, Frankfurter fetch instant/provider identifier, and derived/stale state. It never represents the rate as a tradeable quote. HTTP responses cache for 24 hours; a rate committed to a permanent snapshot is part of that immutable snapshot and is not erased by cache cleanup.

Official evidence: F-01 through F-07 and M-04/M-05/M-06/M-07 in the [source register](#10-official-source-register).

## 7. Chart Technology Comparison Matrix

| Candidate | macOS / integration | Candlestick + volume | Zoom / pan / crosshair / tooltip / ranges | Indicators | Offline / sandbox | License / attribution / maintenance | Cost and result |
|---|---|---|---|---|---|---|---|
| Apple Swift Charts | [F] Native Apple framework for SwiftUI across Apple platforms. | [I] Candles and volume can be composed from marks, but official material does not establish a first-class professional financial-chart component. | [F] Selection, scrolling, visible domains, hover interactions, and marks are documented; [I] a synchronized financial crosshair/tool stack would be custom. | Custom Swift series/marks. | Native and offline; no `WKWebView`. | Apple system framework; maintained with platform; accessibility and vectorized plot material are official. | **ACCEPT for ordinary statistics/heatmaps; REJECT as sole professional K-line engine.** |
| TradingView Lightweight Charts 5.2.x | JavaScript canvas library; [I] macOS integration through local `WKWebView` and a narrow message bridge. | [F] Candlestick and histogram series support; separate pane/series composition supports volume. | [F] Time scale, visible ranges, scrolling/scaling, crosshair, price lines, and plugin/customization APIs documented. Tooltip is application composition over crosshair events. | [F] Plugin/custom-series examples; Aureus computes MA/EMA/RSI/MACD/Bollinger in Swift. | Bundle files locally; deny remote navigation/data. `WKWebView` required. | [F] Apache-2.0; v5.2.0 release dated 2026-04-24; official NOTICE requires TradingView attribution/link. Active official repository. | **ACCEPT — [R][C] professional K-line engine.** Adds bridge, privacy, accessibility fallback, and attribution work. |
| DGCharts 5.1.x | [F] Official repository lists macOS 10.13+ and SwiftPM; AppKit view integration. [I] SwiftUI needs representable wrapping. | [F] CandleStick chart type and combined/bar chart types exist. | [F] scaling, dragging, highlighting, and combined charts are advertised; exact Aureus crosshair/tooltip behavior would be custom. | Custom datasets/renderers; application computes indicators. | Native/offline, no web view. | [F] Apache-2.0; official repository/release 5.1.0; README toolchain baseline Xcode 14/Swift 5.7 is older than current environment. | **REJECT**: feasible but weaker current SwiftUI/macOS-specific evidence and more custom financial interaction work than Lightweight Charts. |

### Frozen split

- **[R][C] Dashboard/Wealth/Portfolio/Analytics charts and heatmaps:** Swift Charts plus minimal native SwiftUI/Canvas only when a heatmap layout needs it.
- **[R][C] Candlestick/volume/interaction:** Lightweight Charts 5.2.x, pinned and bundled offline in an isolated `WKWebView` in Stage 7.
- Technical indicators are authoritative Swift calculations; the chart runtime only renders supplied series.
- The professional chart must ship a native accessible summary/table and keyboard controls. A canvas image does not satisfy accessibility.
- Required Apache-2.0 LICENSE/NOTICE and TradingView attribution are non-optional. The license/attribution evidence is VERIFIED, so chart licensing is not a Stage 1 blocker.

Official evidence: P-15 through P-18 and C-01 through C-07 in the [source register](#10-official-source-register).

## 8. Swift-only vs Python Comparison

| Dimension | Swift-only | Swift + Python | Evidence classification |
|---|---|---|---|
| V1 formulas | Foundation `Decimal`, Collections, Accelerate where genuinely needed, and pure Swift cover the frozen deterministic metrics. | Scientific libraries could accelerate later research/backtesting features not in V1. | [I] Scope-to-capability assessment. |
| App distribution | One signed native app/runtime architecture. | Requires bundling and signing an interpreter/modules or requiring a user installation, plus resource/path/version management. | [I] Packaging consequence; Python's official macOS docs describe framework/distribution variants, R-01. |
| Apple Silicon | Local toolchain is arm64 and system frameworks are native. | Every bundled interpreter/native wheel must also be compatible and signed for the release architecture. | [F] local arm64 evidence; [I] dependency consequence. |
| Sandbox | Native container/file/network APIs match the app security model. | Interpreter subprocess/module loading/file access adds entitlements and audit surface. | [I] based on Apple sandbox model P-11/P-12. |
| Startup and footprint | No second runtime initialization or copied standard library. | Larger bundle and runtime initialization/dependency inventory. | [I]. |
| Testing | Swift Testing/XCTest cover the same process and semantic types. | Cross-language serialization, process failures, versioning, and duplicate fixtures need tests. | [I]. |
| Licensing | Project and two bounded dependencies require review. | Python and each bundled package/native library add notices and compatibility review. | [F] Python has its own PSF license; [I] transitive consequence, R-02. |
| No AI/LLM boundary | Straightforward; no model/runtime added. | Python itself is not AI, but it adds no V1 value and expands a future integration surface. | [I]; governance remains controlling. |

**[R][C] Choice: Swift-only.** Swift meets the actual V1 return, risk, planning, indicator, money, and FX calculations. Python remains a conditional future direction and is not bundled, installed, or invoked in V1.

## 9. Dependency and License Table

| Name | Purpose | Official source / stable series | License | macOS compatibility / maintenance | Why system frameworks are insufficient | Main alternative | Stage 2 required? |
|---|---|---|---|---|---|---|---:|
| GRDB.swift | SQLite schema, migrations, records, transactions, observation, backup, safe connection/concurrency API | Official repository; 7.11.x, latest observed 7.11.1 on 2026-06-18 | MIT | [F] macOS 10.15+, Swift 6.1+, Xcode 16.3+; active 2026 release | Direct SQLite would duplicate binding/migration/backup/concurrency infrastructure; SwiftData/Core Data reduce explicit schema control | Direct SQLite, SwiftData, Core Data | **Yes — sole external Stage 2 dependency** |
| TradingView Lightweight Charts | Professional candlestick/volume/time-scale/crosshair engine | Official repository; 5.2.x, latest observed 5.2.0 on 2026-04-24 | Apache-2.0 plus NOTICE/attribution | Browser JS bundled in `WKWebView`; active 2026 release | Swift Charts lacks a first-class complete professional financial interaction surface | Swift Charts custom implementation; DGCharts | **No — Stage 7 only** |
| SQLite | On-device database engine used by GRDB | SQLite official source/system library | Public domain | Shipped as platform library; official docs updated in 2026 | It is the underlying engine; GRDB supplies the missing Swift ergonomics | None for chosen design | System component, not added package |
| Frankfurter API | Historical/current ECB-backed FX reference rates | Official service/API v2; no client SDK | API/data terms apply; server source is MIT | HTTPS service currently documented; official repository maintained | Foundation has no exchange-rate dataset | Alpha Vantage FX; direct ECB API | No package; later network adapter |
| Apple system frameworks | UI, observation, networking, general charts, web container, secrets, logging, file types, tests | Installed Apple SDK | Apple SDK terms | macOS 14+; maintained by Apple | They are the system solution | Third-party replacements rejected without need | Yes, platform only |

Project source license recommendation: **Apache-2.0 — USER AUTHORIZATION_PENDING**. The recommendation reflects a permissive patent grant and straightforward compatibility with the chosen MIT/Apache dependencies. No project LICENSE exists or is created in Stage 1, and no user authorization is inferred. Distribution must retain GRDB's MIT notice and Lightweight Charts' Apache LICENSE/NOTICE plus required TradingView attribution.

## 10. Official Source Register

Sources P-01 through M-49 were visited on **2026-08-10** unless their row says otherwise. Twelve Data refresh records M-50 through M-61 were visited on **2026-08-11**. Status describes the specific observation, not perpetual availability.

### 10.1 Apple and Swift

| ID | Official page | Current observation | Status | Aureus impact |
|---|---|---|---|---|
| P-01 | [Xcode — System Requirements](https://developer.apple.com/xcode/system-requirements/) | Xcode 26.6 deployment and SDK/OS compatibility table; macOS target range includes macOS 14. | VERIFIED | Supports proposed target with installed Xcode. |
| P-02 | [Xcode 26.6 Release Notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-26_6-release-notes) | Xcode 26.6 toolchain/SDK release information. | VERIFIED | Corroborates local baseline. |
| P-03 | [Discover Observation in SwiftUI — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10149/) | `@Observable`, dependency tracking, and SwiftUI model use. | VERIFIED | Supports native state model. |
| P-04 | [Migrate to SwiftData — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10189/) | SwiftData model/container adoption and Core Data coexistence/migration. | VERIFIED | Establishes alternative capabilities/availability. |
| P-05 | [SchemaMigrationPlan — SwiftData](https://developer.apple.com/documentation/swiftdata/schemamigrationplan) | Versioned schemas and migration stages. | VERIFIED | Migration comparison. |
| P-06 | [Core Data](https://developer.apple.com/documentation/coredata/) | Object graph management and persistence framework. | VERIFIED | System persistence alternative. |
| P-07 | [Staged Migrations — Core Data](https://developer.apple.com/documentation/coredata/staged-migrations) | Staged migration APIs and process. | VERIFIED | Migration comparison. |
| P-08 | [Migrating to Swift 6](https://www.swift.org/migration/) | Swift 6 language mode and concurrency migration guidance. | VERIFIED | Supports foundation language mode. |
| P-09 | [Concurrency — The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) | Tasks, actors, async/await, isolation. | VERIFIED | Supports actor ownership and structured concurrency. |
| P-10 | [URLSession](https://developer.apple.com/documentation/foundation/urlsession) | Native HTTP session, async/task APIs, configuration. | VERIFIED | No third-party networking dependency needed. |
| P-11 | [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) | Sandbox purpose, container access, Mac App Store requirement. | VERIFIED | App Sandbox foundation decision. |
| P-12 | [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) | Standard panels and security-scoped URL/bookmark access. | VERIFIED | Import/export/backup boundary. |
| P-13 | [Keychain Services](https://developer.apple.com/documentation/security/keychain-services) | Keychain storage for passwords, keys, and small secrets. | VERIFIED | Provider credentials go only to Keychain. |
| P-14 | [OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy) | Privacy controls for logged values. | VERIFIED | Supports redacted unified logging policy. |
| P-15 | [Swift Charts](https://developer.apple.com/documentation/charts) | Native chart composition, marks, scales, interaction/accessibility surfaces. | VERIFIED | Ordinary chart choice. |
| P-16 | [Explore pie charts and interactivity in Swift Charts — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10037/) | Selection, scrolling, visible domains, hover-style interaction. | VERIFIED | Native interactive statistics. |
| P-17 | [Swift Charts: Vectorized and function plots — WWDC24](https://developer.apple.com/videos/play/wwdc2024/10155/) | Vectorized plots, larger data, heatmap examples, accessibility. | VERIFIED | Heatmap/performance direction. |
| P-18 | [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) | Embeddable web-content view and navigation/script integration surface. | VERIFIED | Local financial chart container. |
| P-19 | [Swift Testing](https://developer.apple.com/documentation/testing) | Modern Swift test framework, traits, parameterization. | VERIFIED | Unit/integration default. |
| P-20 | [Testing with Xcode](https://developer.apple.com/documentation/xcode/testing) | Xcode testing workflows, unit/UI/performance context. | VERIFIED | XCUI/manual boundary. |
| P-21 | [Decimal](https://developer.apple.com/documentation/foundation/decimal) | Foundation base-10 decimal type and arithmetic surface. | VERIFIED | Decimal intermediate calculation direction. |

### 10.2 Persistence

| ID | Official page | Current observation | Status | Aureus impact |
|---|---|---|---|---|
| D-01 | [GRDB.swift README](https://github.com/groue/GRDB.swift/blob/master/README.md) | Requirements, installation, database queues/pools, records, transactions, migrations, observation, backup/testing guidance. | VERIFIED | Primary persistence capability evidence. |
| D-02 | [GRDB.swift Releases](https://github.com/groue/GRDB.swift/releases) | Latest observed release 7.11.1, dated 2026-06-18. | VERIFIED | Current stable series/maintenance evidence. |
| D-03 | [GRDB.swift LICENSE](https://github.com/groue/GRDB.swift/blob/master/LICENSE) | MIT license. | VERIFIED | Dependency compatibility. |
| D-04 | [SQLite Transactions](https://www.sqlite.org/lang_transaction.html) | Transaction modes, concurrent readers, one simultaneous writer; page updated 2026-02-18. | VERIFIED | Connection/transaction model. |
| D-05 | [SQLite Copyright](https://www.sqlite.org/copyright.html) | SQLite dedicated to public domain; page updated 2026-01-12. | VERIFIED | Engine license evidence. |

### 10.3 Market providers

| ID | Official page | Current observation | Status | Aureus impact |
|---|---|---|---|---|
| M-01 | [yfinance documentation](https://ranaroussi.github.io/yfinance/index.html) | Unaffiliated research/education tool; Yahoo API personal-use notice. | VERIFIED | Reject as production-provider contract. |
| M-02 | [yfinance official repository](https://github.com/ranaroussi/yfinance) | Python wrapper, Apache-2.0 source license, disclaimer and current project activity. | VERIFIED | Wrapper maintenance/license does not grant data rights. |
| M-02A | [yfinance Releases](https://github.com/ranaroussi/yfinance/releases) | Release list showed 1.5.2 as the latest release during the visit. | VERIFIED | Wrapper is maintained; this does not establish Yahoo API support or rights. |
| M-03 | [Yahoo APIs Terms of Use](https://legal.yahoo.com/us/en/yahoo/terms/product-atos/apitnc/index.html) | Yahoo-owned API terms page; automated fetch was not consistently accessible during research. | UNVERIFIED for the exact finance desktop use | No clean usage-rights chain for selection. |
| M-04 | [Alpha Vantage API Documentation](https://www.alphavantage.co/documentation/) | Keyed formal API; time series, search, market status, FX, ETF/index and premium markers; global examples. | VERIFIED | Capability comparison. |
| M-05 | [Alpha Vantage Support](https://www.alphavantage.co/support/) | Observed 25 requests/minute and verified open-source/educational access wording. | CONFLICTING with M-06 | Cannot freeze quota. |
| M-06 | [Alpha Vantage Premium](https://www.alphavantage.co/premium/) | Observed standard free usage at 25 requests/day and paid higher limits. | CONFLICTING with M-05 | Cannot freeze quota. |
| M-07 | [Alpha Vantage Terms of Service](https://www.alphavantage.co/terms_of_service/) | Service license and personal/non-commercial restrictions. | VERIFIED at page level | Terms exist, but exact required data rights remain insufficient. |
| M-08 | [Stooq](https://stooq.com/) | Public market website; accessible content required verification JavaScript. | UNVERIFIED formal API facts | Insufficient for provider freeze. |
| M-09 | [Stooq data download page](https://stooq.com/q/d/?s=aapl.us) | Download UI endpoint, not a formal API/terms/rate-limit specification. | UNVERIFIED | Convenience endpoint is not a production contract. |
| M-10 | [Twelve Data Pricing](https://twelvedata.com/pricing) | Basic free limits and paid individual global-market tiers. | VERIFIED | The user-authorized tiered model permits a user-selected Pro-or-higher entitlement; no purchase is inferred. |
| M-11 | [Twelve Data Exchanges](https://twelvedata.com/exchanges) | US Basic and XHKG/XSHG/XSHE/XJPX plan availability observed at higher individual tier. | VERIFIED | Strongest explicit four-region coverage evidence. |
| M-12 | [Twelve Data API Documentation](https://twelvedata.com/docs) | Formal endpoints for time series, symbols/reference data, market data, and adjustments/actions by entitlement. | VERIFIED | Capability evidence. |
| M-13 | [Twelve Data Terms of Use](https://twelvedata.com/terms) | Terms effective 2026-01-01; internal use, cache/retention, redistribution/display restrictions. | VERIFIED at general level | Stage 6 must validate the actual key's Plan, entitlement, and applicable data rights before claiming market acceptance. |
| M-14 | [Twelve Data Commercial and Personal Usage](https://support.twelvedata.com/en/articles/5332349-commercial-and-personal-usage) | Individual plans described for personal/internal use; redistribution/external display requires rights. | VERIFIED | Open-source code does not erase data-use obligations. |
| M-15 | [Twelve Data Attribution Guidelines](https://support.twelvedata.com/en/articles/12647398-attribution-guidelines-for-using-twelve-data) | Public display attribution guidance; internal/private treatment distinguished. | VERIFIED | UI/export attribution must follow actual use. |
| M-16 | [Marketstack Pricing](https://marketstack.com/pricing/) | The official page timed out in both the text research client and the direct browser during this visit; current numeric plan facts were not recovered from a directly readable page. | UNVERIFIED current pricing | No price or quota from a search summary is used as formal evidence. |
| M-17 | [Marketstack FAQ](https://marketstack.com/faq) | Page contains materially inconsistent free monthly request statements. | CONFLICTING | Reject current selection. |
| M-18 | [Marketstack API Documentation](https://marketstack.com/documentation) | Formal access-key REST API, tickers/exchanges/EOD/intraday endpoints. | VERIFIED | Capability exists but exact scope/rights incomplete. |
| M-19 | [Marketstack Agreement](https://marketstack.com/agreement) | Provider agreement/license terms. | VERIFIED at page level | Does not resolve exact four-market cache/redistribution need. |
| M-20 | [Marketstack API Status](https://marketstack.com/api-status) | The official status page timed out in the research client during this visit. | UNVERIFIED current status | No operational-health claim is made. |
| M-21 | [Twelve Data System Status](https://twelvedata.isitup.cloud/) | Provider-linked status page reported Operational, zero active incidents, and operational API/WebSocket/website components. | VERIFIED point-in-time status | Confirms current operation only; it is not an SLA or terms/coverage decision. |
| M-22 | [Tiingo Pricing](https://www.tiingo.com/about/pricing) | Starter $0 and Power $30/month or $300/year; Starter 500 unique symbols/month, 50 requests/hour, 1,000/day, 1 GB/month; internal use only. | VERIFIED | Quota/price/license evidence. |
| M-23 | [Tiingo EOD Product](https://www.tiingo.com/products/end-of-day-stock-price-data) | Formal REST EOD product; raw/adjusted OHLCV, dividends/splits, 60+ years, US exchanges plus Shanghai/Shenzhen A-shares; no HK/Japan exchange listed. | VERIFIED for listed facts; HK/JP UNVERIFIED | Required coverage is incomplete from official evidence. |
| M-24 | [Tiingo General Documentation](https://www.tiingo.com/documentation/general) | Personal Token, internal-use restriction, no redistribution, and BYOK developer direction. | VERIFIED | Separates client integration from data redistribution. |
| M-25 | [Tiingo Developer Program](https://www.tiingo.com/documentation/appendix/developers) | Software may require each user to supply a separate Tiingo Token without redistribution; Tiingo attribution and developer rules apply. | VERIFIED | Strong BYOK evidence, but not a cache or coverage solution. |
| M-26 | [Tiingo EOD Documentation](https://www.tiingo.com/documentation/end-of-day) | Formal EOD endpoints and data-field semantics. | VERIFIED | API/capability evidence. |
| M-27 | [Tiingo Symbology](https://www.tiingo.com/documentation/appendix/symbology) | Official symbol/reference conventions and supported-ticker direction. | VERIFIED | Symbol model/search integration evidence. |
| M-28 | [Tiingo Terms of Use](https://app.tiingo.com/tos/) | Updated 2026-08-05; Starter/trials forbid durable storage; eligible paid storage ends with deletion on expiry/cancel/downgrade; derived-product and redistribution constraints. | VERIFIED | Starter conflicts directly with bounded persistent cache. |
| M-29 | [Tiingo Status](https://status.tiingo.com/) | All systems and EOD endpoint reported operational during the visit. | VERIFIED point-in-time | Maintenance evidence only, not an SLA. |
| M-30 | [EODHD Pricing](https://eodhd.com/pricing) | Free 20 calls/day, past year; All World $19.99/month or $199/year, 100,000/day, 1,000/minute, 30+ years, personal use. | VERIFIED | Free budget fails larger sensitivity cases; EODHD was not user-selected. |
| M-31 | [EODHD Stock Market List](https://eodhd.com/list-of-stock-markets) | Lists US, Shenzhen `SHE`/`XSHE`, Shanghai `SHG`/`XSHG`; did not list Hong Kong or Tokyo during this visit. | VERIFIED for listed/observed page content; HK/JP UNVERIFIED | “All World” label alone cannot prove four-market EOD coverage. |
| M-32 | [EODHD Historical OHLCV API](https://eodhd.com/financial-apis/api-for-historical-data-and-volumes) | Formal keyed historical EOD endpoint with OHLCV and adjustment parameters. | VERIFIED | Core historical capability evidence. |
| M-33 | [EODHD Search API](https://eodhd.com/financial-apis/search-api-for-stocks-etfs-mutual-funds) | Search for stocks, ETFs, funds and indices; a request consumes one call. | VERIFIED | Search capability and budget input. |
| M-34 | [EODHD API Limits](https://eodhd.com/financial-apis/api-limits) | One symbol generally costs one call; multi-symbol cost follows symbols; exchange bulk costs 100; paid default 100,000/day and 1,000 requests/minute. | VERIFIED | Budget/batch evidence. |
| M-35 | [EODHD Terms and Conditions](https://eodhd.com/financial-apis/terms-conditions) | The direct official page timed out in both the text research client and the browser during this visit. Exact cache, display, redistribution, and post-subscription deletion language was therefore not treated as verified. | UNVERIFIED in this execution | Requires direct terms review or written Provider confirmation before any paid freeze. |
| M-36 | [EODHD Commercial vs Personal Use](https://eodhd.com/financial-apis/commercial-vs-personal-license-use) | Public pricing packages are personal-use plans; commercial use requires separate licensing. | VERIFIED | Source-open and data-license boundaries remain separate. |
| M-37 | [EODHD Exchange Trading Hours](https://eodhd.com/financial-apis/exchanges-api-trading-hours-and-stock-market-holidays) | Trading-hours endpoint includes `XHKG` and `XTKS`, but is available on All-In-One/Extended and is not EOD price-coverage proof. | VERIFIED for calendar endpoint; EOD coverage UNVERIFIED | Prevents misuse of calendar codes as price entitlement evidence. |
| M-38 | [Finnhub General Pricing](https://finnhub.io/pricing) | The official dynamic page returned no readable body in the research client; current Free quota, rate limit, and included data could not be directly verified. | UNVERIFIED current plan facts | No search-summary numbers are used to qualify or reject a plan. |
| M-39 | [Finnhub Market Data Pricing](https://www.finnhub.io/pricing-stock-api-market-data) | The official dynamic page returned no readable body; current paid names, prices, quotas, history, and international venue entitlements could not be directly verified. | UNVERIFIED current plan facts | No paid Finnhub path can be selected from this evidence. |
| M-40 | [Finnhub API Documentation](https://finnhub.io/docs/api) | The official dynamic page returned no readable body in the research client; exact current Search, candle, adjustment, exchange, and key details were not directly verified. | UNVERIFIED detailed capabilities | The formal service exists, but detailed capability evidence is insufficient for A-008. |
| M-41 | [Finnhub Terms of Service](https://finnhub.io/terms-of-service) | Personal-use and redistribution restrictions; data deletion on subscription end. | VERIFIED at general level | Cache/redistribution boundary; exact attribution remains unverified. |
| M-42 | [FMP Pricing](https://site.financialmodelingprep.com/developer/docs/pricing) | Basic Free 250/day, EOD, five years; Starter $22, Premium $59, Ultimate $149 per month billed annually; Ultimate supplies Global Coverage, 30+ years, 3,000/minute and batch/bulk. | VERIFIED | Free is US-limited; its global paid path was not user-selected. |
| M-43 | [FMP Stable API Documentation](https://site.financialmodelingprep.com/developer/docs/stable) | Keyed REST API; search/reference, historical price, split/dividend, ETF and index surfaces. | VERIFIED | Formal capability evidence. |
| M-44 | [FMP Full Historical Price](https://site.financialmodelingprep.com/developer/docs/stable/historical-price-eod-full) | Full EOD OHLCV, changes and VWAP by symbol. | VERIFIED | Historical OHLCV evidence. |
| M-45 | [FMP Dividend-adjusted Price](https://site.financialmodelingprep.com/developer/docs/stable/historical-price-eod-dividend-adjusted) | Dividend-adjusted EOD OHLCV endpoint. | VERIFIED | Adjustment evidence. |
| M-46 | [FMP Non-split-adjusted Price](https://site.financialmodelingprep.com/developer/docs/stable/historical-price-eod-non-split-adjusted) | Explicit unadjusted-for-splits EOD OHLCV endpoint. | VERIFIED | Raw/adjustment semantic evidence. |
| M-47 | [FMP Available Exchanges](https://site.financialmodelingprep.com/developer/docs/stable/available-exchanges) | Keyed endpoint returns a global exchange list, but the public page did not enumerate exact HK/CN/JP codes without a credentialed call. | VERIFIED endpoint; exact four exchanges UNVERIFIED | No credentialed request was permitted, so exact coverage cannot be assumed. |
| M-48 | [FMP Terms of Service](https://site.financialmodelingprep.com/terms-of-service) | Personal license prohibits shared account/data and third-party-accessible app integration; all cached data must be deleted on termination. | VERIFIED | Exact open-source BYOK app rights need confirmation. |
| M-49 | [FMP Status](https://status.financialmodelingprep.com/) | Official status page was accessible but did not expose a machine-readable current state to the research client. | UNVERIFIED point-in-time state | No operational claim is made. |
| M-50 | [Twelve Data Pricing](https://twelvedata.com/pricing) | Basic Free: 8 API credits/minute and 800/day; Pro starts at $99/month and 610+ API/500+ WS credits/minute; individual use is personal/internal/non-commercial. | VERIFIED 2026-08-11 | Current quota/price and tier boundary; no purchase inferred. |
| M-51 | [Twelve Data Exchanges](https://twelvedata.com/exchanges) | United States minimum individual Plan Basic; `XHKG`, `XSHG`, `XSHE`, and `XJPX` minimum individual Plan Pro; page exposes per-market delay labels. | VERIFIED 2026-08-11 for listing | Listing guides capability discovery but does not prove the current key's price entitlement. |
| M-52 | [Twelve Data API Documentation](https://twelvedata.com/docs) | The official main page exceeded the text client's content limit; a focused official Docs route timed out in both direct clients. No search-result summary was accepted as formal evidence. | UNVERIFIED direct full-body refresh | Stage 6 must directly reverify endpoint parameters, including the exact adjustment enumeration. |
| M-53 | [Twelve Data Terms of Use](https://twelvedata.com/terms) | Updated 2026-01-01; internal-use license, tier/add-on-dependent access, credential non-sharing, documented cache-timeframe limit, redistribution/external-display restrictions, and deletion of all Data upon termination. | VERIFIED 2026-08-11 | Governs Keychain/BYOK, cache, disconnect/termination, and export boundaries. |
| M-54 | [Twelve Data Commercial and Personal Usage](https://support.twelvedata.com/en/articles/5332349-commercial-and-personal-usage) | Individual plans are personal/internal; no redistribution or commercial third-party display. Catalog/search can list markets outside the subscription; price access is Plan-dependent. | VERIFIED 2026-08-11 | Entitlement must be observed, not inferred from metadata. |
| M-55 | [Twelve Data Attribution Guidelines](https://support.twelvedata.com/en/articles/12647398-attribution-guidelines-for-using-twelve-data) | Public display/redistribution attribution rules and preferred wording; internal/private use generally exempt; market-specific notices may apply. | VERIFIED 2026-08-11 | Aureus displays a source label and applies stricter current notices where required. |
| M-56 | [How to get historical prices](https://support.twelvedata.com/en/articles/5656039-how-to-get-historical-prices) | Historical OHLCV intervals, daily-history semantics, output/date-window methods, and cache-once/incremental-update recommendation. | VERIFIED 2026-08-11 | Supports bounded incremental local cache design. |
| M-57 | [End of day pricing market data](https://support.twelvedata.com/en/articles/12682324-end-of-day-eod-pricing-market-data) | EOD data/fields and personal-use rule; current guide flags `XHKG` and `XJPX` for license/support status confirmation. | VERIFIED 2026-08-11; conflicts with a simple Pro-equals-access inference | HK/JP EOD remains a Stage 6 entitlement/licensing acceptance item. |
| M-58 | [Are the prices adjusted?](https://support.twelvedata.com/en/articles/5179064-are-the-prices-adjusted) | Daily/weekly/monthly prices are split-adjusted; intraday is unadjusted; `/splits` and `/dividends` support client-side adjustment. | VERIFIED 2026-08-11 | Adjustment semantics exist; exact main-Docs parameter enum still requires Stage 6 refresh. |
| M-59 | [Control over API usage](https://support.twelvedata.com/en/articles/5713553-control-over-api-usage) | `/api_usage` reports current Plan/remaining credits and response headers report credits used/left; the endpoint itself costs one credit. | VERIFIED 2026-08-11 | Stage 6 entitlement/rate actor uses Provider observations, not only user-entered labels. |
| M-60 | [Data delays](https://support.twelvedata.com/en/articles/5203307-data-delays) | REST candles typically appear after processing following close; WebSocket ticks have a different latency profile. | VERIFIED 2026-08-11 | UI must distinguish EOD, delayed, real-time, and last-update time. |
| M-61 | [Twelve Data Trial](https://support.twelvedata.com/en/articles/5335783-trial) | Reconfirms Basic 8/800 and US real-time path; Pro from 610 API/500 WS credits at $99/month and 70+ markets; trial symbols do not prove paid entitlement. | VERIFIED 2026-08-11 | Corroborates tiering without any trial or credentialed request. |

### 10.4 FX

| ID | Official page | Current observation | Status | Aureus impact |
|---|---|---|---|---|
| F-01 | [Frankfurter API Documentation](https://frankfurter.dev/) | v2 API, historical/time-series data, provider filter/attribution, no key/quota, caching recommendation and abuse boundary. | VERIFIED | Selected FX service contract. |
| F-02 | [Frankfurter official repository](https://github.com/lineofflight/frankfurter) | Open-source service implementation and active project. | VERIFIED | Maintenance/provenance, no SDK required. |
| F-03 | [Frankfurter LICENSE](https://github.com/lineofflight/frankfurter/blob/main/LICENSE) | MIT license for server source. | VERIFIED | Does not replace data-source terms. |
| F-04 | [ECB Reference Rates](https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html) | EUR reference rates include USD and CNY and working-day publication context. | VERIFIED | Supports derived USD/CNY reference rate. |
| F-05 | [ECB Exchange Rates — Data Portal](https://data.ecb.europa.eu/key-figures/ecb-interest-rates-and-exchange-rates/exchange-rates) | Reference rates generally updated around 16:00 CET on working days; information/reference role. | VERIFIED | Timestamp/stale behavior. |
| F-06 | [ECB Website Disclaimer and Copyright](https://www.ecb.europa.eu/services/using-our-site/disclaimer/html/index.en.html) | Reuse is generally permitted with source acknowledgment, accuracy, and clear treatment of modifications/derivations. | VERIFIED | Attribution/derived-rate labeling. |
| F-07 | [ECB Data Portal API Overview](https://data.ecb.europa.eu/help/api/overview) | Returned HTTP 503 during this research. | UNVERIFIED for direct adapter | Direct ECB adapter is not selected; Frankfurter remains usable evidence path. |

### 10.5 Charting and Python

| ID | Official page | Current observation | Status | Aureus impact |
|---|---|---|---|---|
| C-01 | [Lightweight Charts official repository](https://github.com/tradingview/lightweight-charts) | Apache-2.0 library, financial series, attribution notice, active project. | VERIFIED | Professional chart candidate. |
| C-02 | [Lightweight Charts Releases](https://github.com/tradingview/lightweight-charts/releases) | Latest observed v5.2.0, dated 2026-04-24. | VERIFIED | Version/maintenance evidence. |
| C-03 | [Lightweight Charts Series Types](https://tradingview.github.io/lightweight-charts/docs/series-types) | Candlestick, histogram, and other series types. | VERIFIED | Candles/volume. |
| C-04 | [Lightweight Charts Time Scale](https://tradingview.github.io/lightweight-charts/docs/time-scale) | Scrolling/scaling and visible logical/time ranges. | VERIFIED | Zoom/pan/range behavior. |
| C-05 | [Lightweight Charts Crosshair](https://tradingview.github.io/lightweight-charts/tutorials/customization/crosshair) | Crosshair configuration and events. | VERIFIED | Crosshair/tooltip composition. |
| C-06 | [Lightweight Charts LICENSE](https://github.com/tradingview/lightweight-charts/blob/master/LICENSE) | Apache License 2.0. | VERIFIED | License compatibility. |
| C-07 | [Lightweight Charts NOTICE](https://github.com/tradingview/lightweight-charts/blob/master/NOTICE) | Attribution/link requirement identified by official project. | VERIFIED | Mandatory in-app attribution and distribution notice. |
| C-08 | [DGCharts official repository](https://github.com/ChartsOrg/Charts) | macOS/SwiftPM support, chart types, interaction features, Apache-2.0, documented toolchain baseline. | VERIFIED | Feasible native alternative. |
| C-09 | [DGCharts Releases](https://github.com/ChartsOrg/Charts/releases) | Latest observed stable series 5.1.x. | VERIFIED | Maintenance/version comparison. |
| R-01 | [Using Python on macOS](https://docs.python.org/3/using/mac.html) | Official macOS interpreter/framework and usage context. | VERIFIED | Packaging comparison input. |
| R-02 | [Python License](https://docs.python.org/3/license.html) | Python Software Foundation license history/terms. | VERIFIED | Extra runtime license inventory if bundled. |

## 11. Unverified or Conflicting Facts

| Issue | State | Why it matters | Required resolution |
|---|---|---|---|
| Alpha Vantage free quota | CONFLICTING | Official support and premium pages state materially different standard limits. | Provider must publish/confirm one applicable entitlement before selection. |
| Alpha Vantage full US/HK/CN/JP tier, adjusted/action, cache, attribution matrix | UNVERIFIED | Generic “global” capability and examples do not prove the complete frozen scope and rights. | Written official plan/endpoint/terms mapping. |
| Yahoo Finance production API/support and desktop-client data rights | UNVERIFIED | yfinance is explicitly unofficial and its Apache source license is not a data license. | Formal Yahoo API and applicable finance-data contract; none established here. |
| Stooq formal API, quota, coverage, status, terms, cache, redistribution, attribution | UNVERIFIED | A download page cannot serve as a stable production contract. | Accessible official API/service documents. |
| Twelve Data Pro-or-higher purchase and exact key entitlement | USER DECISION RECORDED; PURCHASE/ENTITLEMENT UNVERIFIED | The user authorized the Provider and optional tier route, not a subscription purchase. `XHKG`/`XJPX` EOD licensing/status, exact cache duration, and actual-key capabilities remain untested. | Stage 6 real-key, current Terms, exchange/add-on, and four-market acceptance. |
| Marketstack free quota and current paid pricing | CONFLICTING / UNVERIFIED | The directly readable FAQ conflicts internally; the official Pricing page timed out. | Direct readable Pricing plus Provider clarification. |
| Marketstack exact four-region entitlement and usage rights | UNVERIFIED | Broad exchange claims do not prove the needed plan and redistribution/cache boundary. | Official plan/exchange/terms mapping. |
| Tiingo EOD Hong Kong/Japan coverage | UNVERIFIED | Tiingo verifies US and Shanghai/Shenzhen A-shares, while its current EOD exchange list omits Hong Kong and Japan. | Provider-issued EOD coverage/entitlement confirmation; Starter still fails persistent-cache terms. |
| EODHD Hong Kong/Tokyo EOD prices and paid desktop rights | UNVERIFIED | `XHKG`/`XTKS` are verified only for a separate paid trading-hours API; they are absent from the current stock-market list. The direct Terms page was inaccessible, so cache, deletion, attribution, and exact BYOK/private-display rights are also unresolved. | User authorization followed by written All World coverage and rights confirmation plus a direct current Terms review. |
| Finnhub current plans, quota, history, HK/CN/JP coverage, and app rights | UNVERIFIED | Dynamic official Pricing/API pages returned no readable body; the readable Terms page alone cannot prove capability or entitlement. | Direct readable official plan/API/exchange evidence and applicable rights confirmation. |
| FMP exact four-market Ultimate entitlement and BYOK application rights | UNVERIFIED | “Global Coverage” and a keyed exchange-list endpoint do not enumerate the required venues publicly; personal terms restrict third-party-accessible application integration. | User authorization plus provider confirmation of exchanges and app/display/cache terms. |
| Alpha Vantage paid numeric price | UNVERIFIED in the research client | The official premium selector did not expose numeric prices, and no paid Alpha path otherwise satisfies the evidence chain. | Provider pricing confirmation only if reconsidered. |
| Primary Market Data Provider | **SELECTED — Twelve Data BYOK tiered model** | The user explicitly accepted Basic as the US-focused free entry and Pro-or-higher entitlement as the permitted international route. | Reviewer Gate PASS froze the selection; Stage 6 remains the real Provider acceptance gate. |
| Direct ECB API availability | UNVERIFIED during visit | API overview returned 503. | Not core: selected Frankfurter path and ECB dataset evidence remain available; retest before choosing a direct adapter. |
| Project source license | USER AUTHORIZATION_PENDING | Executor cannot create or choose LICENSE for the user. | User authorization; Apache-2.0 is only a recommendation. |
| Signing, notarization, Development Team, distribution channel | USER AUTHORIZATION_PENDING | User-owned credentials and release choices are outside Stage 1. | User-authorized release-stage decision. |

No core architecture item converts an `UNVERIFIED` Provider fact into tested behavior. A-008 is selected at the architecture/product level, while precise entitlements, HK/JP EOD status, retention, credentialed behavior, and Provider acceptance remain explicitly assigned to Stage 6. User-owned license/signing matters remain labeled permissions rather than technical completion.

## 12. Decision Traceability

| Decision | Evidence inputs | Fact-to-inference trace | Candidate outcome |
|---|---|---|---|
| A-001 Platform | Local commands, P-01/P-02/P-03/P-08 | Xcode supports macOS 14 and local arm64 Swift 6.3; Observation supports simple native state. | macOS 14, Swift 6, arm64. |
| A-002 Architecture | P-03/P-09 plus KISS/YAGNI governance | Observation + actor isolation meet state/concurrency needs without a third-party architecture. | Feature-first SwiftUI, manual DI. |
| A-003 Structure | Scope modules and A-002 boundaries | One app has no proven reuse/build-time need for framework/package proliferation. | One app, one test, one UI-test target. |
| A-004 Persistence | P-04–P-07, D-01–D-05 | GRDB uniquely combines explicit SQLite control with maintained Swift ergonomics. | GRDB 7.11.x, two database files. |
| A-005 Precision | P-21, SQLite INTEGER semantics, product constraints | Fixed-point persistence plus Decimal intermediate math preserves semantic exactness. | Distinct checked scaled types. |
| A-006/A-009 FX | F-01–F-06, M-04–M-07 | Frankfurter/ECB supplies keyless reference history and clear provenance; cross-rate is explicitly derived. | CNY base, Frankfurter/ECB. |
| A-007 Time | Foundation/Swift platform semantics, product snapshot/market needs | Instants, civil dates, and exchange sessions are different facts and need separate representations. | UTC instants + civil/session dates/zones. |
| A-008 Market | M-01–M-61 plus user decision dated 2026-08-10 | All nine candidates remain compared. The user selected Twelve Data BYOK and accepted Basic as a US-focused free entry plus Pro-or-higher entitlement for the four-market route; refreshed evidence preserves licensing, retention, and actual-key limitations. | **SELECTED — Twelve Data BYOK tiered model**; Stage 6 real-key and four-market acceptance remains mandatory. |
| A-010 Cache | Product hard constraint + A-004 physical boundary | Numeric limits make behavior testable; separate capability graph makes deletion safety reviewable. | 512 MiB default, typed TTLs, LRU, separate DB. |
| A-011 Charts | P-15–P-18, C-01–C-09 | Native charts optimize wealth accessibility; LWC supplies the specialized market interaction surface. | Swift Charts + bundled LWC. |
| A-012 Runtime | Scope formulas, local Swift toolchain, R-01/R-02 | V1 needs deterministic formulas, not a second analytics ecosystem. | Swift-only. |
| A-013 Networking | P-09/P-10 and provider quota evidence | Native async networking plus one actor owner provides cancellation, rate, and retry control. | URLSession + bounded actor policy. |
| A-014 Privacy | P-11–P-14, governance | Sandbox/container/Keychain/OSLog cover V1 baseline; DB encryption lacks a frozen recovery design. | System privacy controls; no app-layer DB encryption in V1. |
| A-015 Backup/logging | D-01, P-14, physical separation | Consistent DB backup and manifest/hash checks protect permanent data without copying cache/secrets. | Five validated backups; redacted OSLog. |
| A-016 Testing | P-19/P-20 and domain risk analysis | Swift Testing covers deterministic logic; XCUI/manual checks cover app interaction. | Layered synthetic test strategy. |
| A-017 Dependencies | D-02/D-03, C-02/C-06/C-07, D-05 | Only persistence lacks an adequate system-level Swift abstraction at Stage 2; professional chart need occurs later. | GRDB Stage 2; LWC Stage 7; project license pending user. |

## 13. Research Boundary

This evidence supports the frozen Stage 1 baseline, including the user-authorized A-008 selection and Reviewer Gate PASS on 2026-08-11. It does not prove credentialed endpoint behavior, purchase or paid entitlement, four-market access, provider SLA, production latency, signed sandbox behavior, build success, or test success. Provider selection is not Stage 6 acceptance and does not by itself authorize implementation; the current Prompt 2 separately authorizes only Stage 2. No unsupported market claim is converted into a product-scope reduction, purchased-plan claim, or mock-as-production claim.
