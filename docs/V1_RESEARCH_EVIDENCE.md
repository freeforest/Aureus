# Aureus V1 Research Evidence

## 1. Purpose, Method, and Evidence Labels

**Status:** Stage 1 research evidence, visited 2026-08-10.  
**Authority:** This file records evidence and comparison; it does not override [`V1_SCOPE.md`](V1_SCOPE.md) or [`V1_ARCHITECTURE.md`](V1_ARCHITECTURE.md), and no candidate decision is approved until Reviewer Gate PASS.

Research used only primary sources as formal evidence: Apple and Swift documentation, official project documentation/repositories/licenses/releases, and provider-owned API/pricing/terms/attribution/status pages. Search results were used only to locate pages and are not cited as evidence. No account was created, no API key was requested, no credentialed endpoint was called, no dependency was installed, and no package was resolved.

Comparison notation:

- **[F] Fact:** directly observed in an official source.
- **[I] Inference:** Executor interpretation derived from cited facts; not stated verbatim by the source.
- **[R] Recommendation:** Executor's single proposed V1 choice.
- **[C] Candidate:** awaits Reviewer Gate and is not yet a frozen baseline.
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

### 5.1 Formal service, quota, terms, and client suitability

| Candidate | Formal API / key | Free tier and rate limit | Terms / personal use / cache / redistribution | Attribution | Open-source desktop suitability | Decision |
|---|---|---|---|---|---|---|
| Yahoo Finance via yfinance | [F] yfinance says it is not affiliated with, endorsed by, or vetted by Yahoo and is a research/education Python tool; no supported Yahoo Finance client API contract was established. No key in wrapper. | UNVERIFIED formal API quota or service commitment. | [F] yfinance directs users to Yahoo terms and states Yahoo Finance API use is intended for personal use. [I] A wrapper license does not grant market-data rights or availability. | UNVERIFIED for an Aureus client. | **No**: no formal production API/support/rights evidence for the required client. | **REJECT** |
| Alpha Vantage | [F] Formal HTTP API with API key. | **CONFLICTING:** Support page observed 25 requests/minute and a verified open-source/educational statement; Premium page observed standard free service at 25 requests/day. | [F] Official terms grant bounded personal/non-commercial access and impose service/data restrictions. Exact cache/redistribution rights for all required exchanges were not established. | UNVERIFIED exact desktop requirements. | Formal API, but quota conflict and incomplete required-market/tier/rights evidence prevent safe selection. | **REJECT** |
| Stooq | Public download pages exist, but an accessible formal API contract/documentation was not established. | UNVERIFIED. | UNVERIFIED formal API terms, cache, redistribution, and personal-client rights. | UNVERIFIED. | Cannot base a frozen client on undocumented behavior. | **UNVERIFIED** |
| Twelve Data | [F] Formal HTTP/WebSocket API with API key and official docs. | [F] Basic is free with 8 API credits/minute, 800/day, and 3 markets; global exchange access is on paid tiers. | [F] Individual plans are for personal/internal use; terms restrict redistribution/external display and condition caching on permitted periods. Public display attribution guidance exists. Exact subscribed-market retention must be confirmed in the authorized contract. | [F] Twelve Data publishes attribution guidance for public display; private/internal use is treated differently by that official guide. | **Conditional leader**, but required HK/CN/JP exchanges are paid and budget/contract/cache rights are not user-authorized. | **REJECT as current primary; conditional candidate** |
| Marketstack | [F] Formal REST API with access key and official docs. | **CONFLICTING:** Pricing page observed 100 free requests/month; FAQ contains 1,000/month and a later “fewer than 100” statement. | [F] Provider agreement governs license/use; exact cache, redistribution, and all-market/tier entitlement needed here remain unverified. | UNVERIFIED exact Aureus obligation. | Quota conflict and incomplete four-market entitlement/rights evidence prevent a freeze. | **REJECT** |

### 5.2 Capability and market-coverage evidence

Legend: **V** official material verified the capability at some stated tier; **P** only paid/premium material verified it; **U** not verified for the needed candidate/tier; **C** official material conflicted.

| Candidate | Symbol search | Historical OHLCV / span | Intraday | Adjusted price / actions | US | Hong Kong | Mainland China | Japan | ETF / major indexes | Delay/status evidence |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| Yahoo/yfinance | U | Wrapper exposes history, but formal API/contract U | U | U | U | U | U | U | U | Formal status/SLA U |
| Alpha Vantage | V | V; official docs state 20+ years for daily series, free compact window and premium full output | P | Daily adjusted/actions P in current docs | V | U | V examples for Shanghai/Shenzhen symbols | U | V/P depending endpoint | Market/tier delay detail U |
| Stooq | U | Download UI observed; formal span/API U | U | U | U | U | U | U | U | U |
| Twelve Data | V | V; full history varies by tier/market | V/P | V/P; splits/dividends/adjustment depend on endpoint/tier | V, Basic | P, XHKG | P, XSHG/XSHE | P, XJPX | V/P by plan | Exchange page identifies market/tier; exact delay entitlement is plan-specific |
| Marketstack | V through ticker/exchange endpoints | V; pricing advertises 1 year free, 10+ years paid, 15+ years Pro | P | Splits/dividends listed; adjustment semantics require endpoint review | V | U exact tier | U exact tier | U exact tier | U exact scope | EOD/intraday/real-time vary by paid plan; exact four-market status U |

