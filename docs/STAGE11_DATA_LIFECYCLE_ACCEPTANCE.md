# Stage 11 Data Lifecycle Acceptance

## Status

**Stage 11 External Backup Export UI Runtime Candidate — Awaiting Reviewer Gate**

## External Backup Export Foundation round

Prompt 11-EXTERNAL-BACKUP-EXPORT-FOUNDATION-01 adds an explicitly invoked, no-UI external export foundation. It accepts only a generation that passes the existing configured internal Backup-root validation, then exports the byte-identical `aureus.sqlite` and `manifest.json` pair into an operation-scoped caller-injected destination. The destination must be an existing writable absolute file directory, must resolve without symbolic links, and must not overlap the Repository, internal Backup root, Permanent database location, or Market Cache location. The service neither stores the destination nor creates a security-scoped bookmark.

Export uses a unique direct-child staging directory, copies only the two generation files, runs the authoritative streaming SHA-256, byte-count, SQLite query-only quick-check, foreign-key, schema, manifest, file-type, symlink, and exact-artifact validation, then commits by same-filesystem atomic move and validates the committed generation again. Collision never overwrites. Failure cleanup is limited to the operation-owned staging directory; unrelated destination siblings and existing external generations remain untouched. External retention/pruning is not implemented or run, while internal five-generation retention and internal Restore's direct-child root restriction remain unchanged.

The exported artifact is not a ZIP, compressed archive, encrypted wrapper, or new manifest format. It contains no third metadata file and makes no application-layer encryption claim. Settings external file UI, `NSOpenPanel`/`NSSavePanel`, security-scoped access/bookmarks, destination persistence, external Restore/import, raw SQLite import, cloud export, scheduled export, and Stages 12–14 remain outside this round.

Current evidence root: `/private/tmp/Aureus-Stage11-EXTERNAL-BACKUP-EXPORT-FOUNDATION-01-1ngtiQ`.

| Verification | Result | Evidence |
|---|---|---|
| Historical UI/build evidence | `NOT RUN — ACCEPTED HISTORICAL CURRENT-SOURCE EVIDENCE` | Read-only canonical parsing confirmed prior Native CSV `1/1`, Existing focused `10/10`, and full `AureusUITests` `16/16` PASS plus successful Clean Build/BFT; these results were not rerun or counted as this round's UI evidence |
| Initial signed Focused Unit | `INFRASTRUCTURE FAILURE` | Shell exit `65`; complete `FocusedUnit-Signed.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; `57` definitions / `59` executions; App Sandbox denied the known `/private/tmp/AureusTests/<UUID>` roots, so `0` business tests passed and this result is not a business PASS |
| Final Focused Unit | `PASS` | Exact suites `PermanentBackupExportTests` and `PermanentBackupTests`; stable unsigned isolated-host route; shell exit `0`; `57` definitions / `59` dynamic executions; `57` passed / `0` failed / `0` skipped; result interval `9.238 s`; complete `FocusedUnit-Unsigned-Final3.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Affected regression | `PASS` | Exact suites `PermanentBackupExportTests`, `PermanentBackupTests`, `PermanentRestoreTests`, `PermanentMigrationSafetyTests`, `SettingsDataLifecycleTests`, and `PersistenceTests`; shell exit `0`; `130` definitions / `140` dynamic executions; `130/0/0`; result interval `42.203 s`; complete `AffectedRegression-Unsigned.xcresult`; `Info.plist` present; parser exits `0/0` |
| Full Unit | `PASS` | Exact selector `AureusTests`; shell exit `0`; `423` definitions / `466` dynamic executions; `423/0/0`; result interval `84.172 s`; complete `FullAureusTests-Unsigned.xcresult`; `Info.plist` present; parser exits `0/0` |
| Release Export suite | `PASS` | Exact suite `PermanentBackupExportTests`; Release-oriented testability-enabled isolated host; shell exit `0`; `29` definitions / `31` dynamic executions; `29/0/0`; complete `ReleaseExportPerformance-Unsigned.xcresult`; `Info.plist` present; parser exits `0/0`; total result interval `132.010 s`, including build |
| Release workload | `PASS` | `STAGE11_EXTERNAL_BACKUP_EXPORT_PERF rows=10000 export_validate_ms=25 exported_files=2 provider_requests=0 cache_reads=0 credential_reads=0` |
| Clean Debug arm64 Build | `PASS` | Shell exit `0`; status succeeded; errors `0`; four existing `PortfolioView` deprecation warnings; duration `29.344 s`; complete `CleanDebugBuild.xcresult`; `Info.plist` present; build parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings; duration `39.588 s`; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; App and Runner strict codesign exits `0` |
| UI tests | `NOT RUN — NOT AUTHORIZED IN EXTERNAL BACKUP EXPORT FOUNDATION ROUND` | BFT and the accepted prior `16/16` UI bundle are not this round's UI runtime execution |

