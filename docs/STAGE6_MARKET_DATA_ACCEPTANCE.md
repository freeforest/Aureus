# Stage 6 Market Data Acceptance Evidence

**Status:** Stage 6K Follow-up Reply Sufficiency Review — `BLOCKED`  
**Evidence visit:** 2026-08-12–2026-08-17  
**Authority:** This document records Stage 6 implementation and acceptance evidence. It does not replace the frozen V1 Scope or Architecture, prove a paid entitlement, or decide the Stage Gate.

## 1. Acceptance Boundary

Aureus uses Twelve Data as the selected market-data provider with a user-owned API key (BYOK), and Frankfurter v2 filtered to ECB reference rates for USD/CNY reference FX. The Production App accepts a Twelve Data credential only through its native Settings UI and stores it only in the app-scoped macOS Keychain item.

Stage 6G treated the credential involved in the Stage 6F boundary incident as compromised because it had entered conversation, browser-automation context, and a plaintext temporary file. The Production Disconnect path removed the local credential without reading it, stopped Provider admission, and purged only recoverable Twelve Data cache. The user then personally revoked/rotated the old credential server-side and pasted the replacement directly from the Provider site into the Production SecureField; no replacement credential material passed through conversation, automation, files, logs, screenshots, or test inputs. A read-only Production UI check reported only `CONFIGURED`.

Exactly one subsequent Production Validate action used the existing bounded policy (one initial request and at most three internal retries; maximum theoretical budget four credits). It observed the busy state and reached sanitized terminal category `SUCCESS`; `lastSuccessfulValidation` was present. The categorical Observed Plan and Entitlement both remained `Unknown`, so this result verifies only the replacement credential's terminal validation path. It does not verify Basic, actual usage headers, Search, Quote, OHLCV, adjustment, Corporate Actions, freshness, or any market entitlement. No other Twelve Data endpoint was called. The local manual secret record was not accessed.

The implementation makes the following safety distinctions:

- official documentation can verify a published contract but cannot prove the current key's entitlement;
- an exchange listed in a catalog is not proof that the current key may retrieve that market;
- a user-entered Plan label is display metadata, not authorization;
- synthetic transport tests verify code behavior, not Twelve Data service acceptance;
- cache rights are separate from endpoint access;
- open-source application code does not redistribute Provider data, and Provider data is never stored in the Repository.

## 2. Official Source Register

Only Provider-owned pages, the Frankfurter official site/repository, and ECB official pages are used below. Search summaries, blogs, wrappers, and AI-generated material are not evidence.

