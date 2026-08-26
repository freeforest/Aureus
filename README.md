# Aureus Wealth Terminal

Aureus is a local-first, visualization-first Personal Wealth Intelligence Terminal for macOS.

The product is designed around CNY and USD, with CNY as the default unified valuation currency. It keeps original-currency values, exchange-rate context, and converted values distinct. AI and LLM capabilities are outside the product's long-term scope.

Planned product areas are:

- Dashboard
- Wealth
- Markets
- Portfolio
- Analytics
- Ledger
- Goals
- Settings

Privacy is a hard boundary: real accounts, balances, holdings, transactions, databases, backups, credentials, and private imports or exports must not enter the future public repository. Demos and tests may use only synthetic or sanitized data.

## Current Status

Stages 1 through 7 have passed their applicable Reviewer implementation gates. The current state is **Stage 8 Portfolio Implementation Candidate — Awaiting Reviewer Gate**. Portfolio is now a local-first terminal with Portfolio CRUD, Wealth security links, Opening Lot/Buy/Sell/Manual Split activities, deterministic FIFO lots, checked-Decimal CNY cost basis and P&L, quantity reconciliation, atomic Portfolio NAV snapshots, allocation, a native P&L heatmap, and an identifier-only session Benchmark boundary. It remains fully usable offline from user-authored permanent records and never treats a Provider value as a Portfolio source of truth.

Current Stage 8 verification is `PARTIAL`: all Unit/Integration tests and the five inherited focused UI regressions pass, while the bounded Portfolio focused UI and the single full UI run retain one native disclosure Accessibility-label failure (full UI: 11/12). Stage 9 remains `NO-GO` pending independent Reviewer action.

Twelve Data remains the selected Primary Market Data Provider under **Personal Local Mode**: Aureus runs only on one user's Mac for personal/internal, non-commercial use; it is not a hosted service and does not redistribute or commercially display Provider data. Open source applies to program source, not Provider data, credentials, or user financial data. Basic Free remains the usable US-focused entry path, while every endpoint and MIC remains governed by the actual Plan and exchange entitlement.

Twelve Data Production data is session-only in V1. Search, Quote, OHLCV, and entitled Corporate Actions route through one dependency-injected, actor-owned 64 MiB transient memory store with typed TTL, deterministic LRU, checked logical byte accounting, lifecycle clearing, and no serialization or cross-launch recovery. Stage 6MA makes exact expiry stale, clears the complete Provider session before returning confirmed credential/entitlement loss, generation-checks every fresh, stale-fallback, stored, and oversize return, routes Settings Clear through the service lifecycle boundary, and requires complete Split plus Dividend state. Production persistent Twelve Data writes are **Disabled by product policy**; query paths neither read nor write Twelve Data disk rows, and startup performs a Provider-scoped legacy-row purge. Retention rights remain `BLOCKED`, but this deferred disk-cache question is no longer proposed as a permanent Stage 7 implementation blocker. Minimal user-authored symbol/MIC identifiers and UI preferences may persist without Provider descriptions or values.

Prompt 6NBA received Reviewer Gate `PASS` after classifying the previous one-attempt Search failure as `SEARCH_INVALID_PAYLOAD`. Stage 6NBB permanently repairs `/symbol_search` at the row boundary: it keeps strict envelope validation, isolates malformed and out-of-scope rows, preserves Provider relevance order and normalized raw MIC, performs stable first-result de-duplication, and does not expand the V1 market-currency set. Its one live Search responded successfully after exactly one transport attempt, but the old harness accepted only `AAPL/XNAS` and did not report the actual raw MIC; that evidence cannot be retrospectively promoted to an exact US identity or Historical entitlement. Stage 6NBC corrects the criterion to exact symbol `AAPL`, currency `USD`, and raw MIC in `XNAS`, `XNYS`, `XASE`, `ARCX`, `BATS`, `XNCM`, `XNGS`, or `XNMS`, while preserving the selected raw MIC and aggregating capability only as `US`. First-party Twelve Data pages identify AAPL with `XNGS` as catalog/documentation evidence. The single bounded Production re-observation then selected `AAPL/USD/XNGS` in Provider relevance order and returned a nonempty typed `1day`/`.all`/output-size-5 Historical page after exactly two local transport attempts total, with raw MIC `XNGS` retained and observed only under the aggregate `US` capability. This verifies the Search identity and that precise Historical operation only for the current credential at the observed instant; it does not prove that the Actual Plan is Basic or extend to Quote, Corporate Actions, freshness, other MICs, or `XHKG`/`XSHG`/`XSHE`/`XJPX`, which remain `NOT VERIFIED`.

