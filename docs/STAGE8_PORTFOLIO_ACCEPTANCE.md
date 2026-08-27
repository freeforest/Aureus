# Stage 8 Portfolio Acceptance

**Status:** Stage 8AB PARTIAL — Awaiting Reviewer Gate  
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

## 8. Initial Stage 8 verification evidence (historical)

The Stage 8 focused suite covers FIFO lots, fees, Opening Lots, Manual Split, oversell and historical mutation rollback, stable same-day order, checked arithmetic, CNY/USD FX provenance, fresh and v1–v5 migration, CRUD/reopen/delete isolation, same-date snapshot replacement, identifier-only preferences, exact-overlap Benchmark normalization, and a deterministic 10,000-activity replay.

Prompt 8 execution evidence, retained as historical input to the Stage 8A repair:

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

In Prompt 8, the deterministic 10,000-activity FIFO replay completed in 1.484 seconds in the final full Unit run. At that historical checkpoint, separate measured runs for the requested 100-holding summary, 5,000-snapshot chart preparation, repeated Portfolio switching, and idle CPU/memory observation were `NOT RUN`; Section 11 records the later Stage 8A measurements.

Synthetic tests, builds, or UI visibility are implementation evidence only and do not expand live Provider capability.

## 9. Gate boundary

This is **Stage 8A PARTIAL — Awaiting Reviewer Gate**. Stage 8A closes the disclosure split, holding-summary scan, and required performance-evidence implementation work, but bounded Portfolio and existing focused UI failures remain. This document does not declare Stage 8 `PASS`, enter Stage 9, claim V1/Release readiness, enable persistent Twelve Data writes, or change retention from `BLOCKED`.

## 10. Stage 8A disclosure and holding-summary repair

The fixed Provider policy and dynamic Benchmark state are now independent native semantics:

- `portfolio.disclosure` always states: `Portfolio records are local and use Manual Wealth Marks. No Provider request is made automatically.`
- `portfolio.benchmark.disclosure` alone changes for not-loaded, loaded, offline, timeout, missing, denied, or cleared Benchmark session state.
- Portfolio selection, Benchmark success/failure/clear, and session clearing do not overwrite the fixed policy.
- Neither node forwards raw Provider errors or establishes Plan, freshness, or entitlement evidence.

One holding-summary operation now reads ordered links once, activities once, and the relevant Wealth records in one queue read. It performs FIFO replay once, establishes the activity-to-security map once, groups remaining lots and realized results once, and limits each holding to its own groups. Link order, raw MIC, quantity, original/CNY basis, realized/unrealized P&L, mark/FX provenance, reconciliation, NAV, and final weight semantics remain unchanged. No new Store, cache, singleton, telemetry, or Provider request was introduced.

## 11. Stage 8A performance evidence

All workloads used deterministic synthetic data and an optimized unsigned Release test product. The signed Release host was also attempted and retained: 17 tests executed, of which six failed solely because the signed host could not create its isolated `/private/tmp/AureusTests` files. The stable unsigned host then completed the business suite.

| Workload | Method | Observed result |
|---|---|---|
| 10,000-activity FIFO replay | 1 warm-up, 5 measured full replays | 15.889–17.885 ms elapsed; p50 3.212–3.270 ms; p95 3.283–4.265 ms |
| Append Buy after 10,000 | 1 complete replay | 3.407–3.608 ms; quantity/basis assertions passed |
| Append Sell after 10,000 | 1 complete replay | 3.216–3.700 ms; quantity/basis/P&L assertions passed |
| 100 holdings summary/allocation/heatmap | 1 warm-up, 7 complete iterations | 201.624–204.457 ms elapsed; p50 28.545–29.209 ms; p95 29.441–29.622 ms |
| 5,000 NAV snapshots | 1 complete sort/chart/table/exact-overlap preparation | 173.031–210.005 ms; all 5,000 retained |
| 10 Portfolios / 100 switches | 100 selection/reload operations | 203.184–310.550 ms; final selection and isolation assertions passed |
| Synthetic Demo Portfolio idle | `top`, 6 one-second samples after semantic navigation | 0.0% CPU and 74 MiB for every sample |

Single-iteration workloads report p95 as `NOT AVAILABLE`. The small ranges above reflect two parallel XCTest worker copies emitted by the same final focused run; both are retained. The original `< 10 seconds` replay guard passed. No post-hoc hard limit was invented.

## 12. Stage 8A current verification

| Verification | Result |
|---|---|
| Stage 8A focused Unit/Integration | `PASS` — 17/17 definitions |
| Stage 6/7 focused regression | `PASS` — 107 definitions / 116 executions |
| Full `AureusTests` | `PASS` — 227 definitions / 260 executions |
| Final Debug arm64 clean build | `PASS` |
| Final build-for-testing | `PASS` |
| Portfolio focused UI, first business execution | `FAIL` — 0/1; create verification could not find the new Portfolio by static text |
| Portfolio focused UI, final bounded execution | `FAIL` — 0/1; `portfolio.summary.name` existed but its AX label did not contain the created name |
| Existing focused UI, initial run | `PARTIAL` — 3/5; Ledger Dynamic and Markets failed |
| Existing focused UI, bounded retry | `FAIL` — 0/2; Ledger Picker selection and Markets synthetic Search result failed |
| Full `AureusUITests` | `NOT RUN` — gated on Portfolio focused UI final PASS |
| Real Provider requests | `NOT RUN` |