| ID | Official source | Accessed | Observed fact | Status | Aureus impact |
|---|---|---:|---|---|---|
| TD-01 | [Twelve Data Pricing](https://twelvedata.com/pricing) | 2026-08-12 | Basic publishes 8 API credits/minute and 800/day with a US-focused entry path. The page presents Pro as a variable paid tier; displayed price/credits depend on the selected configuration. | VERIFIED for published limits; price is time-sensitive | Basic defaults are conservative rate-gate seeds. No purchase or paid allowance is inferred. |
| TD-02 | [Twelve Data Exchanges](https://twelvedata.com/exchanges) | 2026-08-12 | US coverage is listed on Basic. `XHKG`, `XSHG`, `XSHE`, and `XJPX` are listed with Pro-level plan requirements; displayed delay fields do not establish the current key's rights. | VERIFIED as catalog only | Capability UI keeps each MIC entitlement separate and unverified until an endpoint succeeds. |
| TD-03 | [Twelve Data REST API Documentation](https://twelvedata.com/docs) | 2026-08-12 | Official REST reference describes time series, reference/search, quote, API usage, splits, dividends, pagination and adjustment modes including `all`, `splits`, `dividends`, and `none`. | VERIFIED for documented contract; dynamic sections were not uniformly readable | Adapter uses `URLSession`/`Codable`, explicit adjustment/action mapping, and typed failures. |
| TD-03A | [Twelve Data API Quickstart](https://twelvedata.com/docs/introduction/quickstart) | 2026-08-13 | The official authentication section supports an `Authorization: apikey …` HTTP header and identifies that method as recommended, alongside the query-parameter alternative. | VERIFIED | The adapter uses the supported header form so a credential never enters its URL. |
| TD-04 | [Control over API usage](https://support.twelvedata.com/en/articles/5713553-control-over-api-usage) | 2026-08-12 | API usage can be observed through Provider usage information and response credit headers; the usage request itself consumes a credit. | VERIFIED | Observed limits may only make the gate stricter. A typed Plan name cannot raise a limit. |
| TD-05 | [Credits](https://support.twelvedata.com/en/articles/5615854-credits) | 2026-08-13 | Credits are endpoint-weighted; quota is restored at the start of a new minute and Basic daily credits reset at UTC midnight. | VERIFIED | The gate uses exact epoch-minute and UTC-day boundaries; endpoint cost is checked before queuing; a request cancelled while waiting for concurrency does not consume local credits; each delivered retry attempt does. A verified paid usage response can explicitly represent no daily cap, while an unknown plan cannot relax Basic defaults. 429 preserves checked `Retry-After`. |
| TD-06 | [Historical prices](https://support.twelvedata.com/en/articles/5656039-how-to-get-historical-prices) | 2026-08-13 | Historical time series supports bounded output, date/range selection and incremental update guidance. The page does not state a licensed local retention duration. | VERIFIED retrieval guidance; retention duration NOT VERIFIED | History requests paginate and merge deterministically. Incremental-update guidance is not treated as permission for persistent storage. |
| TD-07 | [Price adjustment](https://support.twelvedata.com/en/articles/5179064-are-the-prices-adjusted) | 2026-08-12 | Daily/weekly/monthly data is described as split-adjusted; intraday is unadjusted; splits and dividends support client-side adjustment. | VERIFIED | Domain records adjustment provenance and actions instead of treating every series as equivalent. |
| TD-08 | [Available symbols](https://support.twelvedata.com/en/articles/5620513-how-to-find-all-available-symbols-at-twelve-data) | 2026-08-12 | Official reference/search mechanisms expose supported symbol metadata. | VERIFIED | Search results remain entitlement-aware and retain MIC/exchange/native quote currency. |
| TD-09 | [End-of-day pricing market data](https://support.twelvedata.com/en/articles/12682324-end-of-day-eod-pricing-market-data) | 2026-08-12 | The current guide describes EOD data and flags `XHKG` and `XJPX` as requiring licensing/current-support confirmation. | CONFLICTING with a simple catalog-based Pro inference | HK and Japan cannot be marked verified from the Exchange Catalog. |
| TD-10 | [Commercial and personal usage](https://support.twelvedata.com/en/articles/5332349-commercial-and-personal-usage) | 2026-08-13 | Individual tiers are for personal/internal use; redistribution and commercial display to third parties are not permitted on those tiers. | VERIFIED at general level | BYOK data remains local to the corresponding user and raw Provider export is disabled. |
| TD-11 | [Twelve Data Terms](https://twelvedata.com/terms) | 2026-08-13 | Internal processing/storage is limited by Plan and Documentation; storing beyond Documentation timeframes and unauthorized redistribution are prohibited. Termination clauses require deletion, with both an immediate effect clause and a section stating deletion within 30 days. No ordinary per-data-type local-cache duration was found. | VERIFIED general duty; NOT VERIFIED ordinary duration | Persistent Twelve Data cache writes stay disabled. Explicit key deletion/Disconnect/confirmed termination uses immediate Provider-scoped purge. |
| TD-12 | [Attribution guidelines](https://support.twelvedata.com/en/articles/12647398-attribution-guidelines-for-using-twelve-data) | 2026-08-13 | Public/external display generally requires attribution; internal/private use is generally exempt; market-specific obligations may still apply. | VERIFIED at general level | Settings shows a compact source label; Stage 7 must refresh surface- and market-specific obligations. |
| TD-14 | [Splits and Dividends API reference](https://twelvedata.com/docs/advanced) | 2026-08-13 | `/splits` and `/dividends` each cost 20 credits per symbol and are available on Grow individual / Venture business and above. | VERIFIED as official catalog contract; live entitlement NOT VERIFIED | Basic no longer advertises Corporate Actions and rejects these 20-credit requests before transport. Each endpoint remains independently observed. |
| TD-13 | [Twelve Data service status](https://twelvedata.isitup.cloud/) | 2026-08-12 | The official status surface reported the service operational during the visit. | VERIFIED point-in-time only | This is maintenance evidence, not an SLA or endpoint acceptance result. |
| FF-01 | [Frankfurter v2 API](https://frankfurter.dev/) and [ECB Provider page](https://frankfurter.dev/providers/ecb/) | 2026-08-13 | Frankfurter v2 is keyless, supports provider filtering, and documents ECB as a reference-rate provider. | VERIFIED for documented contract | Adapter filters to ECB and derives CNY per USD from the two EUR reference legs. |
| FF-02 | [Frankfurter official repository](https://github.com/lineofflight/frankfurter) | 2026-08-12 | The official service implementation is maintained publicly; server source is MIT-licensed. | VERIFIED | No SDK package is required; server-source license does not replace data-source terms. |
| FF-03 | [Frankfurter status](https://frankfurter.instatus.com/) | 2026-08-12 | The official status surface reported operational service during the visit. | VERIFIED point-in-time only | Not an SLA; network and offline states remain explicit. |
| ECB-01 | [ECB euro reference exchange rates](https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html) | 2026-08-12 | ECB publishes USD and CNY reference rates on working days, normally around 16:00 CET, for information/reference purposes rather than executable trading. | VERIFIED | Stored provenance says derived ECB reference rate, never executable quote. |
| ECB-02 | [ECB reference-rate framework](https://www.ecb.europa.eu/stats/pdf/exchange/Frameworkfortheeuroforeignexchangereferencerates.en.pdf) | 2026-08-12 | The framework defines reference publication on TARGET working days and the informational nature of the rates. | VERIFIED | Missing weekends/holidays are not fabricated; reference date is retained. |
| ECB-03 | [ECB website disclaimer and reuse](https://www.ecb.europa.eu/services/using-our-site/disclaimer/html/index.en.html) | 2026-08-12 | ECB material may be reused subject to accuracy, source acknowledgment, and clear identification of changes/derivation. | VERIFIED at general level | Attribution is `ECB reference rates via Frankfurter`, with derived-cross provenance. |

## 3. Conflicts and Conservative Decisions

### 3.1 Four-market entitlement

The Exchanges catalog lists `XHKG`, `XSHG`, `XSHE`, and `XJPX` at Pro-level access, but the current EOD guide requires additional confirmation for Hong Kong and Japan. No Pro-or-higher credential was available for a bounded live acceptance run. Therefore all four international MIC checks remain `NOT VERIFIED`; the frozen US/HK/mainland-China/Japan product scope is unchanged.

### 3.2 Twelve Data cache retention

The public Terms establish that cache/storage rights are plan- and documentation-bounded but did not provide a directly verifiable ordinary retention duration for each implemented data type. Aureus does not invent a perpetual or typed retention right. Production Twelve Data cache authorization is therefore `unverified`, and validated network results are returned without replacing an older cache entry. Persistent Twelve Data writes become eligible only after Stage 6/Reviewer evidence confirms the applicable right and duration.

The typed architectural TTLs are implemented and tested as freshness/cleanup policy. They never grant a legal right to persist data: a stricter Provider retention rule wins.

The endpoint-by-endpoint decision and a copy-ready support inquiry are recorded in [Stage 6 Twelve Data Retention Decision](STAGE6_TWELVE_DATA_RETENTION_DECISION.md). The current result is `BLOCKED`, so Production Twelve Data persistent writes remain disabled.

Stage 6E re-read the public first-party Terms, personal-use guidance, historical-price guidance, and attribution guidance on 2026-08-13. They continue to establish general internal-use, plan, exchange, attribution, and termination boundaries, but do not provide a complete endpoint-by-endpoint maximum local retention duration for this BYOK desktop scenario. On 2026-08-13, Stage 6H submitted exactly one sanitized inquiry through the official Twelve Data Customer Support form under the `Other` category.

Stage 6I reviewed only the user-supplied sanitized reply to that inquiry. It is classified as a Twelve Data Support response; no sender address, ticket identifier, private URL, signature, header, or complete private email was retained. The reply says local caching is permitted in some cases but does not state the applicable data types, plans, markets, or maximum durations. It states that `XHKG` and `XJPX` historical data require direct exchange licensing, confirms no attribution for internal/private use subject to market-specific rules, and supplies no open-source BYOK or `/api_usage` response contract. Its statement that documentation does not specify deletion requirements conflicts with the current public Terms requirement to delete all Data upon termination. Ordinary retention therefore remains `BLOCKED`, Production persistent Twelve Data writes remain disabled, Plan/Entitlement remain `NOT VERIFIED`, and no credentialed endpoint or follow-up message was sent.

On 2026-08-13, Stage 6J submitted exactly one sanitized follow-up through the official Twelve Data Customer Support form under the `Other` category. The submission asked for explicit Yes/No and numerical answers covering eight groups: Search/reference, Quote/market status, OHLCV/EOD, Split/Dividend, lifecycle deletion, five-market licensing by endpoint, open-source BYOK/attribution, and the `/api_usage` JSON contract. Submission count was 1, attachments were 0, and the response is `PENDING`. No credentialed Provider endpoint was called. Retention remains `BLOCKED`, Production persistent Twelve Data writes remain disabled, and Stage 7 remains `NO-GO`.

Stage 6K reviewed only the user-provided sanitized body of the follow-up reply. Based on the body identifying itself as a Twelve Data response, it is classified as a `CUSTOMER SUPPORT WRITTEN RESPONSE`, not a Licensing/Data Compliance authorization. The reply date was not provided. No sender name, salutation, signature, email address, account or ticket identifier, private URL, header, or complete private message was retained. The reply confirms that no specific maximum retention period is documented for Basic, Grow, Pro or Ultra; states a 30-day deletion deadline after subscription termination or expiration; and reiterates that `XHKG` and `XJPX` historical data requires a direct exchange license. It does not close the remaining per-data-type, refresh, lifecycle, market-endpoint, BYOK/attribution, or `/api_usage` gaps. No Provider request or new Support message was sent.

### 3.3 Stage 6K twenty-item sufficiency matrix

| # | Evidence item | Result | Sanitized assessment |
|---:|---|---|---|
| 1 | Search/reference metadata | PARTIALLY ANSWERED | General subscription- and third-party-restriction language is provided, but no explicit persistent-cache permission, Plan mapping or duration is supplied. |
| 2 | Quote/market status | PARTIALLY ANSWERED | Covered only by the same general statement; no current/delayed/EOD distinction, Plan mapping or duration is supplied. |
| 3 | Historical OHLCV/EOD | PARTIALLY ANSWERED | No retention duration is supplied; only `XHKG` and `XJPX` direct-license requirements are identified. |
| 4 | Splits | PARTIALLY ANSWERED | The general no-specified-duration statement applies, but action-specific permission, Plan and lifecycle rules are absent. |
| 5 | Dividends | PARTIALLY ANSWERED | The general no-specified-duration statement applies, but action-specific permission, Plan and lifecycle rules are absent. |
| 6 | Maximum retention duration | PARTIALLY ANSWERED | The reply explicitly says no specific maximum is documented for Basic, Grow, Pro or Ultra; it supplies no usable duration. |
| 7 | Refresh/incremental update | NOT ANSWERED | No refresh duty or effect of incremental update on retention is stated. |
| 8 | Disconnect deletion deadline | NOT ANSWERED | Disconnect is not addressed. |
| 9 | Plan downgrade deletion deadline | NOT ANSWERED | Downgrade is not addressed. |
| 10 | Credential expiry deletion deadline | NOT ANSWERED | Subscription expiration is addressed, but credential expiry is a different lifecycle event and is not answered. |
| 11 | Market-entitlement-loss deletion deadline | NOT ANSWERED | Loss of an exchange entitlement is not addressed. |
| 12 | Account/subscription termination deletion deadline | CONFLICTS WITH OFFICIAL TERMS | The reply says within 30 days, while the reviewed public Terms also contain immediate cessation/deletion language. Aureus retains the stricter immediate Provider-scoped purge. |
| 13 | US endpoint conditions | NOT ANSWERED | No minimum Plan or Search/Quote/OHLCV/action conditions are supplied. |
| 14 | `XHKG` endpoint and license | PARTIALLY ANSWERED | Direct exchange licensing is stated for historical data only; endpoint scope, minimum Plan and official license process are absent. |
| 15 | `XSHG` endpoint and license | NOT ANSWERED | No endpoint, Plan or exchange-license condition is supplied. |
| 16 | `XSHE` endpoint and license | NOT ANSWERED | No endpoint, Plan or exchange-license condition is supplied. |
| 17 | `XJPX` endpoint and license | PARTIALLY ANSWERED | Direct exchange licensing is stated for historical data only; endpoint scope, minimum Plan and official license process are absent. |
| 18 | Open-source BYOK | PARTIALLY ANSWERED | Personal/internal non-commercial use and non-redistribution are restated, but open-source per-user BYOK is not explicitly authorized. |
| 19 | Private/internal attribution | NOT ANSWERED | This reply supplies no attribution requirement or exemption. Existing general public guidance remains separate evidence. |
| 20 | `/api_usage` contract | NOT ANSWERED | The reply says field names, nesting and types are not documented and supplies no formal contract. |

Stage 6D adds a local identity-integrity repair: saving a byte-identical Credential after the existing trim/validation step is an idempotent no-op, so it does not rotate the credential generation, reset quota counters or verified limits, clear live observations, cancel transport, or purge cache. Native Picker and Open/Save Panel test helpers now reacquire accessibility elements after each native UI state transition. These synthetic/local checks do not change any Live Acceptance Matrix status.

The isolated 2026-08-13 Stage 6D verification executed 161 Unit/Integration test definitions (194 expanded executions), including 34 focused Market Data Infrastructure tests, with zero failures or skips. The Ledger Picker flow and native CSV Open/Save flow each passed three consecutive focused runs, passed together as 2/2, and the complete UI suite passed 10/10 on its first bounded run. These are local implementation and regression results only. Stage 6G separately established only the sanitized credential-validation result described above.

### 3.4 Termination and deletion

On explicit key deletion or Disconnect, Aureus stops the Provider client and immediately purges only `provider=twelve-data` recoverable rows. On confirmed subscription/entitlement termination it uses the same strict Provider-scoped purge. A transient network, authentication, or ordinary entitlement error is shown as an error and is not silently recast as confirmed termination. No cleanup path receives a `WealthStore`, permanent database URL, arbitrary delete URL, or recursive filesystem capability.

### 3.5 Stage 6I reply sufficiency

| Inquiry item | Result | Sanitized assessment |
|---|---|---|
| Search/reference persistent caching | PARTIALLY ANSWERED | General caching may be permitted in some cases, but Search/reference applicability, Plan and duration are not stated. |
| Quote/market-status persistent caching | PARTIALLY ANSWERED | General caching language is not mapped to Quote/market status, Plan or duration. |
| Historical OHLCV/EOD persistent caching | PARTIALLY ANSWERED | No retention duration is supplied; `XHKG` and `XJPX` historical access is said to require direct exchange licensing. |
| Split/Dividend persistent caching | NOT ANSWERED | No action-specific cache right, Plan or duration is supplied. |
| Maximum retention duration | NOT ANSWERED | The reply explicitly says the maximum timeframe is not specified. |
| Refresh and lifecycle deletion duties | CONFLICTS WITH PUBLIC TERMS | Refresh is unanswered. The reply says deletion requirements are unspecified, while current public Terms require deletion of all Data upon termination. |
| US/`XHKG`/`XSHG`/`XSHE`/`XJPX` differences | PARTIALLY ANSWERED | Only `XHKG` and `XJPX` historical licensing is addressed; US, `XSHG`, `XSHE`, other endpoints and Plan details remain unanswered. |
| Private attribution and open-source BYOK | PARTIALLY ANSWERED | Internal/private attribution exemption is confirmed subject to exchange rules; open-source BYOK rules are not provided. |
| `/api_usage` public response contract | NOT ANSWERED | The reply says Documentation does not list field names, nesting or types. |

## 4. Implemented Infrastructure Acceptance

| Area | Implementation evidence | Candidate result |
|---|---|---|
| Provider boundary | Vendor-neutral Domain values cover search, quote, OHLCV, intervals/ranges, adjustment, corporate actions, native USD/HKD/CNY/JPY quote currency, timestamps, quality, freshness, entitlement, rate limits, and provenance. Twelve DTOs remain private to the adapter. | PASS — synthetic contract tests |
| Twelve Data transport | Foundation ephemeral `URLSession`, `Codable`, actor-owned client, authorization header injection, redacted errors, pagination/incremental history, usage observation, distinct 401 credential / 403 entitlement / 404 missing / 429 rate states, cancellation, and no SDK. | PASS — injected-transport tests; credentialed live calls NOT VERIFIED |
| Capabilities | Basic remains the US-focused Search/OHLCV catalog path and does not advertise Corporate Actions. Verified `/api_usage` plan state, official minimum-plan catalog evidence, endpoint-specific live observation, and market-specific live observation are independent. Observations are keyed by endpoint plus raw market: US Historical success and XHKG Historical denial remain simultaneously visible, with an explicit mixed aggregate, while Quote/Search remain unchanged. A newer observation replaces only its own endpoint/market key. Raw MIC provenance is preserved. Split and Dividend observations update independently. Session-open flags, interval, plan, and catalog do not manufacture freshness; absent explicit response evidence, freshness is `unknown`. | PASS — deterministic mapping and mixed-observation tests; paid markets and actual freshness NOT VERIFIED |
| Request gate and credential lifecycle | Maximum two concurrent requests; Basic seeds 8 credits/minute and 800/day; exact minute-boundary and UTC-midnight resets use checked arithmetic, including negative epoch time. Unknown/untrusted plan text cannot raise limits; a verified paid response can explicitly represent no daily cap. Validation plan/DTO updates preserve the `/api_usage` attempt and rolling counters; a stricter observed header limit is not relaxed. Credits commit only after concurrency admission and every delivered retry attempt is counted. Shared GETs retain immutable request generations. Revoke and rotation close admission, cancel and await every old transport task, then perform cache purge and Keychain deletion in that order for revoke; rotation stores/enables the new credential only after the old transport generation is terminal and does not purge valid cache. A timeout leaves cache and credential untouched and the provider quiesced. | PASS — deterministic clock, retry, generation, controlled-transport and coordinator-order tests |
| Keychain | App-scoped generic-password item with device-only accessibility; native SecureField Save/Update/Validate/Delete/Disconnect; full key is never read back into UI. | PASS — synthetic Keychain lifecycle tests |
| FX | Frankfurter v2 provider-filtered ECB rows, USD/CNY derived cross, reference date, fetch instant, fixed-point conversion, stale/offline/missing states and 24-hour cache policy. | PASS — injected-transport tests and one bounded unauthenticated live response |
| Market Cache | Independent GRDB cache v2, typed metadata/TTL, access tracking, 512 MiB default, 128 MiB–4 GiB range, 90% trigger, 80% target, cleanup ordering, LRU, expired removal, Provider purge, full own-database reset, and write refusal when the bound cannot be met. Legacy `cached_instruments`/`cached_prices` and current entries are all counted and are all eligible for typed expiry/LRU/capacity cleanup. Reducing the configured maximum flushes pending access metadata and atomically persists the policy, cleans both schema generations to the new 80% target, and records `capacityChange`; failure preserves the old policy and data. It does not update launch/periodic/background schedules. | PASS — v1/current migration, mixed-capacity, rollback, scheduling and Permanent-isolation tests |
| Permanent isolation | Automatic TTL, high-water, LRU, Remove Expired, Provider purge, credential deletion, Disconnect, confirmed termination, and full reset preserve permanent URL/hash/schema plus Wealth, Ledger, Snapshot items and FX provenance. | PASS — parameterized integration tests |
| Settings | Native Provider/Keychain and cache controls; Missing/Invalid/Upgrade/Unsupported/Rate Limited states; verified Plan, official catalog minimum, endpoint/market Live observed, and Not verified are displayed separately; raw observed MICs and `unknown` freshness remain visible. Capacity-change feedback reports the new bound and recoverable entries/bytes removed. The retention-blocked message, attribution, cache usage and destructive confirmations remain. Markets remains a Stage 7 Placeholder. | PASS — implementation and synthetic lifecycle UI automation; Stage 6G Production state `Configured` and terminal validation `SUCCESS`, with Plan/Entitlement still `Unknown` |

## 5. Live Provider Acceptance Matrix

`VERIFIED` requires direct official evidence for a non-credential fact or a bounded real endpoint observation. Synthetic payloads never upgrade a live row.

| Acceptance item | Status | Evidence and limitation |
|---|---|---|
| Replacement credential terminal validation | VERIFIED | After user-confirmed server-side revocation/rotation and direct Production SecureField save, one bounded Validate action reached sanitized `SUCCESS`; busy and terminal completion were observed. No credential value, URL, payload, request ID, or exact quota was retained. |
| Actual Provider plan / entitlement | NOT VERIFIED | The same terminal validation displayed categorical Observed Plan `Unknown` and Entitlement `Unknown`; no Basic or paid-plan inference is made. |
| Basic Free published quota | VERIFIED | Official Pricing/credit pages publish 8 credits/minute and 800/day; no actual-key usage observation was made. |
| Basic Free Search | NOT VERIFIED | Adapter and synthetic transport tests pass; Stage 6F did not call Search. |
| Basic Free historical OHLCV | NOT VERIFIED | Official contract and adapter tests exist; no credentialed endpoint was called. |
| Adjustment modes | NOT VERIFIED | Official docs establish the contract; actual endpoint behavior for a user entitlement was not called. |
| Split/Dividend actions | NOT VERIFIED | Official docs establish 20 credits per symbol and Grow individual / Venture business minimum access. Basic is not advertised as capable and no entitled endpoint was called. |
| Usage/credit response headers | NOT VERIFIED | Terminal validation succeeded, but the sanitized UI did not establish header presence or an actual plan/quota category; no exact quota value was recorded. |
| United States endpoint entitlement | NOT VERIFIED | Basic catalog path is published, but Stage 6F did not verify a US Search, Quote, or OHLCV endpoint. |
| `XHKG` | NOT VERIFIED | No Pro-or-higher credential; EOD guide and catalog require entitlement/licensing reconciliation. |
| `XSHG` | NOT VERIFIED | Catalog lists Pro EOD; no Pro-or-higher credentialed endpoint acceptance. |
| `XSHE` | NOT VERIFIED | Catalog lists Pro EOD; no Pro-or-higher credentialed endpoint acceptance. |
| `XJPX` | NOT VERIFIED | No Pro-or-higher credential; EOD guide and catalog require entitlement/licensing reconciliation. |
| Current/delayed/EOD freshness | NOT VERIFIED | DTO/state mapping is tested, but actual key/market response freshness was not observed. |
| Ordinary Twelve Data persistent-cache duration | BLOCKED | No unambiguous public per-data-type duration was directly confirmed. Production persistent Twelve cache writes remain disabled. |
| Personal/internal-use boundary | VERIFIED | Official personal-use guide and Terms support the bounded per-user local model; actual user/plan obligations must still be honored. |
| Disconnect/termination deletion duty | VERIFIED | Official Terms require deletion; conflicting deadline wording is resolved conservatively by immediate Provider-scoped purge on confirmed lifecycle events. |
| Attribution boundary | VERIFIED | Official guidance distinguishes internal/private and external display. This verifies only the general boundary; Settings shows source, and Stage 7 must refresh any surface/market-specific wording. |
| Frankfurter v2 / ECB contract | VERIFIED | Official keyless API, ECB source filter, ECB working-day/reference framework, provenance and reuse guidance were directly reviewed. |
| Live Frankfurter response | VERIFIED | On 2026-08-13 one bounded, unauthenticated request to the official v2 API with `providers=ECB`, base EUR and quotes USD/CNY returned two positive-rate rows for reference date 2026-08-12. The USD→CNY cross was positive. Only sanitized metadata was retained; no raw payload was stored. |

## 6. Privacy and Data Handling Evidence

- No real API key, token, account identifier, Provider request ID, authenticated URL, raw Provider payload, personal symbol list, or financial record appears in this document.
- The Production credential source is Keychain only. Environment variables, launch arguments, `.env`, plist, UserDefaults, SQLite, source defaults, Repository fixtures, and the local manual record are not credential sources.
- Errors and status surfaces contain Provider/operation/error categories, never the key, complete authenticated URL, raw body, portfolio symbols, wealth values, or private path.
- Twelve Data raw payload export is unavailable.
- Provider cache rows are recoverable and physically separate from the Permanent Wealth Store.
- No Git/GitHub command or `.git` access is part of this acceptance process.

## 7. Reviewer-facing Limitations

The implementation candidate can be built and tested without a credential. Stage 6G verifies only a sanitized terminal validation of the securely rotated replacement credential. It does not claim Basic or paid entitlement, Search/Quote/OHLCV/actions acceptance, complete four-market access, exact market freshness, or ordinary persistent-cache rights. If no Pro-or-higher test condition exists, all four international-market endpoint rows must remain `NOT VERIFIED` rather than inferred from catalog visibility, terminal credential validation, or synthetic tests.
