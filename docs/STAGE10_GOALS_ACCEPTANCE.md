# Stage 10 Goals Foundation Acceptance

## Status

**Stage 10 Goals UI Runtime Candidate — Awaiting Reviewer Gate**

## Stage 10-GOALS-UI-GATE-CLOSURE-01 — Existing Focused and Full UI Evidence

### Current status

**Stage 10 Goals UI Runtime Candidate — Awaiting Reviewer Gate**

This evidence-only round changed no Production Swift, Test Swift, Project, Package, Migration, Entitlement, Target, Scheme, fixture, or Unit test. Exact source-hash verification accepted the current-source Goals focused UI `1/1 PASS`, and every current UI execution reused the same frozen signed arm64 product. The earlier incomplete Existing focused bundle remains historical `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED`; it was not modified, completed, combined with another result, or represented as a business failure.

### Historical evidence classification

- `GoalsFocusedUI.xcresult` from the preceding round contains `Info.plist` and canonically reports `1/1` passed, `0` failed, `0` skipped. It remains accepted current-source focused evidence after exact source and product verification; it was not rerun in this closure round.
- The preceding `ExistingFocusedRegression.xcresult` contains only incomplete `Data` and `Staging` directories and no `Info.plist`. Its parsers cannot form a canonical test result. Business activity in that directory does not establish any accepted definition, execution, or PASS count.
- The historical incomplete directory was neither modified nor deleted. New current results use distinct paths under `/private/tmp/Aureus-Stage10-GOALS-UI-GATE-CLOSURE-01-Hnq5uF`.

### Frozen UI product

The following byte-identical signed BFT product was verified before Gate A, before Gate B, and after Gate B:

- App executable: SHA-256 `2de70a3debbb5d1dce395e338d6a306159164b9a46504f201c91464da34e0bf0`; bundle `com.aureus.wealthterminal`; arm64.
- Runner executable: SHA-256 `07521e34f7c89e2fd3e59bf8744ee746ba18e750d9c5b6710c07cbd5a323a7d3`; bundle `com.aureus.wealthterminal.uitests.xctrunner`; arm64.
- UI Test executable: SHA-256 `c7d2158b3d849eb6844a43b5a298fcddcec857a46145eb41f88d8443465d8496`; bundle `com.aureus.wealthterminal.uitests`; arm64.
- xctestrun: SHA-256 `b3f6360fe5e8101953ef5318592e18a1afaa40dff2d1ec95f6848cab5c3f91cd`.

App and Runner passed `/usr/bin/codesign --verify --deep --strict`. Signing is local ad-hoc (`Signature=adhoc`, no TeamIdentifier). No build or signing operation occurred between the two current UI invocations.

### Current verification evidence

| Verification | Result | Current evidence |
|---|---|---|
| Goals focused UI | `NOT RUN — ACCEPTED CURRENT-SOURCE PASS` | Exact frozen source/product verification preserves the preceding complete `1/1 PASS`; `1` passed, `0` failed, `0` skipped |
| Focused Goals Unit | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit hashes match; accepted evidence remains `35/35 PASS` |
| Full `AureusTests` | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit hashes match; accepted evidence remains `289` definitions / `322` executions PASS |
| Performance | `NOT RUN — INHERITED` | Exact Foundation/Presentation hashes match |
| Clean Debug arm64 Build | `NOT RUN — INHERITED` | Exact Production hashes match the accepted successful build source |
| Existing focused regression | `PASS` | Serial `test-without-building`; `8/8` definitions/business executions; `8` passed, `0` failed, `0` skipped; shell exit `0`; result interval `880.916 s`; complete `ExistingFocusedRegression-Closure.xcresult` with `Info.plist` |
| Full `AureusUITests` | `PASS` | Serial `test-without-building`; `14/14` definitions/business executions; `14` passed, `0` failed, `0` skipped; shell exit `0`; result interval `1020.594 s`; complete `FullAureusUITests-Closure.xcresult` with `Info.plist` |

Both current bundles first encountered the known sandbox TestReport cache permission boundary (`summary/tests` parser exits `64/64`). Standard-permission read-only parsing of each same, already completed bundle exited `0/0`; no test was rerun for parsing. Existing focused used the eight exact Settings, Wealth, Ledger Dynamic, Native CSV, Markets, Portfolio, Analytics, and Goals selectors. Only its canonical `8/8 PASS` authorized the subsequent full `AureusUITests` invocation. Full UI contains fourteen independent business Test Case nodes, all `Passed`.

