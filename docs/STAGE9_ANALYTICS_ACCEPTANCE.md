# Stage 9 Portfolio Analytics Acceptance

**Status:** Stage 9AAAAA PARTIAL — Awaiting Reviewer Gate  
**Implementation date:** 2026-08-28  
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

## 21. Stage 9A current-source UI evidence closure

Prompt 9A first verified every listed current-source hash before making any change. The two Prompt 9 focused UI result bundles remain historical runner-level automation bootstrap timeouts: both contain `Info.plist`, both parse, neither entered the business test, and neither is rewritten as a business result.

The first Stage 9A current-source focused invocation entered the business method and completed Synthetic mode, explicit calculation, all seven metric cards, and both native charts. It then failed at `AureusUITests.swift:302` because `analytics.performance.table` was not queryable as an independent native Accessibility surface. This was a business assertion failure, not a bootstrap timeout.

The one authorized minimal AX-only repair added explicit `.accessibilityElement(children: .contain)` boundaries to the seven existing native Analytics table containers. It did not change Analytics formulas, Domain arithmetic, Feature calculation scheduling, Portfolio data, persistence, Provider routing, Session Store behavior, or UI test assertions. Because Production source changed, the required conditional verification was executed against the modified candidate:

| Verification | Result bundle | Result |
|---|---|---|
| Stage 9 focused Unit | `/private/tmp/Aureus-Stage9A-DrYR4O/Stage9FocusedUnit.xcresult` | `PASS` — exit 0; 20 definitions / 20 executions; 0 failed; 0 skipped |
| Stage 6–8 focused regression | `/private/tmp/Aureus-Stage9A-DrYR4O/Stage68FocusedRegression.xcresult` | `PASS` — exit 0; 204 definitions / 237 executions; 0 failed; 0 skipped |
| Full `AureusTests` | `/private/tmp/Aureus-Stage9A-DrYR4O/FullUnit.xcresult` | `PASS` — exit 0; 254 definitions / 287 executions; 0 failed; 0 skipped |
| Clean Debug arm64 Build | `/private/tmp/Aureus-Stage9A-DrYR4O/CleanDebugBuild.xcresult` | `PASS` — exit 0; build succeeded |
| Final signed build-for-testing | `/private/tmp/Aureus-Stage9A-DrYR4O/FinalBuildForTesting.xcresult` | `PASS` — exit 0; test build succeeded |
| Stage 9A focused UI, first business execution | `/private/tmp/Aureus-Stage9A-DrYR4O/Stage9FocusedUI.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; missing `analytics.performance.table` |
| Stage 9A focused UI, final business retry | `/private/tmp/Aureus-Stage9A-DrYR4O/Stage9FocusedUI-Final.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; same finite AX failure |
| Existing focused UI regression | — | `NOT RUN` — final Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — Existing focused regression was not authorized to start |

Both Stage 9A focused result bundles contain `Info.plist`; summary and tests parsing succeeded in the standard Xcode permission environment. The single business-repair and final-business-retry budget is exhausted. The current blocker is specifically the independent native Performance table AX surface; no evidence establishes a calculation, persistence, or Provider failure. Provider requests remained `NOT RUN`, Twelve Data persistent writes remain `Disabled`, retention remains `BLOCKED`, and Stage 10 remains `NO-GO`.

This is **Stage 9A PARTIAL — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.

## 22. Stage 9AA native accessible-table contract repair

Prompt 9AA preserved the two Prompt 9A business failures as historical evidence. Both Stage 9A result bundles remain complete and parseable, both contain one business execution, and both failed at `analytics.performance.table`; neither result is rewritten as a current Prompt 9AA outcome.

The seven Analytics data regions now expose their identifiers on visible, standalone summary `Text` nodes rather than on parent `.contain` containers. Each summary ignores children, has a unique identifier and a self-contained label with the actual row count, and leaves the real data rows independently accessible. The strengthened Stage 9 UI contract checks table names, `rows`, dynamic counts, representative row identifiers, and self-contained row content without using AXValue, fixed coordinates, row indexes, invisible overlays, or combined whole-table strings. Analytics formulas, Domain arithmetic, FeatureModel scheduling, Portfolio data, persistence, Provider routing, and Stage 9 performance implementation were not changed.

