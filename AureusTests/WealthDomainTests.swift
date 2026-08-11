import Foundation
import Testing
@testable import Aureus

@Suite("Stage 3 wealth domain")
struct WealthDomainTests {
    @Test("CNY identity and USD manual FX retain full provenance")
    func valuationProvenance() throws {
        let date = try CivilDate(canonical: "2026-08-11")
        let instant = UTCInstant(millisecondsSince1970: 1_786_374_000_000)
        let cny = Money(minorUnits: 12_345, currency: .cny)
        let identity = try WealthValuation.valuation(
            original: cny, manualFX: nil, identityDate: date, recordedAt: instant
        )
        #expect(identity.original == cny)
        #expect(identity.rate == .cnyIdentity)
        #expect(identity.convertedCNY == cny)
        #expect(identity.providerIdentifier == "identity")
        #expect(!identity.isManualOverride)

        let usd = Money(minorUnits: 10_000, currency: .usd)
        let manual = try manualFX("7.125", date: date, instant: instant)
        let converted = try WealthValuation.valuation(
            original: usd, manualFX: manual, identityDate: date, recordedAt: instant
        )
        #expect(converted.original == usd)
        #expect(converted.rate.sourceCurrency == .usd)
        #expect(converted.rate.targetCurrency == .cny)
        #expect(converted.convertedCNY == Money(minorUnits: 71_250, currency: .cny))
        #expect(converted.referenceDate == date)
        #expect(converted.fetchedAt == instant)
        #expect(converted.providerIdentifier == "manual")
        #expect(converted.isManualOverride)
    }

    @Test("USD valuation rejects missing, reversed, zero, and negative FX")
    func invalidFX() throws {
        let date = try CivilDate(canonical: "2026-08-11")
        let instant = UTCInstant(millisecondsSince1970: 1_786_374_000_000)
        let usd = Money(minorUnits: 100, currency: .usd)

        #expect(throws: WealthDomainError.missingManualFX) {
            _ = try WealthValuation.valuation(
                original: usd, manualFX: nil, identityDate: date, recordedAt: instant
            )
        }
        #expect(throws: FinancialValueError.directionMismatch) {
            let wrong = try ManualFXInput(
                rate: FXRate(coefficient: 10_000_000_000, sourceCurrency: .cny, targetCurrency: .cny),
                referenceDate: date,
                recordedAt: instant,
                isStale: false
            )
            _ = try WealthValuation.valuation(
                original: usd, manualFX: wrong, identityDate: date, recordedAt: instant
            )
        }
        #expect(throws: FinancialValueError.nonPositiveRate) {
            _ = try FXRate(coefficient: 0, sourceCurrency: .usd, targetCurrency: .cny)
        }
        #expect(throws: FinancialValueError.nonPositiveRate) {
            _ = try FXRate(coefficient: -1, sourceCurrency: .usd, targetCurrency: .cny)
        }
    }

    @Test("Quantity times manual price uses Decimal and half-even money rounding")
    func manualMarketValue() throws {
        let one = try AssetQuantity(decimal: Decimal(string: "1")!)
        let lowerTie = try MarketPrice(decimal: Decimal(string: "1.005")!, quoteCurrency: .cny)
        let upperTie = try MarketPrice(decimal: Decimal(string: "1.015")!, quoteCurrency: .cny)
        #expect(try WealthValuation.marketValue(quantity: one, price: lowerTie).minorUnits == 100)
        #expect(try WealthValuation.marketValue(quantity: one, price: upperTie).minorUnits == 102)

        let quantity = try AssetQuantity(decimal: Decimal(string: "12.5")!)
        let price = try MarketPrice(decimal: Decimal(string: "40")!, quoteCurrency: .usd)
        #expect(
            try WealthValuation.marketValue(quantity: quantity, price: price)
                == Money(minorUnits: 50_000, currency: .usd)
        )
    }

    @Test("Checked aggregation subtracts positive liabilities exactly once")
    func aggregation() throws {
        let records = try SyntheticWealthSeeder.records()
        let summary = try WealthValuation.aggregate(records)
        #expect(summary.totalAssetsCNY == Money(minorUnits: 16_492_206, currency: .cny))
        #expect(summary.totalLiabilitiesCNY == Money(minorUnits: 1_425_000, currency: .cny))
        #expect(summary.netWorthCNY == Money(minorUnits: 15_067_206, currency: .cny))

        let insurance = try #require(records.first { $0.container.kind == .insurance })
        guard case let .insurance(_, _, premium, _, coverage, cashValue, _, _) = insurance.details else {
            Issue.record("Expected an insurance record")
            return
        }
        #expect(premium.minorUnits == 500_000)
        #expect(coverage.minorUnits == 100_000_000)
        #expect(cashValue.minorUnits == 2_000_000)
        #expect(insurance.originalValue == cashValue)
    }

    @Test("Currency mismatch and arithmetic overflow are explicit")
    func checkedFinancialFailures() throws {
        #expect(throws: FinancialValueError.currencyMismatch(expected: .cny, actual: .usd)) {
            _ = try Money(minorUnits: 1, currency: .cny)
                .adding(Money(minorUnits: 1, currency: .usd))
        }
        #expect(throws: FinancialValueError.overflow) {
            _ = try Money(minorUnits: Int64.max, currency: .cny)
                .adding(Money(minorUnits: 1, currency: .cny))
        }
        #expect(throws: FinancialValueError.overflow) {
            _ = try WealthValuation.marketValue(
                quantity: AssetQuantity(coefficient: Int64.max),
                price: MarketPrice(coefficient: Int64.max, quoteCurrency: .cny)
            )
        }
    }

    private func manualFX(
        _ rate: String,
        date: CivilDate,
        instant: UTCInstant
    ) throws -> ManualFXInput {
        try ManualFXInput(
            rate: FXRate(
                decimal: Decimal(string: rate)!, sourceCurrency: .usd, targetCurrency: .cny
            ),
            source: "manual",
            referenceDate: date,
            recordedAt: instant,
            isStale: false
        )
    }
}