### Retry and re-observation accounting

- UI infrastructure retry: `0`.
- Incomplete-result re-observation: `0`.
- Business retry: `0`.
- No partial and complete results were combined. Neither current command session was externally interrupted; each original persistent session remained open until `xcodebuild` exited naturally.

### Provider and data status

Provider requests are `NOT RUN`. Twelve Data and Frankfurter live operations, Provider transport attempts, Credential reads, Keychain metadata reads, Market Cache mutations, and planning-assumption persistence writes are `0`. Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`. Dashboard Goals integration is `NOT AUTHORIZED / NOT RUN`, and Stages 11–14 remain `NO-GO`.

### Current candidate

**Stage 10 Goals UI Runtime Candidate — Awaiting Reviewer Gate**

## Stage 10-GOALS-EVIDENCE-CONTRACT-01 — Calculation Evidence Disclosure

### Current status

**Stage 10-GOALS-EVIDENCE-CONTRACT-01 PARTIAL — Awaiting Reviewer Gate**

The authorized Calculation Evidence text-contract repair is complete. The visible `goals.evidence` Text and its explicit Accessibility label now use the same full disclosure:

> Calculation evidence: local permanent Goals, Wealth, and Ledger records only. Planning assumptions are session-only. No Provider request was made. No Market Cache, Credential, or Keychain data was read. No automatic FX conversion was performed. Planning assumptions were not persisted. Scenarios are not predictions, guarantees, or recommendations.

`goals.evidence.heading` remains an independent visible sibling with the exact label `Goals calculation evidence section`; `goals.evidence` remains unique and independently queryable. The UI contract now requires the complete disclosure by exact equality and preserves the final section boundary: Current Section is Calculation Evidence, Previous is enabled, and Next is disabled. No Goal formula, FeatureModel, persistence, fixture, chart, table, row, formatter, Project, Package, Migration, Target, Scheme, or Entitlement changed.

### Historical failure classification

The preceding chart-round initial focused invocation was a zero-business Automation bootstrap failure. Its authorized retry reused the identical UI product, entered the business method, and passed Synthetic Header, Goal CRUD, Trajectory, FIRE, and Saving Rate before reaching Calculation Evidence. `goals.evidence.heading` and the unique `goals.evidence` node were present; only the old substring label predicate failed at `AureusUITests.swift:1819`. This was a Production/test wording-contract mismatch, not AX exposure, navigation, calculation, persistence, Provider, or bootstrap failure. Historical results are not counted as this round's UI PASS.

### Current verification evidence

All current build and UI artifacts are rooted at `/private/tmp/Aureus-Stage10-GOALS-EVIDENCE-CONTRACT-01-QkxUDQ`.

| Verification | Result | Current evidence |
|---|---|---|
| Focused Goals Unit | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit source hashes match; accepted evidence remains `35/35 PASS` |
| Full `AureusTests` | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit source hashes match; accepted evidence remains `289` definitions / `322` executions PASS |
| Performance | `NOT RUN — INHERITED` | Foundation and presentation performance sources remain byte-identical |
| Final Clean Debug arm64 Build | `PASS` | shell exit `0`; status `succeeded`; errors `0`; four pre-existing PortfolioView deprecation warnings; complete parseable `CleanDebugBuild-Final.xcresult` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; status `succeeded`; errors `0`; warnings `0` for the incremental BFT; App, Runner, UI Test executable, and xctestrun came from one build and passed strict signature verification |
| Goals focused UI | `PASS` | `1/1` business definition/execution; `1` passed, `0` failed, `0` skipped; complete `GoalsFocusedUI.xcresult`; sandbox parsers exited `64`, and standard-permission read-only parsing of the same bundle exited `0/0` |
| Existing focused regression | `INCOMPLETE RESULT — NOT PASS` | The serial eight-selector invocation entered multiple real business methods on the same frozen product, but the executor session was externally interrupted during the final Wealth flow. `ExistingFocusedRegression.xcresult` has no `Info.plist`; summary/tests parsers exit `64/64`; no canonical `8/8` result exists. Because this was not a zero-business bootstrap failure, no retry was authorized. |
| Full `AureusUITests` | `NOT RUN` | Ordered prerequisite Existing focused `8/8 PASS` was not met |

No UI infrastructure retry or UI business retry was used in this round. The incomplete Existing focused execution was not rerun and is not represented as a PASS.

### Exact UI product

Every current UI invocation used the same signed BFT product:

- App executable SHA-256: `2de70a3debbb5d1dce395e338d6a306159164b9a46504f201c91464da34e0bf0`; bundle `com.aureus.wealthterminal`; arm64; ad-hoc Sign to Run Locally.
- Runner executable SHA-256: `07521e34f7c89e2fd3e59bf8744ee746ba18e750d9c5b6710c07cbd5a323a7d3`; bundle `com.aureus.wealthterminal.uitests.xctrunner`; arm64; ad-hoc Sign to Run Locally.
- UI Test executable SHA-256: `c7d2158b3d849eb6844a43b5a298fcddcec857a46145eb41f88d8443465d8496`; bundle `com.aureus.wealthterminal.uitests`; arm64; ad-hoc Sign to Run Locally.
- xctestrun SHA-256: `b3f6360fe5e8101953ef5318592e18a1afaa40dff2d1ec95f6848cab5c3f91cd`.

The four hashes remained unchanged before and after the focused execution and before the Existing focused invocation. App and Runner passed `codesign --verify --deep --strict`.

### Focused runtime boundary

Current focused runtime evidence formally passed the Synthetic Header and Goal CRUD; Trajectory chart/summary/table/row/disclosure; FIRE; Saving Rate chart/summary/table/row/disclosure; Calculation Evidence heading, exact complete disclosure, and final navigation boundary; the USD Goal's original value and typed-unavailable progress/trajectory with no fake zero, chart, table, or rows; stale-report reset; Production Header, absence of Synthetic Goals, Production empty state, blank session inputs, navigation reset; and the no-Provider/data-isolation assertions.

The Existing focused invocation advanced through real selected tests before external interruption, but its incomplete bundle cannot supply canonical definitions, executions, or a combination PASS. Full UI was therefore correctly gated off.

### Provider and data status

Provider requests are `NOT RUN`. Twelve Data and Frankfurter live operations, Provider transport attempts, Credential reads, Keychain metadata reads, Market Cache mutations, and planning-assumption persistence writes are `0`. Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`. Dashboard Goals integration is `NOT AUTHORIZED / NOT RUN`, and Stages 11–14 remain `NO-GO`.

