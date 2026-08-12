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

Stages 1 through 5 are frozen after Reviewer Gate PASS. The current state is **Stage 6C Repair Candidate — Awaiting Reviewer Gate**. Wealth, Ledger, and Dashboard continue to use the Permanent Store. Stage 6 adds a Twelve Data `URLSession`/`Codable` adapter, native Keychain-only BYOK lifecycle, Frankfurter/ECB reference FX, a physically independent bounded Market Cache, typed TTL/LRU cleanup, offline/stale states, and minimal Provider/cache controls in Settings. Stage 6C makes credential revoke/rotation wait for old transport termination, preserves real validation credit usage, retains endpoint-by-market success and denial as simultaneous facts, and applies checked arithmetic to rate-window boundaries. Markets remains an honest Stage 7 Placeholder.

Twelve Data is the frozen Primary Market Data Provider, using a user-owned API key (BYOK) and plan-aware entitlements: Basic Free is the usable US-focused entry path, while complete US/HK/mainland-China/Japan capability depends on the user's own Pro-or-higher entitlement and real endpoint acceptance. No subscription or credential is bundled or shared. A read-only Production Settings observation on 2026-08-13 reported `Missing`; no credentialed call was attempted, so Search/OHLCV/actions/four-market acceptance remains `NOT VERIFIED`. Public documentation did not establish an unambiguous per-data-type ordinary retention duration; Production persistent Twelve Data cache writes remain disabled rather than assuming a right to retain data. A bounded unauthenticated Frankfurter v2 call verified the ECB-filtered USD/CNY reference-rate contract; its cache policy remains 24 hours.

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
