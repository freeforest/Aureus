# Aureus V1 Scope Freeze Candidate

## 1. Status and Authority

**Status:** Stage 1 Freeze Candidate  
**Candidate date:** 2026-08-10  
**Approval boundary:** This document becomes the V1 scope baseline only after a Reviewer Gate decision of PASS.

Authority remains, from highest to lowest:

1. The user's latest explicit instruction.
2. Frozen long-term product decisions.
3. [`Aureus_Wealth_Terminal_项目设计汇总.md`](../Aureus_Wealth_Terminal_%E9%A1%B9%E7%9B%AE%E8%AE%BE%E8%AE%A1%E6%B1%87%E6%80%BB.md).
4. The approved V1 scope, once this candidate is accepted.
5. The current stage prompt.
6. Historical plans or discussions.

This file freezes product scope, not implementation details. The technology candidate is in [`V1_ARCHITECTURE.md`](V1_ARCHITECTURE.md), and its research evidence is in [`V1_RESEARCH_EVIDENCE.md`](V1_RESEARCH_EVIDENCE.md). A change after Reviewer approval requires an explicit, documented scope decision; implementation convenience is not authority to add or remove product requirements.

## 2. Product Boundary

Aureus Wealth Terminal V1 is a macOS, Apple-Silicon-first, local-first Personal Wealth Intelligence Terminal. It is visualization-first and is not a conventional expense tracker. Program source is planned to be open source, while real financial data remains private and outside the Repository.

V1 prioritizes CNY and USD. CNY is the unified valuation currency. A USD-denominated value retains the original USD amount, the applied FX rate, and the converted CNY value. Demo and test paths use synthetic or sanitized data only.

The eight required top-level modules are:

| Module | V1 responsibility |
|---|---|
| Dashboard | Cross-domain wealth summary, trends, allocation, cash flow, goals, market context, and heatmaps. |
| Wealth | Asset containers, accounts, assets, liabilities, insurance, other assets, valuation, and net-worth history. |
| Markets | Market overview, watchlist, symbol search, historical data, professional financial charts, indicators, and offline degradation. |
| Portfolio | Holdings, trades, cost basis, P&L, NAV, benchmark comparison, and portfolio heatmaps. |
| Analytics | Deterministic return, risk, drawdown, cash-flow, and allocation analytics. |
| Ledger | Income, expense, transfer, investment events, categories, tags, deterministic classification, and CSV workflows. |
| Goals | Goal tracking, compound planning, FIRE planning, and saving-rate analysis. |
| Settings | Currency and display preferences, cache controls, imports/exports, backup/restore, privacy, and data maintenance. |

No required module may be removed merely because its implementation occurs in a later V1 stage.

## 3. Required V1 Capabilities

### 3.1 Wealth model and valuation

- Asset Container as the ownership and grouping boundary.
- Account, Asset, and Liability records with explicit relationships and validation.
- Bank and Cash holdings.
- Stock, ETF, and Fund holdings.
- Insurance records.
- Other Asset records without introducing a professional real-estate sub-system.
- CNY and USD monetary values.
- CNY aggregate valuation while preserving original currency values and FX provenance.
- Snapshots and reconstructable Net Worth history.
- Asset Allocation and Cash Flow views.
- Net Worth heatmap and supporting visual summaries.

### 3.2 Ledger and deterministic classification

- Income, Expense, and Transfer semantics.
- Buy, Sell, Dividend, Interest, and Fee investment events.
- Category and Tags.
- CSV Import and CSV Export with explicit preview, validation, error reporting, and user confirmation.
- Deterministic rule classification; the same input and rule set must produce the same result.
- Transfer balance neutrality at aggregate level and prevention of accidental double counting.
- Import and production data paths separated from synthetic demo/test paths.

### 3.3 Market intelligence

- Market Overview.
- Watchlist.
- Symbol Search.
- Historical Prices and OHLCV provenance.
- Candlestick and Volume presentation.
- Zoom, Pan, Crosshair, and Tooltip interactions.
- Time-range selection.
- MA, EMA, RSI, MACD, and Bollinger Bands.
- Market Heatmap.
- Explicit stale, delayed, missing, and offline states.
- Provider attribution and terms compliance.

The required market scope is not silently narrowed by Stage 1 provider uncertainty. A live Primary Market Data Provider remains a documented architecture blocker because current official evidence does not yet establish one safe provider for the required United States, Hong Kong, mainland China, and Japan coverage with acceptable terms and quotas. The Provider-independent domain, cache, UI, and deterministic mock work may proceed only within the contract in `V1_ARCHITECTURE.md`; live-provider implementation may not proceed until the blocker is resolved by an authorized decision.

### 3.4 Portfolio intelligence

- Holdings and Trades.
- Lot-aware Cost Basis.
- Realized and Unrealized P&L.
- Portfolio NAV history.
- Benchmark comparison.
- Total Return, CAGR, TWR, and XIRR.
- Volatility, Sharpe ratio, and Max Drawdown.
- Portfolio Heatmap.
- Deterministic, cited formulas with synthetic regression fixtures.

### 3.5 Planning, operations, and hardening

- Goals and progress tracking.
- Compound Planning.
- FIRE planning.
- Saving Rate analysis.
- Settings for supported preferences and privacy controls.
- Cache Management with bounded capacity, TTL, LRU-style eviction, automatic cleanup, and manual cleanup.
- Import and Export.
- Backup and Restore.
- Schema Migration.
- Keychain-backed provider credentials.
- Offline degradation without presenting stale data as current.
- Accessibility, Performance, and Release hardening.
- Permanent wealth data physically and logically separated from recoverable Market Cache data.
- Cache cleanup that can never delete permanent wealth records.