The stable unsigned route was authorized only after the complete signed result proved the established App Sandbox test-root policy. Three preserved implementation-diagnostic bundles then exposed, in order, destination canonicalization, staging-name validation, and Market Cache parent protection defects. Each was corrected only in the authorized Export/Backup/Test paths. The final current source was rerun through every required Gate; no failed bundle was merged with a later result or reported as PASS. No parser-triggered test retry occurred.

### External Export provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- Settings external file UI: `NOT RUN`
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

## Current External Backup Export Foundation status

**Stage 11 External Backup Export Foundation Candidate — Awaiting Reviewer Gate**

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

## Existing UI independent re-observation round

Prompt 11-EXISTING-UI-REOBSERVATION-01 made no Product, Test, Project, Package, Migration, Entitlement, Target, Scheme, or fixture change. It reused the exact frozen current-source signed UI product after all required source and product hashes matched. The prior `ExistingFocusedRegression.xcresult` remains preserved and classified as `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED`: it has no `Info.plist`, no canonical definitions/executions, and no canonical passed/failed/skipped aggregate. Its console observations were not combined into a result or used as a business-failure count.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-EXISTING-UI-REOBSERVATION-01-APiInh`.

| Verification | Result | Evidence |
|---|---|---|
| Targeted Settings UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | The accepted complete targeted bundle and the frozen App, Runner, UI Test executable, and xctestrun identities matched |
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `101` definitions / `109` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `394` definitions / `435` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT BACKUP/RESTORE/MIGRATION-SAFETY SOURCE-HASH VERIFICATION` | Backup, Restore, and Migration Safety authorities remained byte-identical |
| Clean Build | `NOT RUN — ACCEPTED CURRENT-SOURCE BUILD AFTER EXACT SOURCE/PRODUCT VERIFICATION` | No rebuild was authorized or performed |
| BFT | `NOT RUN — REUSED EXACT FROZEN CURRENT-SOURCE PRODUCT` | No rebuild or re-sign was authorized or performed |
| Ledger Dynamic independent selector | `PASS` | Exact selector `testLedgerDynamicCashFlowTransferInvestmentEditAndDelete`; shell exit `0`; `1/1` definition/execution and one business execution; `1` passed / `0` failed / `0` skipped; complete `LedgerDynamic.xcresult`; `Info.plist` present; initial sandbox parser exits `64/64`, same-bundle standard-permission parser exits `0/0`; method duration `229.752 s`; result interval `248.094 s` |
| Native CSV independent selector | `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `1` during sandboxed Xcode log/destination initialization before the business method; the new `NativeCSV.xcresult` contains only `Data`/`Staging`, has no `Info.plist`, and cannot provide a canonical result; same-bundle summary/tests parser exits were `64/64` because `Info.plist` is absent. It did not satisfy the complete zero-business bootstrap retry condition or the externally interrupted incomplete-result re-observation condition, so it was not rerun. |
| Portfolio independent selector | `PASS` | Exact selector `testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation`; shell exit `0`; `1/1` definition/execution and one business execution; `1` passed / `0` failed / `0` skipped; complete `Portfolio.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; method duration `71.099 s`; result interval `72.300 s` |
| Diagnostic matrix | `PARTIAL` | Ledger Dynamic and Portfolio independently passed, but Native CSV did not produce a canonical result; independent results were not combined into a false aggregate |
| Existing focused regression | `NOT RUN` | Gate A did not close; ordered prerequisite was not met |
| Full `AureusUITests` | `NOT RUN` | Existing focused `10/10` was not run and could not satisfy the prerequisite |