### Current candidate

**Stage 10-GOALS-EVIDENCE-CONTRACT-01 PARTIAL — Awaiting Reviewer Gate**

The independent Reviewer recorded Stage 9 and the Stage 10 Goals Foundation Gate as `PASS`, while Stage 10 Goals UI remains `PARTIAL`. This document preserves the accepted Foundation, Native Goals Terminal, and Header Accessibility history and appends the current Visual Chart Accessibility evidence round; it does not declare Stage 10 `PASS`, V1 Ready, Release Ready, or entry to Stages 11–14.

Historical Executor status before that review: **Stage 10 Goals Foundation Candidate — Awaiting Reviewer Gate**.

## Scope

The foundation provides:

- a validated `Goal` domain model;
- CRUD through the existing permanent `goals` table;
- deterministic compound-planning, Goal-progress, target-date, FIRE, and Saving Rate calculations;
- an `@MainActor @Observable` Goals FeatureModel with explicit calculation and stale-generation isolation;
- synthetic Unit, persistence, lifecycle, and performance evidence.

It deliberately does not provide a `GoalsView`, AppShell destination, charts, Dashboard cards, UI tests, Provider/FX requests, migrations, persisted planning assumptions, Monte Carlo analysis, probability forecasts, recommendations, or a default withdrawal rate.

## Goal domain contract

`Goal` retains a UUID, a trimmed non-empty name, a strictly positive `Money` target in its original CNY or USD currency, and an optional `CivilDate`. Its throwing initializer, `validated()` path, and custom `Codable` decoding all enforce the same typed validation errors. Names are not globally unique. No floating-point value is used as financial authority.

USD targets persist and round-trip in USD. Comparing a USD target with CNY net worth returns the typed state `targetCurrencyUnsupportedForCNYProgress`; the implementation never treats USD as CNY and never obtains FX automatically.

## Persistence boundary