## 4. Required V1 Quality Boundaries

- The app remains local-first and usable for permanent wealth records without a network connection.
- Real accounts, balances, holdings, trades, goals, databases, backups, private imports/exports, credentials, and identifying logs never enter the public Repository.
- All shipped demo data and all automated-test fixtures are visibly synthetic or sanitized.
- Financial calculations are deterministic and testable; persisted authoritative money does not use binary floating point.
- Market and FX facts carry provider and time provenance. Missing or stale data is visible to the user.
- Migration and restore failure must not silently destroy or replace the last valid permanent store.
- A successful mock-provider test is not evidence that a real provider, its coverage, or its terms have been accepted.
- Release readiness includes accessibility, performance, privacy, migration, backup/restore, and offline checks rather than only feature completion.

## 5. Explicit Long-term Non-goals

The following are long-term product exclusions, not Post-V1 features:

- AI or LLM capability of any kind.
- AI Assistant.
- AI classification.
- AI investment advice.
- AI Agent workflows.
- Automatic trading.
- Live order placement.
- Open Banking integration.
- Automatic brokerage synchronization.
- A cloud account system for user wealth data.
- Social or community features.
- High-frequency real-time quotes or trading infrastructure.
- A complex quantitative backtesting platform.

## 6. Deferred or Conditional Directions

These directions are not part of the required V1 baseline. They are not permanently cancelled; each requires a later explicit product and architecture decision.

| Direction | Classification for V1 | Boundary |
|---|---|---|
| Crypto | Deferred | No exchange connectivity, wallet, token pricing, or crypto accounting in V1. |
| HKD and additional currencies | Deferred | HKD examples do not expand the frozen CNY/USD implementation scope. |
| Python Analytics | Deferred | V1 analytics is Swift-only; Python is not bundled or installed. |
| Professional real-estate modeling | Deferred | V1 may represent property as Other Asset, without property-specific cash-flow/tax models. |
| ATR, Fibonacci, Volume Profile | Deferred | The V1 indicator set remains MA, EMA, RSI, MACD, and Bollinger Bands. |
| Sortino, Beta, Alpha, and other secondary metrics | Deferred | The required V1 risk set remains Volatility, Sharpe, and Max Drawdown. |
| Application-layer database encryption | Conditional, excluded from V1 | V1 relies on App Sandbox, Keychain for secrets, and host data-at-rest protection. Adding SQLCipher or equivalent requires threat-model, migration, recovery, export, performance, and license review. |

## 7. Stage Mapping

This mapping assigns the frozen capabilities to the existing Stage 2 through Stage 14 execution sequence. It does not authorize work beyond the current stage and does not replace future stage prompts.

| Stage | V1 ownership |
|---|---|
| Stage 2 | App foundation and shell; target/folder baseline; navigation; domain value types; GRDB persistence bootstrap and migrations; separate permanent/cache stores; synthetic fixture policy; initial unit/UI test targets. No live market provider. |
| Stage 3 | Wealth: Asset Container, Account, Asset, Liability, Bank/Cash, Stock/ETF/Fund, Insurance, Other Asset, CNY/USD valuation foundations. |
| Stage 4 | Ledger: Income, Expense, Transfer, Buy, Sell, Dividend, Interest, Fee, Category, Tags, deterministic classification, and CSV import/export. |
| Stage 5 | Snapshots, Net Worth history, Asset Allocation, Cash Flow, Dashboard summaries, and initial Net Worth/Expense heatmaps. |
| Stage 6 | Markets foundation: Provider contract, deterministic mock, Market Overview, Watchlist, Symbol Search, Historical Prices, bounded cache, attribution/offline states. A live provider requires prior resolution of A-008. |
| Stage 7 | Professional market visualization: candlestick, volume, zoom, pan, crosshair, tooltip, time ranges, MA/EMA/RSI/MACD/Bollinger Bands, and Market Heatmap. |
| Stage 8 | Portfolio: Holdings, Trades, Cost Basis, realized/unrealized P&L, Portfolio NAV, Benchmark, and Portfolio Heatmap. |
| Stage 9 | Analytics: Total Return, CAGR, TWR, XIRR, Volatility, Sharpe, Max Drawdown, formula evidence, and deterministic verification. |
| Stage 10 | Goals: goal tracking, compound planning, FIRE, and Saving Rate. |
| Stage 11 | Settings: preferences, cache management, Keychain UX, import/export controls, and privacy surfaces. |
| Stage 12 | Backup/Restore, migration hardening, data-integrity recovery, privacy boundaries, and security-scoped file workflows. |
| Stage 13 | Accessibility, performance, offline degradation, large synthetic datasets, and cross-feature hardening. |
| Stage 14 | Release readiness, distribution checks, licensing evidence, signing/notarization boundaries, documentation, and final privacy review. User-owned release and Git/GitHub actions remain outside Agent authority. |

## 8. Scope Change Control

After Reviewer approval, a change must identify the affected capability, rationale, data/migration consequence, privacy consequence, tests, stage ownership, and explicit approving authority. A provider limitation, implementation difficulty, or schedule pressure must be surfaced as a decision request; it must not silently reduce frozen scope. Conversely, future directions do not enter V1 without explicit authorization.
