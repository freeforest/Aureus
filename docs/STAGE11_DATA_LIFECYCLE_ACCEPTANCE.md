# Stage 11 Data Lifecycle Acceptance

## Status

**Stage 11-SETTINGS-DATA-LIFECYCLE-UI-01 PARTIAL — Awaiting Reviewer Gate**

## Settings internal data-lifecycle UI round

The Reviewer accepted Backup Foundation, Restore Foundation, and Migration Safety as `PASS` before authorizing this bounded Settings round. Their manifest, validation, retention, replacement, rollback, recovery-required, migration, schema-version-6, and Provider-isolation contracts remain byte-identical.

Settings now presents one native internal-only data-lifecycle section driven by a separate `SettingsDataLifecycleModel`. Initial load and reconstruction only inventory validated generations under the injected internal Backup root. `Create Backup` is explicit; selecting a visible valid generation enables `Restore Selected Backup`; Restore requires native confirmation, revalidates the candidate, delegates to the existing Restore foundation, and reloads inventory. Ordinary failures and `recoveryRequired` are finite and independently accessible. Invalid or unknown siblings are counted only as ignored diagnostics and are never selectable or deleted. No arbitrary path, raw SQLite, external import/export, `NSOpenPanel`, security-scoped bookmark, automatic schedule, Provider, Credential, Keychain, or Market Cache dependency was added.

`AppDependencies` and `AppShellView` inject the existing `WealthStore`, the environment-specific internal Backup root, normalized app version, and generation identity dependency. Production and Synthetic/temporary roots remain isolated. The Project adds only the Production membership for `SettingsDataLifecycleModel.swift` and the Unit membership for `SettingsDataLifecycleTests.swift`.

### Settings round verification evidence

Final evidence is rooted at `/private/tmp/Aureus-Stage11-SETTINGS-DATA-LIFECYCLE-UI-01-SbVnOZ`.

