import Foundation
import Testing
@testable import Aureus

@Suite("Financial value foundations")
struct FinancialValueTests {
    @Test("Money construction and Decimal round-trip")
    func moneyConstruction() throws {
        let money = try Money(
            decimal: FixedPointMath.parseCanonical("123.45"),
            currency: .cny
        )
        let expected = try FixedPointMath.parseCanonical("123.45")
        #expect(money.minorUnits == 12_345)
        #expect(money.decimal == expected)
    }

    @Test("Money rejects mixed-currency arithmetic")
    func currencyMismatch() {
        let cny = Money(minorUnits: 100, currency: .cny)
        let usd = Money(minorUnits: 100, currency: .usd)
        var captured: FinancialValueError?
        do {
            _ = try cny.adding(usd)
        } catch let error as FinancialValueError {
            captured = error
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(captured == .currencyMismatch(expected: .cny, actual: .usd))
    }

    @Test("Checked add and subtract do not wrap")
    func checkedArithmeticAndOverflow() throws {
        let left = Money(minorUnits: 500, currency: .usd)
        let right = Money(minorUnits: 125, currency: .usd)
        #expect(try left.adding(right) == Money(minorUnits: 625, currency: .usd))
        #expect(try left.subtracting(right) == Money(minorUnits: 375, currency: .usd))

        var captured: FinancialValueError?
        do {
            _ = try Money(minorUnits: .max, currency: .cny)
                .adding(Money(minorUnits: 1, currency: .cny))
        } catch let error as FinancialValueError {
            captured = error
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(captured == .overflow)
    }

    @Test("Round-half-even handles positive and negative ties")
    func bankersRounding() throws {
        #expect(try Money(decimal: FixedPointMath.parseCanonical("1.005"), currency: .cny).minorUnits == 100)
        #expect(try Money(decimal: FixedPointMath.parseCanonical("1.015"), currency: .cny).minorUnits == 102)
        #expect(try Money(decimal: FixedPointMath.parseCanonical("-1.005"), currency: .cny).minorUnits == -100)
        #expect(try Money(decimal: FixedPointMath.parseCanonical("-1.015"), currency: .cny).minorUnits == -102)
        #expect(try Money(decimal: .zero, currency: .usd).minorUnits == 0)
    }

    @Test("Fixed scales remain semantically distinct")
    func semanticScales() throws {
        let quantity = try AssetQuantity(decimal: FixedPointMath.parseCanonical("1.23456789"))
        let price = try MarketPrice(
            decimal: FixedPointMath.parseCanonical("9.87654321"),
            quoteCurrency: .usd
        )
        let rate = try FXRate(
            decimal: FixedPointMath.parseCanonical("7.1234567890"),
            sourceCurrency: .usd,
            targetCurrency: .cny
        )
        let percentage = try Percentage(decimal: FixedPointMath.parseCanonical("0.1250000000"))
        let ratio = try Ratio(decimal: FixedPointMath.parseCanonical("1.5000000000"))

        #expect(quantity.coefficient == 123_456_789)
        #expect(price.coefficient == 987_654_321)
        #expect(rate.coefficient == 71_234_567_890)
        #expect(percentage.coefficient == 1_250_000_000)
        #expect(ratio.coefficient == 15_000_000_000)
    }

    @Test("USD to CNY keeps direction and provenance")
    func fxValuationProvenance() throws {
        let original = Money(minorUnits: 1_000, currency: .usd)
        let rate = try FXRate(
            decimal: FixedPointMath.parseCanonical("7.1230000000"),
            sourceCurrency: .usd,
            targetCurrency: .cny
        )
        let date = try CivilDate(canonical: "2026-01-15")
        let instant = UTCInstant(millisecondsSince1970: 1_768_435_200_000)
        let valuation = try FXValuation(
            original: original,
            rate: rate,
            referenceDate: date,
            fetchedAt: instant,
            providerIdentifier: "synthetic.stage2.fx",
            isStale: false
        )

        #expect(valuation.original == original)
        #expect(valuation.rate.sourceCurrency == .usd)
        #expect(valuation.rate.targetCurrency == .cny)
        #expect(valuation.convertedCNY == Money(minorUnits: 7_123, currency: .cny))
        #expect(valuation.referenceDate == date)
        #expect(valuation.fetchedAt == instant)
    }

    @Test("FX direction mismatch is explicit")
    func fxDirectionMismatch() throws {
        let rate = try FXRate(
            decimal: FixedPointMath.parseCanonical("7.1000000000"),
            sourceCurrency: .usd,
            targetCurrency: .cny
        )
        var captured: FinancialValueError?
        do {
            _ = try rate.convert(Money(minorUnits: 100, currency: .cny))
        } catch let error as FinancialValueError {
            captured = error
        } catch {
            Issue.record("Unexpected error type")
        }
        #expect(captured == .currencyMismatch(expected: .usd, actual: .cny))
    }

    @Test("Maximum persisted coefficient is representable")
    func maximumBoundary() {
        let maximum = Money(minorUnits: .max, currency: .cny)
        #expect(maximum.minorUnits == Int64.max)
    }
}
