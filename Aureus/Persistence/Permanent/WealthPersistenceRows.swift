import Foundation
import GRDB

enum WealthPersistenceError: Error, Equatable, Sendable {
    case containerNotFound
    case protectedPermanentDependents
    case corruptIdentifier
    case corruptCurrency
    case corruptKind
    case corruptDate
    case corruptRecord
    case storedValuationMismatch
}

struct AssetContainerPersistenceRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "asset_containers"

    let id: String
    let accountID: String?
    let name: String
    let kind: String
    let institution: String?
    let primaryCurrencyCode: String
    let notes: String?
    let createdDate: String
    let updatedDate: String

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case name
        case kind
        case institution
        case primaryCurrencyCode = "primary_currency_code"
        case notes
        case createdDate = "created_date"
        case updatedDate = "updated_date"
    }

    init(container: AssetContainer) {
        id = container.id.uuidString
        accountID = container.accountID?.uuidString
        name = container.name
        kind = container.kind.rawValue
        institution = container.institution
        primaryCurrencyCode = container.primaryCurrency.rawValue
        notes = container.notes
        createdDate = container.createdDate.description
        updatedDate = container.updatedDate.description
    }

    func domain() throws -> AssetContainer {
        guard let id = UUID(uuidString: id) else { throw WealthPersistenceError.corruptIdentifier }
        let accountID: UUID?
        if let rawAccountID = self.accountID {
            guard let parsed = UUID(uuidString: rawAccountID) else {
                throw WealthPersistenceError.corruptIdentifier
            }
            accountID = parsed
        } else {
            accountID = nil
        }
        guard let kind = AssetContainerKind(rawValue: kind) else {
            throw WealthPersistenceError.corruptKind
        }
        guard let currency = CurrencyCode(rawValue: primaryCurrencyCode) else {
            throw WealthPersistenceError.corruptCurrency
        }
        guard let created = try? CivilDate(canonical: createdDate),
              let updated = try? CivilDate(canonical: updatedDate) else {
            throw WealthPersistenceError.corruptDate
        }
        return AssetContainer(
            id: id,
            accountID: accountID,
            name: name,
            kind: kind,
            institution: institution,
            primaryCurrency: currency,
            notes: notes,
            createdDate: created,
            updatedDate: updated
        )
    }
}

