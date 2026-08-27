# Stage 9 Portfolio Analytics Acceptance

**Status:** Stage 9 Analytics Implementation Candidate — Awaiting Reviewer Gate  
**Implementation date:** 2026-08-27  
**Authority:** This document records implementation and bounded local/synthetic evidence. It does not decide the Stage 9 Gate, authorize Stage 10, or establish any Provider capability.

## 1. Gate and scope boundary

The independent Reviewer recorded Stage 8 as `PASS` and authorized Stage 9 implementation. Stage 9 replaces the Analytics placeholder with a native Portfolio Analytics terminal. It does not change Stage 8 Portfolio authority, migrations, Market Provider behavior, Market Session Store, Market Cache, Credential lifecycle, Wealth/Ledger semantics, or Twelve Data persistence policy.

Analytics is local and deterministic. It reads only:

- one existing Portfolio definition;
- that Portfolio's stored Opening Lot, Buy, Sell, and Manual Split activities;
- that Portfolio's complete NAV snapshot headers and items;
- a non-persisted user risk-free-rate assumption for the current calculation.

It does not read Market Session Store values, Market Cache values, Provider payloads, quotes, OHLCV, Benchmark session series, credentials, Keychain metadata, or external files. Opening the page and changing inputs do not calculate or request data; `Calculate` is the only computation trigger. Provider requests were `NOT RUN`.

## 2. Units, signs, dates, and missing data

| Contract | Stage 9 rule |
|---|---|
| Base unit | CNY Money at the existing minor-unit boundary |
| Working arithmetic | checked `Decimal`, working scale 16 |
| Portfolio contribution sign | Opening Lot and Buy are positive |
| Portfolio withdrawal sign | Sell is negative |
| Manual Split | zero capital flow |
| XIRR investor sign | initial NAV/contributions negative; withdrawals/final NAV positive |
| Activity range | `(start, end]` |
| Calendar | Gregorian UTC civil dates |
| Annualization | actual integer civil-day offsets; 365-day basis |
| Snapshot eligibility | complete snapshots only |
| Missing dates | missing; never forward-filled, backfilled, interpolated, or replaced by zero |
| Duplicate complete date | rejected as typed invalid input |
| Risk series | adjacent one-day observations only |

Stored CNY conversion and acquisition/sale FX provenance are reused as recorded. Stage 9 never recomputes historical FX and never treats USD as CNY.

## 3. Cash-flow-adjusted total return

For starting NAV `V0`, ending NAV `V1`, contributions `C`, and withdrawals `W`:

```text
cash-flow-adjusted P&L = V1 - V0 - (C - W)
cash-flow-adjusted total return = cash-flow-adjusted P&L / V0
```

The result is explicitly labeled cash-flow-adjusted total return. It is not presented as TWR, XIRR, CAGR, tax return, or investment advice. Starting NAV must be positive and all Money/Decimal operations are checked.

## 4. Time-weighted return and base-100 index

For adjacent complete valuation boundaries and the Portfolio cash flow recorded on the ending boundary:

```text
subperiod factor = (Vt - CFt) / Vprevious
subperiod return = subperiod factor - 1
TWR = product(all subperiod factors) - 1
base-100 index at t = 100 * product(factors through t)
```

Every nonzero flow date must have a complete valuation boundary. A missing flow-date valuation returns `missingValuationBoundary`; it is never hidden through interpolation. Subperiods retain start/end dates, starting/ending NAV, the exact Portfolio-perspective cash flow, and return provenance.