No business retry, business repair, UI infrastructure retry, or incomplete-result re-observation was used. The Native CSV invocation is preserved as an incomplete infrastructure result and is not represented as a business failure or PASS. Provider requests remained `NOT RUN`; Twelve Data operations, Frankfurter live operations, Provider transports, Credential reads, Keychain metadata reads, and Market Cache reads/mutations remained `0`. Twelve Data persistent writes remain `Disabled`, Provider retention rights remain `BLOCKED`, external file implementation remains `NOT RUN`, and Stages 12–14 remain `NO-GO`.

## Current existing UI re-observation status

**Stage 11-EXISTING-UI-REOBSERVATION-01 PARTIAL — Awaiting Reviewer Gate**

## Native CSV standard-permission closure round

Prompt 11-NATIVE-CSV-UI-CLOSURE-01 changed no Product, Unit Test, UI Test, Project, Package, Migration, Entitlement, Target, Scheme, fixture, Backup, Restore, or Migration Safety behavior. The round used the exact frozen signed current-source App, Runner, UI Test executable, and xctestrun. Unlike the preceding sandboxed attempt, the new invocation started directly in the explicitly authorized standard Xcode permission environment.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-NATIVE-CSV-UI-CLOSURE-01-Yey8Vo`.

| Verification | Result | Evidence |
|---|---|---|
| Settings lifecycle targeted UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Complete historical result remained current after exact source and product verification |
| Ledger Dynamic independent UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Complete historical result remained current |
| Portfolio independent UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Complete historical result remained current |
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `101` definitions / `109` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT MODEL/FOUNDATION/UNIT SOURCE-HASH VERIFICATION` | Accepted `394` definitions / `435` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT BACKUP/RESTORE/MIGRATION-SAFETY SOURCE-HASH VERIFICATION` | Frozen authorities remained byte-identical |
| Clean Build | `NOT RUN — ACCEPTED CURRENT-SOURCE BUILD AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Rebuild was not authorized or performed |
| Signed BFT | `NOT RUN — REUSED EXACT FROZEN CURRENT-SOURCE PRODUCT` | Rebuild and re-sign were not authorized or performed |
| Native CSV Gate | `FAIL` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `65`; canonical definitions/executions `1/1`; one business execution; passed/failed/skipped `0/1/0`; method duration `64.016 s`; result interval `76.266 s`; complete `NativeCSV-Standard.xcresult`; `Info.plist` present; standard-permission summary/tests parser exits `0/0`; failure source `AureusUITests.swift:2482` |
| Existing focused regression | `NOT RUN` | Native CSV Gate did not pass; ordered prerequisite was not met |
| Full `AureusUITests` | `NOT RUN` | Existing focused `10/10` was not run and could not satisfy the prerequisite |

The Native CSV business method successfully entered the existing synthetic file-selection flow, produced and verified the import preview, confirmed the import, verified the imported synthetic expense, invoked export, and opened the native Save Panel. It then produced the complete assertion failure `Save Panel did not expose its current filename field`. This is a canonical business failure rather than a Runner, Automation, testmanagerd, bootstrap, discovery, or parser failure. No business repair, business retry, infrastructure retry, or incomplete-result re-observation was authorized or used.

The preceding sandboxed Native CSV directory remains preserved as `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED`. Its short staging diagnostics identify a pre-business `com.apple.testmanagerd.control` sandbox restriction and Runner PID `0`; it was not modified, completed, deleted, combined, or substituted for the current complete result.

Provider requests remained `NOT RUN`; Twelve Data operations, Frankfurter live operations, Provider transports, Credential reads, Keychain metadata reads, and Market Cache reads/mutations remained `0`. Twelve Data persistent writes remain `Disabled`, Provider retention rights remain `BLOCKED`, external file implementation remains `NOT RUN`, and Stages 12–14 remain `NO-GO`.

## Current Native CSV closure status