`GoalPersistence.swift` extends `WealthStore` and reuses the schema-version-6 `goals` table (`id`, `name`, `target_minor`, `currency_code`, `target_date`). It implements validated create/fetch/fetch-by-ID/update/delete operations. Update and delete require exactly one affected row; missing rows and corrupt persisted records are typed failures. Mutations are transactional, reopen round-trips are covered, and deterministic fetch order is:

1. dated Goals before undated Goals;
2. target date ascending;
3. undated Goal name case-insensitively;
4. UUID as the stable final key.

`DatabaseMigrations.swift` and `SyntheticFoundationSeeder.swift` remain unchanged. Permanent schema version remains `6`; no second Goal table, migration, or `REAL` financial-authority column was added.

## Formula conventions

### Compound planning

Inputs are CNY initial capital, nonnegative CNY monthly contribution, a nominal annual `Ratio`, and `0...1200` months. Contributions occur at month end. With `r = annualReturn / 12` and `f = (1 + r)^months`:

- when `r != 0`, future value is `initial × f + contribution × ((f - 1) / r)`;
- when `r == 0`, future value is `initial + contribution × months`.

The engine uses checked `Decimal` operations and deterministic repeated multiplication, not binary `pow`, `Double`, or `Float`. Intermediate balances are not rounded to cents each month; final `Money` uses the existing banker-rounding authority. Invalid rates, month counts, decimal operations, and overflow are typed failures. Reports disclose initial capital, total contributions, assumption growth, duration, and annual-return assumption, and describe the result as an assumption-based scenario rather than a prediction or recommendation.

### Goal progress and trajectory

CNY progress is `currentNetWorthCNY / targetCNY` and is intentionally unclamped, allowing negative and above-100% values. Remaining value is `max(target - currentNetWorth, 0)`. Current net worth uses existing `WealthValuation.aggregate` semantics.

Target-date periods use Gregorian `(year, month)` buckets; the stored day remains available for record/display but does not create a partial compounding month. Missing dates, non-future target months, already-reached Goals, unsupported USD progress, and failure to reach within the bounded 1,200-month search are finite typed states. Estimated reach uses the same month-end contribution recurrence and never uses logarithmic floating-point shortcuts.

### FIRE scenario

FIRE is an arithmetic scenario using user-supplied assumptions. `fireNumberCNY = annualSpendingCNY / withdrawalRate`, with positive spending and `0 < withdrawalRate <= 1`. Progress remains unclamped and estimated reach uses the same bounded engine. Outputs preserve every supplied assumption. No withdrawal rate is defaulted, preselected, described as safe, or presented as recommended or guaranteed.

### Saving Rate

For an explicit inclusive `CivilDate` range:

- ordinary income includes only `TransactionKind.income`;
- ordinary expense includes only `TransactionKind.expense`;
- ordinary savings is income minus expense;
- Saving Rate is savings divided by positive income.

Transfers, buys, sells, dividends, interest, and fees are excluded without changing Ledger cash-flow semantics. The calculation reuses each posting's stored `convertedCNY` provenance and performs no FX recalculation or Provider request. Months are Gregorian civil buckets and appear only when at least one ordinary income or expense exists; empty months are not zero-filled. Expense-only months preserve negative savings with typed `nonPositiveIncome`, and negative valid Saving Rates are not clamped.

## FeatureModel lifecycle

`GoalsFeatureModel` is `@MainActor @Observable` and is not wired into AppShell. Its only data sources are permanent Goals, Wealth containers, Ledger entries, and the pure planning functions. It supports load, Goal CRUD, selected Goal, current CNY net worth, session-only planning assumptions, and explicit Calculate across finite idle/loading/ready/calculating/failed states.

Load, CRUD, source/input changes, cancellation of an old generation, and error transitions never trigger automatic calculation. Source or assumption mutations invalidate the prior report, and generation checks prevent an older asynchronous result from overwriting newer state. Confirmed permanent records remain available after calculation errors. Delete requires an explicit caller confirmation flag. Planning assumptions are not written to `goals`, UserDefaults, any other database table, Market Cache, backup, or export.

## Verification evidence

All final results were produced from the same final source candidate in the isolated root `/private/tmp/Aureus-Stage10-GOALS-FOUNDATION-01-nDJE3c`.