This follows the valuation-boundary and geometrically linked subperiod approach described in the [GIPS calculation methodology](https://www.gipsstandards.org/wp-content/uploads/2021/03/calculation_methodology_gs_2011.pdf).

## 5. CAGR

CAGR is derived from the already chained TWR factor rather than from raw NAV endpoints:

```text
daily factor = positiveNthRoot(1 + TWR, actual civil-day span)
CAGR = dailyFactor^365 - 1
```

The day span is an integer Gregorian UTC civil-day count. Nonpositive factors, invalid roots, invalid exponents, precision loss, and overflow are finite typed results rather than traps or fabricated zeros.

## 6. XIRR

XIRR uses investor-perspective cash-flow signs and exact integer civil-day offsets. Same-date flows are aggregated. The solver:

1. requires at least one positive and one negative nonzero flow;
2. accepts only the conventional topology of an initial negative flow, a final positive flow, and one sign transition;
3. samples a fixed, deterministic daily-rate bracket set;
4. rejects no-root and multiple-root cases explicitly;
5. runs at most 256 bisection iterations;
6. requires daily-rate width at most `1e-12` and NPV magnitude at most CNY `0.01` unless NPV is exactly zero;
7. annualizes the solved daily rate as `(1 + dailyRate)^365 - 1`.

The implementation uses checked Decimal arithmetic with an explicit banker-rounded scale-16 boundary for XIRR intermediate operations. It does not use `Double`, Newton iteration, an unbounded search, locale time, or wall-clock time. Nonconventional cash flows are reported as `nonConventionalCashFlows` instead of returning an arbitrary root. The day-based cash-flow convention is aligned with the documented [Microsoft XIRR contract](https://support.microsoft.com/en-us/office/xirr-function-de1242ec-6477-445b-b11b-a303ad9adc9d); the local solver remains independently implemented and more restrictive about topology.

## 7. Volatility and Sharpe ratio

Risk metrics require consecutive daily snapshot boundaries. Sparse observations return `irregularDailySeries`.

```text
sample variance = sum((ri - mean)^2) / (n - 1)
annualized volatility = sqrt(sample variance) * sqrt(365)
daily risk-free = positiveNthRoot(1 + annual risk-free, 365) - 1
Sharpe = ((mean daily return - daily risk-free) / daily sample deviation) * sqrt(365)
```

The denominator uses the sample `n - 1` convention documented by the [NIST Engineering Statistics Handbook](https://www.itl.nist.gov/div898/handbook/eda/section3/eda356.htm). The risk-free rate is an explicit, session-only user assumption, defaults to 0%, is never persisted, and is never fetched from a Provider. Zero volatility returns `zeroVolatility`; it never produces infinity. The ratio is presented as descriptive local analytics, consistent with the general reward-to-variability framing in the [CFA Institute Sharpe ratio discussion](https://rpc.cfainstitute.org/sites/default/files/-/media/documents/code/gips/sharpe-ratio-and-the-information-ratio.pdf), not as investment advice.

## 8. Maximum drawdown

Drawdown is computed from the Stage 9 TWR wealth index:

```text
signed drawdown = current index / running peak - 1
maximum drawdown magnitude = maximum absolute negative drawdown
```

The report retains the earliest applicable peak, trough, and the first later observation that recovers the peak, if any. No recovery is fabricated. It describes only observed snapshot boundaries and never claims intraperiod drawdown. This matches the peak-to-trough concept described in the [CFA Institute drawdown discussion](https://blogs.cfainstitute.org/blog/2013/02/12/sculpting-investment-portfolios-maximum-drawdown-and-optimal-portfolio-strategy/).

## 9. Observed monthly and annual TWR

Subperiod returns are grouped by the end observation's calendar month/year and geometrically chained. Each row discloses its first and last covered dates, subperiod count, and either `completeCalendarPeriod` or `partialObservedPeriod`. Missing months/years remain absent; sparse periods are not filled with zero and are not presented as complete calendar returns.

## 10. Typed results and finite failures

Metric values use `available(value)` or `unavailable(error)`. The bounded taxonomy includes absent/insufficient snapshots, duplicate dates, invalid order/NAV, missing valuation boundary, irregular daily series, insufficient risk observations, zero volatility, invalid risk-free rate, missing positive/negative XIRR signs, nonconventional cash flows, no/multiple XIRR root, non-convergence, overflow, underflow, precision loss, division by zero, invalid scale/root/exponent, cancellation, stale generation, and unexpected local failure.

The UI maps these cases to finite sanitized explanations. It does not use raw Provider text, URLs, credentials, payloads, or arbitrary error descriptions. `Unavailable` is never rendered as zero.

## 11. Architecture and concurrency

- `PortfolioAnalyticsCalculator` is a pure Domain boundary.
- `AnalyticsFeatureModel` is `@MainActor` and owns presentation state only.
- Calculation runs away from the Main Actor and supports cancellation.
- Portfolio/range/risk-free changes advance a generation and clear the previous report.
- A stale or cancelled generation cannot overwrite current UI state.
- App, Synthetic Demo, and tests use dependency-injected stores; no singleton, Event Bus, plugin system, or second persistence framework was added.

## 12. Native UI and accessibility

The native SwiftUI/Swift Charts terminal provides Portfolio selection, ranges `1M/3M/YTD/1Y/3Y/5Y/MAX`, session-only annual risk-free input, explicit Calculate/Cancel, and seven required metric cards:

- cash-flow-adjusted total return;
- TWR;
- CAGR;
- XIRR;
- annualized volatility;
- Sharpe ratio;
- maximum drawdown.

It also provides a base-100 TWR chart, drawdown chart, observed monthly matrix, annual table, capital-flow table, TWR subperiod table, XIRR investor-flow table, performance/drawdown native accessible tables, coverage disclosure, exact starting/ending NAV, and stable Accessibility identifiers. Signed text accompanies color. Charts have self-contained native summaries and are never the only information source.

## 13. Persistence and privacy

Analytics reports, metrics, chart points, risk-free assumptions, calculated cash flows, and presentation tables are not written to SQLite, UserDefaults, files, logs, snapshots, backups, exports, WKWebView, or Market Cache. The existing Portfolio activities and complete NAV snapshots remain the only permanent inputs and are not mutated by calculation.

| Boundary | Result |
|---|---|
| New migration | None |
| Portfolio/Wealth/Ledger/Snapshot mutation | None |
| Market Session Store access | None |
| Market Cache read/write | None |
| Provider request | `NOT RUN` |
| Twelve Data persistent writes | `Disabled` |
| Retention | `BLOCKED` |
| Stage 10 | `NO-GO` |
| AI/LLM/Python/telemetry | Not added |

## 14. Formula reference register

References were accessed read-only on 2026-08-27. They support the named contract boundary but are not implementation or test evidence.

| Title | Publisher | Direct URL | Aureus contract supported |
|---|---|---|---|
| Calculation Methodology | Global Investment Performance Standards (GIPS) | [PDF](https://www.gipsstandards.org/wp-content/uploads/2021/03/calculation_methodology_gs_2011.pdf) | valuation-boundary subperiod returns and geometric TWR linking |
| GIPS Standards Handbook for Firms | Global Investment Performance Standards (GIPS) | [Handbook](https://www.gipsstandards.org/standards/gips-standards-for-firms/gips-standards-handbook-for-firms/) | distinction between time-weighted and money-weighted/IRR presentation |
| XIRR function | Microsoft Support | [Official function documentation](https://support.microsoft.com/en-us/office/xirr-function-de1242ec-6477-445b-b11b-a303ad9adc9d) | dated cash flows and a 365-day annual basis |
| Measures of Scale: Standard Deviation | NIST/SEMATECH | [Engineering Statistics Handbook](https://www.itl.nist.gov/div898/handbook/eda/section3/eda356.htm) | sample standard deviation with `n - 1` denominator |
| The Sharpe Ratio and the Information Ratio | CFA Institute | [Research PDF](https://rpc.cfainstitute.org/sites/default/files/-/media/documents/code/gips/sharpe-ratio-and-the-information-ratio.pdf) | reward-to-variability ratio framing; Aureus separately freezes daily observations and `sqrt(365)` annualization |
| Sculpting Investment Portfolios: Maximum Drawdown and Optimal Portfolio Strategy | CFA Institute Enterprising Investor | [Article](https://blogs.cfainstitute.org/blog/2013/02/12/sculpting-investment-portfolios-maximum-drawdown-and-optimal-portfolio-strategy/) | observed peak-to-trough maximum drawdown concept |

The exact formulas, units, CNY signs, UTC civil-date handling, 365-day basis, checked scale-16 rounding, missing-data rules, and edge cases used by each calculation boundary are frozen in Sections 2–9 of this document and in deterministic golden/invariant tests. No authenticated Provider documentation was accessed.

## 15. Synthetic and Production separation

Synthetic Demo seeds two clearly labeled fictional Portfolios: one daily regular series with flow boundaries, a drawdown and an excluded incomplete snapshot; and one sparse series with nonconventional XIRR signs and USD provenance. Production starts from local permanent records and never displays synthetic success. Synthetic tests do not establish Provider capability, plan, freshness, market access, or investment outcome.

## 16. Unit and integration evidence

The final current-source evidence is:

| Verification | Result bundle | Result |
|---|---|---|
| Stage 9 focused Domain + Feature | `/private/tmp/Aureus-Stage9-4PMOaO/Stage9Focused-FinalCurrent.xcresult` | `PASS` — 20 definitions / 20 executions, 0 failed, 0 skipped |
| Stage 6–8 focused regression | `/private/tmp/Aureus-Stage9-4PMOaO/Stage68FocusedRegression-FinalCurrent.xcresult` | `PASS` — 204 definitions / 237 parameterized executions, 0 failed, 0 skipped |
| Full `AureusTests` | `/private/tmp/Aureus-Stage9-4PMOaO/FullUnit-FinalCurrent.xcresult` | `PASS` — 254 definitions / 287 parameterized executions, 0 failed, 0 skipped |
| Final Debug arm64 clean build | `/private/tmp/Aureus-Stage9-4PMOaO/FinalCleanDebugBuild.xcresult` | `PASS` — exit 0, clean/build succeeded |
| Final signed build-for-testing | `/private/tmp/Aureus-Stage9-4PMOaO/FinalBuildForTesting.xcresult` | `PASS` — exit 0, test build succeeded |

Earlier compile, focused-correctness, and performance-fixture failures are retained in the Execution Report; they are not represented as final passes.

## 17. UI evidence and bounded budget

The Stage 9 focused selector was invoked once and then retried once under the Prompt's single global infrastructure-retry allowance. Both executions failed before the business test method entered because the UI runner timed out while enabling automation mode. Each xcresult contains `Info.plist`, parses successfully, and records a runner-level failure; there were zero Stage 9 business executions. Later bounded performance diagnosis required Domain arithmetic and synthetic performance-fixture corrections, after which the Unit suites and signed build-for-testing were rerun. The exhausted UI budget was not reset, so the final current source has no business UI execution and remains `NOT VERIFIED`.

| Verification | Result bundle | Result |
|---|---|---|
| Stage 9 focused UI, first | `/private/tmp/Aureus-Stage9-4PMOaO/Stage9FocusedUI.xcresult` | `NOT VERIFIED` — xcodebuild exit 65; UI runner bootstrap timeout; 0 business tests |
| Stage 9 focused UI, infrastructure retry | `/private/tmp/Aureus-Stage9-4PMOaO/Stage9FocusedUI-InfraRetry.xcresult` | `NOT VERIFIED` — xcodebuild exit 65; same pre-entry timeout; 0 business tests |
| Existing focused UI regression | — | `NOT RUN` — Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — focused UI gate did not pass |

No business assertion failure was observed, but absence of execution is not a pass. The Stage 9 UI Gate remains unverified.

## 18. Performance evidence

All workloads used full-size deterministic synthetic inputs in an optimized unsigned Release test product. The final performance result bundle passed 3/3 tests.

| Workload | Method | Observed result |
|---|---|---|
| 10,000 complete observations + 10,000 capital flows | 1 warm-up + 5 full calculations | 4,759–4,834 ms; p50 4,770 ms; p95 4,834 ms; every measured run below 10 seconds |
| Independent sibling worker for the same workload | 1 warm-up + 5 full calculations | 4,769–4,839 ms; p50 4,780 ms; p95 4,839 ms |
| 10 Portfolios / 100 selection and range reloads | complete Store load plus generation checks | 1,190 ms primary; 1,203 ms sibling; final selection correct; Provider requests 0 |
| 5,000 observations presentation preparation | chart, accessible index, drawdown, monthly and annual rows | 210 ms primary; 283 ms sibling; all 5,000 points retained |
| Exact signed Synthetic Analytics idle | semantic navigation, 6 samples over 5 seconds | CPU 0.0% for all samples; RSS 139,744 KiB for all samples |

The performance xcresult is `/private/tmp/Aureus-Stage9-4PMOaO/Stage9Performance-FixtureFix.xcresult`; it contains `Info.plist`, parses successfully, and reports 3 passed, 0 failed, 0 skipped. Earlier Release-host and fixture failures are retained in the Execution Report. No smaller data set or truncated presentation was substituted.

## 19. Exact signed candidate evidence

The final signed build-for-testing produced:

| Artifact | Evidence |
|---|---|
| App | `/private/tmp/Aureus-Stage9-4PMOaO/FinalUIBuildDerivedData/Build/Products/Debug/Aureus.app` |
| App executable SHA-256 | `6bc20473d501ab20cf04aae97cd1b140a72980700eb5a8b752d76b2bff2e22a2` |
| App identifier / architecture | `com.aureus.wealthterminal` / arm64 |
| App signing | local ad-hoc (`Signature=adhoc`, no TeamIdentifier) |
| UI runner executable SHA-256 | `0ab8673ad992c809b1c9b65937169d59930e07e481d0d1afa2a32be02d48f9c3` |
| xctestrun SHA-256 | `f2ca05c2dab1556aa70d7da44a9ea41d73004e3b048218accda30a973cfffacd` |

## 20. Limitations and gate boundary

- Stage 9 focused UI is `NOT VERIFIED` because the macOS XCTest runner never entered the business test in either bounded infrastructure attempt.
- Existing focused UI `7/7` and full UI `13/13` are `NOT RUN` under the ordered Gate.
- Risk statistics are intentionally unavailable for sparse/non-daily observations.
- XIRR intentionally refuses nonconventional sign topology rather than selecting one of potentially multiple roots.
- Monthly/annual rows are observed-period TWR and disclose partial coverage; they are not fabricated complete-period performance.
- Analytics does not include taxes, benchmark attribution, Alpha/Beta, forecasting, advice, or Stage 10 functionality.

This is **Stage 9 Analytics Implementation Candidate — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.