### 5.3 SDK, maintenance, and status evidence

| Candidate | SDK necessity | Maintenance / service-status observation | Evidence state |
|---|---|---|---|
| Yahoo Finance via yfinance | yfinance is a Python wrapper, not a necessary or acceptable Swift client dependency. A future formal API could be called with `URLSession`. | The official yfinance repository is active and its releases page showed 1.5.2 as latest; Yahoo Finance API support/SLA/status for this desktop use was not established. | Wrapper maintenance VERIFIED; production service status UNVERIFIED. |
| Alpha Vantage | No SDK is necessary; the documented REST API can use `URLSession`. | Official support/docs were accessible and carry 2026 copyright, but no dedicated public operational-status/SLA evidence was established. | Documentation maintenance VERIFIED; service-status commitment UNVERIFIED. |
| Stooq | No official SDK requirement or formal API client path was established. | The public site/download page required verification JavaScript; no formal API status or maintenance commitment was established. | UNVERIFIED. |
| Twelve Data | No SDK is necessary; official REST/WebSocket docs permit a direct adapter. | Pricing, exchange, terms, and support materials were current. The System Status link published on the official pricing page reported Operational, zero active incidents, and operational Price API/Fundamentals API/WebSocket/Website components when visited. | Documentation maintenance and point-in-time service status VERIFIED. |
| Marketstack | No SDK is necessary; official REST docs support a direct adapter. | Official API documentation/pricing were accessible; the provider's API-status page timed out during this visit. | Documentation maintenance VERIFIED; current service status UNVERIFIED. |

An active wrapper repository or accessible documentation is not an SLA. None of the status observations repairs the coverage/terms/quota gaps above.

### 5.4 Required candidate outcome

- Yahoo/yfinance: **REJECT**.
- Alpha Vantage: **REJECT**.
- Stooq: **UNVERIFIED**.
- Twelve Data: **REJECT as current Primary**, retained only as the leading paid conditional candidate.
- Marketstack: **REJECT**.
- V1 Primary Market Data Provider: **BLOCKED — no selection**.
- Test/mock direction: **ACCEPT — deterministic in-memory synthetic provider conforming to the minimal `MarketDataProvider` contract; no network, key, or copied restricted payload.**

**Blocking basis:** [F] Current official pages do not give one usable, non-conflicting evidence chain for all four required regions, required data semantics, quota, and client usage/cache rights. [I] Choosing anyway would either silently reduce scope or accept operational/legal assumptions. The architecture therefore permits Provider-independent foundation work but forbids a live adapter until an authorized market-scope/budget/contract decision resolves A-008.

