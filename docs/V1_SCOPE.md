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

The required market scope is not silently narrowed by Stage 1 provider uncertainty. A production Primary Market Data Provider remains a documented architecture blocker because current official evidence does not establish a free, practically usable provider for the required United States, Hong Kong, mainland China, and Japan coverage with acceptable terms, quotas, and local-cache rights. A Provider-independent foundation is only a bounded architectural direction: it does **not** mean Stage 1 has passed, does **not** authorize Stage 2, and cannot substitute for resolving A-008. Production-provider implementation may not proceed until the blocker is resolved by an authorized decision.

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

## 5. Permanent Long-term Exclusion

The only frozen permanent long-term product exclusion is **AI / LLM and every product variant built on it**, including an AI Assistant, AI Agent, AI classification, AI investment advice, automated financial guidance, or any equivalent AI-mediated workflow. This is not a Post-V1 item and cannot enter scope through a later-stage implementation prompt.

## 6. V1 Non-goals, Deferred, or Conditional Directions

### 6.1 V1 non-goals

The following capabilities are not developed in V1 and must not be added incidentally anywhere in the current Stage 2–14 route. They are not promised for a future version, and only an explicit user product and architecture decision can bring one into a later scope. Except for AI / LLM above, they are **not** declared permanent long-term exclusions:

- Automatic Trading.
- Live Order Placement.
- Open Banking.
- Automatic Brokerage Synchronization.
- Cloud Account System.
- Social or Community Features.
- High-frequency Real-time Quotes or Trading Infrastructure.
- Complex Quantitative Backtesting Platform.

### 6.2 Deferred or conditional directions

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
| Stage 2 | **App Foundation + Persistence Core:** App shell; Navigation; core domain/value types; GRDB persistence bootstrap; Migration foundation; permanent/cache physical separation; synthetic demo policy; Unit/Integration/UI testing foundation; Provider-independent contracts only. A-008 remains blocked, Stage 1 has not passed by implication, and this mapping does not authorize Stage 2. |
| Stage 3 | **Wealth + Asset Container.** |
| Stage 4 | **Ledger + Cash Flow.** |
| Stage 5 | **Wealth Snapshot + Dashboard + Core Visualization.** |
| Stage 6 | **Market Data Infrastructure only:** `MarketDataProvider` production boundary; Symbol model and search backend; Historical Prices; FX; Market Cache; Size limit; TTL/LRU; automatic/manual cleanup; retry/error/rate-limit/offline behavior; permanent wealth data safety. Market Overview, Watchlist UI, Heatmap, and single-stock professional chart UI are excluded from Stage 6. |
| Stage 7 | **Markets Terminal:** Market Overview; Watchlist; Day/Week/Month/Quarter/Year interaction; Market Heatmap; Stock detail; Candlestick; Volume; Zoom/Pan/Crosshair/Tooltip; MA/EMA/RSI/MACD/Bollinger Bands. |
| Stage 8 | **Portfolio.** |
| Stage 9 | **Analytics.** |
| Stage 10 | **Goals + Wealth Intelligence.** |
| Stage 11 | **Privacy + Settings + Data Lifecycle + Reliability:** Settings; Cache controls; Import/export lifecycle; Backup; Restore; Migration reliability; Keychain; Secret handling; privacy-safe logging; Demo mode; Offline degradation; Data integrity. |
| Stage 12 | **V1 UX / Performance / Regression Hardening.** |
| Stage 13 | **V1 Release Candidate Audit.** |
| Stage 14 | **V1 Release preparation.** Stage 14 does not authorize an Executor to Push, Tag, create a GitHub Release, or publicly publish; the user alone decides and performs Git/GitHub and release actions. |

## 8. Scope Change Control

After Reviewer approval, a change must identify the affected capability, rationale, data/migration consequence, privacy consequence, tests, stage ownership, and explicit approving authority. A provider limitation, implementation difficulty, or schedule pressure must be surfaced as a decision request; it must not silently reduce frozen scope. Conversely, future directions do not enter V1 without explicit authorization.