The required current-candidate verification produced the following evidence:

| Verification | Result bundle | Result |
|---|---|---|
| Stage 9 focused Unit, final | `/private/tmp/Aureus-Stage9AA-hnEvhC/Stage9FocusedUnit-Final.xcresult` | `PASS` — exit 0; 20 definitions / 20 executions; 0 failed; 0 skipped |
| Stage 6–8 focused regression, final | `/private/tmp/Aureus-Stage9AA-hnEvhC/Stage68FocusedRegression-Final.xcresult` | `PASS` — exit 0; 204 definitions / 237 executions; 0 failed; 0 skipped |
| Full `AureusTests`, first final attempt | `/private/tmp/Aureus-Stage9AA-hnEvhC/FullUnit-Final.xcresult` | `PARTIAL` — worker/coverage finalization hung after tests; bounded interruption; exit 143; incomplete result bundle |
| Full `AureusTests`, equivalent infrastructure retry | `/private/tmp/Aureus-Stage9AA-hnEvhC/FullUnit-Final-Retry.xcresult` | `PASS` — exit 0; 254 definitions / 287 executions; 0 failed; 0 skipped |
| Clean Debug arm64 Build, final | `/private/tmp/Aureus-Stage9AA-hnEvhC/CleanDebugBuild-Final.xcresult` | `PASS` — exit 0; build succeeded; errors 0 |
| Signed build-for-testing, final | `/private/tmp/Aureus-Stage9AA-hnEvhC/BuildForTesting-Final.xcresult` | `PASS` — exit 0; test build succeeded; errors 0 |
| Stage 9AA focused UI, initial business execution | `/private/tmp/Aureus-Stage9AA-hnEvhC/Stage9FocusedUI.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; existing chart-summary element was outside the visible scroll region |
| Stage 9AA focused UI, final business retry | `/private/tmp/Aureus-Stage9AA-hnEvhC/Stage9FocusedUI-Final.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; existing `analytics.coverage` element was outside the visible scroll region |
| Existing focused UI regression | — | `NOT RUN` — final Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — ordered focused UI prerequisite did not pass |

All final successful result bundles contain `Info.plist` and their summary/tests reports parse successfully. The first full-Unit final attempt is retained as an infrastructure interruption rather than hidden; the equivalent unsigned-host retry used the same source and assertions with code coverage disabled and passed completely. Both Stage 9AA UI invocations entered the business method, so the authorized two-business-execution budget is exhausted. The final focused failure occurred before the new table assertions; therefore the source-level table contract and Unit/build evidence are present, but the complete focused Synthetic/typed-unavailable/Production-isolation flow is not UI-verified in this round.

Performance is `NOT RUN — accepted Stage 9 performance implementation unchanged`. Provider requests remain `NOT RUN`; Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 10 remains `NO-GO`.

This is **Stage 9AA PARTIAL — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.

## 23. Stage 9AAA viewport-aware UI lifecycle repair

Prompt 9AAA preserves both Stage 9AA focused business failures as historical evidence. The initial Stage 9AA execution failed at the offscreen `analytics.chart.performance.summary`; its one authorized retry failed at `analytics.coverage` before reaching the seven table-summary, representative-row, typed-unavailable, or Production-isolation assertions. Neither historical result is rewritten as a Stage 9AAA result.

The Stage 9 UI test now uses one bounded, bidirectional viewport helper. Every iteration performs a fresh identifier query; `towardTop` semantically calls `swipeDown()` and `towardBottom` calls `swipeUp()` on the uniquely identified `analytics.detail.scroll`. The helper has finite timeout and scroll-count bounds, never retains an element across a scroll or state transition, and does not use coordinates, row indexes, a transient menu tree, or an infinite loop. The ordered test contract verifies the initial top state, returns to coverage after Calculate, proceeds through metrics and the performance/drawdown/observed/detail tables from top to bottom, returns to the top after selecting the sparse Portfolio, and launches a separate Production process for isolation checks.

