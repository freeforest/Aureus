# Aureus Repository Governance

## Project Identity

- **Aureus Wealth Terminal** is a macOS, local-first Personal Wealth Intelligence Terminal.
- The product is visualization-first; it is not a conventional expense tracker.
- Do not copy another product's source code or UI. External products may inform principles, not implementation duplication.

## Product Hard Constraints

- Prioritize macOS and Apple Silicon.
- Keep the product local-first. Program source is planned to be open source; real financial data always remains private.
- Prioritize CNY and USD. CNY is the default unified valuation currency.
- Preserve the USD original amount, the applied FX rate, and the converted CNY value together.
- Market cache must have a capacity limit, TTL, automatic cleanup, and manual cleanup. Cache cleanup must never delete permanent wealth records.
- Demo and test data must be synthetic or sanitized.
- No AI or LLM capability is a long-term product boundary, not a deferred feature.

### Personal Local Mode

- Aureus is a single-user, local-only macOS application for personal/internal, non-commercial use. It is not a hosted service and does not provide commercial display, sharing, resale, or redistribution of Provider data.
- Open source applies to Aureus program source, schemas, synthetic fixtures, and public documentation. It never includes Provider data, Provider credentials, or the user's financial data.
- Personal Local Mode does not authorize any request beyond the current user's actual Plan, endpoint entitlement, rate limit, or exchange license. Catalog visibility and a user-selected symbol or MIC are not entitlement evidence.
- Twelve Data Production data is session-only in V1: bounded in-memory processing is allowed after the applicable endpoint/MIC succeeds, while persistent Twelve Data writes remain disabled by product policy. The session work set is cleared at App termination and on explicit user clear, Disconnect, Credential rotation, confirmed entitlement loss, or termination. User-authored symbol/MIC identifiers and UI preferences may persist only when they contain no Provider description, quote, OHLCV, action, freshness, or raw-response content.
- The existing isolated Market Cache infrastructure remains governed by its capacity, TTL, cleanup, and Permanent Store isolation rules. It does not authorize Twelve Data persistence; Provider-specific storage requires separately verified rights and an explicit later product decision.

## Sources of Truth

Product and requirement priority, from highest to lowest:

1. The user's latest explicit instruction.
2. Frozen long-term product decisions.
3. `Aureus_Wealth_Terminal_项目设计汇总.md`.
4. The approved V1 scope.
5. The current stage prompt.
6. Historical plans or discussions.

Engineering-governance priority, from highest to lowest:

1. The user's current explicit instruction.
2. This root `AGENTS.md`.
3. The current stage prompt.
4. Existing engineering conventions.

Repository files and actual build/test results take precedence over an Executor report when determining completion. Repository reality does not authorize changing product requirements.

## Reviewer and Executor Roles

- The Reviewer independently reviews work, owns Stage Gates, Architecture Gates, Release Gates, and authors the next prompt.
- The Executor implements only the current prompt, verifies the result, reports, and stops. The Executor cannot enter the next stage or declare V1 complete.

## Stage Gate

- Gate outcomes are: **PASS** (all required evidence satisfies the gate), **PARTIAL** (some requirements are met but bounded work remains), **FAIL** (requirements or evidence materially fail), and **BLOCKED** (completion cannot proceed because a required dependency or authority is unavailable).
- Only the Reviewer may decide a gate outcome.

## Multi-thread Rules

- Work is serial by default.
- Parallel work is allowed only for independent, clearly owned, low-conflict tasks.
- The Reviewer must consolidate and accept all parallel results.

## Scope Discipline

- No scope creep, next-stage work, unauthorized refactoring, unapproved long-term features, or unilateral removal of frozen V1 scope.
- Make only the changes required by the current authorized prompt.

## Engineering Discipline

- Apply KISS, YAGNI, clear boundaries, testable code, and the minimum necessary abstraction.
- Find root causes, make the smallest correct fix, and add necessary regression coverage.
- Do not under-design Money, FX, time and time zones, trading calendars, migrations, cost basis, snapshots, cache lifecycle, backup/restore, or data integrity.

## Data Privacy

Never place any of the following in a future public repository:

- Real accounts, balances, holdings, trades, costs, insurance data, goals, or wealth history.
- A real local database, SQLite sidecars, backups, or private imports/exports.
- API keys, tokens, secrets, credentials, private keys, or certificates containing private material.
- Logs that reveal a user's identity or wealth position.

Defensive ignore rules are not permission to store private data in the project directory.

### Narrow Local-only Twelve Data Secret Exception

- The only authorized local manual secret record is `/.secrets/twelve-data-api-key.local.txt`. It is a user-authorized local-filesystem exception, not Repository content.
- `.secrets/` must remain excluded by `.gitignore`; the directory permission is `700` and the file permission is `600`.
- Agents must never read, print, transcribe, hash, scan, copy, back up, or report the file's contents. Metadata-only existence, type, and permission checks are allowed.
- The file is never a Build, Test, Runtime, or Production credential source. The Production App must store and retrieve the Twelve Data API key only through Keychain.
- This exception does not authorize any other secret, real financial data, database, backup, private import, or private export inside the project directory. Every additional local secret file requires new explicit user authorization.

## User-owned Git and GitHub Boundary

- The user manually owns every Git and GitHub operation.
- Agents must not run any `git` or `gh` command by default, including read-only commands, and must not create, read, or modify `.git`.
- Agents must not initialize a repository; stage, commit, pull, push, merge, rebase, tag, or release; create branches or pull requests; or change remotes.
- Each execution reports only a filesystem change list. The Reviewer assesses repository files, test evidence, and any Git evidence supplied by the user.
- This boundary changes only if the user explicitly changes this long-term decision in a later instruction.

## Tests

- A test not executed must be reported as **NOT RUN**. Never fabricate tests or conceal failures.
- Tests and demos must not use real personal data.
- Demo paths and production paths must remain distinct.

## Report Protocol

Every execution round must end with a structured Execution Report covering actual changes, verification, limitations, and privacy findings, then stop. The Executor must not advance the stage.
