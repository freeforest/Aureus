# Privacy & Data

## Local wealth records

Aureus is a local-first, single-user wealth terminal. Accounts, holdings, transactions, goals, and valuations are maintained as local permanent records. CNY is the unified valuation currency; USD original amounts, applied exchange rates, and converted CNY values are retained together.

There is no AI/LLM feature, cloud account system, or automatic brokerage synchronization in V1. Local-first does not mean that optional market requests never use the network.

## Permanent records and cache

Permanent wealth data is separated from Market Cache. Cache capacity limits, TTL expiry, automatic cleanup, and manual cleanup must not remove permanent records. This separation is a product boundary, not permission to retain Provider data.

## Market data and credentials

Twelve Data Production data is session-only in V1. Persistent Provider writes are disabled. Search results, quotes, historical bars, actions, freshness, and raw responses must not become permanent wealth records, cached disk history, backups, or exports. The bounded in-memory work set is cleared at termination and explicit session clearing, with additional credential and entitlement lifecycle invalidation.

Minimal user-authored symbol/MIC identifiers and UI preferences may persist; they are not Provider prices or permission evidence. After relaunch, session market data is unavailable offline until an authorized request succeeds.

Each user supplies their own Production key through native Settings. The application-scoped Keychain is the credential source; a local secret note is not a runtime source. Key ownership, plan, endpoint entitlement, exchange permission, and rate limits govern access. Catalog visibility alone does not establish access.

Aureus's Personal Local Mode does not authorize sharing, resale, or redistribution of Provider data. The MIT source license grants no Provider data or credential rights.

## Backups and host protection

Backups are managed by the user and are not independently encrypted by Aureus. V1 does not add application-layer database encryption. Protect your Mac and backup location, and keep an independent private copy of important records. Do not treat the only internal backup as a complete recovery strategy.

## Public feedback

Useful issue reports include the App version, macOS version and chip, reproduction steps, and expected versus actual behavior. Use synthetic examples or carefully sanitized material.

Never publish real financial records, balances, account identifiers, keys, databases, private backups, or complete runtime logs. Acceptance of unfinished log-privacy validation is not permission to publish private logs.

## Evidence boundary

The formal 1.0.0 release used a user-exception decision. Technical evidence remains PARTIAL, including unfinished log-privacy and final-runtime verification. Repository-history safety remains NOT VERIFIED; historical content has not been comprehensively audited. These policies are not a claim that all system access, logs, or past repository objects have been proven safe.

[Verification summary](evidence/release-1.0.0.md) · [Documentation](README.md)
