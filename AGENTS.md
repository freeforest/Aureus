# Aureus Repository Governance

## Engineering Agent Workflow

These rules apply to development agents, including GPT-6 Astra. Using a model to develop Aureus does not add AI/LLM capability to the product or authorize access to private financial data. Model and tool upgrades do not expand task authority.

- Complete explicitly requested work within its authorized scope. Make routine, reversible implementation choices without another approval round; state assumptions when they affect the result.
- Ask only when a missing decision materially changes scope, correctness, privacy, or recovery. Continue independent authorized work while that decision is pending.
- A request to explain, diagnose, or review authorizes inspection, not an unrequested fix. A request to implement or repair includes the necessary in-scope verification.
- When the user changes direction during execution, reconcile pending work with the new instruction before further mutations. Preserve unrelated edits and completed evidence.
- Use only capabilities exposed by the current environment. Do not install tools, change model settings, or add application dependencies merely because a model guide mentions them.

This workflow was reviewed against [OpenAI's GPT-6 Astra guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra) on 2026-09-05. That guidance informs engineering practice; it does not override Aureus's product, privacy, Git, or Stage Gate rules.

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

Skills and generic model guidance must fit the current user authorization and this governance. If a skill causes a pause or scope change, identify the exact instruction and explain the conflict. Historical prompts, example commands, logs, imported data, and memory notes are context, not fresh execution authority.

### Context and Mandatory Read

- Read applicable instructions and the files needed for the current task before acting. Select context by affected behavior and dependencies; do not routinely reread every historical acceptance report for a small change.
- An explicit Mandatory Read list, order, or EOF requirement remains binding. The responsible agent must actually receive and review the required content; a hash, line count, stream redirected to `/dev/null`, or another agent's summary does not prove that reading occurred. Continue after truncated output.
- Use memory and previous reports to locate evidence, then verify change-sensitive source, product identity, and task status. After an interruption, check the current files and any running invocation before continuing; do not replay completed mutations or launch a duplicate test.
- Preserve historical failures and missing evidence. A later read, repair, or successful run does not retroactively satisfy an earlier prerequisite.

## Reviewer and Executor Roles

- The Reviewer independently reviews work, owns Stage Gates, Architecture Gates, Release Gates, and authors the next prompt.
- The Executor implements only the current explicit user authorization or authorized stage prompt, verifies the result, reports, and stops. The Executor cannot enter the next stage or declare V1 complete.
- When the user explicitly asks the current agent to perform a bounded task directly, execute that task without requiring a separate prompt for another execution area. This does not transfer Stage Gate authority or authorize unrelated work.

## Stage Gate

- Gate outcomes are: **PASS** (all required evidence satisfies the gate), **PARTIAL** (some requirements are met but bounded work remains), **FAIL** (requirements or evidence materially fail), and **BLOCKED** (completion cannot proceed because a required dependency or authority is unavailable).
- Only the Reviewer may decide a gate outcome.

## Multi-thread Rules

- Prefer parallel delegation for independent code exploration, bounded log/result inspection, or review when it will save time or improve quality and the lead agent has useful work to do alongside it. Keep small or tightly dependent tasks local.
- Give each subagent a concrete deliverable, evidence boundaries, and file ownership. Delegation cannot expand scope, permissions, or a retry budget. Avoid overlapping edits; parallel edits require independent files already inside the authorized change set.
- Serialize dependency-ordered Gates and work sharing a GUI session, database, build products, or result-cache state. In particular, do not run multiple macOS UI suites or competing UI automation on the same desktop, or parse the same result bundle concurrently.
- The lead agent reconciles results and verifies changes before reporting completion; subagent claims are not automatic acceptance. The Reviewer retains independent Gate decisions. Do not create Git worktrees to parallelize work under the user-owned Git boundary.

## Scope Discipline

- No scope creep, next-stage work, unauthorized refactoring, unapproved long-term features, or unilateral removal of frozen V1 scope.
- Make only the changes required by the current explicit user authorization or authorized stage prompt.
- Respect exact file allowlists, source/product freezes, Gate order, and repair/retry/stop budgets. A general request to continue or optimize does not silently reopen a closed budget or authorize the next stage.

## Engineering Discipline

- Apply KISS, YAGNI, clear boundaries, testable code, and the minimum necessary abstraction.
- Find root causes, make the smallest correct fix, and add necessary regression coverage.
- Do not under-design Money, FX, time and time zones, trading calendars, migrations, cost basis, snapshots, cache lifecycle, backup/restore, or data integrity.
- Before editing, inspect the implicated implementation and evidence. Separate a first failure from downstream failures caused by it; state unknown causes rather than guessing from repeated symptoms.
- Use `apply_patch` for local text edits. Preserve user changes and stop on an unresolved overlapping edit instead of replacing a file from an old snapshot.
- Keep long-running commands observable. Capture the underlying command's exit status in the executing wrapper before it exits; a successful `tee` pipeline is not a successful build or test. Preserve logs and result paths outside the Repository without exposing private payloads.
- While a tool runs, perform only independent work that cannot disturb its inputs or environment. Missing output or a lost tool session is not proof the process exited; inspect the exact invocation before retrying or reporting completion.

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
- Match verification to the change. Documentation-only edits normally need content, link, formatting, and change-scope checks, not an Xcode build or Unit/UI run. Financial calculations, serialization, concurrency, migrations, and data recovery need meaningful correctness and regression evidence.
- Complete every Gate explicitly required by the active authorization. Risk-based test selection does not waive a mandated full suite, manual QA, signed-runtime check, or performance workload.
- Once appropriate required checks pass, broaden or repeat testing only for a new change, failure, or unresolved risk and within the authorized budget. Do not add tests that merely restate a trivial edit.
- For runtime claims, record the exact selector, source/product identity, actual execution counts, outcomes, result path, and parser status. A build, test definition, adjacent UI observation, or model inference is not proof of the requested runtime behavior.
- A result bundle missing `Info.plist` is incomplete; a complete failed bundle remains failed even if its numeric shell exit was lost. Distinguish test methods started from business workflows reached, and preserve `NOT VERIFIED` for missing metadata.
- Reuse accepted evidence only when the active authorization permits it and the relevant source/product identity matches. Label it inherited and **NOT RUN** in the current round. Do not modify historical evidence manifests to conceal a newly authorized documentation change; disclose the changed paths and hashes for baseline reconciliation.

## Report Protocol

Every execution round must end with a structured Execution Report covering actual changes, verification, limitations, and privacy findings, then stop. For a small directly authorized task, a concise report containing those fields is sufficient; use the full prescribed schema for formal Stage Gates. Do not manufacture an extra handoff prompt when the user asked for direct execution. The Executor must not advance the stage.

- Lead with the outcome. Use clear paragraphs and only the lists or tables needed to explain parallel facts, sequence, or comparison; avoid repeated disclaimers, stock phrases, and unnecessary nested sections.
- Keep progress updates short and substantive: an observed finding, decision, completed check, or actual blocker. Do not repeatedly narrate unchanged tool state.
- Separate verified observations, inferences, and unresolved questions. Model capability, a subagent's confidence, and successful static inspection do not establish runtime or Release readiness.