The initial Stage 9AAA business execution completed the initial Synthetic state and Calculate. Sanitized activity titles showed that `analytics.coverage` was present as one unique node on every query; the failure was the test's literal `incomplete excluded` predicate, while the frozen Production AX label is the more specific `incomplete snapshots excluded`. The one authorized test-only repair changed that predicate without modifying Production or weakening the identifier, uniqueness, coverage-content, or state assertions.

The fresh final UI product built successfully, but the only authorized final focused business retry failed at `analytics.chart.performance`. It completed coverage and all top metric assertions, then the finite 8-second helper bound permitted three semantic `swipeUp()` operations before timing out. This is a current business assertion failure in the UI-test viewport lifecycle, not evidence of an Analytics formula, Domain, persistence, Provider, or Production AX-node failure. The focused business-retry budget is exhausted, so the ordered `7/7` regression and `13/13` full UI suite were not run.

| Verification | Result bundle | Result |
|---|---|---|
| Initial fresh build-for-testing | `/private/tmp/Aureus-Stage9AAA-VYK9KL/BuildForTesting.xcresult` | `PASS` by complete build summary — status succeeded, errors 0; original shell exit became `NOT AVAILABLE` after the asynchronous command handle was lost |
| Stage 9AAA focused UI, initial business execution | `/private/tmp/Aureus-Stage9AAA-VYK9KL/Stage9FocusedUI.xcresult` | `FAIL` — shell exit `NOT AVAILABLE`; 1 executed / 0 passed / 1 failed / 0 skipped; unique coverage node did not satisfy the overly literal label predicate |
| Final fresh signed build-for-testing | `/private/tmp/Aureus-Stage9AAA-VYK9KL/FinalBuildForTesting.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; errors 0 |
| Stage 9AAA focused UI, final business retry | `/private/tmp/Aureus-Stage9AAA-VYK9KL/Stage9FocusedUI-Final.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; finite viewport timeout before `analytics.chart.performance` |
| Existing focused UI regression | — | `NOT RUN` — final Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — Existing focused regression prerequisite did not pass |

All four listed result bundles contain `Info.plist` and parse successfully. The initial parser attempt against the still-running focused bundle returned exit 64 because `Info.plist` had not yet been finalized; the same bundle parsed with exit 0 after the original process completed, and no test was rerun for parsing.

Because only `AureusUITests.swift` changed, Stage 9 focused Unit `20/20`, Stage 6–8 regression `204` definitions / `237` executions, full Unit `254` definitions / `287` executions, Stage 9 performance `3/3`, and Clean Debug arm64 Build are `NOT RUN — INHERITED AFTER EXACT Production/Unit SOURCE-HASH VERIFICATION`. Analytics Production, Domain, FeatureModel, persistence, migrations, Provider routing, entitlements, Package, project, and chart assets remained byte-identical.

Provider requests remain `NOT RUN`; Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 10 remains `NO-GO`.

This is **Stage 9AAA PARTIAL — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.

## 24. Stage 9AAAA finite-scroll-budget closure

Prompt 9AAAA preserves the two Stage 9AAA business failures as historical evidence. The initial Stage 9AAA execution failed at the coverage-label predicate; its final retry corrected that predicate, completed the top coverage and metric assertions, and then failed at `analytics.chart.performance` after the former 8-second global deadline allowed only three `swipeUp()` operations. Neither historical failure is rewritten as a current Prompt 9AAAA result.

The Stage 9 UI test now makes the finite scroll count its executable boundary. It first performs a fresh identifier query, then permits at most 12 element-scoped scroll operations, re-queries both `analytics.detail.scroll` and the target before and after each operation, and derives the finite wall-clock allowance as `maximumScrollCount × 4 + 5` seconds (53 seconds for 12 operations). Success and exhaustion activities report only the identifier, direction, actual count, and maximum count; they do not export an AX hierarchy. The frozen Production coverage wording remains `incomplete snapshots excluded`.

The first current business execution completed Calculate, coverage, the Portfolio report title, all seven metric cards, the accessible-data toggle, and the risk-free disclosure. It then performed all 12 authorized semantic `swipeUp()` operations and failed at `analytics.chart.performance`. This proves the old 8-second truncation was removed but does not establish the downstream chart or table runtime contracts.

