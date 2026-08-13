# Stage 6 Twelve Data Retention Decision

**Status:** `BLOCKED` — Production Twelve Data persistent cache writes remain disabled  
**Decision date:** 2026-08-13  
**Stage status:** Stage 6J Retention Contract Follow-up — `BLOCKED`; response `PENDING`, and Plan/Entitlement remain `NOT VERIFIED`.  
**Scope:** Twelve Data BYOK, individual personal/internal use in the local-first Aureus macOS app

This record answers only whether Aureus has sufficient current official evidence to persist Twelve Data market data on the user's Mac. It does not change the selected Provider, plan-aware entitlement model, four-market V1 scope, or Stage 6 implementation boundary.

## 1. Decision

Current public first-party materials establish that an individual subscriber may process and store data for internal use, subject to the subscription tier, Documentation, exchange restrictions, and termination obligations. The Terms also prohibit storing or caching data beyond timeframes specified in the Documentation. The reviewed public Documentation does not state an unambiguous local persistent-cache duration for each Aureus data type and plan.

Stage 6G corrected the Stage 6F credential-boundary incident without changing retention evidence: the old credential was treated as compromised, disconnected locally without being read, and user-confirmed as revoked/rotated server-side. The replacement was transferred only by the user directly into the Production SecureField. Production Settings reports it configured, and one bounded validation reached sanitized terminal `SUCCESS`, while Plan and Entitlement remained `Unknown`. On 2026-08-13, Stage 6H sent exactly one sanitized inquiry through the official Twelve Data Customer Support form under the `Other` category.

Stage 6I reviewed the user-supplied sanitized Support reply. It confirms only that local caching is permitted in some cases and that internal/private use generally does not require attribution. It supplies no per-data-type/plan maximum retention duration, no complete refresh or deletion policy, no open-source BYOK rule, and no `/api_usage` field contract. It also states that `XHKG` and `XJPX` historical access requires direct exchange licensing. Because none of the five cache data types satisfies the complete evidence test, this decision and the disabled-write policy are unchanged. No credentialed endpoint was called and no follow-up was sent.

On 2026-08-13, Stage 6J submitted exactly one sanitized follow-up through the official Twelve Data Customer Support form under the `Other` category. Submission count was 1, attachments were 0, and the response is `PENDING`. The follow-up requests explicit per-data-type, per-Plan, per-market retention periods, deletion deadlines, market-license requirements, BYOK/attribution boundaries, and the official `/api_usage` schema. Sending the inquiry does not resolve the evidence gap: Retention remains `BLOCKED`, Production persistent Twelve Data writes remain disabled, and Stage 7 remains `NO-GO`. No credentialed Provider endpoint was called.

Therefore:

- Twelve Data responses may be validated and returned to the requesting user in memory.
- Production writes of Twelve Data Search, Quote, OHLCV, Split, and Dividend data to the persistent Market Cache remain disabled.
- Architectural freshness TTLs do not grant a legal retention right. A verified Provider limit would override them when stricter.
- Key deletion, explicit Disconnect, or confirmed termination purges Twelve Data recoverable cache rows only; it cannot reach the Permanent Wealth Store.
- No right to indefinite retention is inferred from personal/internal use, incremental-update guidance, or open-source application code.

## 2. Evidence Matrix

Access date for every source below: **2026-08-13**.

| Data type | Relevant individual plans | Personal/local BYOK use | Persistent local cache duration | Refresh/update duty | Disconnect/termination duty | Attribution | Decision |
|---|---|---|---|---|---|---|---|
| Symbol Search/reference metadata | Basic, Grow, Pro, or higher subject to the current catalog and entitlement | Support says caching is permitted in some cases but does not map that statement to Search/reference or a Plan | Not specified | Not specified | Support says Documentation is silent; current Terms require deletion on termination, so Aureus keeps immediate Provider-scoped purge | Private/internal use generally exempt; market rules may differ | `BLOCKED` for persistent writes |
| Latest Quote/market status | Plan and market entitlement dependent | General caching statement is not Quote-specific | Not specified | Not specified | Same conservative Terms-based policy | Same as above | `BLOCKED` for persistent writes |
| Historical OHLCV / EOD | Basic US-focused entry path; international access is plan/entitlement dependent | General caching statement is not sufficient; `XHKG` and `XJPX` historical access requires direct exchange licensing | Not specified | Incremental guidance is not a retention grant | Same conservative Terms-based policy | Same as above | `BLOCKED` for persistent writes |
| Splits | Grow individual / Venture business and above; 20 credits per symbol in current official API Documentation | Support reply does not answer Split caching | Not specified | Not specified | Same conservative Terms-based policy | Same as above | `BLOCKED`; Basic request is rejected before transport |
| Dividends | Grow individual / Venture business and above; 20 credits per symbol in current official API Documentation | Support reply does not answer Dividend caching | Not specified | Not specified | Same conservative Terms-based policy | Same as above | `BLOCKED`; Basic request is rejected before transport |