Both Portfolio UI executions reached the Portfolio page, CNY NAV, synthetic holding, NAV chart/table, heatmap, Benchmark control, and both disclosure nodes before failing. Because the required CRUD/reorder/delete/Production-isolation tail did not execute to completion and the two-business-run budget is exhausted, Stage 8A remains `PARTIAL`. Synthetic evidence does not expand live Provider capability. Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 9 remains `NO-GO`.

## 13. Stage 8AA native UI gate-closure evidence

Prompt 8AA preserved the accepted Portfolio domain, persistence, FIFO, FX, NAV, Benchmark, and performance implementation. It made only bounded native UI/Accessibility observability changes and corresponding UI-test lifecycle updates. The Portfolio summary now declares an explicit field label and value contract; the Ledger container Picker is re-queried around native popup transitions; Markets exposes a finite independent Search-status Accessibility label before the synthetic result is queried.

| Verification | Result |
|---|---|
| Stage 8/8A focused Unit/Integration | `PASS` — 17 definitions / 17 executions |
| Stage 6/7 focused regression | `PASS` — 107 definitions / 116 parameterized executions |
| Full `AureusTests` | `PASS` — 227 definitions / 260 parameterized executions |
| Final Debug arm64 clean build | `PASS` |
| Final build-for-testing | `PASS` |
| Portfolio focused UI, first execution | `FAIL` — 0/1; `portfolio.summary.name` did not expose the asserted created-name value |
| Portfolio focused UI, one authorized final execution | `FAIL` — 0/1; the same bounded semantic-value assertion remained unresolved |
| Ledger Dynamic focused UI, first execution | `FAIL` — 0/1; native Picker flow completed, then a Ledger summary value was not exposed through AX |
| Ledger Dynamic focused UI, one authorized final execution | `FAIL` — 0/1; `ledger.summary.ordinaryInflow` still did not expose the asserted value |
| Markets focused UI, first execution | `FAIL` — 0/1; Search binding and submit completed, but the independent status node exposed no finite value |
| Markets focused UI, one authorized final execution | `PASS` — 1/1; Ready status, result, chart/accessibility, clear, and Production isolation completed |
| Existing focused regression combination | `NOT RUN` — Portfolio and Ledger focused gates did not pass |
| Full `AureusUITests` | `NOT RUN` — focused UI gate did not pass |
| Real Provider requests | `NOT RUN` |

The two failed focused gates cannot be offset by Unit, build, or Markets evidence. Stage 8AA therefore remains `PARTIAL` and awaits independent Reviewer action. No live capability is expanded; Twelve Data persistent writes remain `Disabled`, retention remains `BLOCKED`, and Stage 9 remains `NO-GO`.

## 14. Stage 8AB static-summary Accessibility evidence

Prompt 8AB made only the authorized native summary and UI-lifecycle changes. `portfolio.summary.name` now exposes a self-contained `Portfolio name: <selected name>` label with ignored children. Ledger summary identifiers now expose complete labels that bind each existing title to the existing formatted Money, while Transfers states the count and cash-flow exclusion. Neither change modifies Portfolio/Ledger calculation, persistence, Picker, Provider, Session Store, Migration, or Market behavior.

The Portfolio UI helper now uses finite deadlines and re-queries `XCUIApplication` on every poll. It verifies the stable summary label rather than AXValue, observes two stable Portfolio row identifiers after creation, re-queries Move Up before and after reordering, and navigates away and back before checking the persisted selection and order. The initial Stage 8AB execution failed only because an additional test assertion expected an unsupported Portfolio row label after the row count had already reached two. The one authorized lifecycle repair removed that non-contract label dependency and retained stable row identifiers. The final authorized execution passed creation, selected-summary, reorder, and navigation/reload checks, then failed because the row count did not return to one within five seconds after confirmed deletion. The two-business-execution budget was exhausted, so no further repair or UI execution occurred.

| Verification | Result |
|---|---|
| Stage 8/8A focused Unit, first sandboxed command | `NOT RUN` as business evidence — exit 65; runner communication failed before test entry |
| Stage 8/8A focused Unit, signed host | `FAIL` — 11/17 passed; six filesystem-dependent cases received the retained `/private/tmp/AureusTests` sandbox denial |
| Stage 8/8A focused Unit, stable unsigned host | `PASS` — 17 definitions / 17 executions |
| Stage 6/7 focused regression, stable unsigned host | `PASS` — 107 definitions / 116 parameterized executions |
| Full `AureusTests`, stable unsigned host | `PASS` — 227 definitions / 260 parameterized executions |
| Final Debug arm64 clean build | `PASS` |
| Final build-for-testing, first attempt | `FAIL` — exit 74; cached GRDB submodule transfer ended early |
| Final build-for-testing, fixed-cache bounded retry | `PASS` — GRDB 7.11.1 reused without changing `Package.resolved` |
| Portfolio focused UI, first execution | `FAIL` — 0/1; unsupported row-label assertion after row count reached two |
| Portfolio focused UI, one authorized final execution | `FAIL` — 0/1; deletion confirmation completed, but row count did not become one within the finite deadline |
| Ledger focused UI | `NOT RUN` — Portfolio focused gate did not pass |
| Markets focused regression | `NOT RUN` — Portfolio focused gate did not pass; Markets source/test remained frozen |
| Existing focused regression combination | `NOT RUN` — focused UI gate did not pass |
| Full `AureusUITests` | `NOT RUN` — focused UI gate did not pass |
| Real Provider requests | `NOT RUN` |

Unit and build evidence cannot offset the exhausted Portfolio UI gate. Stage 8AB therefore remains `PARTIAL` and awaits independent Reviewer action. No live capability is expanded; Twelve Data persistent writes remain `Disabled`, retention remains `BLOCKED`, and Stage 9 remains `NO-GO`.