The single authorized direct UI-test lifecycle repair replaced the swipe call with element-scoped native relative scrolling on the freshly queried `analytics.detail.scroll`; no Production Swift, calculation, fixture, Accessibility identifier, label, or business assertion changed. A fresh final signed build-for-testing passed. The only authorized final focused business retry again completed all top assertions and 12 bounded relative-scroll operations, then failed at the same `analytics.chart.performance` identifier. The two-business-execution budget is exhausted, so no third focused run, Existing focused regression, or full UI run occurred.

| Verification | Result bundle | Result |
|---|---|---|
| Initial fresh signed build-for-testing | `/private/tmp/Aureus-Stage9AAAA-dbQmEQ/BuildForTesting.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; `Info.plist` present; build summary parse exit 0; errors 0 |
| Stage 9AAAA focused UI, initial business execution | `/private/tmp/Aureus-Stage9AAAA-dbQmEQ/Stage9FocusedUI.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; 12/12 semantic swipes completed; failure at `analytics.chart.performance` |
| Final fresh signed build-for-testing | `/private/tmp/Aureus-Stage9AAAA-dbQmEQ/BuildForTesting-Final.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; `Info.plist` present; build summary parse exit 0; errors 0 |
| Stage 9AAAA focused UI, final business retry | `/private/tmp/Aureus-Stage9AAAA-dbQmEQ/Stage9FocusedUI-Final.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; 12/12 native relative-scroll operations completed; same finite identifier failure |
| Existing focused UI regression | — | `NOT RUN` — final Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — Existing focused regression prerequisite did not pass |

Both focused bundles contain `Info.plist`. Their first sandboxed summary/tests parser attempts returned exit 64 because the TestReport cache was not writable; read-only parsing of the same bundles in the standard Xcode permission environment returned exit 0, without rerunning either test. Both focused invocations entered the business method, so neither is an infrastructure retry. The second is the one authorized business retry.

Because only `AureusUITests.swift` changed, Stage 9 focused Unit `20/20`, Stage 6–8 regression `204` definitions / `237` executions, full Unit `254` definitions / `287` executions, Stage 9 performance `3/3`, and Clean Debug arm64 Build are `NOT RUN — INHERITED AFTER EXACT Production/Unit SOURCE-HASH VERIFICATION`. Analytics Production, Domain, FeatureModel, Unit tests, persistence, migrations, Provider routing, entitlements, Package, project, and chart assets remained byte-identical.

The performance and remaining native table assertions, sparse-Portfolio typed-unavailable flow, and Production isolation were not reached in either current focused execution and remain `NOT VERIFIED`. Provider requests remain `NOT RUN`; Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 10 remains `NO-GO`.

This is **Stage 9AAAA PARTIAL — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.

## 25. Stage 9AAAAA viewport-direction calibration

Prompt 9AAAAA preserves both Prompt 9AAAA focused failures as historical evidence. Those executions established that the finite count could complete but recorded only submitted scroll events, not viewport movement. Neither historical failure is rewritten as a current Prompt 9AAAAA result.

The current UI test adds a sanitized viewport relation model (`aboveViewport`, `insideViewport`, `belowViewport`, `notExposed`, `invalidFrame`) and calibrates direction against the existing `analytics.coverage` anchor. It never logs coordinates or exports an AX hierarchy. In both current business executions, a positive relative delta left coverage inside the viewport without observable progress; a negative relative delta moved it from inside to above the viewport and was therefore selected for `towardBottom`, while the positive inverse returned coverage to the top. Navigation re-queries the target and `analytics.detail.scroll` after every operation, treats event delivery and viewport progress as different facts, and stops after two consecutive no-progress observations.

The initial current business execution completed Calculate, coverage, Portfolio title, all seven metrics, the accessible-data toggle, and the risk-free disclosure. The first negative delta toward the independent `analytics.chart.performance.summary` anchor demonstrated progress, but later deltas stalled. The test stopped at the finite stall boundary and failed at that independent summary node.

