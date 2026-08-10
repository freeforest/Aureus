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

The repository contains the project design and repository-governance baseline, but no buildable app, business implementation, build target, or test target.

Stage 1 now contains a Final Freeze Candidate awaiting Reviewer Gate; no implementation stage has begun. Twelve Data is the user-authorized Primary Market Data Provider candidate, using a user-owned API key (BYOK) and plan-aware entitlements: Basic Free is the usable US-focused entry path, while complete US/HK/mainland-China/Japan capability depends on the user's Pro-or-higher entitlement and later Stage 6 verification.

- [V1 Scope Freeze Candidate](docs/V1_SCOPE.md)
- [V1 Architecture & Technology Freeze Candidate](docs/V1_ARCHITECTURE.md)
- [V1 Research Evidence](docs/V1_RESEARCH_EVIDENCE.md)

The canonical product design source for later stages is [Aureus_Wealth_Terminal_项目设计汇总.md](Aureus_Wealth_Terminal_项目设计汇总.md).

The specific open-source license has not yet been frozen. All Git and GitHub operations are managed manually by the user.
