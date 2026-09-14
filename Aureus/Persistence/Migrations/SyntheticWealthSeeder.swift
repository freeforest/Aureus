import Foundation

enum SyntheticWealthSeeder {
    static let demoDate = try! CivilDate(canonical: "2026-01-15")
    static let demoInstant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)

    static func records() throws -> [WealthContainer] {
        let manualRate = try FXRate(
            decimal: FixedPointMath.parseCanonical("7.1250000000"),
            sourceCurrency: .usd,
            targetCurrency: .cny
        )
        let manualFX = try ManualFXInput(
            rate: manualRate,
            source: "manual.synthetic.stage3",
            referenceDate: demoDate,
            recordedAt: demoInstant,
            isStale: false
        )

        return [
            try makeRecord(
                id: "00000000-0000-4000-8000-000000003001",
                name: "Synthetic CNY Cash Lab",
                kind: .bankCash,
                institution: "Fictional Pine Bank",
                currency: .cny,
                notes: "Synthetic demonstration balance only.",
                details: .bankCash(
                    balance: try Money(
                        decimal: FixedPointMath.parseCanonical("125000.00"),
                        currency: .cny
                    ),
                    interestRate: try Percentage(
                        decimal: FixedPointMath.parseCanonical("0.0125000000")
                    )
                ),
                manualFX: nil
            ),
            try makeRecord(
                id: "00000000-0000-4000-8000-000000003002",
                name: "Synthetic USD Cash Lab",
                kind: .bankCash,
                institution: "Fictional Cedar Bank",
                currency: .usd,
                notes: "Synthetic USD balance with a manual FX rate.",
                details: .bankCash(
                    balance: try Money(
                        decimal: FixedPointMath.parseCanonical("1000.00"),
                        currency: .usd
                    ),
                    interestRate: nil
                ),
                manualFX: manualFX
            ),
            try makeRecord(
                id: "00000000-0000-4000-8000-000000003003",
                name: "Synthetic Orchard Stock",
                kind: .stock,
                institution: "Fictional North Broker",
                currency: .usd,
                notes: "Manual valuation; no market Provider data.",
                details: .security(
                    ticker: "SYNX",
                    mic: "XSYN",
                    quantity: try AssetQuantity(
                        decimal: FixedPointMath.parseCanonical("12.50000000")
                    ),
                    manualPrice: try MarketPrice(
                        decimal: FixedPointMath.parseCanonical("40.00000000"),
                        quoteCurrency: .usd
                    )
                ),
                manualFX: manualFX
            ),
            try makeRecord(
                id: "00000000-0000-4000-8000-000000003004",
                name: "Synthetic River Fund",
                kind: .fund,
                institution: "Fictional Garden Fund House",
                currency: .cny,
                notes: "Synthetic manual fund valuation.",
                details: .security(
                    ticker: "SYN-FUND",
                    mic: nil,
                    quantity: try AssetQuantity(
                        decimal: FixedPointMath.parseCanonical("100.00000000")
                    ),
                    manualPrice: try MarketPrice(
                        decimal: FixedPointMath.parseCanonical("12.34560000"),
                        quoteCurrency: .cny
                    )
                ),
                manualFX: nil
            ),
            try makeRecord(
                id: "00000000-0000-4000-8000-000000003005",
                name: "Synthetic Harbor Policy",
                kind: .insurance,
                institution: "Fictional Harbor Assurance",
                currency: .cny,
                notes: "Only synthetic cash value contributes to wealth.",
                details: .insurance(
                    company: "Fictional Harbor Assurance",
                    productName: "Synthetic Steady Harbor Plan",
                    premium: Money(minorUnits: 500_000, currency: .cny),
                    paymentFrequency: .annual,
                    coverage: Money(minorUnits: 100_000_000, currency: .cny),
                    currentCashValue: Money(minorUnits: 2_000_000, currency: .cny),
                    startDate: try CivilDate(canonical: "2024-01-15"),
                    maturityDate: try CivilDate(canonical: "2034-01-15")
                ),
                manualFX: nil
            ),
            try makeRecord(
                id: "00000000-0000-4000-8000-000000003006",
                name: "Synthetic Workshop Asset",
                kind: .otherAsset,
                institution: nil,
                currency: .cny,
                notes: "Synthetic simple valued asset.",
                details: .otherAsset(
                    categoryDescription: "Synthetic equipment",
                    currentValue: Money(minorUnits: 800_000, currency: .cny)
                ),
                manualFX: nil
            ),
            try makeRecord(
                id: "00000000-0000-4000-8000-000000003007",
                name: "Synthetic USD Liability",
                kind: .liability,
                institution: "Fictional Stone Lender",
                currency: .usd,
                notes: "Positive magnitude; deducted exactly once.",
                details: .liability(
                    outstandingBalance: Money(minorUnits: 200_000, currency: .usd),
                    interestRate: try Percentage(
                        decimal: FixedPointMath.parseCanonical("0.0450000000")
                    )
                ),
                manualFX: manualFX
            )
        ]
    }

    private static func makeRecord(
        id: String,
        name: String,
        kind: AssetContainerKind,
        institution: String?,
        currency: CurrencyCode,
        notes: String?,
        details: WealthRecordDetails,
        manualFX: ManualFXInput?
    ) throws -> WealthContainer {
        let original = try details.currentValue()
        let valuation = try WealthValuation.valuation(
            original: original,
            manualFX: manualFX,
            identityDate: demoDate,
            recordedAt: demoInstant
        )
        return try WealthContainer(
            container: AssetContainer(
                id: UUID(uuidString: id)!,
                accountID: nil,
                name: name,
                kind: kind,
                institution: institution,
                primaryCurrency: currency,
                notes: notes,
                createdDate: demoDate,
                updatedDate: demoDate
            ),
            details: details,
            valuation: valuation
        )
    }
}