The one authorized direct test-lifecycle repair added a single semantic-swipe fallback after exactly one verified no-progress delta. The fallback becomes the calibrated driver only if its own anchor evidence proves progress. No Production Swift, Analytics calculation, fixture, identifier, label, table contract, or business assertion changed. A fresh final signed build-for-testing passed. In the final business retry, the first negative delta again progressed; the next delta stalled; the one semantic `swipeUp` fallback also stalled. The test therefore stopped without blind repetition and failed at `analytics.chart.performance.summary`. The focused two-business-execution budget is exhausted.

| Verification | Result bundle | Result |
|---|---|---|
| Initial fresh signed build-for-testing | `/private/tmp/Aureus-Stage9AAAAA-EZchHC/BuildForTesting-Final.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; `Info.plist` present; build summary parse exit 0; errors 0 |
| Stage 9AAAAA focused UI, initial business execution | `/private/tmp/Aureus-Stage9AAAAA-EZchHC/Stage9FocusedUI.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; independent performance summary remained unexposed after finite progress/stall detection |
| Final fresh signed build-for-testing | `/private/tmp/Aureus-Stage9AAAAA-EZchHC/BuildForTesting-Retry.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; `Info.plist` present; build summary parse exit 0; errors 0 |
| Stage 9AAAAA focused UI, final business retry | `/private/tmp/Aureus-Stage9AAAAA-EZchHC/Stage9FocusedUI-Final.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; calibrated delta and bounded semantic fallback both stalled before `analytics.chart.performance.summary` |
| Existing focused UI regression | — | `NOT RUN` — final Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — Existing focused regression prerequisite did not pass |

Both focused bundles contain `Info.plist`; summary and tests parsing returned exit 0. Both invocations entered the business method, so neither is an infrastructure retry. The second is the single authorized business retry. The performance/chart/table runtime assertions below the missing navigation anchor, sparse-Portfolio typed-unavailable flow, and Production isolation remain `NOT VERIFIED`.

Because only `AureusUITests.swift` changed, Stage 9 focused Unit `20/20`, Stage 6–8 regression `204` definitions / `237` executions, full Unit `254` definitions / `287` executions, Stage 9 performance `3/3`, and Clean Debug arm64 Build are `NOT RUN — INHERITED AFTER EXACT Production/Unit SOURCE-HASH VERIFICATION`. Analytics Production, Domain, FeatureModel, Unit tests, persistence, migrations, Provider routing, entitlements, Package, project, and chart assets remained byte-identical.

Provider requests remain `NOT RUN`; Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 10 remains `NO-GO`.

This is **Stage 9AAAAA PARTIAL — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.

## 26. Stage 9-UI-02 detail-scroll witness isolation

Prompt 9-UI-02 preserves both Prompt 9AAAAA focused business failures as historical evidence. They selected negative relative delta for `towardBottom` but used an application-wide progress-witness set whose left-side fixed risk-free disclosure could be mistaken for right-side ScrollView content. Neither historical failure is rewritten as a current result.

The current UI test now requires positive horizontal and vertical intersection with `analytics.detail.scroll` before classifying a node as inside its viewport. No-horizontal-overlap nodes are `outsideScrollRegion`. Every Analytics detail target and progress witness is queried from the freshly resolved detail ScrollView descendants; fixed controls remain app-scoped, and `analytics.risk-free.disclosure` is explicitly verified outside the detail region. Progress compares the same descendant identifier before and after a scroll, while absent or incomparable witnesses allow the next bounded candidate instead of immediately proving a stall. No coordinate value or AX hierarchy is logged.

The initial current business execution completed direction calibration and the top Analytics assertions. Positive delta left coverage inside without downward progress; negative delta moved coverage from inside to above. It then failed with an XCTest matching-snapshot error because the witness loop read `identifier` from an offscreen unresolved candidate before short-circuiting on its `notExposed` viewport relation. This is a direct UI-test lifecycle failure, not an Analytics calculation or Production failure.

The single authorized UI-test-only repair reversed that safe-evaluation order: it now accepts a witness identifier only after the two-dimensional relation is `insideViewport`. A fresh final signed build-for-testing passed. The final business retry preserved calibration and produced right-side progress using the same identifiers: `analytics.report.portfolio`, `analytics.performance.table`, `analytics.drawdown.table`, and `analytics.monthly.table` moved from inside to above, while later `analytics.xirr-flow.table` observations provided the finite stall boundary. Despite that demonstrated traversal, `analytics.chart.performance.summary` remained `notExposed`; the unchanged assertion failed after seven of the maximum twelve bounded operations. No third focused run is authorized.