| Verification | Result | Evidence |
|---|---|---|
| Stage 10 focused Unit | `PASS` | `25` definitions / `25` executions; `25` passed, `0` failed, `0` skipped; final parsers `0` |
| Full `AureusTests` | `PASS` | `279` canonical definitions / `312` dynamic executions; `0` failed, `0` skipped; final parsers `0` |
| Release performance workload | `PASS` | 1,000 compound scenarios, 10,000 synthetic Ledger entries, 120 observed months, Saving Rate grouping, and 1,200-month Goal/FIRE searches completed in `433 ms` |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing PortfolioView deprecation warnings |
| Fresh signed arm64 build-for-testing | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings |
| UI tests | `NOT RUN — NOT AUTHORIZED IN GOALS FOUNDATION ROUND` | No Goals UI or AppShell wiring is in scope |

The signed Unit host's known App Sandbox denial for `/private/tmp/AureusTests/<UUID>` was retained as infrastructure evidence. The same source, selectors, and assertions passed in the prompt-authorized stable unsigned isolated host. Earlier zero-test build-configuration and compile-diagnostic bundles were not counted as PASS. Every final result bundle contains `Info.plist` and its applicable summary/tests or build-summary parser exited `0`.

## Performance boundary

The reported Release workload checks deterministic repeated output, leaves inputs unchanged, performs no network request or persistence write, and uses finite loops only. System duration measurement is not a financial authority; every financial result remains checked Decimal/fixed-point. The measured `433 ms` is current-host evidence, not a cross-device guarantee.

## Provider and privacy boundary

