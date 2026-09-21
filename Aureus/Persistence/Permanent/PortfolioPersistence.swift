import Foundation
import GRDB

enum PortfolioPersistenceError: Error, Equatable, Sendable {
    case notFound
    case duplicate
    case corruptRecord
    case invalidHistoricalMutation
    case snapshotIncomplete
}

extension WealthStore {
    func seedSyntheticPortfolio() throws {
        let portfolioID = UUID(uuidString: "00000000-0000-4000-8000-000000008001")!
        let linkID = UUID(uuidString: "00000000-0000-4000-8000-000000008002")!
        let containerID = UUID(uuidString: "00000000-0000-4000-8000-000000003003")!
        let instant = SyntheticWealthSeeder.demoInstant
        let date = SyntheticWealthSeeder.demoDate
        let rate = try FXRate(decimal: Decimal(string: "7.125", locale: FixedPointMath.canonicalLocale)!, sourceCurrency: .usd, targetCurrency: .cny)
        try queue.write { db in
            let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM portfolio_definitions WHERE id = ?", arguments: [portfolioID.uuidString]) ?? 0
            guard exists == 0 else { return }
            let portfolio = try PortfolioRecord(id: portfolioID, name: "Synthetic Local Portfolio", createdAt: instant, updatedAt: instant, sortOrder: 0)
            try db.execute(sql: "INSERT INTO portfolio_definitions (id, name, base_currency_code, created_at_ms, updated_at_ms, sort_order) VALUES (?, ?, 'CNY', ?, ?, 0)", arguments: [portfolio.id.uuidString, portfolio.name, instant.millisecondsSince1970, instant.millisecondsSince1970])
            let link = try PortfolioSecurityLink(id: linkID, portfolioID: portfolioID, wealthContainerID: containerID, symbol: "SYNX", rawMIC: "XSYN", currency: .usd, assetKind: .stock, sortOrder: 0)
            try db.execute(sql: "INSERT INTO portfolio_security_links (id, portfolio_id, wealth_container_id, symbol, raw_mic, currency_code, asset_kind, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?, 0)", arguments: [link.id.uuidString, portfolioID.uuidString, containerID.uuidString, link.symbol, link.rawMIC, link.currency.rawValue, link.assetKind.rawValue])
            let opening = Money(minorUnits: 30_000, currency: .usd)
            let openingFX = try PortfolioFXProvenance(original: opening, rate: rate, source: "manual.synthetic.stage8", referenceDate: date, recordedAt: instant, isManual: true, isStale: false)
            let openingActivity = try PortfolioActivity(id: UUID(uuidString: "00000000-0000-4000-8000-000000008003")!, portfolioID: portfolioID, securityLinkID: linkID, civilDate: try CivilDate(canonical: "2025-12-15"), recordedAt: instant, exchangeTimeZoneIdentifier: "America/New_York", payload: .openingLot(quantity: AssetQuantity(coefficient: 1_000_000_000), totalCost: opening, fx: openingFX, note: "Synthetic opening lot"))
            try Self.insert(openingActivity, in: db)
            let buyTotal = Money(minorUnits: 10_100, currency: .usd)
            let buyFX = try PortfolioFXProvenance(original: buyTotal, rate: rate, source: "manual.synthetic.stage8", referenceDate: date, recordedAt: instant, isManual: true, isStale: false)
            let buy = try PortfolioActivity(id: UUID(uuidString: "00000000-0000-4000-8000-000000008004")!, portfolioID: portfolioID, securityLinkID: linkID, civilDate: date, recordedAt: UTCInstant(millisecondsSince1970: instant.millisecondsSince1970 + 1), exchangeTimeZoneIdentifier: "America/New_York", payload: .buy(quantity: AssetQuantity(coefficient: 250_000_000), unitPrice: try MarketPrice(coefficient: 4_000_000_000, quoteCurrency: .usd), fee: Money(minorUnits: 100, currency: .usd), fx: buyFX))
            try Self.insert(buy, in: db)
            try Self.validatePortfolioReplay(portfolioID, in: db)
        }
    }

