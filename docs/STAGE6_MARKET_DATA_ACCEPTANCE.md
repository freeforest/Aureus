# Stage 6 Market Data Acceptance Evidence

**Status:** Stage 6 Implementation Candidate — awaiting Reviewer Gate  
**Evidence visit:** 2026-08-12–2026-08-13  
**Authority:** This document records Stage 6 implementation and acceptance evidence. It does not replace the frozen V1 Scope or Architecture, prove a paid entitlement, or decide the Stage Gate.

## 1. Acceptance Boundary

Aureus uses Twelve Data as the selected market-data provider with a user-owned API key (BYOK), and Frankfurter v2 filtered to ECB reference rates for USD/CNY reference FX. The Production App accepts a Twelve Data credential only through its native Settings UI and stores it only in the app-scoped macOS Keychain item.

No Twelve Data account, trial, subscription, API key, or credentialed request was created or used in this execution. The local manual secret record was not accessed. Consequently, endpoint behavior that requires an actual Basic or Pro-or-higher entitlement remains `NOT VERIFIED`, even where official documentation establishes the intended contract.

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
| TD-05 | [Credits](https://support.twelvedata.com/en/articles/5615854-credits) | 2026-08-12 | Credits are endpoint-weighted, daily limits reset on a documented schedule, and exhausted quotas produce rate-limit behavior. | VERIFIED | Endpoint weights are explicit; 429 and `Retry-After` map to rate-limited state. |
| TD-06 | [Historical prices](https://support.twelvedata.com/en/articles/5656039-how-to-get-historical-prices) | 2026-08-12 | Historical time series supports bounded output, date/range selection and incremental update guidance; the page recommends caching history once and updating incrementally. | VERIFIED | History requests paginate, merge deterministically, and never imply a right to persist beyond Terms. |
| TD-07 | [Price adjustment](https://support.twelvedata.com/en/articles/5179064-are-the-prices-adjusted) | 2026-08-12 | Daily/weekly/monthly data is described as split-adjusted; intraday is unadjusted; splits and dividends support client-side adjustment. | VERIFIED | Domain records adjustment provenance and actions instead of treating every series as equivalent. |
| TD-08 | [Available symbols](https://support.twelvedata.com/en/articles/5620513-how-to-find-all-available-symbols-at-twelve-data) | 2026-08-12 | Official reference/search mechanisms expose supported symbol metadata. | VERIFIED | Search results remain entitlement-aware and retain MIC/exchange/native quote currency. |
| TD-09 | [End-of-day pricing market data](https://support.twelvedata.com/en/articles/12682324-end-of-day-eod-pricing-market-data) | 2026-08-12 | The current guide describes EOD data and flags `XHKG` and `XJPX` as requiring licensing/current-support confirmation. | CONFLICTING with a simple catalog-based Pro inference | HK and Japan cannot be marked verified from the Exchange Catalog. |
| TD-10 | [Commercial and personal usage](https://support.twelvedata.com/en/articles/5332349-commercial-and-personal-usage) | 2026-08-12 | Individual tiers are for personal/internal use; redistribution and external/commercial display require applicable rights. | VERIFIED at general level | BYOK data remains local to the corresponding user and raw Provider export is disabled. |
| TD-11 | [Twelve Data Terms](https://twelvedata.com/terms) | 2026-08-12 | Internal processing/storage is limited by Plan and Documentation; redistribution is restricted; termination requires deletion. Public wording observed in the page does not yield an unambiguous per-data-type ordinary cache duration and contains different termination-retention wording. | VERIFIED general duty; CONFLICTING/UNVERIFIED exact retention deadline | Persistent Twelve Data cache writes are disabled until the applicable retention right is verified. Disconnect/key deletion uses immediate Provider-scoped purge; confirmed termination uses the stricter deletion path. |
| TD-12 | [Attribution guidelines](https://support.twelvedata.com/en/articles/12647398-attribution-guidelines-for-using-twelve-data) | 2026-08-12 | Attribution differs between internal/private and external/public display and may include market-specific obligations. | VERIFIED at general level | Settings shows a compact source label; Stage 7 must refresh any surface-specific notice before displaying Provider data. |
| TD-13 | [Twelve Data service status](https://twelvedata.isitup.cloud/) | 2026-08-12 | The official status surface reported the service operational during the visit. | VERIFIED point-in-time only | This is maintenance evidence, not an SLA or endpoint acceptance result. |
| FF-01 | [Frankfurter v2 API](https://frankfurter.dev/) | 2026-08-12 | Frankfurter v2 is keyless, supports historical rates and provider filtering, documents responsible use/caching, and can return ECB-provider rows for USD and CNY. | VERIFIED for documented contract | Adapter filters to ECB and derives CNY per USD from the two EUR reference legs. |
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

### 3.3 Termination and deletion

On explicit key deletion or Disconnect, Aureus stops the Provider client and immediately purges only `provider=twelve-data` recoverable rows. On confirmed subscription/entitlement termination it uses the same strict Provider-scoped purge. A transient network, authentication, or ordinary entitlement error is shown as an error and is not silently recast as confirmed termination. No cleanup path receives a `WealthStore`, permanent database URL, arbitrary delete URL, or recursive filesystem capability.

## 4. Implemented Infrastructure Acceptance

| Area | Implementation evidence | Candidate result |
|---|---|---|
| Provider boundary | Vendor-neutral Domain values cover search, quote, OHLCV, intervals/ranges, adjustment, corporate actions, native USD/HKD/CNY/JPY quote currency, timestamps, quality, freshness, entitlement, rate limits, and provenance. Twelve DTOs remain private to the adapter. | PASS — synthetic contract tests |
| Twelve Data transport | Foundation ephemeral `URLSession`, `Codable`, actor-owned client, authorization header injection, redacted errors, pagination/incremental history, usage observation, typed HTTP/provider/data failures, cancellation, and no SDK. | PASS — injected-transport tests; live calls NOT VERIFIED |
| Request gate | Maximum two concurrent requests; Basic seeds 8 credits/minute and 800/day; explicit endpoint weights; observed stricter limits; identical in-flight request deduplication; GET-only transient retry, `Retry-After`, initial plus at most three retries, bounded jitter and injectable sleeper. | PASS — deterministic tests |
| Keychain | App-scoped generic-password item with device-only accessibility; native SecureField Save/Update/Validate/Delete/Disconnect; full key is never read back into UI. | PASS — synthetic Keychain lifecycle tests |
| FX | Frankfurter v2 provider-filtered ECB rows, USD/CNY derived cross, reference date, fetch instant, fixed-point conversion, stale/offline/missing states and 24-hour cache policy. | PASS — injected-transport tests; public live service call NOT REQUIRED for code acceptance |
| Market Cache | Independent GRDB cache v2, typed metadata/TTL, access tracking, 512 MiB default, 128 MiB–4 GiB range, 90% trigger, 80% target, cleanup ordering, LRU, expired removal, Provider purge, full own-database reset, and write refusal when the bound cannot be met. | PASS — cache/migration/isolation tests |
| Permanent isolation | Automatic TTL, high-water, LRU, Remove Expired, Provider purge, credential deletion, Disconnect, confirmed termination, and full reset preserve permanent URL/hash/schema plus Wealth, Ledger, Snapshot items and FX provenance. | PASS — parameterized integration tests |
| Settings | Native Provider/Keychain and cache controls, plan metadata separated from observed entitlement, five-market status, freshness/error states, attribution, last validation, cache usage and destructive confirmations. Markets remains a Stage 7 Placeholder. | PASS — UI automation |

## 5. Live Provider Acceptance Matrix

`VERIFIED` requires direct official evidence for a non-credential fact or a bounded real endpoint observation. Synthetic payloads never upgrade a live row.

| Acceptance item | Status | Evidence and limitation |
|---|---|---|
| Basic Free published quota | VERIFIED | Official Pricing/credit pages publish 8 credits/minute and 800/day; no actual-key usage observation was made. |
| Basic Free Search | NOT VERIFIED | Adapter and synthetic transport tests pass; no Production Keychain credential was present for a real request. |
| Basic Free historical OHLCV | NOT VERIFIED | Official contract and adapter tests exist; no credentialed endpoint was called. |
| Adjustment modes | NOT VERIFIED | Official docs establish the contract; actual endpoint behavior for a user entitlement was not called. |
| Split/Dividend actions | NOT VERIFIED | Official docs establish endpoints/credit cost and plan gating; no entitled endpoint was called. |
| Usage/credit response headers | NOT VERIFIED | Published contract is verified; current-key values were not requested or recorded. |
| United States endpoint entitlement | NOT VERIFIED | Basic catalog path is published, but this execution did not possess or validate a Production Keychain credential. |
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
| Live Frankfurter response | NOT VERIFIED | Implementation uses injected synthetic transport for acceptance; no live payload is stored or cited as test evidence. |

## 6. Privacy and Data Handling Evidence

- No real API key, token, account identifier, Provider request ID, authenticated URL, raw Provider payload, personal symbol list, or financial record appears in this document.
- The Production credential source is Keychain only. Environment variables, launch arguments, `.env`, plist, UserDefaults, SQLite, source defaults, Repository fixtures, and the local manual record are not credential sources.
- Errors and status surfaces contain Provider/operation/error categories, never the key, complete authenticated URL, raw body, portfolio symbols, wealth values, or private path.
- Twelve Data raw payload export is unavailable.
- Provider cache rows are recoverable and physically separate from the Permanent Wealth Store.
- No Git/GitHub command or `.git` access is part of this acceptance process.

## 7. Reviewer-facing Limitations

The implementation candidate can be built and tested without a credential. It does not claim live Twelve Data acceptance, paid entitlement, complete four-market access, exact market freshness, or ordinary persistent-cache rights. A later bounded acceptance run is allowed only after a user independently enters a credential through the Production Settings UI. If no Pro-or-higher test condition exists, all four international-market endpoint rows must remain `NOT VERIFIED` rather than inferred from catalog visibility or synthetic tests.