Official evidence: M-01 through M-21 in the [source register](#10-official-source-register).

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

Every source below was visited on **2026-08-10**. Status describes the specific observation, not perpetual availability.

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
| M-10 | [Twelve Data Pricing](https://twelvedata.com/pricing) | Basic free limits and paid individual global-market tiers. | VERIFIED | Required global coverage entails paid authorization. |
| M-11 | [Twelve Data Exchanges](https://twelvedata.com/exchanges) | US Basic and XHKG/XSHG/XSHE/XJPX plan availability observed at higher individual tier. | VERIFIED | Strongest explicit four-region coverage evidence. |
| M-12 | [Twelve Data API Documentation](https://twelvedata.com/docs) | Formal endpoints for time series, symbols/reference data, market data, and adjustments/actions by entitlement. | VERIFIED | Capability evidence. |
| M-13 | [Twelve Data Terms of Use](https://twelvedata.com/terms) | Terms effective 2026-01-01; internal use, cache/retention, redistribution/display restrictions. | VERIFIED at general level | Exact purchased entitlement must precede integration. |
| M-14 | [Twelve Data Commercial and Personal Usage](https://support.twelvedata.com/en/articles/5332349-commercial-and-personal-usage) | Individual plans described for personal/internal use; redistribution/external display requires rights. | VERIFIED | Open-source code does not erase data-use obligations. |
| M-15 | [Twelve Data Attribution Guidelines](https://support.twelvedata.com/en/articles/12647398-attribution-guidelines-for-using-twelve-data) | Public display attribution guidance; internal/private treatment distinguished. | VERIFIED | UI/export attribution must follow actual use. |
| M-16 | [Marketstack Pricing](https://marketstack.com/pricing/) | Free 100 requests/month; EOD/free history and paid intraday/history features. | VERIFIED on this page; conflicts with M-17 | Quota cannot be frozen across official pages. |
| M-17 | [Marketstack FAQ](https://marketstack.com/faq) | Page contains materially inconsistent free monthly request statements. | CONFLICTING | Reject current selection. |
| M-18 | [Marketstack API Documentation](https://marketstack.com/documentation) | Formal access-key REST API, tickers/exchanges/EOD/intraday endpoints. | VERIFIED | Capability exists but exact scope/rights incomplete. |
| M-19 | [Marketstack Agreement](https://marketstack.com/agreement) | Provider agreement/license terms. | VERIFIED at page level | Does not resolve exact four-market cache/redistribution need. |
| M-20 | [Marketstack API Status](https://marketstack.com/api-status) | The official status page timed out in the research client during this visit. | UNVERIFIED current status | No operational-health claim is made. |
| M-21 | [Twelve Data System Status](https://twelvedata.isitup.cloud/) | Provider-linked status page reported Operational, zero active incidents, and operational API/WebSocket/website components. | VERIFIED point-in-time status | Confirms current operation only; it is not an SLA or terms/coverage decision. |

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
| Twelve Data paid authorization and exact subscribed cache/display/export rights | UNVERIFIED for Aureus entitlement | The capability appears strongest, but the user has not authorized purchase/account/contract and terms vary by use. | User budget/use authorization plus current contract review across XNYS/XNAS/XHKG/XSHG/XSHE/XJPX needs. |
| Marketstack free quota | CONFLICTING | Official pricing and FAQ conflict. | Provider clarification. |
| Marketstack exact four-region entitlement and usage rights | UNVERIFIED | Broad exchange claims do not prove the needed plan and redistribution/cache boundary. | Official plan/exchange/terms mapping. |
| Primary Market Data Provider | **BLOCKED** | No candidate safely satisfies the combined product/operations/terms evidence. | Authorized paid global-provider path or explicit product-scope decision; then update A-008. |
| Direct ECB API availability | UNVERIFIED during visit | API overview returned 503. | Not core: selected Frankfurter path and ECB dataset evidence remain available; retest before choosing a direct adapter. |
| Project source license | USER AUTHORIZATION_PENDING | Executor cannot create or choose LICENSE for the user. | User authorization; Apache-2.0 is only a recommendation. |
| Signing, notarization, Development Team, distribution channel | USER AUTHORIZATION_PENDING | User-owned credentials and release choices are outside Stage 1. | User-authorized release-stage decision. |

No other core architecture item relies on an `UNVERIFIED` fact as if it were frozen. A-008 is expressly blocked; user-owned license/signing matters are labeled permissions rather than technical completion.

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
| A-008 Market | M-01–M-19 | Every candidate has a material official-evidence gap or conflict against frozen scope/rights. | BLOCKED; protocol + synthetic mock only. |
| A-010 Cache | Product hard constraint + A-004 physical boundary | Numeric limits make behavior testable; separate capability graph makes deletion safety reviewable. | 512 MiB default, typed TTLs, LRU, separate DB. |
| A-011 Charts | P-15–P-18, C-01–C-09 | Native charts optimize wealth accessibility; LWC supplies the specialized market interaction surface. | Swift Charts + bundled LWC. |
| A-012 Runtime | Scope formulas, local Swift toolchain, R-01/R-02 | V1 needs deterministic formulas, not a second analytics ecosystem. | Swift-only. |
| A-013 Networking | P-09/P-10 and provider quota evidence | Native async networking plus one actor owner provides cancellation, rate, and retry control. | URLSession + bounded actor policy. |
| A-014 Privacy | P-11–P-14, governance | Sandbox/container/Keychain/OSLog cover V1 baseline; DB encryption lacks a frozen recovery design. | System privacy controls; no app-layer DB encryption in V1. |
| A-015 Backup/logging | D-01, P-14, physical separation | Consistent DB backup and manifest/hash checks protect permanent data without copying cache/secrets. | Five validated backups; redacted OSLog. |
| A-016 Testing | P-19/P-20 and domain risk analysis | Swift Testing covers deterministic logic; XCUI/manual checks cover app interaction. | Layered synthetic test strategy. |
| A-017 Dependencies | D-02/D-03, C-02/C-06/C-07, D-05 | Only persistence lacks an adequate system-level Swift abstraction at Stage 2; professional chart need occurs later. | GRDB Stage 2; LWC Stage 7; project license pending user. |

## 13. Research Boundary

This evidence supports a coherent architecture candidate except for A-008. It does not prove live endpoint behavior, paid entitlement, provider SLA, production latency, signed sandbox behavior, build success, or test success. Those require later authorized implementation and acceptance evidence. No unsupported market claim is converted into a product scope reduction.