    func createPortfolio(_ portfolio: PortfolioRecord) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO portfolio_definitions
                    (id, name, base_currency_code, created_at_ms, updated_at_ms, sort_order)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    portfolio.id.uuidString, portfolio.name, portfolio.baseCurrency.rawValue,
                    portfolio.createdAt.millisecondsSince1970,
                    portfolio.updatedAt.millisecondsSince1970, portfolio.sortOrder
                ])
        }
    }

    func fetchPortfolios() throws -> [PortfolioRecord] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM portfolio_definitions ORDER BY sort_order, created_at_ms, id")
                .map(Self.portfolioDomain)
        }
    }

    func renamePortfolio(id: UUID, name: String, updatedAt: UTCInstant) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PortfolioDomainError.emptyName }
        try queue.write { db in
            try db.execute(
                sql: "UPDATE portfolio_definitions SET name = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [normalized, updatedAt.millisecondsSince1970, id.uuidString]
            )
            guard db.changesCount == 1 else { throw PortfolioPersistenceError.notFound }
        }
    }

    func reorderPortfolios(_ ids: [UUID], updatedAt: UTCInstant) throws {
        try queue.write { db in
            let stored = try String.fetchAll(db, sql: "SELECT id FROM portfolio_definitions ORDER BY id")
            guard stored == ids.map(\.uuidString).sorted(), Set(ids).count == ids.count else {
                throw PortfolioPersistenceError.notFound
            }
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE portfolio_definitions SET sort_order = ?, updated_at_ms = ? WHERE id = ?",
                    arguments: [index, updatedAt.millisecondsSince1970, id.uuidString]
                )
            }
        }
    }

    func deletePortfolio(id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM portfolio_definitions WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw PortfolioPersistenceError.notFound }
        }
    }

    func linkPortfolioSecurity(_ link: PortfolioSecurityLink) throws {
        try queue.write { db in
            guard try Self.wealthSecurityMatches(link, in: db) else {
                throw PortfolioDomainError.unsupportedSecurity
            }
            do {
                try db.execute(sql: """
                    INSERT INTO portfolio_security_links
                        (id, portfolio_id, wealth_container_id, symbol, raw_mic,
                         currency_code, asset_kind, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        link.id.uuidString, link.portfolioID.uuidString,
                        link.wealthContainerID.uuidString, link.symbol, link.rawMIC,
                        link.currency.rawValue, link.assetKind.rawValue, link.sortOrder
                    ])
            } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
                throw PortfolioDomainError.duplicateSecurity
            }
        }
    }

    func fetchPortfolioSecurityLinks(portfolioID: UUID) throws -> [PortfolioSecurityLink] {
        try queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM portfolio_security_links WHERE portfolio_id = ? ORDER BY sort_order, id",
                arguments: [portfolioID.uuidString]
            ).map(Self.securityLinkDomain)
        }
    }

    func unlinkPortfolioSecurity(id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM portfolio_security_links WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw PortfolioPersistenceError.notFound }
        }
    }

    func createPortfolioActivity(_ activity: PortfolioActivity) throws {
        try queue.write { db in
            try Self.insert(activity, in: db)
            try Self.validatePortfolioReplay(activity.portfolioID, in: db)
        }
    }

    func updatePortfolioActivity(_ activity: PortfolioActivity) throws {
        try queue.write { db in
            let existingPortfolio: String? = try String.fetchOne(
                db, sql: "SELECT portfolio_id FROM portfolio_activities WHERE id = ?",
                arguments: [activity.id.uuidString]
            )
            guard existingPortfolio == activity.portfolioID.uuidString else {
                throw PortfolioPersistenceError.notFound
            }
            try Self.insert(activity, in: db, updating: true)
            do { try Self.validatePortfolioReplay(activity.portfolioID, in: db) }
            catch { throw PortfolioPersistenceError.invalidHistoricalMutation }
        }
    }

    func deletePortfolioActivity(id: UUID) throws {
        try queue.write { db in
            guard let portfolioID = try String.fetchOne(
                db, sql: "SELECT portfolio_id FROM portfolio_activities WHERE id = ?", arguments: [id.uuidString]
            ), let parsed = UUID(uuidString: portfolioID) else { throw PortfolioPersistenceError.notFound }
            try db.execute(sql: "DELETE FROM portfolio_activities WHERE id = ?", arguments: [id.uuidString])
            do { try Self.validatePortfolioReplay(parsed, in: db) }
            catch { throw PortfolioPersistenceError.invalidHistoricalMutation }
        }
    }

    func fetchPortfolioActivities(portfolioID: UUID) throws -> [PortfolioActivity] {
        try queue.read { db in try Self.activities(portfolioID, in: db) }
    }

    func portfolioReplay(portfolioID: UUID) throws -> PortfolioReplayResult {
        try PortfolioFIFOEngine.replay(fetchPortfolioActivities(portfolioID: portfolioID))
    }

    func portfolioHoldingSummaries(portfolioID: UUID) throws -> [PortfolioHoldingSummary] {
        let inputs = try queue.read { db -> (
            links: [PortfolioSecurityLink],
            activities: [PortfolioActivity],
            wealthByID: [UUID: WealthContainer]
        ) in
            let links = try Row.fetchAll(
                db,
                sql: "SELECT * FROM portfolio_security_links WHERE portfolio_id = ? ORDER BY sort_order, id",
                arguments: [portfolioID.uuidString]
            ).map(Self.securityLinkDomain)
            let activities = try Self.activities(portfolioID, in: db)
            guard !links.isEmpty else { return (links, activities, [:]) }

            let containerIDs = links.map { $0.wealthContainerID.uuidString }
            let placeholders = Array(repeating: "?", count: containerIDs.count).joined(separator: ",")
            let arguments = StatementArguments(containerIDs)
            let containerRows = try AssetContainerPersistenceRow.fetchAll(
                db,
                sql: "SELECT * FROM asset_containers WHERE id IN (\(placeholders))",
                arguments: arguments
            )
            let recordRows = try WealthRecordPersistenceRow.fetchAll(
                db,
                sql: "SELECT * FROM wealth_records WHERE container_id IN (\(placeholders))",
                arguments: arguments
            )
            let recordsByContainer = Dictionary(uniqueKeysWithValues: recordRows.map { ($0.containerID, $0) })
            let wealth = try containerRows.map { row -> WealthContainer in
                guard let record = recordsByContainer[row.id] else {
                    throw PortfolioPersistenceError.corruptRecord
                }
                return try record.domain(container: row.domain())
            }
            return (links, activities, Dictionary(uniqueKeysWithValues: wealth.map { ($0.id, $0) }))
        }
        let replay = try PortfolioFIFOEngine.replay(inputs.activities)
        let activityLinkByID = Dictionary(uniqueKeysWithValues: inputs.activities.map { ($0.id, $0.securityLinkID) })
        var lotsByLink: [UUID: [PortfolioLot]] = [:]
        for lot in replay.lots { lotsByLink[lot.securityLinkID, default: []].append(lot) }
        var realizedByLink: [UUID: [PortfolioRealizedResult]] = [:]
        for result in replay.realized {
            guard let linkID = activityLinkByID[result.activityID] else {
                throw PortfolioPersistenceError.corruptRecord
            }
            realizedByLink[linkID, default: []].append(result)
        }

        var drafts: [(PortfolioSecurityLink, AssetQuantity, AssetQuantity, Money, Money, Money, Money, MarketPrice, Money, Money, PortfolioFXProvenance, CivilDate)] = []
        var nav = Money(minorUnits: 0, currency: .cny)
        for link in inputs.links {
            guard let wealth = inputs.wealthByID[link.wealthContainerID],
                  case let .security(ticker, mic, wealthQuantity, manualMark) = wealth.details,
                  ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == link.symbol,
                  mic?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == link.rawMIC,
                  manualMark.quoteCurrency == link.currency else {
                throw PortfolioPersistenceError.corruptRecord
            }
            let linkLots = lotsByLink[link.id] ?? []
            let quantityCoefficient = try linkLots.map(\.remainingQuantity.coefficient).reduce(Int64(0)) { partial, value in
                let result = partial.addingReportingOverflow(value)
                guard !result.overflow else { throw PortfolioDomainError.arithmeticOverflow }
                return result.partialValue
            }
            let quantity = AssetQuantity(coefficient: quantityCoefficient)
            let originalBasis = try linkLots
                .map(\.remainingOriginalBasis)
                .reduce(Money(minorUnits: 0, currency: link.currency)) { try $0.adding($1) }
            let cnyBasis = try linkLots
                .map(\.remainingCNYBasis)
                .reduce(Money(minorUnits: 0, currency: .cny)) { try $0.adding($1) }
            let linkRealized = realizedByLink[link.id] ?? []
            let realizedOriginal = try linkRealized
                .map(\.originalPnL).reduce(Money(minorUnits: 0, currency: link.currency)) { try $0.adding($1) }
            let realizedCNY = try linkRealized
                .map(\.cnyPnL).reduce(Money(minorUnits: 0, currency: .cny)) { try $0.adding($1) }
            let marketValue = try PortfolioCheckedMath.moneyProduct(quantity: quantity, price: manualMark)
            let wealthFX = try PortfolioFXProvenance(
                original: marketValue,
                rate: wealth.valuation.rate,
                source: wealth.valuation.providerIdentifier,
                referenceDate: wealth.valuation.referenceDate,
                recordedAt: wealth.valuation.fetchedAt,
                isManual: wealth.valuation.isManualOverride,
                isStale: wealth.valuation.isStale
            )
            nav = try nav.adding(wealthFX.convertedCNY)
            drafts.append((link, quantity, wealthQuantity, originalBasis, cnyBasis, realizedOriginal, realizedCNY, manualMark, marketValue, wealthFX.convertedCNY, wealthFX, wealth.container.updatedDate))
        }
        return try drafts.map { item in
            let weight = nav.minorUnits == 0 ? nil : try Percentage(
                decimal: PortfolioCheckedMath.divide(item.9.decimal, nav.decimal)
            )
            return PortfolioHoldingSummary(
                link: item.0,
                portfolioQuantity: item.1,
                wealthQuantity: item.2,
                reconciliation: item.1 == item.2 ? .matched : .quantityMismatch,
                remainingOriginalBasis: item.3,
                remainingCNYBasis: item.4,
                realizedOriginalPnL: item.5,
                realizedCNYPnL: item.6,
                manualMark: item.7,
                marketValue: item.8,
                marketValueCNY: item.9,
                unrealizedOriginalPnL: try item.8.subtracting(item.3),
                unrealizedCNYPnL: try item.9.subtracting(item.4),
                weight: weight,
                wealthFX: item.10,
                wealthUpdatedDate: item.11
            )
        }
    }

    func replacePortfolioNAVSnapshot(_ snapshot: PortfolioNAVSnapshot) throws {
        guard snapshot.isComplete, snapshot.totalCNY.currency == .cny,
              snapshot.items.allSatisfy({ $0.fx.convertedCNY == $0.convertedCNYValue }) else {
            throw PortfolioPersistenceError.snapshotIncomplete
        }
        try queue.write { db in
            if let priorID: String = try String.fetchOne(
                db,
                sql: "SELECT id FROM portfolio_nav_snapshots WHERE portfolio_id = ? AND civil_date = ?",
                arguments: [snapshot.portfolioID.uuidString, snapshot.civilDate.description]
            ) {
                try db.execute(sql: "DELETE FROM portfolio_nav_snapshots WHERE id = ?", arguments: [priorID])
            }
            try db.execute(sql: """
                INSERT INTO portfolio_nav_snapshots
                    (id, portfolio_id, civil_date, created_at_ms, total_cny_minor, is_complete)
                VALUES (?, ?, ?, ?, ?, 1)
                """, arguments: [snapshot.id.uuidString, snapshot.portfolioID.uuidString,
                    snapshot.civilDate.description, snapshot.createdAt.millisecondsSince1970,
                    snapshot.totalCNY.minorUnits])
            var sum = Money(minorUnits: 0, currency: .cny)
            for item in snapshot.items {
                sum = try sum.adding(item.convertedCNYValue)
                try db.execute(sql: """
                    INSERT INTO portfolio_nav_snapshot_items
                        (id, snapshot_id, security_link_id, quantity_coefficient,
                         manual_mark_coefficient, original_market_value_minor,
                         original_currency_code, fx_coefficient, fx_source,
                         fx_reference_date, fx_recorded_at_ms, fx_is_manual, fx_is_stale,
                         converted_cny_minor, remaining_cny_basis_minor, reconciliation)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [item.id.uuidString, snapshot.id.uuidString,
                        item.securityLinkID.uuidString, item.quantity.coefficient,
                        item.manualMark.coefficient, item.originalMarketValue.minorUnits,
                        item.originalMarketValue.currency.rawValue, item.fx.rate.coefficient,
                        item.fx.source, item.fx.referenceDate.description,
                        item.fx.recordedAt.millisecondsSince1970, item.fx.isManual,
                        item.fx.isStale, item.convertedCNYValue.minorUnits,
                        item.remainingCNYBasis.minorUnits, item.reconciliation.rawValue])
            }
            guard sum == snapshot.totalCNY else { throw PortfolioPersistenceError.snapshotIncomplete }
        }
    }

    func fetchPortfolioNAVSnapshots(portfolioID: UUID) throws -> [PortfolioNAVSnapshot] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM portfolio_nav_snapshots WHERE portfolio_id = ? ORDER BY civil_date, created_at_ms, id", arguments: [portfolioID.uuidString]).map { row in
                guard let id = UUID(uuidString: row["id"]),
                      let portfolio = UUID(uuidString: row["portfolio_id"]),
                      let date = try? CivilDate(canonical: row["civil_date"]) else { throw PortfolioPersistenceError.corruptRecord }
                let itemRows = try Row.fetchAll(db, sql: "SELECT * FROM portfolio_nav_snapshot_items WHERE snapshot_id = ? ORDER BY security_link_id", arguments: [id.uuidString])
                let items = try itemRows.map(Self.snapshotItemDomain)
                return PortfolioNAVSnapshot(
                    id: id, portfolioID: portfolio, civilDate: date,
                    createdAt: UTCInstant(millisecondsSince1970: row["created_at_ms"]),
                    totalCNY: Money(minorUnits: row["total_cny_minor"], currency: .cny),
                    isComplete: (row["is_complete"] as Int) == 1, items: items
                )
            }
        }
    }

    func portfolioStorageTypes() throws -> [String] {
        try queue.read { db in
            let columns = [
                "SELECT typeof(quantity_coefficient) FROM portfolio_activities WHERE quantity_coefficient IS NOT NULL LIMIT 1",
                "SELECT typeof(total_original_minor) FROM portfolio_activities WHERE total_original_minor IS NOT NULL LIMIT 1",
                "SELECT typeof(fx_coefficient) FROM portfolio_activities WHERE fx_coefficient IS NOT NULL LIMIT 1"
            ]
            return try columns.map { try String.fetchOne(db, sql: $0) ?? "missing" }
        }
    }

    private nonisolated static func portfolioDomain(_ row: Row) throws -> PortfolioRecord {
        guard let id = UUID(uuidString: row["id"]), let currency = CurrencyCode(rawValue: row["base_currency_code"]) else {
            throw PortfolioPersistenceError.corruptRecord
        }
        return try PortfolioRecord(id: id, name: row["name"], baseCurrency: currency,
            createdAt: UTCInstant(millisecondsSince1970: row["created_at_ms"]),
            updatedAt: UTCInstant(millisecondsSince1970: row["updated_at_ms"]), sortOrder: row["sort_order"])
    }

    private nonisolated static func securityLinkDomain(_ row: Row) throws -> PortfolioSecurityLink {
        guard let id = UUID(uuidString: row["id"]), let portfolioID = UUID(uuidString: row["portfolio_id"]),
              let wealthID = UUID(uuidString: row["wealth_container_id"]),
              let currency = CurrencyCode(rawValue: row["currency_code"]),
              let kind = AssetContainerKind(rawValue: row["asset_kind"]) else { throw PortfolioPersistenceError.corruptRecord }
        return try PortfolioSecurityLink(id: id, portfolioID: portfolioID, wealthContainerID: wealthID,
            symbol: row["symbol"], rawMIC: row["raw_mic"], currency: currency, assetKind: kind, sortOrder: row["sort_order"])
    }

    private nonisolated static func wealthSecurityMatches(_ link: PortfolioSecurityLink, in db: Database) throws -> Bool {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT c.kind, c.primary_currency_code, w.ticker, w.mic
            FROM asset_containers c JOIN wealth_records w ON w.container_id = c.id
            WHERE c.id = ?
            """, arguments: [link.wealthContainerID.uuidString]) else { return false }
        return (row["kind"] as String) == link.assetKind.rawValue
            && (row["primary_currency_code"] as String) == link.currency.rawValue
            && (row["ticker"] as String?)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == link.symbol
            && (row["mic"] as String?)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == link.rawMIC
    }

    private nonisolated static func insert(_ activity: PortfolioActivity, in db: Database, updating: Bool = false) throws {
        var quantity: Int64?, price: Int64?, fee: Int64?, total: Int64?, currency: String?
        var converted: Int64?, fxCoefficient: Int64?, fxSource: String?, fxDate: String?, fxRecorded: Int64?
        var fxManual: Bool?, fxStale: Bool?, splitFrom: Int64?, splitTo: Int64?, note: String?
        func assign(_ fx: PortfolioFXProvenance) {
            total = fx.original.minorUnits; currency = fx.original.currency.rawValue
            converted = fx.convertedCNY.minorUnits; fxCoefficient = fx.rate.coefficient
            fxSource = fx.source; fxDate = fx.referenceDate.description
            fxRecorded = fx.recordedAt.millisecondsSince1970; fxManual = fx.isManual; fxStale = fx.isStale
        }
        switch activity.payload {
        case let .openingLot(value, _, fx, sanitized): quantity = value.coefficient; assign(fx); note = sanitized
        case let .buy(value, unitPrice, tradeFee, fx), let .sell(value, unitPrice, tradeFee, fx):
            quantity = value.coefficient; price = unitPrice.coefficient; fee = tradeFee.minorUnits; assign(fx)
        case let .manualSplit(from, to): splitFrom = from.coefficient; splitTo = to.coefficient
        }
        let arguments: StatementArguments = [activity.id.uuidString, activity.portfolioID.uuidString,
            activity.securityLinkID.uuidString, activity.kind.rawValue, activity.civilDate.description,
            activity.recordedAt.millisecondsSince1970, activity.exchangeTimeZoneIdentifier,
            activity.ledgerEntryID?.uuidString, quantity, price, fee, total, currency, converted,
            fxCoefficient, fxSource, fxDate, fxRecorded, fxManual, fxStale, splitFrom, splitTo, note]
        if updating {
            try db.execute(sql: """
                UPDATE portfolio_activities SET
                    id = ?, portfolio_id = ?, security_link_id = ?, kind = ?, civil_date = ?, recorded_at_ms = ?,
                    exchange_time_zone_id = ?, ledger_entry_id = ?, quantity_coefficient = ?,
                    unit_price_coefficient = ?, fee_minor = ?, total_original_minor = ?, currency_code = ?,
                    converted_cny_minor = ?, fx_coefficient = ?, fx_source = ?, fx_reference_date = ?,
                    fx_recorded_at_ms = ?, fx_is_manual = ?, fx_is_stale = ?, split_from_coefficient = ?,
                    split_to_coefficient = ?, sanitized_note = ? WHERE id = ?
                """, arguments: arguments + [activity.id.uuidString])
            guard db.changesCount == 1 else { throw PortfolioPersistenceError.notFound }
            return
        }
        try db.execute(sql: """
            INSERT INTO portfolio_activities
                (id, portfolio_id, security_link_id, kind, civil_date, recorded_at_ms,
                 exchange_time_zone_id, ledger_entry_id, quantity_coefficient,
                 unit_price_coefficient, fee_minor, total_original_minor, currency_code,
                 converted_cny_minor, fx_coefficient, fx_source, fx_reference_date,
                 fx_recorded_at_ms, fx_is_manual, fx_is_stale, split_from_coefficient,
                 split_to_coefficient, sanitized_note)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: arguments)
    }

    private nonisolated static func activities(_ portfolioID: UUID, in db: Database) throws -> [PortfolioActivity] {
        try Row.fetchAll(db, sql: "SELECT * FROM portfolio_activities WHERE portfolio_id = ? ORDER BY civil_date, recorded_at_ms, id", arguments: [portfolioID.uuidString]).map(Self.activityDomain)
    }

    private nonisolated static func activityDomain(_ row: Row) throws -> PortfolioActivity {
        guard let id = UUID(uuidString: row["id"]), let portfolioID = UUID(uuidString: row["portfolio_id"]),
              let linkID = UUID(uuidString: row["security_link_id"]),
              let date = try? CivilDate(canonical: row["civil_date"]),
              let kind = PortfolioActivity.Kind(rawValue: row["kind"]) else { throw PortfolioPersistenceError.corruptRecord }
        let ledgerID = (row["ledger_entry_id"] as String?).flatMap(UUID.init(uuidString:))
        let payload: PortfolioActivityPayload
        if kind == .manualSplit {
            guard let from: Int64 = row["split_from_coefficient"], let to: Int64 = row["split_to_coefficient"] else { throw PortfolioPersistenceError.corruptRecord }
            payload = .manualSplit(from: Ratio(coefficient: from), to: Ratio(coefficient: to))
        } else {
            guard let quantity: Int64 = row["quantity_coefficient"], let total: Int64 = row["total_original_minor"],
                  let currency = CurrencyCode(rawValue: row["currency_code"]), let converted: Int64 = row["converted_cny_minor"],
                  let coefficient: Int64 = row["fx_coefficient"], let source: String = row["fx_source"],
                  let fxDate = try? CivilDate(canonical: row["fx_reference_date"]), let fxRecorded: Int64 = row["fx_recorded_at_ms"],
                  let manual: Bool = row["fx_is_manual"], let stale: Bool = row["fx_is_stale"] else { throw PortfolioPersistenceError.corruptRecord }
            let money = Money(minorUnits: total, currency: currency)
            let rate = try FXRate(coefficient: coefficient, sourceCurrency: currency, targetCurrency: .cny)
            let fx = try PortfolioFXProvenance(original: money, rate: rate, source: source, referenceDate: fxDate,
                recordedAt: UTCInstant(millisecondsSince1970: fxRecorded), isManual: manual, isStale: stale)
            guard fx.convertedCNY.minorUnits == converted else { throw PortfolioPersistenceError.corruptRecord }
            if kind == .openingLot { payload = .openingLot(quantity: AssetQuantity(coefficient: quantity), totalCost: money, fx: fx, note: row["sanitized_note"]) }
            else {
                guard let price: Int64 = row["unit_price_coefficient"], let fee: Int64 = row["fee_minor"] else { throw PortfolioPersistenceError.corruptRecord }
                let p = try MarketPrice(coefficient: price, quoteCurrency: currency)
                let f = Money(minorUnits: fee, currency: currency)
                payload = kind == .buy ? .buy(quantity: AssetQuantity(coefficient: quantity), unitPrice: p, fee: f, fx: fx) : .sell(quantity: AssetQuantity(coefficient: quantity), unitPrice: p, fee: f, fx: fx)
            }
        }
        return try PortfolioActivity(id: id, portfolioID: portfolioID, securityLinkID: linkID, civilDate: date,
            recordedAt: UTCInstant(millisecondsSince1970: row["recorded_at_ms"]), exchangeTimeZoneIdentifier: row["exchange_time_zone_id"], ledgerEntryID: ledgerID, payload: payload)
    }

    private nonisolated static func validatePortfolioReplay(_ portfolioID: UUID, in db: Database) throws {
        _ = try PortfolioFIFOEngine.replay(activities(portfolioID, in: db))
    }

    private nonisolated static func snapshotItemDomain(_ row: Row) throws -> PortfolioNAVSnapshotItem {
        guard let id = UUID(uuidString: row["id"]), let linkID = UUID(uuidString: row["security_link_id"]),
              let currency = CurrencyCode(rawValue: row["original_currency_code"]),
              let date = try? CivilDate(canonical: row["fx_reference_date"]),
              let reconciliation = PortfolioHoldingSummary.Reconciliation(rawValue: row["reconciliation"]) else { throw PortfolioPersistenceError.corruptRecord }
        let original = Money(minorUnits: row["original_market_value_minor"], currency: currency)
        let rate = try FXRate(coefficient: row["fx_coefficient"], sourceCurrency: currency, targetCurrency: .cny)
        let fx = try PortfolioFXProvenance(original: original, rate: rate, source: row["fx_source"], referenceDate: date,
            recordedAt: UTCInstant(millisecondsSince1970: row["fx_recorded_at_ms"]), isManual: row["fx_is_manual"], isStale: row["fx_is_stale"])
        let converted = Money(minorUnits: row["converted_cny_minor"], currency: .cny)
        guard fx.convertedCNY == converted else { throw PortfolioPersistenceError.corruptRecord }
        return PortfolioNAVSnapshotItem(id: id, securityLinkID: linkID, quantity: AssetQuantity(coefficient: row["quantity_coefficient"]),
            manualMark: try MarketPrice(coefficient: row["manual_mark_coefficient"], quoteCurrency: currency), originalMarketValue: original,
            fx: fx, convertedCNYValue: converted, remainingCNYBasis: Money(minorUnits: row["remaining_cny_basis_minor"], currency: .cny), reconciliation: reconciliation)
    }
}