## 3. Official Source Register

| Source | Current observation | Evidence status |
|---|---|---|
| [Twelve Data Terms of Use](https://twelvedata.com/terms) | Internal access/processing/storage is plan-bounded; caching beyond Documentation timeframes is prohibited; redistribution requires applicable rights. On termination access ceases and data must be deleted; a later retention section states deletion within 30 days. It does not supply the missing ordinary endpoint-specific retention durations. | `VERIFIED` general duties; `NOT VERIFIED` ordinary duration |
| [Commercial and personal usage](https://support.twelvedata.com/en/articles/5332349-commercial-and-personal-usage) | Basic/Grow/Pro/Ultra individual plans are for personal or internal use and do not permit redistribution or commercial display to third parties. | `VERIFIED` general use boundary |
| [Twelve Data API Documentation](https://twelvedata.com/docs) | Search/reference, Quote, Time Series/EOD, adjustment, Split, and Dividend contracts are documented. No reviewed endpoint section supplied a local persistent-cache duration. | `VERIFIED` API contract; `NOT VERIFIED` retention duration |
| [Credits](https://support.twelvedata.com/en/articles/5615854-credits) | Endpoint weights apply; quota restores at the start of a new minute and Basic daily credits reset at UTC midnight. Client-side storage guidance does not state a retention duration. | `VERIFIED` quota boundary; `NOT VERIFIED` retention duration |
| [How to get historical prices](https://support.twelvedata.com/en/articles/5656039-how-to-get-historical-prices) | Historical series can be fetched by range and updated incrementally. The guidance does not establish how long an Aureus local persistent copy may be retained. | `VERIFIED` retrieval/update guidance; `NOT VERIFIED` retention duration |
| [End-of-day pricing market data](https://support.twelvedata.com/en/articles/12682324-end-of-day-eod-pricing-market-data) | EOD coverage and individual non-commercial-use boundaries are described. No local retention duration is stated. | `VERIFIED` general EOD boundary; `NOT VERIFIED` retention duration |
| [Attribution guidelines](https://support.twelvedata.com/en/articles/12647398-attribution-guidelines-for-using-twelve-data) | Public/external display requires attribution unless contractually exempt; internal/private use is generally exempt, and market-specific rules may still apply. | `VERIFIED` general attribution boundary |
| [Splits endpoint](https://twelvedata.com/docs/advanced) | `/splits` costs 20 credits per symbol and is available on Grow individual / Venture business and above. | `VERIFIED` catalog contract; live entitlement `NOT VERIFIED` |
| [Dividends endpoint](https://twelvedata.com/docs/advanced) | `/dividends` costs 20 credits per symbol and is available on Grow individual / Venture business and above. | `VERIFIED` catalog contract; live entitlement `NOT VERIFIED` |

## 4. Support Inquiry Packet

The following was submitted once to the official Twelve Data Customer Support form on 2026-08-13 under the `Other` category. A sanitized response was received and reviewed in Stage 6I, but it did not supply the complete plan- and data-type-specific retention or `/api_usage` contract evidence requested below.

**Subject:** Local persistent-cache terms for a BYOK open-source macOS desktop app

> Hello Twelve Data Support,
>
> We are building Aureus, a local-first, open-source macOS desktop application for personal wealth analysis. Each end user supplies and controls their own Twelve Data API key (BYOK). Aureus does not bundle, share, proxy, resell, or redistribute API credentials or raw market data. Provider data is displayed only to the same individual user and stays on that user's Mac for personal/internal, non-commercial use.
>
> Could you please confirm in writing, separately for Basic, Grow, Pro, and any higher individual plan:
>
> 1. Whether the user may persistently cache Symbol Search/reference metadata, latest Quote/market-status data, historical OHLCV/EOD bars, Splits, and Dividends on their own Mac.
> 2. The maximum permitted local retention duration for each data type.
> 3. Whether historical OHLCV may remain locally after incremental refresh, and what refresh/update obligations apply.
> 4. Whether the permission differs for US, Hong Kong (`XHKG`), Shanghai (`XSHG`), Shenzhen (`XSHE`), and Japan (`XJPX`) data.
> 5. What must be deleted, and by when, when a key is disconnected, a plan is downgraded, an entitlement expires, or a subscription terminates.
> 6. Whether locally cached data must be deleted immediately when the applicable market entitlement is lost, even if the overall account remains active.
> 7. What attribution is required inside a private desktop UI, and whether any exchange-specific attribution applies to these five market identifiers.
> 8. Whether an open-source application may implement this BYOK local-cache behavior when neither the repository nor the application developer receives or redistributes Provider data.
> 9. Please provide the current officially supported JSON field names, nesting and value types returned by `/api_usage` for the plan name, API credits per minute, daily cap, credits used and credits remaining. Please also confirm whether the response shape differs between Basic and paid Individual plans. We need only the public response contract; please do not include or request an API key.
>
> Please identify any Documentation section, plan add-on, exchange agreement, or separate written license that governs these rights. We will keep persistent Twelve Data cache writes disabled until the applicable duration and deletion obligations are confirmed.
>
> Thank you.

## 5. `/api_usage` Contract Comparison

The current private `TwelveUsageDTO` accepts top-level optional `String` values under `plan_name` or `plan`, an optional top-level `Int` under `api_credits_per_minute`, and an optional top-level `Int` under `daily_limit`. `ProviderUsageObservation` maps those values to an optional Plan name, entitlement, optional minute limit and a typed capped/uncapped/unknown daily quota. It does not treat credits-used or credits-remaining fields as Domain authority.

The Support reply says the Documentation does not list the JSON field names, nesting or value types and supplies no replacement contract. Result: **NOT VERIFIED — neither `COMPATIBLE` nor `PROVEN CONTRACT MISMATCH` can be established.** Production source is unchanged; a separate authorized repair would be required only if a concrete official contract later proves a mismatch.

## 6. Submitted Follow-up

`SENT — 2026-08-13 through the official Twelve Data Customer Support form (Other). Submission count: 1. Attachments: 0. Response: PENDING.`

**Subject:** Follow-up: explicit local retention periods, deletion deadlines, market licensing, and /api_usage schema

> Hello Twelve Data Support,
>
> Thank you for your earlier reply. We are following up because the remaining answers determine whether Aureus can enable persistent market-data writes.
>
> Aureus is a local-first, open-source macOS desktop application. Each individual user supplies their own Twelve Data API key (BYOK). Data stays on that user's Mac for personal/internal, non-commercial use; Aureus does not redistribute Provider data or create a shared market-data database.
>
> Please confirm the following in writing, separately by data type, individual Plan, and market:
>
> 1. **Search/reference metadata:** For Basic, Grow, Pro, and Ultra, is persistent local storage permitted, and what is the exact maximum retention period for each Plan?
> 2. **Quote/market status:** Is persistent local storage permitted, what is the exact maximum retention period, and do the rules differ for current, delayed, and EOD data?
> 3. **Historical OHLCV/EOD:** What is the exact maximum retention period for each Plan? Does an incremental update restart or otherwise change the retention period? Do the rules differ for US, `XHKG`, `XSHG`, `XSHE`, and `XJPX`?
> 4. **Splits and Dividends:** Is persistent local storage permitted for each endpoint, and what is the exact maximum retention period for Basic, Grow, Pro, and Ultra?
> 5. **Deletion obligations:** What is the exact deletion deadline after each of: key disconnect, Plan downgrade, credential expiry, loss of a market entitlement, and account or subscription termination? How should your answer be reconciled with the public Terms requirement to delete all Data upon termination?
> 6. **Market licensing:** For US, `XHKG`, `XSHG`, `XSHE`, and `XJPX`, what is the minimum Plan for Search, Quote, historical OHLCV/EOD, Splits, and Dividends? Which markets require a separate exchange agreement, and what official process should an individual user follow to obtain the required `XHKG` or `XJPX` license?
> 7. **Open-source BYOK and attribution:** Is this model permitted: an open-source macOS desktop app, each user supplies their own Key, data is used only by that user locally for personal/internal purposes, and there is no redistribution or shared database? What attribution is required, including any market-specific attribution?
> 8. **`/api_usage` response contract:** Please provide the officially supported JSON field names, nesting, and value types for Plan name, minute limit, daily cap, credits used, and credits remaining. How does the response differ between Basic and paid Individual plans? How is no daily cap represented? Is there a stable versioned schema or official example?
>
> Please provide explicit Yes/No answers and exact numerical periods or deadlines for each applicable Plan and data type, together with the governing official Terms or Documentation links. If first-line Support cannot provide these licensing and data-compliance answers, please transfer this request to Licensing/Data Compliance while keeping it in the same conversation.
>
> We will keep Production Twelve Data persistent writes disabled until the applicable retention and deletion rights are confirmed. Please do not include or request an API key or account-specific information in your response.
>
> Thank you.

## 7. Unblock Condition

This item can move from `BLOCKED` only after an applicable official plan page, Documentation provision, user-visible official plan term, or written Twelve Data response clearly states the retention duration and deletion obligations for the intended BYOK personal-local scenario. Stage 6/Reviewer must then map the granted duration to each cache data type and retain the stricter of legal retention and architectural freshness TTL.