Provider requests are `NOT RUN`. Twelve Data operations, Frankfurter live operations, Provider transport attempts, Credential reads, Keychain metadata reads, and Market Cache mutations are `0`. Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`. Fixtures are synthetic or sanitized. Goal persistence tests use isolated temporary databases only, and no real financial data or Provider payload is stored in the Repository.

## Known limitations

- No Goals UI, navigation destination, visualization, Dashboard integration, or UI evidence exists in this foundation round.
- USD Goal progress against CNY net worth remains explicitly unavailable until a separately authorized FX source/provenance contract exists.
- Planning assumptions are session-only and intentionally do not survive relaunch.
- The formulas omit inflation, tax, pension, insurance, Monte Carlo, and probabilistic modeling.
- Scenarios are arithmetic disclosures, not forecasts, guarantees, recommendations, or automated financial guidance.
- Stage 11 data lifecycle, backup/restore, release work, and Stages 12–14 remain outside authorization.

## Current candidate

The Foundation result above remains accepted historical evidence. The current repository status is recorded in the following independent UI-round section.

## Stage 10-GOALS-UI-01 — Native Goals Terminal

### Current status

**Stage 10-GOALS-UI-01 PARTIAL — Awaiting Reviewer Gate**

The Native Goals Terminal implementation, focused/full Unit suites, Clean Debug arm64 Build, and fresh signed build-for-testing all completed. The Goals focused UI entered the business method twice under the one authorized business-repair budget, but both executions failed at `AureusUITests.swift:771`: `goals.page` was exposed while `goals.mode.synthetic` did not become independently queryable. The final focused UI is therefore `0/1`; Existing focused `8/8` and full UI `14/14` are `NOT RUN` by their ordered prerequisites.

### Implemented boundary

- `GoalsView` is injected only with `WealthStore`, `Clock`, and `AppDataMode`; no Provider, Credential, Keychain, or Market Cache dependency is added.
- Synthetic Demo mode seeds two fixed validated Goals idempotently through `WealthStore.createGoal`: `Synthetic Freedom Goal` in CNY and `Synthetic USD Education Goal` in USD. Production does not call the seeder.
- The native terminal provides Goal list selection, add/edit sheets, confirmed deletion, an explicit session-input command, Calculate/Cancel, and five finite report sections: Overview, Trajectory, FIRE, Saving Rate, and Calculation Evidence.
- Trajectory and Saving Rate use native Swift Charts plus independent self-contained summary and table siblings. Row identifiers are derived from real presentation points or observed months; unavailable USD trajectory renders no fake chart, table, or row.
- Session financial inputs start blank. Percentages and amounts are parsed with checked Decimal/fixed-point authority, applied atomically only after every field validates, remain session-only, clear stale reports, and never auto-calculate. No withdrawal rate is defaulted or recommended.
- Presentation trajectories call the accepted `GoalPlanning.compound` engine for each bounded point, use at most 1,201 points, support cancellation/generation isolation, and do not create a second financial formula.

### Current verification evidence

Final-source evidence is rooted at `/private/tmp/Aureus-Stage10-GOALS-UI-01-gtvA2E`.

| Verification | Result | Current evidence |
|---|---|---|
| Focused Goal Unit | `PASS` | `35` definitions / `35` executions; `35` passed, `0` failed, `0` skipped; summary/tests parser exits `0/0` |
| Full `AureusTests` | `PASS` | `289` canonical definitions / `322` dynamic executions; `0` failed, `0` skipped; summary/tests parser exits `0/0` |
| Foundation performance | `PASS` | Release workload ran inside both final Unit gates; presentation workload also generated the maximum `1,201` points deterministically and read-only, below 10 seconds |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status `succeeded`; errors `0`; four pre-existing `PortfolioView` deprecation warnings |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; App, Runner, UI Test, and xctestrun came from the same build |
| Goals focused UI — initial | `BUSINESS ASSERTION FAILURE` | `1/1` definition/execution; `0` passed, `1` failed, `0` skipped; `goals.page` passed, then `goals.mode.synthetic` was not queryable at line 771 |
| Goals focused UI — final | `BUSINESS ASSERTION FAILURE` | authorized direct AX repair applied and all Unit/Build gates rerun; final `1/1` definition/execution remained `0/1/0` at the same line/identifier |
| Existing focused regression | `NOT RUN` | Requires current Goals focused UI `1/1 PASS` |
| Full `AureusUITests` | `NOT RUN` | Requires current Existing focused `8/8 PASS` |

The initial mode implementation attached a ternary identifier to the title Text. The single authorized direct repair replaced it with symmetric, visible Synthetic and Production Text nodes using static identifiers. Static uniqueness, build, and Unit checks passed, but the final runtime query still did not expose the Synthetic mode node. No third Goals business execution is authorized; this remains the current evidence blocker rather than a calculation, persistence, Provider, or automation-bootstrap failure.

### Runtime contracts not reached

Because the focused test stopped at the mode AX assertion, current-source runtime evidence for Goal CRUD/reconstruction/deletion, explicit CNY calculation, Overview, Trajectory, FIRE, Saving Rate `84%`, Calculation Evidence, USD typed-unavailable behavior, and Production isolation is `NOT VERIFIED` in this round. Their source and Unit contracts do not substitute for the missing UI Gate.

### Provider and data status

Provider requests are `NOT RUN`; Twelve Data and Frankfurter live operations, Provider transport attempts, Credential reads, Keychain metadata reads, Market Cache mutations, and planning-assumption persistence writes are `0`. Twelve Data persistent writes remain `Disabled`, retention remains `BLOCKED`, Dashboard Goals integration is `NOT AUTHORIZED / NOT RUN`, and Stages 11–14 remain `NO-GO`.

### Current candidate

**Stage 10-GOALS-UI-01 PARTIAL — Awaiting Reviewer Gate**

## Stage 10-GOALS-HEADER-AX-01 — Goals Header Accessibility

### Current status

**Stage 10-GOALS-HEADER-AX-01 PARTIAL — Awaiting Reviewer Gate**

The authorized Header-only repair is complete. `goals.page`, the Synthetic/Production mode nodes, and `goals.disclosure.local-only` are now separate visible native Text siblings with explicit, self-contained labels. The common layout parent has no business identifier and does not combine or ignore these children. Static uniqueness, Clean Debug arm64 Build, and fresh signed build-for-testing all passed.

The first Goals focused invocation failed before any business method entered because the UI runner timed out while enabling automation mode. Its complete result contains one runner system-failure node and zero business definitions/executions. The single global infrastructure retry reused byte-identical App, Runner, UI Test executable, and xctestrun artifacts without rebuilding or changing source. That retry entered the business method, passed the Synthetic Header count/label and alternate-mode-absence assertions, and continued through Goal CRUD. It then failed at `AureusUITests.swift:1819` because `goals.chart.trajectory` did not satisfy its existing label contract. Header had already passed, so this is a later report-presentation business boundary outside the current authorization; no business repair or retry followed.

### Header contract

- `goals.page` is owned by the visible `Goals` Text and has the explicit label `Goals page`.
- Synthetic mode uses one visible Text with `goals.mode.synthetic` and `Goals mode: Synthetic Demo`.
- Production mode uses one visible Text with `goals.mode.production` and `Goals mode: Production Local`.
- `goals.disclosure.local-only` remains a visible, independent Text with the complete local-only disclosure as its explicit label.
- The four identifiers each occur exactly once in Production source. No layout ancestor carries them; no `.combine`, transparent overlay, hidden fake node, dynamic identifier, or UI-test-only Production branch was introduced.
- The focused test separately requires count one plus an exact label for the current page, mode, and disclosure, and count zero for the alternate mode. It re-queries after Production relaunch and does not weaken CRUD, report, USD-unavailable, stale-state, Production-isolation, or Provider-zero assertions.

### Current verification evidence

All new build and UI artifacts are rooted at `/private/tmp/Aureus-Stage10-GOALS-HEADER-AX-01-FU86lS`.

| Verification | Result | Current evidence |
|---|---|---|
| Focused Goals Unit | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit source hashes match; accepted current-source evidence remains `35/35 PASS` |
| Full `AureusTests` | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit source hashes match; accepted evidence remains `289` definitions / `322` executions PASS |
| Performance | `NOT RUN — INHERITED` | Foundation and presentation performance sources remain byte-identical |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status `succeeded`; errors `0`; four pre-existing PortfolioView deprecation warnings; complete parseable result |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; status `succeeded`; errors `0`; four pre-existing warnings; App, Runner, UI Test, and xctestrun came from one build |
| Goals focused — initial | `RUNNER/AUTOMATION BOOTSTRAP FAILURE` | shell exit `65`; runner timed out while enabling automation; business definitions/executions `0/0`; no assertion failure |
| Goals focused — infrastructure retry | `BUSINESS ASSERTION FAILURE` | `1/1` definition/execution; `0` passed, `1` failed, `0` skipped; Header and CRUD passed; later failure at `goals.chart.trajectory`, line 1819 |
| Existing focused regression | `NOT RUN` | Ordered prerequisite Goals focused `1/1 PASS` was not met |
| Full `AureusUITests` | `NOT RUN` | Ordered prerequisite Existing focused `8/8 PASS` was not met |

### Runtime boundary

The current Synthetic execution formally established one `goals.page` with the exact page label, one `goals.mode.synthetic` with the exact Synthetic label, zero `goals.mode.production`, and one exact local-only disclosure node. It also passed the existing Goal load/create/update/reconstruction/delete/reconstruction flow before reaching Trajectory. Production mode, USD typed-unavailable, later report sections, Production isolation, and Provider-zero runtime assertions were not reached in this execution and remain `NOT VERIFIED`; static or inherited evidence does not replace them.

### Provider and data status

Provider requests are `NOT RUN`. Twelve Data and Frankfurter live operations, Provider transport attempts, Credential reads, Keychain metadata reads, Market Cache mutations, and planning-assumption persistence writes are `0`. Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`. Dashboard Goals integration is `NOT AUTHORIZED / NOT RUN`, and Stages 11–14 remain `NO-GO`.

