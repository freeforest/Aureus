import Foundation
import GRDB

enum LedgerPersistenceError: Error, Equatable, Sendable {
    case transactionNotFound
    case categoryNotFound
    case tagNotFound
    case ruleNotFound
    case duplicateName
    case categoryInUse
    case tagInUse
    case duplicateTransactionID
    case duplicateFingerprint
    case corruptRecord
}

struct LedgerImportIdentities: Equatable, Sendable {
    let transactionIDs: Set<UUID>
    let fingerprints: Set<String>
}

struct LedgerTransactionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ledger_transactions"
    let id: String
    let kind: String
    let civilDate: String
    let recordedAtMS: Int64
    let description: String
    let payee: String?
    let categoryID: String?
    let note: String?
    let importFingerprint: String?
    let createdAtMS: Int64
    let updatedAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case id, kind, description, payee, note
        case civilDate = "civil_date"
        case recordedAtMS = "recorded_at_ms"
        case categoryID = "category_id"
        case importFingerprint = "import_fingerprint"
        case createdAtMS = "created_at_ms"
        case updatedAtMS = "updated_at_ms"
    }
}

struct LedgerPostingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ledger_postings"
    let id: String
    let transactionID: String
    let role: String
    let containerID: String
    let originalMinor: Int64
    let originalCurrencyCode: String
    let convertedCNYMinor: Int64
    let fxCoefficient: Int64
    let fxSourceCurrencyCode: String
    let fxTargetCurrencyCode: String
    let fxSource: String
    let fxReferenceDate: String
    let fxRecordedAtMS: Int64
    let fxIsManual: Bool
    let fxIsStale: Bool

    enum CodingKeys: String, CodingKey {
        case id, role
        case transactionID = "transaction_id"
        case containerID = "container_id"
        case originalMinor = "original_minor"
        case originalCurrencyCode = "original_currency_code"
        case convertedCNYMinor = "converted_cny_minor"
        case fxCoefficient = "fx_coefficient"
        case fxSourceCurrencyCode = "fx_source_currency_code"
        case fxTargetCurrencyCode = "fx_target_currency_code"
        case fxSource = "fx_source"
        case fxReferenceDate = "fx_reference_date"
        case fxRecordedAtMS = "fx_recorded_at_ms"
        case fxIsManual = "fx_is_manual"
        case fxIsStale = "fx_is_stale"
    }

    init(transactionID: UUID, posting: LedgerPosting) {
        id = posting.id.uuidString
        self.transactionID = transactionID.uuidString
        role = posting.role.rawValue
        containerID = posting.containerID.uuidString
        originalMinor = posting.valuation.original.minorUnits
        originalCurrencyCode = posting.valuation.original.currency.rawValue
        convertedCNYMinor = posting.valuation.convertedCNY.minorUnits
        fxCoefficient = posting.valuation.rate.coefficient
        fxSourceCurrencyCode = posting.valuation.rate.sourceCurrency.rawValue
        fxTargetCurrencyCode = posting.valuation.rate.targetCurrency.rawValue
        fxSource = posting.valuation.providerIdentifier
        fxReferenceDate = posting.valuation.referenceDate.description
        fxRecordedAtMS = posting.valuation.fetchedAt.millisecondsSince1970
        fxIsManual = posting.valuation.isManualOverride
        fxIsStale = posting.valuation.isStale
    }

    func domain() throws -> LedgerPosting {
        guard let id = UUID(uuidString: id),
              let transactionContainerID = UUID(uuidString: containerID),
              let role = LedgerPostingRole(rawValue: role),
              let currency = CurrencyCode(rawValue: originalCurrencyCode),
              let sourceCurrency = CurrencyCode(rawValue: fxSourceCurrencyCode),
              let targetCurrency = CurrencyCode(rawValue: fxTargetCurrencyCode),
              let referenceDate = try? CivilDate(canonical: fxReferenceDate),
              let rate = try? FXRate(
                coefficient: fxCoefficient,
                sourceCurrency: sourceCurrency,
                targetCurrency: targetCurrency
              ),
              let valuation = try? FXValuation(
                original: Money(minorUnits: originalMinor, currency: currency),
                rate: rate,
                referenceDate: referenceDate,
                fetchedAt: UTCInstant(millisecondsSince1970: fxRecordedAtMS),
                providerIdentifier: fxSource,
                isManualOverride: fxIsManual,
                isStale: fxIsStale
              ),
              valuation.convertedCNY.minorUnits == convertedCNYMinor else {
            throw LedgerPersistenceError.corruptRecord
        }
        return try LedgerPosting(id: id, role: role, containerID: transactionContainerID, valuation: valuation)
    }
}

