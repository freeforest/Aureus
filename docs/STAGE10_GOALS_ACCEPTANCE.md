# Stage 10 Goals Foundation Acceptance

## Status

**Stage 10 Goals Foundation Candidate — Awaiting Reviewer Gate**

The independent Reviewer recorded Stage 9 as `PASS` and authorized only this no-UI Stage 10 foundation. This document records Executor implementation and verification evidence; it does not declare Stage 10 `PASS`, V1 Ready, Release Ready, or entry to Stages 11–14.

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

**Stage 10 Goals Foundation Candidate — Awaiting Reviewer Gate**