The 2026-08-17 Terms refresh records §12.5 as immediate cessation of access with a deletion obligation and §16.2 as the operational deadline to delete within 30 days after termination or expiration. Aureus keeps immediate Provider-scoped purge as a stricter internal policy, not as a claimed Provider deadline. `/api_usage` remains `NOT VERIFIED`. No real Provider request was performed for Stage 7 implementation or automated verification.

Stage 7 preserves the accepted live evidence boundary: only the previously observed `AAPL/USD/XNGS` Search identity and precise `1day`/`.all` Historical operation are recorded as verified at that observation instant. Actual Plan, Quote, Corporate Actions, actual freshness, other symbols/MICs, and all international markets remain `NOT VERIFIED`. Twelve Data persistent writes remain **Disabled** and retention rights remain **BLOCKED**. Synthetic Demo UI and tests are conspicuously identified and never count as live acceptance.

Stage 7A freezes chart panes as candlestick/main overlays `0`, volume `1`, RSI `2`, and MACD `3`; the local renderer returns only a sanitized series/type/pane/point-count summary for integration evidence. Range requests now use Gregorian UTC civil dates (`1D` latest returned daily bar, calendar `1W/1M/3M/YTD/1Y/5Y`, and bounded `MAX`) and presentation filters inclusively. Zoom/pan visible-range callbacks use typed dates and drive the native summary and accessible table. Theme updates, bridge byte/string/date limits, Watchlist reorder controls, and range-scoped multi-instrument heatmap values remain local and do not trigger or imply Provider capability.

Stage 7AA preserved the four earlier Stage 7A accessibility failures as historical evidence, then tested the final source without a pre-test source change. The independent `markets.chart.status` and `markets.chart.visible-range` nodes passed the first bounded Stage 7 focused UI run (`1/1`), so no AX-only repair or focused retry occurred. The single authorized full UI run passed `11/11`; Stage 7 focused Unit/Integration passed `26/26`, the stable unsigned full Unit suite passed `210/210` definitions (`243` executions), and final clean build plus build-for-testing passed. These local and synthetic results close the implementation evidence requested by Prompt 7AA but do not decide the Reviewer Gate or expand live Provider acceptance.

Stage 8 appends `permanent_v6_portfolio` without changing the v1–v5 migration blocks. Active Portfolio tables are separate from legacy foundation placeholders, use foreign keys and INTEGER authoritative values, and preserve Wealth/Ledger deletion boundaries. Wealth manual marks and saved FX provenance are the only persistent valuation inputs. Benchmark values are loaded only after an explicit user action, remain in the transient market session, compare exact overlapping civil dates at base 100, and are never stored in Portfolio tables or preferences. Stage 9 return/risk analytics, brokerage sync, live pricing, and investment advice are not implemented.

- [V1 Scope — Frozen](docs/V1_SCOPE.md)
- [V1 Architecture & Technology — Frozen](docs/V1_ARCHITECTURE.md)
- [V1 Research Evidence](docs/V1_RESEARCH_EVIDENCE.md)
- [Stage 6 Market Data Acceptance Evidence](docs/STAGE6_MARKET_DATA_ACCEPTANCE.md)
- [Stage 6 Twelve Data Retention Decision](docs/STAGE6_TWELVE_DATA_RETENTION_DECISION.md)
- [Stage 7 Markets Terminal Acceptance](docs/STAGE7_MARKETS_TERMINAL_ACCEPTANCE.md)
- [Stage 8 Portfolio Acceptance](docs/STAGE8_PORTFOLIO_ACCEPTANCE.md)
- [Third-Party Notices](THIRD_PARTY_NOTICES.md)

## Build and Test

Resolve the single external dependency, GRDB 7.11.1:

```sh
xcodebuild -resolvePackageDependencies -project Aureus.xcodeproj -scheme Aureus
```

Build the arm64 Debug app and all test products in isolated DerivedData:

```sh
xcodebuild -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage8-DerivedData clean build
xcodebuild -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage8-DerivedData build-for-testing
```

Run the complete Unit/Integration suite, then the UI suite. The UI test runner uses only local ad-hoc signing and does not require a Development Team:

```sh
xcodebuild test -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage8-Unit -only-testing:AureusTests CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage8-UI -only-testing:AureusUITests
```

The canonical product design source for later stages is [Aureus_Wealth_Terminal_项目设计汇总.md](Aureus_Wealth_Terminal_项目设计汇总.md).

The specific open-source license has not yet been frozen. All Git and GitHub operations are managed manually by the user.