### Current candidate

**Stage 10-GOALS-HEADER-AX-01 PARTIAL — Awaiting Reviewer Gate**

## Stage 10-GOALS-CHART-AX-01 — Goals Visual Chart Accessibility

### Current status

**Stage 10-GOALS-CHART-AX-01 PARTIAL — Awaiting Reviewer Gate**

The authorized chart-only repair is complete. The real Trajectory and Saving Rate Swift Chart visual groups now use native child-ignoring Accessibility representations with the explicit labels `Goal trajectory chart` and `Observed Saving Rate chart`. Each chart identifier occurs exactly once. The corresponding summary, table, real rows, and disclosure remain independent siblings; chart marks remain hidden from Accessibility because the native tables and rows carry the complete numeric data. The USD typed-unavailable branch still exposes no fake Trajectory chart, table, or rows.

The focused UI initial invocation failed before the business method entered because the Runner timed out while enabling Automation mode. Its complete result has one Runner system-failure node and business definitions/executions `0/0`. The single authorized infrastructure retry reused byte-identical App, Runner, UI Test executable, and xctestrun artifacts without rebuilding or changing source. The retry entered the business method and formally passed the Synthetic Header, Goal CRUD, Trajectory chart exact-label contract, Trajectory summary/table/real-row/disclosure, FIRE, Saving Rate chart exact-label contract, and Saving Rate summary/table/real-row/disclosure. It then failed at the later `goals.evidence` label assertion at `AureusUITests.swift:1819`. Because both authorized chart contracts had already passed, that Calculation Evidence failure is outside this chart-only repair boundary; no source change or business retry followed.

