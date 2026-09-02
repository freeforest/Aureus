# Stage 11 Data Lifecycle Acceptance

## Status

**Stage 11 Restore Foundation Candidate — Awaiting Reviewer Gate**

Stage 10 and the Stage 11 Backup Foundation have independent Reviewer `PASS` decisions. This document preserves the first bounded Backup round and records the current no-UI Restore Foundation candidate. It does not declare Stage 11 `PASS`, Restore UI Ready, V1 Ready, Release Ready, or entry to Stages 12–14.

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

**Stage 11 Restore Foundation Candidate — Awaiting Reviewer Gate**
