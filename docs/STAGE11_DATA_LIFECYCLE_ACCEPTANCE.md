# Stage 11 Data Lifecycle Acceptance

## Status

**Stage 11 Backup Foundation Candidate — Awaiting Reviewer Gate**

Stage 10 has an independent Reviewer `PASS`. This document records only the first bounded Stage 11 internal Backup foundation. It does not declare Stage 11 `PASS`, Restore Ready, V1 Ready, Release Ready, or entry to Stages 12–14.

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

## Restore and migration boundary

**Restore: NOT IMPLEMENTED / NOT AUTHORIZED IN THIS FOUNDATION ROUND.**

No permanent database replacement, safety restore, rollback, maintenance mode, user-selected restore, old-schema import, pre-migration backup hook, or migration is implemented. Permanent schema version remains `6`; all migration identifiers and the cache schema remain unchanged. Validation does not imply Restore readiness.

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

- Restore, database replacement, rollback, and external import/export remain unimplemented and unauthorized.
- Backup creation is not yet wired to Settings or scheduling.
- Backup artifacts are not claimed to have application-layer encryption.
- Four pre-existing `PortfolioView` string-interpolation deprecation warnings remain; this round added no warning.
- The Mandatory Read prompt named the absent path `Aureus/Domain/Values/TimeValues.swift`; the canonical existing file `Aureus/Domain/Time/TimeValues.swift` was read to EOF, and no path was invented or changed.

## Current candidate

**Stage 11 Backup Foundation Candidate — Awaiting Reviewer Gate**