**Stage 11-NATIVE-CSV-UI-CLOSURE-01 PARTIAL — Awaiting Reviewer Gate**

## Native CSV public-default-filename Save Panel round

Prompt 11-NATIVE-CSV-SAVE-PANEL-01 changed only the authorized UI test before formal Gate execution. The repaired Native CSV helper preserves the Product's public `defaultFilename: "Aureus-Ledger-V1"` contract, verifies that `Aureus-Ledger-V1.csv` does not exist before export, follows the existing Go To Folder flow, re-queries the active Save Panel after that sheet closes, requires the current `OKButton` to exist and be enabled, clicks it exactly once, waits for the Save Panel to disappear, and verifies the exact exported file. Product and Test references to Apple's internal `saveAsNameTextField` are now zero. No Product Swift, Unit test, Project, Package, Migration, Entitlement, Target, Scheme, fixture, Backup, Restore, Migration Safety, Settings, Goals, Portfolio, Markets, or Analytics behavior changed.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-NATIVE-CSV-SAVE-PANEL-01-R7vbvB`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Domain, Persistence, FeatureModel, and Unit sources remained frozen |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted current-source Unit evidence remained applicable |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Backup, Restore, and Migration Safety authorities remained frozen |
| Clean Debug arm64 Build | `PASS` | Shell exit `0`; result `Succeeded`; errors `0`; four existing `PortfolioView` deprecation warnings; duration `31.783 s`; complete `CleanDebugBuild.xcresult`; `Info.plist` present; final build parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings; duration `34.641 s`; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; App and Runner strict codesign exit `0` |
| Native CSV targeted UI | `PASS` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `0`; definitions/executions `1/1`; one business execution; passed/failed/skipped `1/0/0`; method duration `55.340 s`; result interval `63.758 s`; complete `NativeCSVTargetedUI.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Existing focused regression | `PASS` | Ten exact selectors in one serial invocation; shell exit `0`; definitions/executions `10/10`; ten business executions; passed/failed/skipped `10/0/0`; result interval `1033.251 s`; complete `ExistingFocusedRegression.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Full `AureusUITests` | `PASS` | Exact selector `AureusUITests`; shell exit `0`; definitions/executions `16/16`; sixteen business executions; passed/failed/skipped `16/0/0`; all sixteen canonical Test Case nodes `Passed`; method aggregate `1165.334 s`; result interval `1178.296 s`; complete `FullAureusUITests.xcresult`; `Info.plist` present; tests parser exit `0`; summary parser initial concurrent-cache exit `64`, same-bundle sequential read-only reparse exit `0` |

All UI invocations used one frozen signed product with parallel testing disabled and maximum concurrent destination `1`. The final product identities are App `6af5d12fd5c49c2de82c6bc0a09024efae07a4d1c223fa4fb3ffff38bda94d66`, Runner `253d63c1ca59775d09a518862becf045df5decc3d7a8e78034807575aece58b8`, UI Test executable `1c57bd87815675a7bccd14f8af4ff73db9edb293dd7b6022475aae6ec1e6b98c`, and xctestrun `6c48af20976451375d9329674d1ad2dc9b0f0c2051931f1f245bdb7c62dc7c43`. Their hashes remained unchanged across all three UI Gates. The same-bundle parser re-read did not rerun any test.

The preceding complete Native CSV Save Panel assertion failure and the earlier incomplete sandboxed Native CSV result remain historical facts; neither was modified, merged, downgraded, or substituted. This round used exactly one pre-Gate UI-test repair. After formal Gate execution began, business repair, business retry, infrastructure retry, and incomplete-result re-observation were all `0`.

Provider requests remained `NOT RUN`; Twelve Data operations, Frankfurter operations, Provider transports, Credential reads, Keychain metadata reads, and Market Cache reads/mutations remained `0`. Twelve Data persistent writes remain `Disabled`, Provider retention rights remain `BLOCKED`, external file implementation remains `NOT RUN`, and Stages 12–14 remain `NO-GO`.

## Current Data Lifecycle UI runtime status

**Stage 11 Data Lifecycle UI Runtime Candidate — Awaiting Reviewer Gate**

## Settings external Backup Export UI round

Prompt 11-SETTINGS-EXTERNAL-BACKUP-EXPORT-UI-01 connects the accepted no-UI external Export foundation to the existing Settings data-lifecycle model and view. The Production composition root supplies the real Permanent, internal Backup, and Market Cache paths without deriving a source-checkout path. Settings uses SwiftUI `.fileImporter` with `.folder`, starts security-scoped access immediately after selection, holds it across the asynchronous export, and stops it on every completed path. The model retains no destination URL, filename history, or bookmark. The visible External Backup warning and its AX label are identical; the heading, warning, Export button, and result are independent nodes. External Restore/import, scheduling, cloud export, external retention, ZIP/compression, and application-layer encryption remain unimplemented.

Current evidence is rooted at `/private/tmp/Aureus-Stage11-SETTINGS-EXTERNAL-BACKUP-EXPORT-UI-01-ayEbIL`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `PASS` | Final-source stable unsigned isolated-host route; exact suites `SettingsDataLifecycleTests`, `PermanentBackupExportTests`, and `PermanentBackupTests`; shell exit `0`; `77` definitions / `79` dynamic executions; `77` passed / `0` failed / `0` skipped; complete `FocusedUnit-Final.xcresult`; `Info.plist` present; summary/tests parsers `0/0`; result interval `41.920 s` |
| Affected regression | `PASS` | Six exact suites; shell exit `0`; `136` definitions / `146` dynamic executions; `136/0/0`; complete `AffectedRegression-Final.xcresult`; `Info.plist` present; parsers `0/0`; result interval `7.435 s` |
| Full Unit | `PASS` | Exact selector `AureusTests`; shell exit `0`; `429` definitions / `472` dynamic executions; `429/0/0`; complete `FullAureusTests-Final.xcresult`; `Info.plist` present; parsers `0/0`; result interval `50.519 s` |
| Release External Export | `PASS` | Exact suite `PermanentBackupExportTests`; shell exit `0`; `29` definitions / `31` dynamic executions; `29/0/0`; complete `ReleaseExternalExportPerformance-Final.xcresult`; `Info.plist` present; parsers `0/0`; actual line `STAGE11_EXTERNAL_BACKUP_EXPORT_PERF rows=10000 export_validate_ms=26 exported_files=2 provider_requests=0 cache_reads=0 credential_reads=0` |
| Clean Debug arm64 Build | `PASS` | Shell exit `0`; status succeeded; errors `0`; four existing `PortfolioView` warnings and no new warning; complete `CleanDebugBuild-Final.xcresult`; `Info.plist` present; build parser `0`; duration `28.487 s` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings; complete `BuildForTesting-Final.xcresult`; `Info.plist` present; build parser `0`; duration `34.369 s`; App/Runner strict codesign exit `0` |
| Targeted Settings External Export UI, initial | `FAIL` | Exact selector `testStage11SettingsExternalBackupExportToUserSelectedFolderAndIsolation`; shell exit `65`; definitions/executions `1/1`; one business execution; `0/1/0`; complete `TargetedExternalExportUI.xcresult`; `Info.plist` present; parsers `0/0`; failure at old source line `1550` after the native directory panel opened but the panel-scoped typed `Cancel` query did not match |
| Targeted Settings External Export UI, final | `FAIL` | Same exact selector on rebuilt final source/product; shell exit `65`; definitions/executions `1/1`; one business execution; `0/1/0`; complete `TargetedExternalExportUI-Final.xcresult`; `Info.plist` present; parsers `0/0`; result interval `50.953 s`; failure `AureusUITests.swift:1549` because the native panel's public visible-label `Cancel` control remained unqueryable through a type-independent application-wide query |
| Existing focused regression | `NOT RUN` | Gate G did not pass; the ordered prerequisite for the eleven exact selectors was not met |
| Full `AureusUITests` | `NOT RUN` | Existing focused `11/11` was not run and could not satisfy the prerequisite for current inventory `17/17` |

The first signed Focused Unit bundle is retained as an infrastructure result: it discovered all `77` definitions, but the known App Sandbox policy denied `/private/tmp/AureusTests/<UUID>` before `57` Backup/Export tests could use their synthetic roots. The authorized stable unsigned isolated-host route then produced the complete final-source Unit evidence above. This route is infrastructure handling, not a business retry. Gate G used exactly one authorized direct UI-test lifecycle repair, two business executions total, no infrastructure retry, and no incomplete-result re-observation. The final failure occurred before Cancel, Choose, artifact creation, reconstruction, and Production-isolation tail assertions; those runtime portions remain `NOT VERIFIED` in this round. Historical external Export foundation and prior `16/16` UI evidence were not substituted for the newly affected UI Gate.

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
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Scheduling/cloud export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

All Unit, performance, build, BFT, and UI artifacts remain below the current `/private/tmp` evidence root. No database, external generation, security-scoped bookmark, DerivedData, or xcresult was written into the Repository.

## Current Settings external Export UI status

**Stage 11-SETTINGS-EXTERNAL-BACKUP-EXPORT-UI-01 PARTIAL — Awaiting Reviewer Gate**

## External Backup Export panel Escape-cancel round

Prompt 11-EXTERNAL-BACKUP-EXPORT-PANEL-CANCEL-01 changes only `AureusUITests.swift` before formal execution. The targeted flow no longer queries the system-owned directory panel `Cancel` node by identifier, label, element type, count, enabled, hittable, or click state. It proves that the native panel appears, sends exactly one public macOS/XCTest `Escape` action, waits for dismissal, and verifies zero Cancel side effects before reopening a new panel and retaining the existing public `PathTextField` / `OKButton` success path. Production Swift, Unit tests, Project, Package, migrations, entitlements, targets, scheme, and synthetic fixtures remain unchanged.

Current evidence root: `/private/tmp/Aureus-Stage11-EXTERNAL-BACKUP-EXPORT-PANEL-CANCEL-01-KuDiH0`.

| Verification | Result | Evidence |
|---|---|---|
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT PRODUCTION/MODEL/UNIT SOURCE-HASH VERIFICATION` | Accepted `77` definitions / `79` dynamic executions PASS |
| Affected regression | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `136` definitions / `146` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `429` definitions / `472` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `29` definitions / `31` dynamic executions PASS; 10,000-row export/validate workload `26 ms` |
| Clean Debug arm64 Build, initial | `INFRASTRUCTURE FAILURE` | Shell exit `74`; GRDB checkout's SQLiteLib submodule fetch failed with a transient TLS transport error before source compilation; complete `CleanDebugBuild.xcresult`; `Info.plist` present; not counted as a source/build PASS |
| Clean Debug arm64 Build, infrastructure retry | `PASS` | Shell exit `0`; status `succeeded`; errors `0`; four existing `PortfolioView` deprecation warnings and no new warning; duration `27.136 s`; complete `CleanDebugBuild-InfraRetry.xcresult`; `Info.plist` present; build parser exit `0` |
| Fresh signed arm64 BFT | `PASS` | Shell exit `0`; `TEST BUILD SUCCEEDED`; errors `0`; four existing warnings and no new warning; duration `33.126 s`; complete `BuildForTesting.xcresult`; `Info.plist` present; build parser exit `0`; App/Runner strict codesign exits `0` |
| Gate G targeted External Export UI | `PASS` | Exact selector `testStage11SettingsExternalBackupExportToUserSelectedFolderAndIsolation`; shell exit `0`; definitions/executions `1/1`; one business execution; passed/failed/skipped `1/0/0`; method duration `85.288 s`; result interval `93.639 s`; complete `TargetedExternalExportUI.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Gate H Existing focused regression | `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED` | One serial invocation requested all eleven exact selectors. The command session was externally interrupted after completed business failures at current-source `AureusUITests.swift:2160` (Ledger Dynamic matching snapshot), `AureusUITests.swift:2679` (Native CSV Save Panel export state), and `AureusUITests.swift:235` (Portfolio summary name). Accurate xcodebuild/App/Runner processes then measured `0`; `ExistingFocusedRegression.xcresult` has no `Info.plist`; no canonical definitions/executions or passed/failed/skipped aggregate exists; summary/tests parsers exit `64/64`; no re-observation is authorized after completed business assertions |
| Gate I full `AureusUITests` | `NOT RUN` | Gate H did not produce the required canonical `11/11 PASS`; current inventory `17/17` was not executed |

Gate G formally proves the complete Cancel and success branches: Cancel leaves the synthetic destination empty, internal inventory at one valid generation, selection usable, status `Ready`, and result/error/recovery/safety/artifact state absent. The subsequent success path completes security-scoped External Export, exposes `External Backup Export Completed`, produces one ordinary non-symlink generation containing only ordinary non-symlink `aureus.sqlite` and `manifest.json`, validates manifest format `1`, schema `6`, and byte count, preserves internal inventory without a safety generation, and passes navigation reconstruction and Production isolation through the Provider-zero tail.

The source file `SettingsDataLifecycleTests.swift` remained frozen at the complete SHA-256 `c1f6d3b7b341e908c0a0445180e785509ba178ed46fbcff239ba41769653dcbf`. Gate G used one targeted business execution and no repair or business retry. Gate H was not rerun, repaired, or combined; the globally authorized incomplete-result re-observation was not used because complete business assertions already existed. Gate I remained `NOT RUN`.

### Escape-cancel round provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Scheduling/cloud export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

## Current External Backup Export UI runtime status

**Stage 11-EXTERNAL-BACKUP-EXPORT-PANEL-CANCEL-01 PARTIAL — Awaiting Reviewer Gate**

## Existing UI diagnostic closure round

Prompt 11-EXISTING-UI-DIAGNOSTIC-CLOSURE-02 是零源码修改、零重建、零重签名的 evidence-only round。修改前全部规定 Source Identity 精确匹配；测试前的普通文件系统 inventory 包含 `114` 个 ordinary files，并显式排除 `.git/**`、`.secrets/**` 与 `default.profraw` payload。三项独立诊断、Existing focused 与 Full UI 全部串行复用同一个 frozen signed product。上一轮缺少 `Info.plist` 的 `ExistingFocusedRegression.xcresult` 保持 `INCOMPLETE RESULT — NOT PASS / NOT VERIFIED`，其三条 console assertion 线索未被合并或转换成 canonical aggregate。

Current evidence root: `/private/tmp/Aureus-Stage11-EXISTING-UI-DIAGNOSTIC-CLOSURE-02-uRH4fF`.

| Verification | Result | Evidence |
|---|---|---|
| External Export Targeted UI | `NOT RUN — ACCEPTED CURRENT-SOURCE 1/1 PASS AFTER EXACT SOURCE/PRODUCT VERIFICATION` | Accepted bundle `TargetedExternalExportUI.xcresult`; `Info.plist` present; definitions/executions `1/1`; `1/0/0`; canonical result `Passed`; summary/tests parser exits `0/0` |
| Focused Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `77` definitions / `79` dynamic executions PASS |
| Affected Unit Regression | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `136` definitions / `146` dynamic executions PASS |
| Full Unit | `NOT RUN — INHERITED AFTER EXACT SOURCE-HASH VERIFICATION` | Accepted `429` definitions / `472` dynamic executions PASS |
| Performance | `NOT RUN — INHERITED AFTER EXACT FOUNDATION SOURCE-HASH VERIFICATION` | Accepted `29` definitions / `31` dynamic executions PASS; real 10,000-row export/validate workload `26 ms` |
| Clean Build | `NOT RUN — ACCEPTED CURRENT-SOURCE BUILD AFTER EXACT SOURCE/PRODUCT VERIFICATION` | No build was authorized or performed |
| BFT | `NOT RUN — REUSED EXACT FROZEN CURRENT-SOURCE SIGNED PRODUCT` | No rebuild or re-sign was authorized or performed |
| Ledger Dynamic diagnostic | `PASS` | Exact selector `testLedgerDynamicCashFlowTransferInvestmentEditAndDelete`; shell exit `0`; definitions/executions `1/1`; one business execution; `1/0/0`; method duration `230.696 s`; result interval `243.204 s`; complete `LedgerDynamicDiagnostic.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; picker matching-snapshot failure did not recur |
| Native CSV diagnostic | `PASS` | Exact selector `testLedgerNativeCSVImportPreviewConfirmationAndExport`; shell exit `0`; definitions/executions `1/1`; one business execution; `1/0/0`; method duration `52.287 s`; result interval `54.157 s`; complete `NativeCSVDiagnostic.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; import, preview, confirmation, Save Panel, `OKButton`, exact default export, and Ledger Error absence passed |
| Portfolio diagnostic | `PASS` | Exact selector `testStage8PortfolioSyntheticCRUDHoldingsSnapshotAndIsolation`; shell exit `0`; definitions/executions `1/1`; one business execution; `1/0/0`; method duration `71.760 s`; result interval `72.916 s`; complete `PortfolioDiagnostic.xcresult`; `Info.plist` present; summary/tests parser exits `0/0`; summary-name, ordering, holdings/snapshot, reload/delete, and Production isolation passed |
| Diagnostic matrix | `PASS` | 三项均各自形成独立完整 `1/1 PASS`；未将三个 bundle相加成伪造 aggregate |
| Existing focused regression | `PASS` | 十一个 exact selectors在单次 serial invocation中执行；shell exit `0`; definitions/executions `11/11`; business executions `11`; passed/failed/skipped `11/0/0`; canonical result `Passed`; result interval `1109.470 s`; complete `ExistingFocusedRegression.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |
| Full `AureusUITests` | `PASS` | Exact selector `AureusUITests`; shell exit `0`; definitions/executions `17/17`; business executions `17`; passed/failed/skipped `17/0/0`; canonical result `Passed`; all `17` Test Case nodes `Passed`; method aggregate `1262.523 s`; result interval `1274.760 s`; complete `FullAureusUITests.xcresult`; `Info.plist` present; summary/tests parser exits `0/0` |

三项历史 console 线索均未在独立诊断、单次 Existing focused 聚合或 Full UI 中复现。所有 invocation 使用 `-parallel-testing-enabled NO`、maximum concurrent destination `1` 与同一个 frozen product：App SHA-256 `57de6848ec47b9df768adf3a2fab6af0dd48e5935b7701ccbdadf00b7e850a71`，Runner `a0a8835f2b59a28602d6b9a457c3d2edc8a005661641301675049c787cad0fae`，UI Test executable `de158835679de7d511b6d275e70972544aef0677210862c5d3125523e49ca7ce`，xctestrun `0446c244aec3849e52f45dacd7bb08e3af74da5333d2cdce3d7863a6b6fd2bd9`。App/Runner strict codesign复核通过，architecture为 `arm64`，Gate之间未 build、sign或修改产品。Business repair、business retry、UI infrastructure retry 与 incomplete-result re-observation实际用量均为 `0`。

### Diagnostic closure provider and data boundary

- Provider requests: `NOT RUN`
- Twelve Data operations: `0`
- Frankfurter live operations: `0`
- Provider transport attempts: `0`
- Credential reads: `0`
- Keychain metadata reads: `0`
- Market Cache reads/mutations: `0`
- Twelve Data persistent writes: `Disabled`
- Provider retention rights: `BLOCKED`
- External Restore/import: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Scheduling/cloud export: `NOT IMPLEMENTED / NOT AUTHORIZED`
- External retention: `NOT IMPLEMENTED / NOT AUTHORIZED`
- Stages 12–14: `NO-GO`

测试停止后、文档更新前，系统 `shasum -c` 对全部 `114` 个 pre-inventory ordinary files返回 `OK`，确认 Product/Test/Project及其他 Repository路径在测试期间保持逐字节不变。所有 UI 与 result artifacts 均位于 `/private/tmp`；未向 Repository 写入数据库、Backup/export generation、staging、DerivedData或 xcresult。

## Current Stage 11 UI runtime candidate status

**Stage 11 External Backup Export UI Runtime Candidate — Awaiting Reviewer Gate**

本状态仅是 Executor candidate evidence，不宣布 Stage 11 `PASS`、V1 Ready、Release Ready或 Stage 12授权。
