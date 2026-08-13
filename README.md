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

Stages 1 through 5 are frozen after Reviewer Gate PASS. The current state is **Stage 6H External Contract Inquiry — BLOCKED — WAITING FOR PROVIDER RESPONSE**. Wealth, Ledger, and Dashboard continue to use the Permanent Store. Stage 6 adds a Twelve Data `URLSession`/`Codable` adapter, native Keychain-only BYOK lifecycle, Frankfurter/ECB reference FX, a physically independent bounded Market Cache, typed TTL/LRU cleanup, offline/stale states, and minimal Provider/cache controls in Settings. Stage 6D local correctness and native UI regression repairs remain intact. Markets remains an honest Stage 7 Placeholder.

Twelve Data is the frozen Primary Market Data Provider, using a user-owned API key (BYOK) and plan-aware entitlements: Basic Free is the usable US-focused entry path, while complete US/HK/mainland-China/Japan capability depends on the user's own Pro-or-higher entitlement and real endpoint acceptance. No subscription or credential is bundled or shared. Stage 6G treated the Stage 6F credential-boundary incident as a compromise: the local credential was disconnected without reading it, and the user confirmed server-side revocation/rotation before directly saving a replacement through the Production SecureField. Production UI then reported only the categorical state `Configured in Keychain`. Exactly one bounded Validate action reached sanitized terminal category `SUCCESS`, with a maximum theoretical budget of four credits; the observed Plan and Entitlement remained `Unknown`. Search, Quote, OHLCV, actions, exact usage headers, freshness and four-market acceptance therefore remain `NOT VERIFIED`. Current first-party public material still does not establish an unambiguous per-data-type ordinary retention duration; Production persistent Twelve Data cache writes remain disabled. On 2026-08-13, one sanitized inquiry was sent through the official Twelve Data Customer Support form; the response is `PENDING`, and no credentialed endpoint was called in Stage 6H. The previously completed bounded unauthenticated Frankfurter v2 check remains the evidence for the ECB-filtered USD/CNY reference-rate contract; it was not rerun in Stage 6H.

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