| Verification | Result bundle | Result |
|---|---|---|
| Initial fresh signed build-for-testing | `/private/tmp/Aureus-Stage9-UI-02-KSS3LN/BuildForTesting.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; `Info.plist` present; build-summary parse exit 0; errors 0 |
| Stage 9-UI-02 focused UI, initial business execution | `/private/tmp/Aureus-Stage9-UI-02-KSS3LN/Stage9FocusedUI.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; direct offscreen-witness query lifecycle failure |
| Final fresh signed build-for-testing | `/private/tmp/Aureus-Stage9-UI-02-KSS3LN/BuildForTesting-Final.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; `Info.plist` present; build-summary parse exit 0; errors 0 |
| Stage 9-UI-02 focused UI, final business retry | `/private/tmp/Aureus-Stage9-UI-02-KSS3LN/Stage9FocusedUI-Final.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; `analytics.chart.performance.summary` remained unexposed after real detail-region progress and bounded traversal |
| Existing focused UI regression | — | `NOT RUN` — final Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — Existing focused regression prerequisite did not pass |

Both focused bundles contain `Info.plist`. The initial sandboxed summary/tests parser attempts returned exit 64 because the TestReport cache was unavailable; read-only parsing of the same result bundle in the standard Xcode permission environment returned exit 0 without rerunning the test. Final summary/tests parsing returned exit 0. Both focused invocations entered the business method; the second is the single authorized business retry.

Because only `AureusUITests.swift` changed, Stage 9 focused Unit `20/20`, Stage 6–8 regression `204` definitions / `237` executions, full Unit `254` definitions / `287` executions, Clean Debug arm64 Build, and Stage 9 performance `3/3` are `NOT RUN — INHERITED AFTER EXACT Production/Unit SOURCE-HASH VERIFICATION`. Analytics Production, Domain, FeatureModel, Unit tests, persistence, migrations, Provider routing, entitlements, Package, project, and chart assets remained byte-identical.

The Performance summary/chart/table runtime assertions, remaining tables, sparse-Portfolio typed-unavailable flow, and Production isolation remain `NOT VERIFIED`. Provider requests remain `NOT RUN`; Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 10 remains `NO-GO`.

This is **Stage 9-UI-02 PARTIAL — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.

## 27. Stage 9-AX-01 native chart Accessibility closure

Prompt 9-AX-01 preserves both Prompt 9-UI-02 focused business failures as historical evidence. The initial historical failure was an offscreen-witness matching lifecycle failure; its final retry proved real right-side detail traversal but left `analytics.chart.performance.summary` unexposed. Neither historical result is rewritten as a current result, and neither replaces the current UI Gate.

The current Production repair is limited to the two homologous native chart regions. The Performance outer layout no longer owns `analytics.chart.performance`; an inner visual group owns that identifier while the existing self-contained `analytics.chart.performance.summary` and `analytics.performance.table` remain independent siblings. Drawdown now has the same structure for `analytics.chart.drawdown`, `analytics.drawdown.summary`, and `analytics.drawdown.table`. Each of the six identifiers occurs exactly once. No `.combine`, duplicate identifier, invisible test node, transparent overlay, calculation change, collection change, or test launch-argument branch was introduced.

Required current-source verification completed in order. Stage 9 focused Unit passed `20/20`. The signed Stage 6–8 host produced a retained infrastructure failure because 84 tests could not create their isolated `/private/tmp/AureusTests/<UUID>` directories; the authorized stable unsigned isolated host then passed the complete `204` definitions / `237` executions. Full Unit passed `254` definitions / `287` executions on the same unsigned isolated-host policy. Clean Debug arm64 Build and both signed build-for-testing products passed with zero errors and four existing PortfolioView deprecation warnings.