### Chart contracts

- `goals.chart.trajectory` is owned by the real visible Trajectory chart group, uses `.accessibilityElement(children: .ignore)`, and has the exact label `Goal trajectory chart`.
- `goals.chart.saving-rate` is owned by the real visible Saving Rate chart group, uses `.accessibilityElement(children: .ignore)`, and has the exact label `Observed Saving Rate chart`.
- `goals.trajectory.summary`, `goals.trajectory.table`, real `goals.trajectory.row.<month>` nodes, and `goals.trajectory.disclosure` remain independent siblings.
- `goals.saving-rate.summary`, `goals.saving-rate.table`, real `goals.saving-rate.row.<period>` nodes, and `goals.saving-rate.disclosure` remain independent siblings.
- Header identifiers and labels are unchanged. No `.combine`, transparent overlay, invisible fake node, dynamic identifier, test-only Production branch, formula, data collection, formatter, or chart-point change was introduced.
- The Goals focused test now requires count one and exact labels for both visual charts. It retains all summary, dynamic-row-count, real-row, FIRE, Calculation Evidence, USD typed-unavailable, stale-state, Production-isolation, and Provider-zero assertions without added timeout, sleep, gesture, coordinate, or AX dump.

### Current verification evidence

All current artifacts are rooted at `/private/tmp/Aureus-Stage10-GOALS-CHART-AX-01-TGoCBa`.

| Verification | Result | Current evidence |
|---|---|---|
| Focused Goals Unit | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit source hashes match; accepted current-source evidence remains `35/35 PASS` |
| Full `AureusTests` | `NOT RUN — INHERITED` | Exact Domain/Feature/Unit source hashes match; accepted evidence remains `289` definitions / `322` executions PASS |
| Performance | `NOT RUN — INHERITED` | Foundation and presentation performance sources remain byte-identical |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status `succeeded`; errors `0`; four pre-existing PortfolioView deprecation warnings; complete parseable result |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; status `succeeded`; errors `0`; four pre-existing warnings; App, Runner, UI Test executable, and xctestrun came from one build and passed strict signature verification |
| Goals focused — initial | `RUNNER/AUTOMATION BOOTSTRAP FAILURE` | shell exit `65`; Runner timed out while enabling Automation; business definitions/executions `0/0`; complete parseable result; no assertion failure |
| Goals focused — infrastructure retry | `BUSINESS ASSERTION FAILURE` | `1/1` business definition/execution; `0` passed, `1` failed, `0` skipped; both chart contracts and their siblings passed; later failure at `goals.evidence`, line 1819 |
| Existing focused regression | `NOT RUN` | Ordered prerequisite Goals focused `1/1 PASS` was not met |
| Full `AureusUITests` | `NOT RUN` | Ordered prerequisite Existing focused `8/8 PASS` was not met |

### Runtime boundary

Current runtime evidence formally closes both chart count and exact-label contracts, the Trajectory endpoint/table/row disclosure path, FIRE, and the Saving Rate `CNY 5,000.00` income / `CNY 800.00` expense / `CNY 4,200.00` savings / `84%` rate table path. Calculation Evidence did not satisfy its existing label contract. USD typed-unavailable behavior, stale-state isolation, Production Header/isolation, and Provider-zero assertions occur later and are `NOT VERIFIED` in this execution. Static, inherited, or previously accepted evidence does not substitute for those missing current runtime assertions.

### Provider and data status

Provider requests are `NOT RUN`. Twelve Data and Frankfurter live operations, Provider transport attempts, Credential reads, Keychain metadata reads, Market Cache mutations, and planning-assumption persistence writes are `0`. Twelve Data persistent writes remain `Disabled`; retention remains `BLOCKED`. Dashboard Goals integration is `NOT AUTHORIZED / NOT RUN`, and Stages 11–14 remain `NO-GO`.

### Current candidate

**Stage 10-GOALS-CHART-AX-01 PARTIAL — Awaiting Reviewer Gate**