struct WealthRecordPersistenceRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "wealth_records"

    let containerID: String
    let recordKind: String
    let originalMinor: Int64
    let originalCurrencyCode: String
    let convertedCNYMinor: Int64
    let fxCoefficient: Int64
    let fxSourceCurrencyCode: String
    let fxTargetCurrencyCode: String
    let fxSource: String
    let fxReferenceDate: String
    let fxRecordedAtMilliseconds: Int64
    let fxIsManual: Bool
    let fxIsStale: Bool
    let interestRateCoefficient: Int64?
    let ticker: String?
    let mic: String?
    let quantityCoefficient: Int64?
    let manualPriceCoefficient: Int64?
    let insuranceCompany: String?
    let insuranceProductName: String?
    let premiumMinor: Int64?
    let paymentFrequency: String?
    let coverageMinor: Int64?
    let startDate: String?
    let maturityDate: String?
    let categoryDescription: String?

    enum CodingKeys: String, CodingKey {
        case containerID = "container_id"
        case recordKind = "record_kind"
        case originalMinor = "original_minor"
        case originalCurrencyCode = "original_currency_code"
        case convertedCNYMinor = "converted_cny_minor"
        case fxCoefficient = "fx_coefficient"
        case fxSourceCurrencyCode = "fx_source_currency_code"
        case fxTargetCurrencyCode = "fx_target_currency_code"
        case fxSource = "fx_source"
        case fxReferenceDate = "fx_reference_date"
        case fxRecordedAtMilliseconds = "fx_recorded_at_ms"
        case fxIsManual = "fx_is_manual"
        case fxIsStale = "fx_is_stale"
        case interestRateCoefficient = "interest_rate_coefficient"
        case ticker
        case mic
        case quantityCoefficient = "quantity_coefficient"
        case manualPriceCoefficient = "manual_price_coefficient"
        case insuranceCompany = "insurance_company"
        case insuranceProductName = "insurance_product_name"
        case premiumMinor = "premium_minor"
        case paymentFrequency = "payment_frequency"
        case coverageMinor = "coverage_minor"
        case startDate = "start_date"
        case maturityDate = "maturity_date"
        case categoryDescription = "category_description"
    }

    init(record: WealthContainer) {
        containerID = record.id.uuidString
        recordKind = record.container.kind.rawValue
        originalMinor = record.originalValue.minorUnits
        originalCurrencyCode = record.originalValue.currency.rawValue
        convertedCNYMinor = record.convertedCNYValue.minorUnits
        fxCoefficient = record.valuation.rate.coefficient
        fxSourceCurrencyCode = record.valuation.rate.sourceCurrency.rawValue
        fxTargetCurrencyCode = record.valuation.rate.targetCurrency.rawValue
        fxSource = record.valuation.providerIdentifier
        fxReferenceDate = record.valuation.referenceDate.description
        fxRecordedAtMilliseconds = record.valuation.fetchedAt.millisecondsSince1970
        fxIsManual = record.valuation.isManualOverride
        fxIsStale = record.valuation.isStale

        switch record.details {
        case let .bankCash(_, interestRate), let .liability(_, interestRate):
            interestRateCoefficient = interestRate?.coefficient
            ticker = nil
            mic = nil
            quantityCoefficient = nil
            manualPriceCoefficient = nil
            insuranceCompany = nil
            insuranceProductName = nil
            premiumMinor = nil
            paymentFrequency = nil
            coverageMinor = nil
            startDate = nil
            maturityDate = nil
            categoryDescription = nil
        case let .security(ticker, mic, quantity, manualPrice):
            interestRateCoefficient = nil
            self.ticker = ticker
            self.mic = mic
            quantityCoefficient = quantity.coefficient
            manualPriceCoefficient = manualPrice.coefficient
            insuranceCompany = nil
            insuranceProductName = nil
            premiumMinor = nil
            paymentFrequency = nil
            coverageMinor = nil
            startDate = nil
            maturityDate = nil
            categoryDescription = nil
        case let .insurance(company, productName, premium, frequency, coverage, _, start, maturity):
            interestRateCoefficient = nil
            ticker = nil
            mic = nil
            quantityCoefficient = nil
            manualPriceCoefficient = nil
            insuranceCompany = company
            insuranceProductName = productName
            premiumMinor = premium.minorUnits
            paymentFrequency = frequency.rawValue
            coverageMinor = coverage.minorUnits
            startDate = start.description
            maturityDate = maturity?.description
            categoryDescription = nil
        case let .otherAsset(description, _):
            interestRateCoefficient = nil
            ticker = nil
            mic = nil
            quantityCoefficient = nil
            manualPriceCoefficient = nil
            insuranceCompany = nil
            insuranceProductName = nil
            premiumMinor = nil
            paymentFrequency = nil
            coverageMinor = nil
            startDate = nil
            maturityDate = nil
            categoryDescription = description
        }
    }

    func domain(container: AssetContainer) throws -> WealthContainer {
        guard recordKind == container.kind.rawValue,
              let originalCurrency = CurrencyCode(rawValue: originalCurrencyCode),
              let fxSourceCurrency = CurrencyCode(rawValue: fxSourceCurrencyCode),
              let fxTargetCurrency = CurrencyCode(rawValue: fxTargetCurrencyCode),
              let referenceDate = try? CivilDate(canonical: fxReferenceDate) else {
            throw WealthPersistenceError.corruptRecord
        }

        let original = Money(minorUnits: originalMinor, currency: originalCurrency)
        let rate = try FXRate(
            coefficient: fxCoefficient,
            sourceCurrency: fxSourceCurrency,
            targetCurrency: fxTargetCurrency
        )
        let valuation = try FXValuation(
            original: original,
            rate: rate,
            referenceDate: referenceDate,
            fetchedAt: UTCInstant(millisecondsSince1970: fxRecordedAtMilliseconds),
            providerIdentifier: fxSource,
            isManualOverride: fxIsManual,
            isStale: fxIsStale
        )
        guard valuation.convertedCNY.minorUnits == convertedCNYMinor else {
            throw WealthPersistenceError.storedValuationMismatch
        }

        let details: WealthRecordDetails
        switch container.kind {
        case .bankCash:
            details = .bankCash(
                balance: original,
                interestRate: interestRateCoefficient.map(Percentage.init(coefficient:))
            )
        case .stock, .etf, .fund:
            guard let ticker,
                  let quantityCoefficient,
                  let manualPriceCoefficient else {
                throw WealthPersistenceError.corruptRecord
            }
            details = .security(
                ticker: ticker,
                mic: mic,
                quantity: AssetQuantity(coefficient: quantityCoefficient),
                manualPrice: try MarketPrice(
                    coefficient: manualPriceCoefficient,
                    quoteCurrency: container.primaryCurrency
                )
            )
        case .insurance:
            guard let insuranceCompany,
                  let insuranceProductName,
                  let premiumMinor,
                  let paymentFrequency,
                  let frequency = InsurancePaymentFrequency(rawValue: paymentFrequency),
                  let coverageMinor,
                  let startDate,
                  let parsedStart = try? CivilDate(canonical: startDate) else {
                throw WealthPersistenceError.corruptRecord
            }
            let parsedMaturity: CivilDate?
            if let maturityDate {
                guard let value = try? CivilDate(canonical: maturityDate) else {
                    throw WealthPersistenceError.corruptDate
                }
                parsedMaturity = value
            } else {
                parsedMaturity = nil
            }
            details = .insurance(
                company: insuranceCompany,
                productName: insuranceProductName,
                premium: Money(minorUnits: premiumMinor, currency: container.primaryCurrency),
                paymentFrequency: frequency,
                coverage: Money(minorUnits: coverageMinor, currency: container.primaryCurrency),
                currentCashValue: original,
                startDate: parsedStart,
                maturityDate: parsedMaturity
            )
        case .otherAsset:
            guard let categoryDescription else { throw WealthPersistenceError.corruptRecord }
            details = .otherAsset(
                categoryDescription: categoryDescription,
                currentValue: original
            )
        case .liability:
            details = .liability(
                outstandingBalance: original,
                interestRate: interestRateCoefficient.map(Percentage.init(coefficient:))
            )
        }
        return try WealthContainer(container: container, details: details, valuation: valuation)
    }
}