The initial focused business execution used the baseline UI test and the repaired Production AX structure. It formally passed the Performance summary, chart container, table summary, dynamic row-count, and representative row assertions, and then passed the corresponding Drawdown summary, chart, table, and representative row assertions. It later failed at `AureusUITests.swift:1834` when the helper's bounded semantic `.fast` `swipeUp` timed out while synthesizing an event during navigation toward `analytics.observed.tables`. This is a direct UI-test lifecycle failure, not evidence of a missing repaired chart node or Analytics arithmetic failure.

The single authorized UI-test-only repair replaced `.fast` semantic swipes with XCTest's default bounded swipes; it did not alter drivers, counts, timeouts, assertions, Production, or financial semantics. A fresh final signed build-for-testing passed. The only authorized final focused business retry again formally passed the Performance and Drawdown runtime contracts, then failed at the same event-synthesis boundary with the default `swipeUp` velocity. No third focused execution is authorized.

| Verification | Result bundle | Result |
|---|---|---|
| Stage 9 focused Unit | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/Stage9FocusedUnit.xcresult` | `PASS` — exit 0; 20 definitions / 20 executions; 20 passed / 0 failed / 0 skipped |
| Stage 6–8 signed regression | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/Stage68FocusedRegression.xcresult` | `INFRASTRUCTURE FAIL` — exit 65; 204 definitions; 120 passed / 84 failed / 0 skipped; failures were temporary-directory permission denials |
| Stage 6–8 unsigned isolated regression | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/Stage68FocusedRegression-Unsigned.xcresult` | `PASS` by complete test result — shell exit `NOT AVAILABLE` after the unified command handle closed; 204 definitions / 237 executions; 0 failed / 0 skipped |
| Full Unit, unsigned isolated host | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/FullUnit-Unsigned.xcresult` | `PASS` by complete test result — shell exit `NOT AVAILABLE` after the unified command handle closed; 254 definitions / 287 executions; 0 failed / 0 skipped |
| Clean Debug arm64 Build | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/CleanDebugBuild.xcresult` | `PASS` by complete build summary — shell exit `NOT AVAILABLE` after the unified command handle closed; errors 0; warnings 4 |
| Initial signed build-for-testing | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/BuildForTesting.xcresult` | `PASS` by complete build summary — shell exit `NOT AVAILABLE` after the unified command handle closed; `TEST BUILD SUCCEEDED`; errors 0 |
| Stage 9-AX-01 focused UI, initial business execution | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/Stage9FocusedUI.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; semantic event-synthesis timeout after Performance and Drawdown runtime contracts passed |
| Final signed build-for-testing | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/BuildForTesting-Final.xcresult` | `PASS` — exit 0; `TEST BUILD SUCCEEDED`; errors 0 |
| Stage 9-AX-01 focused UI, final business retry | `/private/tmp/Aureus-Stage9-AX-01-bFyiwV/Stage9FocusedUI-Final.xcresult` | `FAIL` — exit 65; 1 executed / 0 passed / 1 failed / 0 skipped; default semantic event-synthesis timeout at the same lifecycle boundary |
| Existing focused UI regression | — | `NOT RUN` — final Stage 9 focused UI did not pass |
| Full `AureusUITests` | — | `NOT RUN` — Existing focused regression prerequisite did not pass |

All listed result bundles contain `Info.plist`. Test-result parsing inside the restricted sandbox returned exit 64 because its TestReport cache was not writable; read-only parsing of the same completed result bundles in the standard Xcode permission environment returned exit 0 without rerunning tests. Both focused invocations entered the business method; the second is the single authorized business retry, not an infrastructure retry.

Monthly/Annual and the remaining native table assertions, sparse-Portfolio typed-unavailable flow, and Production isolation were not reached after the final lifecycle failure and remain `NOT VERIFIED`. Performance is `NOT RUN — INHERITED AFTER EXACT DOMAIN/FEATURE/PERFORMANCE SOURCE-HASH VERIFICATION`; the accepted Stage 9 performance implementation did not change. Provider requests remain `NOT RUN`; Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`; Stage 10 remains `NO-GO`.

This is **Stage 9-AX-01 PARTIAL — Awaiting Reviewer Gate**. It is not Stage 9 `PASS`, V1 Ready, Release Ready, or Stage 10 authorization.