| Verification | Result | Evidence |
|---|---|---|
| Focused lifecycle/Backup/Restore/Migration Unit | `PASS` | Exact five suites; `101` definitions / `109` dynamic executions; `109` passed, `0` failed, `0` skipped; final unsigned isolated-host shell exit `0`; complete `FocusedUnit-Unsigned-AfterRepair.xcresult`; summary/tests parser exits `0/0`; signed-host permission failure retained separately |
| Full `AureusTests` | `PASS` | `394` definitions / `435` dynamic executions; `435` passed, `0` failed, `0` skipped; final unsigned isolated-host shell exit `0`; complete `FullAureusTests-Unsigned-AfterRepair.xcresult`; parser exits `0/0`; signed-host permission failure retained separately |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted Backup, Restore, and Migration Safety Release workloads remain unchanged; this is not a current-round execution |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` warnings; complete `CleanDebugBuild-Final.xcresult`; parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing warnings; complete `BuildForTesting-Final.xcresult`; parser exit `0`; App and Runner strict codesign exit `0` |
| Targeted Settings UI initial | `FAIL` | `1/1` business execution, `0` passed / `1` failed / `0` skipped; complete `Stage11SettingsTargetedUI.xcresult`; the XCTest identifier shortcut rejected the 149-character confirmation text at `AureusUITests.swift:1336` |
| Targeted Settings UI final | `FAIL` | `1/1` business execution, `0` passed / `1` failed / `0` skipped; complete `Stage11SettingsTargetedUI-Final.xcresult`; Backup creation, Goal probe, inventory reload, selection, and Restore-button lifecycle passed before the exact warning `StaticText` was not found at `AureusUITests.swift:1340` |
| Existing focused regression | `NOT RUN` | Gate prerequisite failed; no business repair or retry authorized after the final Targeted UI execution |
| Full `AureusUITests` | `NOT RUN` | Existing focused Gate was not reached |

The first complete targeted business failure authorized one direct UI-test lifecycle repair: the full confirmation warning moved from XCTest's length-limited identifier subscript to an exact `label ==` predicate without weakening its text. The prompt-required focused Unit, full Unit, Clean Build, BFT, and targeted UI sequence was then repeated on final source. The final targeted failure exhausted the two-business-execution budget, so no third run or second repair was performed. Infrastructure retry and incomplete-result re-observation were both `0`.

### Settings round provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External Backup/import/export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All test records and internal generations were synthetic and isolated under `/private/tmp`. The remaining runtime boundary is the native confirmation dialog's independent exact-label exposure; it is not a Backup, Restore, migration, Persistence, Provider, or test-discovery failure.

## Current Settings UI round status

**Stage 11-SETTINGS-DATA-LIFECYCLE-UI-01 PARTIAL — Awaiting Reviewer Gate**

Stage 10 and the Stage 11 Backup and Restore Foundations have independent Reviewer `PASS` decisions. This document preserves those bounded rounds and records the current no-UI Permanent Migration Safety candidate. It does not declare Stage 11 `PASS`, Restore UI Ready, V1 Ready, Release Ready, or entry to Stages 12–14.

## Scope

The foundation provides:

- a Production internal Backup root at `Application Support/Aureus/Backups/` formed through Foundation container APIs;
- an isolated temporary Backup root at `<injected temporary root>/Backups/`;
- consistent SQLite backup within `WealthStore` actor ownership through GRDB;
- a versioned manifest, complete generation validation, inventory, and valid-only five-generation retention;
- synthetic Unit and Release-oriented performance evidence.

It adds no UI, scheduled/background backup, cloud backup, sync, external file panel, migration hook, import/export, or generic file manager abstraction.

## Backup artifact contract

Each committed generation is a direct child of the configured Backup root and contains exactly:

- `aureus.sqlite`
- `manifest.json`

Generation names use UTC time components plus a random identity and contain no account, Goal, Portfolio, amount, user-path, or other business value. Staging is operation-specific and is atomically moved into its final generation only after complete validation. SQLite WAL/SHM sidecars, Market Cache, Provider data, Credential/Keychain data, UserDefaults, logs, temporary imports, exports, chart assets, and Repository files are excluded.

## Manifest schema

The stable sorted-key JSON manifest has exactly these fields:

| Field | Contract |
|---|---|
| `backupFormatVersion` | Fixed at `1` |
| `appVersion` | Explicitly supplied by the caller |
| `schemaVersion` | Read from the completed backup database |
| `createdAt` | UTC date representation |
| `databaseByteCount` | Exact final database byte count |
| `databaseSHA256` | Lowercase streaming SHA-256 |

The manifest contains no absolute path, record count, financial summary, account, symbol, Goal, Portfolio, Provider, Credential, or device identity. It makes no application-layer encryption claim; V1 relies on macOS and user-storage protection.

## Consistent backup and validation

The source is never copied as a live ordinary file. `WealthStore` passes its owned GRDB source connection to SQLite's consistent backup operation, closes the destination connection, hashes the finalized standalone database in bounded chunks, writes the manifest, validates staging, atomically commits, validates the committed generation again, and only then applies retention.

Validation independently requires:

- a safe direct-child generation path and rejection of symbolic links;
- regular `aureus.sqlite` and `manifest.json` files with no extra artifact or sidecar;
- decodable format-version-1 manifest with exact byte count and SHA-256;
- read-only SQLite open with `PRAGMA query_only = ON`;
- successful `PRAGMA quick_check`;
- zero `PRAGMA foreign_key_check` violations;
- permanent schema metadata matching the manifest without migration.

Finite typed errors distinguish unsafe paths, symbolic links, missing/malformed/unsupported manifests, missing databases, unexpected artifacts, byte-count/hash mismatches, database/integrity failures, foreign-key failures, schema mismatches, consistent-backup failures, and retention failures. Diagnostics do not expose rows, credentials, or user paths.

## Five-generation retention

Only valid generations count toward retention. They are ordered by manifest UTC creation time and then stable generation identity. Pruning starts only after the new committed generation passes a second validation and removes only older, valid, strict-pattern direct children of the configured root until five remain. A failed new generation leaves the existing five valid generations unchanged. Invalid and unknown siblings are diagnosed but neither counted nor automatically deleted.

## Isolation and source integrity

Synthetic tests establish that committed permanent records appear in the backup, later source mutation does not alter an older generation, and backup creation does not mutate the source schema or records. Adjacent Market Cache and key-like sentinels remain unchanged and absent from generations. The implementation has no Provider, Credential, Keychain, or Market Cache dependency.

## Backup Foundation round: Restore and migration boundary

**Restore: NOT IMPLEMENTED / NOT AUTHORIZED IN THIS FOUNDATION ROUND.**

No permanent database replacement, safety restore, rollback, maintenance mode, user-selected restore, old-schema import, pre-migration backup hook, or migration is implemented. Permanent schema version remains `6`; all migration identifiers and the cache schema remain unchanged. Validation does not imply Restore readiness.

This statement is retained as the historical boundary of Prompt 11-BACKUP-FOUNDATION-01. The Reviewer subsequently accepted that Backup Foundation and separately authorized the bounded no-UI Restore Foundation recorded below.

## Verification evidence

Final current-source artifacts are rooted at `/private/tmp/Aureus-Stage11-BACKUP-FOUNDATION-01-CgeiqO`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `PASS` | Exact suites `PermanentBackupTests` and `PersistenceTests`; `34/34` definitions/executions; `34` passed, `0` failed, `0` skipped; shell exit `0`; complete `FocusedUnit-Final.xcresult`; summary/tests parser exits `0/0` |
| Full `AureusTests` | `PASS` | `327` definitions / `360` dynamic executions; `327` passed, `0` failed, `0` skipped; shell exit `0`; complete `FullAureusTests-Final.xcresult`; summary/tests parser exits `0/0` |
| Release backup suite | `PASS` | `28/28`; the real 10,000-row workload entered and emitted `STAGE11_BACKUP_PERF rows=10000 create_validate_ms=16 provider_requests=0 cache_reads=0 credential_reads=0`; measured create plus validate `16 ms`, below 10 seconds |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` deprecation warnings; complete `CleanDebugBuild-Final.xcresult` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting-Final.xcresult`; App and Runner strict codesign verification passed |
| UI tests | `NOT RUN — NOT AUTHORIZED IN BACKUP FOUNDATION ROUND` | A signed BFT is build evidence, not UI execution |

The signed Unit host's proven App Sandbox rejection of `/private/tmp/AureusTests/<UUID>` is preserved as infrastructure evidence. The prompt-authorized stable unsigned isolated host ran the same final source, selectors, and assertions for both final Unit gates. Earlier compile, source-candidate, zero-test discovery, and failed diagnostic bundles remain failures or diagnostics and are not counted as PASS. The first Release attempt did not enter the workload because Release omitted testability; the final equivalent Release suite used command-line `ENABLE_TESTABILITY=YES` without changing Project settings.

Every retained result bundle contains `Info.plist`. A final read-only audit preserved sandbox TestReport-cache parser exits `64` for the non-final test bundles and then parsed each same bundle under standard Xcode permissions with exit `0`; no test was rerun for parser recovery. All five final Gate bundles parsed directly with exit `0` in the final evidence path.

## Performance boundary

The Release-oriented suite created at least 10,000 synthetic permanent rows, performed a real consistent backup, streaming SHA-256, manifest generation, SQLite integrity, foreign-key, and schema validation, and verified unchanged source sentinels. The `16 ms` result is current-host evidence only, not a cross-device guarantee. Provider requests, Market Cache reads/mutations, and Credential/Keychain reads were zero.

## Provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Retention: `BLOCKED`
- Stages 12–14: `NO-GO`

All fixtures are synthetic or sanitized. No Repository database, backup generation, Provider payload, Credential, or real financial record was created.

## Known issues and limitations

- Backup creation is not yet wired to Settings or scheduling.
- Restore UI, external import/export, arbitrary/user-selected paths, startup migration hooks, and automatic Restore remain unimplemented and unauthorized.
- Backup artifacts are not claimed to have application-layer encryption.
- Four pre-existing `PortfolioView` string-interpolation deprecation warnings remain; this round added no warning.
- The Mandatory Read prompt named the absent path `Aureus/Domain/Values/TimeValues.swift`; the canonical existing file `Aureus/Domain/Time/TimeValues.swift` was read to EOF, and no path was invented or changed.

## Backup Foundation Reviewer decision

The Reviewer accepted the prior Backup Foundation evidence as `PASS`. The accepted contract remains unchanged: each valid generation contains only `aureus.sqlite` and `manifest.json`, uses streaming SHA-256 and exact byte count, passes SQLite/foreign-key/schema validation, and participates in valid-only five-generation retention. The accepted Backup implementation, `RuntimePaths`, manifest schema, migration source, and schema version `6` remain unchanged in this Restore round.

## Restore Foundation candidate

The internal Restore service accepts only a format-version-1 generation that is a validated direct child of the configured Backup root. Raw SQLite files, arbitrary/external paths, symlinks, live databases, Market Cache files, WAL/SHM sidecars, archives, and future schema versions are rejected before Permanent Store replacement. The selected Backup generation and manifest are never migrated or modified.

Before replacement, the service copies the closed validated candidate into an operation-owned staging file beside the live `aureus.sqlite`, recomputes its streaming byte count and SHA-256, and repeats read-only integrity, foreign-key, and schema validation. It then creates and validates an internal safety generation from the current actor-owned GRDB queue. A safety failure leaves the live queue and database unchanged.

`WealthStore` owns a finite `ready` / `restoring` / `recoveryRequired` maintenance state and a mutable actor-isolated queue. From queue close until a restored or rolled-back queue is rebound, the synchronous actor method contains no suspension point. It checkpoints the live Store, closes the queue, handles only the explicit live database and sidecar paths, and uses same-filesystem atomic replacement without deleting the current database first.

Current-schema candidates reopen without business-data rewriting. Supported legacy schema versions `1...5` run only through the existing `DatabaseMigrations.permanentMigrator()` after replacement; the Backup artifact itself remains untouched. Post-restore validation requires `quick_check`, zero foreign-key violations, permanent schema version `6`, all six existing migration identifiers, required permanent tables, reopen success, and continued reads through the same `WealthStore` actor.

Any open, migration, integrity, foreign-key, schema, or application-invariant failure after replacement triggers rollback from the validated safety generation through a separately revalidated same-filesystem staging file and atomic replacement. Successful rollback rebinds the original Store and returns typed `restoreFailedRollbackSucceeded`. If rollback itself fails, the actor enters `recoveryRequired`, returns typed `rollbackFailed`, retains the safety generation, and performs no automatic alternate-generation loop.

Successful Restore retains the safety generation and then restores valid-only retention to at most five generations. Failed Restore does not prune the safety generation required for recovery. Cleanup is limited to operation-owned, exact staging and sidecar paths whose ownership and parent are verified.

## Restore verification evidence

Final current-source evidence is rooted at `/private/tmp/Aureus-Stage11-RESTORE-FOUNDATION-01-xtAUHU`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Restore/Backup Unit | `PASS` | Exact suites `PermanentRestoreTests`, `PermanentBackupTests`, and `PersistenceTests`; `60` definitions / `64` dynamic executions; `64` passed, `0` failed, `0` skipped; shell exit `0`; complete `FocusedRestoreBackupUnit.xcresult`; summary/tests parser exits `0/0`; result interval `5.701 s` |
| Affected persistence regression | `PASS` | Exact suites `WealthPersistenceTests`, `LedgerPersistenceTests`, `DashboardPersistenceTests`, `PortfolioTerminalTests`, and `GoalPersistenceTests`; `65` definitions / `68` dynamic executions; `68` passed, `0` failed, `0` skipped; shell exit `0`; complete `AffectedPersistenceRegression.xcresult`; parser exits `0/0`; result interval `9.079 s` |
| Full `AureusTests` | `PASS` | `353` definitions / `390` dynamic executions; `390` passed, `0` failed, `0` skipped; shell exit `0`; complete `FullAureusTests.xcresult`; parser exits `0/0`; result interval `47.624 s` |
| Release Restore suite | `PASS` | `26` definitions / `30` dynamic executions; `30` passed, `0` failed, `0` skipped; shell exit `0`; complete `ReleaseRestorePerformance-Final.xcresult`; parser exits `0/0`; real workload emitted `STAGE11_RESTORE_PERF rows=10000 safety_backup_restore_validate_ms=63 migration_applied=0 provider_requests=0 cache_reads=0 credential_reads=0`; result interval `3.062 s` |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` deprecation warnings; complete `CleanDebugBuild.xcresult`; build parser exit `0`; result interval `20.964 s` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting.xcresult`; build parser exit `0`; result interval `30.261 s`; App and Runner strict codesign verification passed |
| UI tests | `NOT RUN — NOT AUTHORIZED IN RESTORE FOUNDATION ROUND` | Signed BFT is build evidence only and is not UI runtime evidence |

The initial Release-oriented build failed before test execution because default Release omitted testability; its complete exit-65 result is preserved and was not counted as PASS. The corrected equivalent Release product used command-line `ENABLE_TESTABILITY=YES` without changing Project settings. A subsequent method-level selector produced a complete 0-test/unknown result and likewise was not counted as PASS; the same frozen Release product then ran the complete `PermanentRestoreTests` suite, which entered the 10,000-row workload and produced the final evidence above. No business assertion retry, Provider operation, UI execution, or source adaptation was hidden.

## Restore provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Restore UI and Settings integration: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All Restore fixtures and databases are synthetic and isolated below the current `/private/tmp` evidence root. No Repository database, Backup generation, Restore staging file, safety database, Provider payload, Credential, or real financial record was created.

## Current candidate

The historical Restore candidate above was independently accepted by the Reviewer as `PASS`. Its safety-backup, same-filesystem atomic replacement, forward-migration, validation, rollback, and `recoveryRequired` contracts remain unchanged.

## Migration state classification

Permanent Store startup and explicit `WealthStore.migrate()` now use one migration-safety authority built from canonical `DatabaseMigrator` applied identifiers, their stored order, and `schema_metadata`:

- a genuinely fresh Store has no applied permanent migration and no unexplained business schema, creates no pre-migration Backup, and migrates to schema `6`;
- a current Store has all six identifiers in order and schema `6`, creates no Backup, and performs an idempotent no-op followed by validation;
- a recognized legacy Store has a strict non-empty v1...v5 identifier prefix and matching schema `1...5`;
- unknown identifiers, gaps, reorderings, future schema, metadata/schema mismatch, non-permanent metadata, unexplained schema-zero business state, and unsafe/symlink Store paths are typed rejections before migration.

## Production composition-root wiring

`AppDependencies.make` supplies the real `WealthStore` construction path with the selected `RuntimePaths.internalBackupDirectoryURL`, a normalized application version, UTC creation instant, random generation identity, and the existing permanent migrator. Temporary and Synthetic dependency graphs use their injected temporary Backup root. No `WealthStore` legacy migration path, including explicit `migrate()`, can silently bypass this gate. Restore candidate migration remains inside its already validated safety-rollback flow and is not wrapped in a duplicate pre-migration generation.

## Pre-migration Backup and failure boundaries

Each recognized v1...v5 Store creates exactly one consistent format-version-1 generation before any pending migration. The committed generation is revalidated for manifest, streaming SHA-256, byte count, SQLite integrity, foreign keys, original schema, and the exact original migration prefix. Its original synthetic records remain readable. Only after that gate passes does the unchanged `DatabaseMigrations.permanentMigrator()` run.

Backup creation, commit, validation, unsafe-root, collision, or filesystem failure prevents migrator invocation and leaves the live legacy Store unchanged. A migration transaction failure preserves the valid pre-migration generation and reports a finite availability state; no automatic Restore, alternate-generation selection, or loop is performed. A post-migration validation failure likewise retains the pre-migration generation and does not report the Store ready.

## Shared post-migration validation

Backup, Restore, and Migration Safety share one authoritative permanent-database validator. Current-schema validation requires `PRAGMA quick_check == ok`, zero foreign-key violations, schema version `6`, all six identifiers in order, all required permanent tables, successful reads, and no `REAL` financial-authority column. `DatabaseMigrations.swift`, its six identifiers, schema version `6`, Backup manifest fields and retention semantics, and Restore ordering/rollback/recovery behavior remain unchanged.

## Retention and idempotence

Only fully committed and validated generations participate in valid-only five-generation retention. Invalid or unknown siblings remain uncounted and undeleted. A first legacy open creates one generation; reopening or explicitly migrating the now-current Store creates none. Fresh and repeated current Store operations likewise create none. Concurrent construction is serialized so it cannot create a second pre-migration generation.

## Migration Safety verification evidence

Final current-source evidence is rooted at `/private/tmp/Aureus-Stage11-MIGRATION-SAFETY-01-jSZ2Ys`.

| Verification | Result | Evidence |
|---|---|---|
| Focused migration/Backup/Restore Unit | `PASS` | Exact suites `PermanentMigrationSafetyTests`, `PermanentBackupTests`, `PermanentRestoreTests`, `PersistenceTests`, and `PortfolioTerminalTests`; `108` definitions / `116` dynamic executions; `116` passed, `0` failed, `0` skipped; shell exit `0`; complete `FocusedMigrationBackupRestoreUnit-Final.xcresult`; summary/tests parser exits `0/0`; result interval `17.835 s` |
| Affected persistence regression | `PASS` | Exact eight suites; `146` definitions / `157` dynamic executions; `157` passed, `0` failed, `0` skipped; shell exit `0`; complete `AffectedPersistenceRegression.xcresult`; parser exits `0/0`; result interval `13.563 s` |
| Full `AureusTests` | `PASS` | `380` definitions / `421` dynamic executions; `421` passed, `0` failed, `0` skipped; shell exit `0`; complete `FullAureusTests.xcresult`; parser exits `0/0`; result interval `49.070 s` |
| Release migration-safety suite | `PASS` | `27` definitions / `31` dynamic executions; `31` passed, `0` failed, `0` skipped; shell exit `0`; complete `ReleaseMigrationSafetyPerformance.xcresult`; parser exits `0/0`; the 10,000-row workload emitted `STAGE11_MIGRATION_SAFETY_PERF rows=10000 start_schema=1 backup_migrate_validate_ms=35 provider_requests=0 cache_reads=0 credential_reads=0` |
| Clean Debug arm64 Build | `PASS` | shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` deprecation warnings; complete `CleanDebugBuild.xcresult`; build parser exit `0`; result interval `20.253 s` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting.xcresult`; build parser exit `0`; result interval `30.446 s`; App and Runner strict codesign verification passed |
| UI tests | `NOT RUN — NOT AUTHORIZED IN MIGRATION SAFETY ROUND` | BFT is build evidence only; Settings Backup/Restore UI, Existing focused UI, and full `AureusUITests` were not executed |

The initial signed focused Unit result is preserved as an infrastructure failure: its complete bundle discovered all `108` definitions but App Sandbox denied the known `/private/tmp/AureusTests/<UUID>` test roots. The authorized stable unsigned isolated-host route then exposed two direct test-adaptation failures, which were retained; final current source reran the affected Gate and passed. Sandbox TestReport-cache parser attempts returned `64`; the same complete bundles parsed read-only under standard Xcode permissions with exit `0`. No parser recovery reran tests and no failed result was counted as PASS.

## Migration Safety provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Settings UI and external file flow: `NOT RUN / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All migration fixtures and databases are synthetic and isolated below the current `/private/tmp` evidence root. No Repository database, Backup generation, migration staging file, Provider payload, Credential, or real financial record was created.

