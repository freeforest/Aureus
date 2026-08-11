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

Stage 1 and Stage 2 are frozen after Reviewer Gate PASS. The current state is **Stage 3 Implementation Candidate — Awaiting Reviewer Gate**. The native Wealth workspace now supports persistent Container CRUD for bank/cash, stock, ETF, fund, insurance cash value, other assets, and liabilities; CNY aggregation; and manual USD → CNY valuation with retained FX provenance. All market-security values are explicitly manual—no live Provider is connected.

Twelve Data is the frozen Primary Market Data Provider, using a user-owned API key (BYOK) and plan-aware entitlements: Basic Free is the usable US-focused entry path, while complete US/HK/mainland-China/Japan capability depends on the user's Pro-or-higher entitlement and later Stage 6 verification. Provider integration remains outside Stage 3; the app contains provider-independent contracts only and does not make live Provider requests.

- [V1 Scope — Frozen](docs/V1_SCOPE.md)
- [V1 Architecture & Technology — Frozen](docs/V1_ARCHITECTURE.md)
- [V1 Research Evidence](docs/V1_RESEARCH_EVIDENCE.md)

## Build and Test

Resolve the single external dependency, GRDB 7.11.1:

```sh
xcodebuild -resolvePackageDependencies -project Aureus.xcodeproj -scheme Aureus
```

Build the arm64 Debug app and all test products in isolated DerivedData:

```sh
xcodebuild -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage3-DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage3-DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing
```

Run the complete Unit/Integration suite, then the UI suite. The UI test runner uses only local ad-hoc signing and does not require a Development Team:

```sh
xcodebuild test-without-building -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage3-DerivedData -only-testing:AureusTests CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
xcodebuild test-without-building -project Aureus.xcodeproj -scheme Aureus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/Aureus-Stage3-DerivedData -only-testing:AureusUITests CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

The canonical product design source for later stages is [Aureus_Wealth_Terminal_项目设计汇总.md](Aureus_Wealth_Terminal_项目设计汇总.md).

The specific open-source license has not yet been frozen. All Git and GitHub operations are managed manually by the user.
