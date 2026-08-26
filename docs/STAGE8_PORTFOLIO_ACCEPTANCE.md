# Stage 8 Portfolio Acceptance

**Status:** Stage 8 Portfolio Implementation Candidate — Awaiting Reviewer Gate  
**Implementation date:** 2026-08-26  
**Authority:** This document records Stage 8 implementation and synthetic verification evidence. It does not decide the Stage 8 Gate or authorize Stage 9.

## 1. Product and evidence boundary

Portfolio is an offline-first permanent user-record feature. Its source of truth is user-authored Portfolio activity plus existing Wealth manual marks and saved FX provenance. No real Provider request is part of Stage 8 automated verification. Twelve Data values remain session-only, persistent writes remain `Disabled`, and retention remains `BLOCKED`.

Stage 7 Reviewer Gate is inherited as `PASS`. Its observed `AAPL/USD/XNGS` Search/Historical evidence is not promoted into Portfolio valuation, Benchmark entitlement, live pricing, actual Plan, freshness, Quote, Corporate Actions, other MICs, or international coverage.

## 2. Portfolio source of truth

- A Portfolio has a UUID, non-empty name, fixed CNY base currency, UTC created/updated instants, and deterministic order.
- A security link references one existing Wealth Stock, ETF, or Fund container and preserves normalized ticker, raw MIC, and CNY/USD security currency.
- Portfolio quantity comes only from Opening Lot, Buy, Sell, and Manual Split activity replay. Wealth quantity remains an independent user record.
- Quantity disagreement is displayed as `Quantity Mismatch`; neither source is silently modified.
- Opening Lots are explicitly manual pre-Portfolio records and never create or impersonate a Broker trade or Ledger cash flow.

## 3. FIFO and currency contract

Activities sort by civil date, recorded UTC instant, then UUID. Each Buy or Opening Lot creates an independent FIFO lot. A Sell consumes the oldest remaining lots and rejects short positions. Partial and multi-lot disposal preserve basis; the final consumed segment absorbs deterministic rounding residual. Manual Split changes remaining quantity by a checked positive ratio without changing total basis or realized P&L.

All authoritative arithmetic uses checked `Decimal` and existing Money/Quantity/Price value boundaries. CNY FX is strict identity. USD acquisition, sale, and current valuation each require explicit saved provenance with source, reference civil date, recorded/fetched instant, and manual/stale state. Missing FX is not treated as CNY.

| Value | Frozen Stage 8 rule |
|---|---|
| Buy lot basis | quantity × unit price + buy fee |
| Sell net proceeds | quantity × unit price − sell fee |
| Realized P&L | sell net proceeds − disposed FIFO basis |
| Unrealized P&L | manual marked value − remaining basis |
| Portfolio weight | holding CNY value ÷ Portfolio CNY NAV |

## 4. Persistence and migration

The only new migration is append-only `permanent_v6_portfolio`. It creates active Portfolio definitions, security links, activities, NAV snapshot headers, and NAV snapshot items. Foreign keys, CHECK/UNIQUE constraints, and indexes protect identity and lifecycle. Authoritative financial values use SQLite `INTEGER` plus semantic columns; no `REAL` financial authority is introduced.

The v1–v5 migration blocks are not modified. Fresh databases and every v1–v5 forward fixture migrate to version 6. Historical activity mutation is replay-validated in the same transaction, so an edit or deletion that causes a later oversell rolls back. Portfolio deletion cascades only through its own records and never into Wealth, Ledger, Dashboard snapshots, Market Cache, credentials, or another Portfolio.

Complete Portfolio NAV snapshots are atomic header/item transactions. A Portfolio has at most one complete snapshot per civil date; a same-date capture explicitly replaces that Portfolio snapshot. Items store Portfolio-derived quantity, manual Wealth mark, original and converted CNY values, saved FX provenance, remaining basis, and reconciliation state. No Twelve Data payload, freshness, credential, or Market Cache row is stored.

## 5. UI and accessibility

The Stage 8 terminal replaces the Portfolio placeholder with:

- native Portfolio create, rename, reorder, and confirmed delete;
- Wealth security linking and independent quantity reconciliation;
- Opening Lot, Buy, Sell, and Manual Split activity history;
- holdings with manual-mark labels, currency/FX provenance, basis, realized/unrealized P&L, and weight;
- a native Swift Charts NAV curve and accessible snapshot table;
- asset-kind and currency allocation;
- an equal-area P&L heatmap with signed text as well as color;
- an identifier-only Benchmark preference and explicit session load/clear controls.

Sector and geography are `Unavailable` unless the user has a real supported source. Production empty state is honest; Synthetic Demo is visibly labeled and uses only deterministic synthetic records. Stable accessibility identifiers are used instead of fixed coordinates or row numbers.

## 6. Benchmark boundary

Preferences persist only normalized symbol, raw MIC, and UI range. Provider description, currency, bars, returns, freshness, observation, and payload are excluded. Entering Portfolio or selecting a Portfolio makes no request. `Load Session Benchmark` is the sole explicit trigger: it resolves the exact symbol/raw MIC through the existing market boundary, loads daily `.all` data into the transient session, and compares only exact overlapping civil dates. At least two overlap points are required, each series is indexed independently to 100 at the first overlap, and no forward fill occurs. The comparison is not labeled TWR, CAGR, Alpha, or investment advice.

## 7. Isolation matrix

| Boundary | Stage 8 state |
|---|---|
| Portfolio permanent records | Enabled in active v6 tables |
| Wealth/Ledger/Dashboard ownership | Unchanged and isolated |
| Twelve Data Portfolio persistence | Disabled |
| Benchmark value persistence | Disabled; session-only |
| Frankfurter/ECB policy | Unchanged |
| Market Cache policy | Unchanged; not a Portfolio source |
| Credential lifecycle | Unchanged |
| AI/LLM/Python/Broker sync | Not implemented |
| Stage 9 metrics | Not implemented |

## 8. Verification evidence

The Stage 8 focused suite covers FIFO lots, fees, Opening Lots, Manual Split, oversell and historical mutation rollback, stable same-day order, checked arithmetic, CNY/USD FX provenance, fresh and v1–v5 migration, CRUD/reopen/delete isolation, same-date snapshot replacement, identifier-only preferences, exact-overlap Benchmark normalization, and a deterministic 10,000-activity replay.

Current execution evidence:

| Verification | Result |
|---|---|
| Stage 8 plus Stage 6/7 focused Unit/Integration | `PASS` — 137 definitions / 140 executions |
| Full `AureusTests` | `PASS` — 223 definitions / 256 executions |
| Final Debug arm64 clean build | `PASS` |
| Final build-for-testing | `PASS` |
| Existing focused UI regressions | `PASS` — Settings, Wealth, Ledger Dynamic, Native CSV, and Markets (5/5) |
| Portfolio focused UI, initial run | `FAIL` — 0/1; disclosure Accessibility label assertion |
| Portfolio focused UI, one bounded post-repair run | `FAIL` — 0/1; the same disclosure Accessibility label assertion |
| Full `AureusUITests`, single bounded run | `PARTIAL` — 11/12; only the Portfolio disclosure assertion failed |
| Real Provider requests | `NOT RUN` |

The Portfolio UI run did verify that the Portfolio page, CNY NAV summary, synthetic holding, native NAV chart and table, P&L heatmap, and explicit Benchmark control were independently queryable before the disclosure assertion. The attempted minimal native Accessibility-label repair compiled but did not close that assertion, so the failure is retained rather than bypassed or retried again.

The deterministic 10,000-activity FIFO replay completed in 1.484 seconds in the final full Unit run. Separate measured runs for the requested 100-holding summary, 5,000-snapshot chart preparation, repeated Portfolio switching, and idle CPU/memory observation were not completed and remain `NOT RUN`.

Synthetic tests, builds, or UI visibility are implementation evidence only and do not expand live Provider capability.

## 9. Gate boundary

This is **Stage 8 Portfolio Implementation Candidate — Awaiting Reviewer Gate**. The current implementation evidence is `PARTIAL` because the Portfolio disclosure Accessibility assertion and several requested performance measurements remain open. This document does not declare Stage 8 `PASS`, enter Stage 9, claim V1/Release readiness, enable persistent Twelve Data writes, or change retention from `BLOCKED`.