## Current Migration Safety candidate

**Stage 11 Migration Safety Candidate — Awaiting Reviewer Gate**

## Restore confirmation native Accessibility round

Prompt 11-RESTORE-CONFIRMATION-AX-01 replaced only the Restore-specific system-managed `confirmationDialog` with an application-owned native SwiftUI sheet. The existing Delete Key, Disconnect, and Reset Market Cache confirmation dialogs remain unchanged. The sheet exposes four independent visible nodes: `settings.dataLifecycle.restore.dialog.heading`, `settings.dataLifecycle.restore.dialog.warning`, `settings.dataLifecycle.restore.cancel`, and `settings.dataLifecycle.restore.confirm`. The warning's visible text, Accessibility label, and UI-test exact string are identical. Cancel only dismisses the sheet; Confirm dismisses it and invokes the existing confirmed Restore path exactly once. No Foundation, lifecycle model, App wiring, Project, Package, Migration, Entitlement, external-file flow, or Provider path changed.

### Current-round verification

Current evidence is rooted at `/private/tmp/Aureus-Stage11-RESTORE-CONFIRMATION-AX-01-Gn6kSi`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted current-source evidence remains `101` definitions / `109` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted current-source evidence remains `394` definitions / `435` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT BACKUP/RESTORE/MIGRATION-SAFETY SOURCE-HASH VERIFICATION` | Backup, Restore, and Migration Safety authorities remained byte-identical |
| Clean Debug arm64 Build | `PASS` | Final shell exit `0`; status succeeded; errors `0`; four pre-existing `PortfolioView` warnings and no new warning; complete `CleanDebugBuild-Final.xcresult`; `Info.plist` present; build parser exit `0`; result interval `33.283 s` |
| Fresh signed arm64 BFT | `PASS` | shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four pre-existing warnings; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; result interval `34.694 s`; App and Runner strict codesign verification passed |
| Targeted Settings UI | `PASS` | Exact selector `testStage11SettingsInternalBackupRestoreLifecycleAndIsolation`; `1/1` definition/execution and one business execution; `1` passed / `0` failed / `0` skipped; shell exit `0`; complete `Stage11RestoreConfirmationTargetedUI.xcresult`; `Info.plist` present; initial sandbox TestReport parser exits `64/64`, same-bundle standard-permission parser exits `0/0`; method duration `107.337 s` |
| Existing focused regression | `INCOMPLETE RESULT — NOT PASS` | Exact ten selectors used the same frozen product. The command session was externally interrupted and `ExistingFocusedRegression.xcresult` contains only `Data`/`Staging` without `Info.plist`; before interruption, complete business assertions failed in `testLedgerDynamicCashFlowTransferInvestmentEditAndDelete` at line `1968`, `testLedgerNativeCSVImportPreviewConfirmationAndExport` at line `2439`, and `testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation` at line `235`. Because completed business failures exist, the result is ineligible for incomplete-result re-observation and is not reported as a canonical aggregate PASS or FAIL count. |
| Full `AureusUITests` | `NOT RUN` | Existing focused did not pass; ordered Gate prerequisite was not met |

The targeted runtime proved the exact heading and warning, the independently enabled Cancel and Confirm controls, Cancel dismissal of all four sheet nodes with inventory still at one and status still Ready, re-open and fresh element queries, one Confirm click, inventory growth to two valid generations, `Restore Completed`, absence of recovery-required/error state, disappearance of the probe Goal, restoration of both original Synthetic Goals, Settings reconstruction, and Production root isolation. Provider, Credential, Keychain, and Market Cache operations remained zero in the test's tail.

The initial Clean command used conflicting architecture specification and exited `70` before compilation; that configuration artifact is preserved as `CleanDebugBuild.xcresult` and is not counted as PASS. The corrected final Clean and BFT used final source. UI infrastructure retry, targeted business repair/retry, and parser-triggered test retry were all `0`. The externally interrupted Existing focused result consumed no re-observation because its completed business failures make it ineligible under the prompt.

### Current-round provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External file flow: `NOT RUN`
- Stages 12–14: `NO-GO`

No Restore, Backup, safety, database, DerivedData, or xcresult artifact was written into the Repository. The remaining Gate boundary is the incomplete and business-failing Existing focused regression; Full UI is therefore not current-round evidence.

## Current Restore confirmation round status

**Stage 11-RESTORE-CONFIRMATION-AX-01 PARTIAL — Awaiting Reviewer Gate**
