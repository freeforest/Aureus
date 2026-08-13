# Stage 6 Twelve Data Retention Decision

**Status:** `BLOCKED` — Production Twelve Data persistent cache writes remain disabled  
**Decision date:** 2026-08-13  
**Stage status:** Stage 6G Security Recovery / Terminal Validation Candidate — `BLOCKED`; the compromised credential was revoked/rotated by the user, a replacement reports `Configured`, terminal validation succeeded with Plan/Entitlement still `Unknown`, and no Provider inquiry was sent.  
**Scope:** Twelve Data BYOK, individual personal/internal use in the local-first Aureus macOS app

This record answers only whether Aureus has sufficient current official evidence to persist Twelve Data market data on the user's Mac. It does not change the selected Provider, plan-aware entitlement model, four-market V1 scope, or Stage 6 implementation boundary.

## 1. Decision

Current public first-party materials establish that an individual subscriber may process and store data for internal use, subject to the subscription tier, Documentation, exchange restrictions, and termination obligations. The Terms also prohibit storing or caching data beyond timeframes specified in the Documentation. The reviewed public Documentation does not state an unambiguous local persistent-cache duration for each Aureus data type and plan.

Stage 6G corrected the Stage 6F credential-boundary incident without changing retention evidence: the old credential was treated as compromised, disconnected locally without being read, and user-confirmed as revoked/rotated server-side. The replacement was transferred only by the user directly into the Production SecureField. Production Settings reports it configured, and one bounded validation reached sanitized terminal `SUCCESS`, while Plan and Entitlement remained `Unknown`. No user-visible retention term or written Provider response was supplied. The available material still does not close the per-data-type and per-plan duration gap, so this decision and the disabled-write policy are unchanged. The Support Inquiry Packet remains unsent.

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
| Symbol Search/reference metadata | Basic, Grow, Pro, or higher subject to the current catalog and entitlement | General internal-use license is documented | No endpoint-specific duration found in reviewed public Documentation | No binding local-cache refresh interval found | Terms require access to cease and data deletion on termination; the Terms also state deletion within 30 days, while Aureus uses immediate Provider-scoped purge for explicit lifecycle actions | Private/internal use is generally exempt; public display can require visible and market-specific attribution | `BLOCKED` for persistent writes |
| Latest Quote/market status | Plan and market entitlement dependent | General internal-use license is documented | No endpoint-specific duration found | No binding duration found; freshness and entitlement remain runtime states | Same as above | Same as above | `BLOCKED` for persistent writes |
| Historical OHLCV / EOD | Basic US-focused entry path; international access is plan/entitlement dependent | Personal plans are documented for individual, non-commercial use | Historical/incremental-fetch guidance does not state a licensed local retention duration | Incremental updates are recommended, but that recommendation is not a cache-duration grant | Same as above | Same as above | `BLOCKED` for persistent writes |
| Splits | Grow individual / Venture business and above; 20 credits per symbol in current official API Documentation | Not a Basic capability; actual current-key access is not verified | No endpoint-specific duration found | No binding duration found | Same as above | Same as above | `BLOCKED`; Basic request is rejected before transport |
| Dividends | Grow individual / Venture business and above; 20 credits per symbol in current official API Documentation | Not a Basic capability; actual current-key access is not verified | No endpoint-specific duration found | No binding duration found | Same as above | Same as above | `BLOCKED`; Basic request is rejected before transport |

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

The following can be sent unchanged to Twelve Data Support or licensing. It requests a written, plan-specific answer without disclosing a credential or account identifier.

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
>
> Please identify any Documentation section, plan add-on, exchange agreement, or separate written license that governs these rights. We will keep persistent Twelve Data cache writes disabled until the applicable duration and deletion obligations are confirmed.
>
> Thank you.

## 5. Unblock Condition

This item can move from `BLOCKED` only after an applicable official plan page, Documentation provision, user-visible official plan term, or written Twelve Data response clearly states the retention duration and deletion obligations for the intended BYOK personal-local scenario. Stage 6/Reviewer must then map the granted duration to each cache data type and retain the stricter of legal retention and architectural freshness TTL.