struct ClassificationRuleRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "classification_rules"
    let id: String
    let name: String
    let priority: Int
    let isEnabled: Bool
    let matchMode: String
    let payeePattern: String?
    let kind: String?
    let sourceContainerID: String?
    let amountDirection: String?
    let resultCategoryID: String?

    enum CodingKeys: String, CodingKey {
        case id, name, priority, kind
        case isEnabled = "is_enabled"
        case matchMode = "match_mode"
        case payeePattern = "payee_pattern"
        case sourceContainerID = "source_container_id"
        case amountDirection = "amount_direction"
        case resultCategoryID = "result_category_id"
    }
}

extension WealthStore {
    func createLedgerEntry(_ entry: LedgerEntry) throws {
        try queue.write { db in try Self.insertLedgerEntry(entry, in: db) }
    }

    func updateLedgerEntry(_ entry: LedgerEntry) throws {
        try queue.write { db in try Self.updateLedgerEntry(entry, in: db) }
    }

    static func updateLedgerEntry(_ entry: LedgerEntry, in db: Database) throws {
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_transactions WHERE id = ?", arguments: [entry.id.uuidString]) == 1 else {
                throw LedgerPersistenceError.transactionNotFound
            }
            let now = entry.recordedAt.millisecondsSince1970
            // Keep the parent identity and creation time: external references belong to this row.
            try db.execute(sql: """
                UPDATE ledger_transactions
                SET kind = ?, civil_date = ?, recorded_at_ms = ?, description = ?,
                    payee = ?, category_id = ?, note = ?, import_fingerprint = ?, updated_at_ms = ?
                WHERE id = ?
                """, arguments: [
                    entry.kind.rawValue, entry.civilDate.description, now, entry.description,
                    entry.payee, entry.category?.id.uuidString, entry.note, entry.importFingerprint,
                    now, entry.id.uuidString
                ])
            try db.execute(sql: "DELETE FROM ledger_postings WHERE transaction_id = ?", arguments: [entry.id.uuidString])
            try db.execute(sql: "DELETE FROM ledger_transaction_tags WHERE transaction_id = ?", arguments: [entry.id.uuidString])
            try Self.insertLedgerChildren(entry, in: db)
    }

    func deleteLedgerEntry(id: UUID) throws {
        try queue.write { db in
            try LedgerCorrectionSQL.deletionContext(db, id: id)
            try db.execute(sql: "DELETE FROM ledger_transactions WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw LedgerPersistenceError.transactionNotFound }
        }
    }

    func fetchLedgerEntries(filter: LedgerFilter = .all) throws -> [LedgerEntry] {
        try queue.read { db in
            try Self.fetchLedgerEntries(in: db).filter(filter.includes)
        }
    }

    func ledgerSummary(filter: LedgerFilter = .all) throws -> CashFlowSummary {
        try LedgerCashFlow.summarize(fetchLedgerEntries(filter: filter))
    }

    func existingImportFingerprints() throws -> Set<String> {
        try queue.read { db in
            try Self.canonicalImportIdentities(in: db).fingerprints
        }
    }

    func existingImportIdentities() throws -> LedgerImportIdentities {
        try queue.read { db in
            try Self.canonicalImportIdentities(in: db)
        }
    }

    func importLedgerEntries(_ entries: [LedgerEntry], batchID: UUID, importedAt: UTCInstant) throws {
        try queue.write { db in
            guard !entries.isEmpty else { return }
            let existing = try Self.canonicalImportIdentities(in: db)
            var transactionIDs = existing.transactionIDs
            var fingerprints = existing.fingerprints
            for incoming in entries {
                guard transactionIDs.insert(incoming.id).inserted else {
                    throw LedgerPersistenceError.duplicateTransactionID
                }
                let fingerprint = try LedgerCSV.semanticFingerprint(for: incoming)
                guard fingerprints.insert(fingerprint).inserted else {
                    throw LedgerPersistenceError.duplicateFingerprint
                }
                let canonical = try Self.importEntry(incoming, fingerprint: fingerprint)
                try Self.insertLedgerEntry(canonical, in: db)
            }
            try db.execute(
                sql: "INSERT INTO ledger_import_batches (id, schema_version, imported_at_ms, transaction_count) VALUES (?, 'AUREUS_LEDGER_V1', ?, ?)",
                arguments: [batchID.uuidString, importedAt.millisecondsSince1970, entries.count]
            )
        }
    }

    func createCategory(name: String, id: UUID = UUID()) throws -> Category {
        let display = try LedgerNameNormalization.displayName(name)
        let key = try LedgerNameNormalization.key(name)
        let category = Category(id: id, parentID: nil, name: display)
        do {
            try queue.write { db in
                try db.execute(sql: "INSERT INTO categories (id, parent_id, name, normalized_name) VALUES (?, NULL, ?, ?)", arguments: [id.uuidString, display, key])
            }
        } catch is DatabaseError {
            throw LedgerPersistenceError.duplicateName
        }
        return category
    }

    func fetchCategories() throws -> [Category] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, parent_id, name FROM categories ORDER BY normalized_name, id").map { row in
                let rawID: String = row["id"]
                let rawParent: String? = row["parent_id"]
                guard let id = UUID(uuidString: rawID) else { throw LedgerPersistenceError.corruptRecord }
                let parentID = rawParent.flatMap(UUID.init(uuidString:))
                return Category(id: id, parentID: parentID, name: row["name"])
            }
        }
    }

    func deleteCategory(id: UUID) throws {
        try queue.write { db in
            let used = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_transactions WHERE category_id = ?", arguments: [id.uuidString]) ?? 0)
                + (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM classification_rules WHERE result_category_id = ?", arguments: [id.uuidString]) ?? 0)
            guard used == 0 else { throw LedgerPersistenceError.categoryInUse }
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw LedgerPersistenceError.categoryNotFound }
        }
    }

    func updateCategory(id: UUID, name: String) throws -> Category {
        let display = try LedgerNameNormalization.displayName(name)
        let key = try LedgerNameNormalization.key(name)
        do {
            try queue.write { db in
                try db.execute(sql: "UPDATE categories SET name = ?, normalized_name = ? WHERE id = ?", arguments: [display, key, id.uuidString])
                guard db.changesCount == 1 else { throw LedgerPersistenceError.categoryNotFound }
            }
        } catch let error as LedgerPersistenceError { throw error }
        catch is DatabaseError { throw LedgerPersistenceError.duplicateName }
        return Category(id: id, parentID: nil, name: display)
    }

    func createTag(name: String, id: UUID = UUID()) throws -> Tag {
        let display = try LedgerNameNormalization.displayName(name)
        let key = try LedgerNameNormalization.key(name)
        let tag = Tag(id: id, name: display)
        do {
            try queue.write { db in
                try db.execute(sql: "INSERT INTO tags (id, name, normalized_name) VALUES (?, ?, ?)", arguments: [id.uuidString, display, key])
            }
        } catch is DatabaseError {
            throw LedgerPersistenceError.duplicateName
        }
        return tag
    }

    func fetchTags() throws -> [Tag] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name FROM tags ORDER BY normalized_name, id").map { row in
                guard let id = UUID(uuidString: row["id"]) else { throw LedgerPersistenceError.corruptRecord }
                return Tag(id: id, name: row["name"])
            }
        }
    }

    func deleteTag(id: UUID) throws {
        try queue.write { db in
            let used = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_transaction_tags WHERE tag_id = ?", arguments: [id.uuidString]) ?? 0)
                + (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM classification_rule_tags WHERE tag_id = ?", arguments: [id.uuidString]) ?? 0)
                + (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transaction_tags WHERE tag_id = ?", arguments: [id.uuidString]) ?? 0)
            guard used == 0 else { throw LedgerPersistenceError.tagInUse }
            try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw LedgerPersistenceError.tagNotFound }
        }
    }

    func updateTag(id: UUID, name: String) throws -> Tag {
        let display = try LedgerNameNormalization.displayName(name)
        let key = try LedgerNameNormalization.key(name)
        do {
            try queue.write { db in
                try db.execute(sql: "UPDATE tags SET name = ?, normalized_name = ? WHERE id = ?", arguments: [display, key, id.uuidString])
                guard db.changesCount == 1 else { throw LedgerPersistenceError.tagNotFound }
            }
        } catch let error as LedgerPersistenceError { throw error }
        catch is DatabaseError { throw LedgerPersistenceError.duplicateName }
        return Tag(id: id, name: display)
    }

    func createClassificationRule(_ rule: ClassificationRule) throws {
        let rule = try rule.validated()
        try queue.write { db in
            try Self.insertClassificationRule(rule, in: db)
        }
    }

    func updateClassificationRule(_ rule: ClassificationRule) throws {
        let rule = try rule.validated()
        try queue.write { db in
            guard try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM classification_rules WHERE id = ?",
                arguments: [rule.id.uuidString]
            ) == 1 else { throw LedgerPersistenceError.ruleNotFound }
            try db.execute(sql: "DELETE FROM classification_rules WHERE id = ?", arguments: [rule.id.uuidString])
            try Self.insertClassificationRule(rule, in: db)
        }
    }

    func setClassificationRuleEnabled(id: UUID, enabled: Bool) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE classification_rules SET is_enabled = ? WHERE id = ?",
                arguments: [enabled, id.uuidString]
            )
            guard db.changesCount == 1 else { throw LedgerPersistenceError.ruleNotFound }
        }
    }

    func deleteClassificationRule(id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM classification_rules WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw LedgerPersistenceError.ruleNotFound }
        }
    }

    func fetchClassificationRules() throws -> [ClassificationRule] {
        try queue.read { db in try Self.fetchClassificationRules(in: db) }
    }

    func ledgerTransactionCount() throws -> Int {
        try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ledger_transactions") ?? 0 }
    }

    func ledgerFinancialStorageClasses() throws -> Set<String> {
        try queue.read { db in
            Set(try Row.fetchAll(db, sql: "SELECT typeof(original_minor) AS a, typeof(converted_cny_minor) AS b, typeof(fx_coefficient) AS c FROM ledger_postings").flatMap { row in
                [row["a"] as String, row["b"] as String, row["c"] as String]
            })
        }
    }

    private static func insertLedgerEntry(_ entry: LedgerEntry, in db: Database) throws {
        let now = entry.recordedAt.millisecondsSince1970
        try LedgerTransactionRow(
            id: entry.id.uuidString, kind: entry.kind.rawValue,
            civilDate: entry.civilDate.description, recordedAtMS: now,
            description: entry.description, payee: entry.payee,
            categoryID: entry.category?.id.uuidString, note: entry.note,
            importFingerprint: entry.importFingerprint, createdAtMS: now, updatedAtMS: now
        ).insert(db)
        try insertLedgerChildren(entry, in: db)
    }

    private static func insertLedgerChildren(_ entry: LedgerEntry, in db: Database) throws {
        for posting in entry.postings { try LedgerPostingRow(transactionID: entry.id, posting: posting).insert(db) }
        for tag in entry.tags {
            try db.execute(sql: "INSERT INTO ledger_transaction_tags (transaction_id, tag_id) VALUES (?, ?)", arguments: [entry.id.uuidString, tag.id.uuidString])
        }
    }

    private static func canonicalImportIdentities(in db: Database) throws -> LedgerImportIdentities {
        let entries = try fetchLedgerEntries(in: db)
        return LedgerImportIdentities(
            transactionIDs: Set(entries.map(\.id)),
            fingerprints: Set(try entries.map { try LedgerCSV.semanticFingerprint(for: $0) })
        )
    }

    private static func importEntry(_ entry: LedgerEntry, fingerprint: String) throws -> LedgerEntry {
        try LedgerEntry(
            id: entry.id,
            kind: entry.kind,
            civilDate: entry.civilDate,
            recordedAt: entry.recordedAt,
            description: entry.description,
            payee: entry.payee,
            category: entry.category,
            tags: entry.tags,
            postings: entry.postings,
            note: entry.note,
            importFingerprint: fingerprint
        )
    }

    private static func insertClassificationRule(_ rule: ClassificationRule, in db: Database) throws {
        try ClassificationRuleRow(
            id: rule.id.uuidString,
            name: rule.name,
            priority: rule.priority,
            isEnabled: rule.isEnabled,
            matchMode: rule.matchMode.rawValue,
            payeePattern: rule.payeePattern,
            kind: rule.kind?.rawValue,
            sourceContainerID: rule.sourceContainerID?.uuidString,
            amountDirection: rule.amountDirection?.rawValue,
            resultCategoryID: rule.resultCategory?.id.uuidString
        ).insert(db)
        for tag in rule.resultTags {
            try db.execute(
                sql: "INSERT INTO classification_rule_tags (rule_id, tag_id) VALUES (?, ?)",
                arguments: [rule.id.uuidString, tag.id.uuidString]
            )
        }
    }

    static func fetchLedgerEntries(in db: Database) throws -> [LedgerEntry] {
        let rows = try LedgerTransactionRow.fetchAll(db, sql: "SELECT * FROM ledger_transactions ORDER BY civil_date DESC, recorded_at_ms DESC, id")
        let categories = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, parent_id, name FROM categories").map { row -> (String, Category) in
            guard let id = UUID(uuidString: row["id"]) else { throw LedgerPersistenceError.corruptRecord }
            let rawParent: String? = row["parent_id"]
            return (row["id"], Category(id: id, parentID: rawParent.flatMap(UUID.init(uuidString:)), name: row["name"]))
        })
        let tags = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, name FROM tags").map { row -> (String, Tag) in
            guard let id = UUID(uuidString: row["id"]) else { throw LedgerPersistenceError.corruptRecord }
            return (row["id"], Tag(id: id, name: row["name"]))
        })
        return try rows.map { row in
            guard let id = UUID(uuidString: row.id),
                  let kind = TransactionKind(rawValue: row.kind),
                  let date = try? CivilDate(canonical: row.civilDate) else { throw LedgerPersistenceError.corruptRecord }
            let postings = try LedgerPostingRow.fetchAll(db, sql: "SELECT * FROM ledger_postings WHERE transaction_id = ? ORDER BY role", arguments: [row.id]).map { try $0.domain() }
            let linkedTags = try String.fetchAll(db, sql: "SELECT tag_id FROM ledger_transaction_tags WHERE transaction_id = ? ORDER BY tag_id", arguments: [row.id]).map { tagID in
                guard let tag = tags[tagID] else { throw LedgerPersistenceError.corruptRecord }
                return tag
            }
            let category: Category?
            if let categoryID = row.categoryID {
                guard let storedCategory = categories[categoryID] else { throw LedgerPersistenceError.corruptRecord }
                category = storedCategory
            } else {
                category = nil
            }
            return try LedgerEntry(
                id: id, kind: kind, civilDate: date,
                recordedAt: UTCInstant(millisecondsSince1970: row.recordedAtMS),
                description: row.description, payee: row.payee,
                category: category, tags: linkedTags,
                postings: postings, note: row.note, importFingerprint: row.importFingerprint
            )
        }
    }

    private static func fetchClassificationRules(in db: Database) throws -> [ClassificationRule] {
        let categories = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, parent_id, name FROM categories").compactMap { row -> (String, Category)? in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let rawParent: String? = row["parent_id"]
            return (row["id"], Category(id: id, parentID: rawParent.flatMap(UUID.init(uuidString:)), name: row["name"]))
        })
        let tags = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, name FROM tags").compactMap { row -> (String, Tag)? in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return (row["id"], Tag(id: id, name: row["name"]))
        })
        return try ClassificationRuleRow.fetchAll(db, sql: "SELECT * FROM classification_rules ORDER BY priority, id").map { row in
            guard let id = UUID(uuidString: row.id), let mode = ClassificationMatchMode(rawValue: row.matchMode) else { throw LedgerPersistenceError.corruptRecord }
            let tagIDs = try String.fetchAll(db, sql: "SELECT tag_id FROM classification_rule_tags WHERE rule_id = ? ORDER BY tag_id", arguments: [row.id])
            return ClassificationRule(
                id: id, name: row.name, priority: row.priority, isEnabled: row.isEnabled,
                matchMode: mode, payeePattern: row.payeePattern,
                kind: row.kind.flatMap(TransactionKind.init(rawValue:)),
                sourceContainerID: row.sourceContainerID.flatMap(UUID.init(uuidString:)),
                amountDirection: row.amountDirection.flatMap(LedgerAmountDirection.init(rawValue:)),
                resultCategory: row.resultCategoryID.flatMap { categories[$0] },
                resultTags: tagIDs.compactMap { tags[$0] }
            )
        }
    }
}

enum LedgerImportFingerprintRepair {
    static func migrateCandidateFingerprints(in db: Database) throws {
        let importedIDs = try String.fetchAll(
            db,
            sql: "SELECT id FROM ledger_transactions WHERE import_fingerprint IS NOT NULL ORDER BY id"
        )
        guard !importedIDs.isEmpty else { return }

        let entriesByID = Dictionary(
            uniqueKeysWithValues: try WealthStore.fetchLedgerEntries(in: db).map {
                ($0.id.uuidString.lowercased(), $0)
            }
        )
        try db.execute(sql: "UPDATE ledger_transactions SET import_fingerprint = NULL WHERE import_fingerprint IS NOT NULL")

        var assigned = Set<String>()
        for id in importedIDs {
            guard let entry = entriesByID[id.lowercased()] else {
                throw LedgerPersistenceError.corruptRecord
            }
            let fingerprint = try LedgerCSV.semanticFingerprint(for: entry)
            guard assigned.insert(fingerprint).inserted else { continue }
            try db.execute(
                sql: "UPDATE ledger_transactions SET import_fingerprint = ? WHERE id = ?",
                arguments: [fingerprint, id]
            )
        }
    }
}
