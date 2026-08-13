# Aureus Wealth Terminal

Aureus is a local-first, visualization-first Personal Wealth Intelligence Terminal for macOS.

The product is designed around CNY and USD, with CNY as the default unified valuation currency. It keeps original-currency values, exchange-rate context, and converted values distinct. AI and LLM capabilities are outside the product's long-term scope.

Planned product areas are:

- Dashboard
- Wealth
- Markets
- Portfolio
- Analytics
- Ledger
- Goals
- Settings

Privacy is a hard boundary: real accounts, balances, holdings, transactions, databases, backups, credentials, and private imports or exports must not enter the future public repository. Demos and tests may use only synthetic or sanitized data.

## Current Status

Stages 1 through 5 are frozen after Reviewer Gate PASS. The current state is **Stage 6F Account Bootstrap / External Acceptance — BLOCKED pending validated provider evidence and retention rights**. Wealth, Ledger, and Dashboard continue to use the Permanent Store. Stage 6 adds a Twelve Data `URLSession`/`Codable` adapter, native Keychain-only BYOK lifecycle, Frankfurter/ECB reference FX, a physically independent bounded Market Cache, typed TTL/LRU cleanup, offline/stale states, and minimal Provider/cache controls in Settings. Stage 6D local correctness and native UI regression repairs remain intact. Markets remains an honest Stage 7 Placeholder.

Twelve Data is the frozen Primary Market Data Provider, using a user-owned API key (BYOK) and plan-aware entitlements: Basic Free is the usable US-focused entry path, while complete US/HK/mainland-China/Japan capability depends on the user's own Pro-or-higher entitlement and real endpoint acceptance. No subscription or credential is bundled or shared. In Stage 6F the user completed the official Basic account flow and manually saved the credential through Production Settings; an isolated read-only UI check reported `Configured in Keychain`. One bounded Production Validate action was then triggered, but no Basic plan/entitlement result was confirmed before the verification timeout, so actual plan, Search/Quote/OHLCV/actions and four-market acceptance remain `NOT VERIFIED`. Current first-party public material still does not establish an unambiguous per-data-type ordinary retention duration; Production persistent Twelve Data cache writes remain disabled rather than assuming a right to retain data. The previously completed bounded unauthenticated Frankfurter v2 check remains the evidence for the ECB-filtered USD/CNY reference-rate contract; it was not rerun in Stage 6F.

- [V1 Scope — Frozen](docs/V1_SCOPE.md)
- [V1 Architecture & Technology — Frozen](docs/V1_ARCHITECTURE.md)
- [V1 Research Evidence](docs/V1_RESEARCH_EVIDENCE.md)
- [Stage 6 Market Data Acceptance Evidence](docs/STAGE6_MARKET_DATA_ACCEPTANCE.md)
- [Stage 6 Twelve Data Retention Decision](docs/STAGE6_TWELVE_DATA_RETENTION_DECISION.md)

## Build and Test

Resolve the single external dependency, GRDB 7.11.1:

```sh
xcodebuild -resolvePackageDependencies -project Aureus.xcodeproj -scheme Aureus
```

Build the arm64 Debug app and all test products in isolated DerivedData:

```sh
xcodebuild -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage6-DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage6-DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
```

Run the complete Unit/Integration suite, then the UI suite. The UI test runner uses only local ad-hoc signing and does not require a Development Team:

```sh
xcodebuild test -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage6-DerivedData -only-testing:AureusTests CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage6-UI-DerivedData -only-testing:AureusUITests
```

The canonical product design source for later stages is [Aureus_Wealth_Terminal_项目设计汇总.md](Aureus_Wealth_Terminal_项目设计汇总.md).

The specific open-source license has not yet been frozen. All Git and GitHub operations are managed manually by the user.
