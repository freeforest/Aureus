import CryptoKit
import Foundation

enum LedgerCSVError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidUTF8
    case malformedCSV(String)
    case invalidHeader
    case unsupportedSchema(String)
    case invalidField(String)
    case unknownContainer(String)
    case unknownCategory(String)
    case unknownTag(String)
    case ambiguousCategory(String)
    case ambiguousTag(String)
    case convertedValueMismatch

    var description: String {
        switch self {
        case .invalidUTF8: "The file is not valid UTF-8."
        case .malformedCSV(let reason): "Malformed CSV: \(reason)"
        case .invalidHeader: "The CSV columns do not match Aureus Ledger V1."
        case .unsupportedSchema(let version): "Unsupported CSV schema: \(version)."
        case .invalidField(let field): "Invalid value for \(field)."
        case .unknownContainer(let value): "Unknown container: \(value)."
        case .unknownCategory(let value): "Unknown category: \(value)."
        case .unknownTag(let value): "Unknown tag: \(value)."
        case .ambiguousCategory(let value): "Ambiguous category: \(value). Multiple preserved categories match this name."
        case .ambiguousTag(let value): "Ambiguous tag: \(value). Multiple preserved tags match this name."
        case .convertedValueMismatch: "Converted CNY does not match the amount and FX rate."
        }
    }
}

struct LedgerImportPreviewRow: Identifiable, Equatable, Sendable {
    let id: Int
    let entry: LedgerEntry?
    let error: String?
    let duplicateReasons: [LedgerImportDuplicateReason]
    let ruleApplication: LedgerImportRuleApplication?

    var isDuplicate: Bool { !duplicateReasons.isEmpty }
}

enum LedgerImportDuplicateReason: String, Equatable, Sendable {
    case existingFingerprint
    case fileFingerprint
    case existingTransactionID
    case fileTransactionID
}

enum LedgerImportValueSource: String, Equatable, Sendable {
    case csv = "CSV"
    case rule = "Rule fallback"
    case none = "None"
}

struct LedgerImportRuleApplication: Equatable, Sendable {
    let ruleID: UUID
    let ruleName: String
    let finalCategoryName: String?
    let finalTagNames: [String]
    let categorySource: LedgerImportValueSource
    let tagsSource: LedgerImportValueSource
}

struct LedgerImportPreview: Equatable, Sendable {
    let rows: [LedgerImportPreviewRow]
    var validEntries: [LedgerEntry] { rows.filter { !$0.isDuplicate && $0.error == nil }.compactMap(\.entry) }
    var errorCount: Int { rows.count { $0.error != nil } }
    var duplicateCount: Int { rows.count { $0.isDuplicate } }
    var canImport: Bool { !validEntries.isEmpty && errorCount == 0 && duplicateCount == 0 }
}

enum LedgerCSV {
    static let schemaVersion = "AUREUS_LEDGER_V1"
    static let header = [
        "schema_version", "transaction_id", "kind", "civil_date", "recorded_at_ms",
        "description", "payee", "category", "tags", "source_container_id",
        "source_currency", "source_amount", "source_fx_rate", "source_converted_cny",
        "source_fx_source", "source_fx_reference_date", "source_fx_recorded_at_ms",
        "source_fx_manual", "source_fx_stale", "target_container_id", "target_currency",
        "target_amount", "target_fx_rate", "target_converted_cny", "target_fx_source",
        "target_fx_reference_date", "target_fx_recorded_at_ms", "target_fx_manual",
        "target_fx_stale", "note"
    ]

    static func export(_ entries: [LedgerEntry]) -> Data {
        var records = [header]
        records.append(contentsOf: entries.sorted { lhs, rhs in
            lhs.civilDate == rhs.civilDate ? lhs.id.uuidString < rhs.id.uuidString : lhs.civilDate < rhs.civilDate
        }.map(exportRecord))
        let text = records.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data(text.utf8)
    }

    static func preview(
        data: Data,
        containers: [WealthContainer],
        categories: [Category],
        tags: [Tag],
        rules: [ClassificationRule],
        existingFingerprints: Set<String>,
        existingTransactionIDs: Set<UUID> = []
    ) throws -> LedgerImportPreview {
        guard let text = String(data: data, encoding: .utf8) else { throw LedgerCSVError.invalidUTF8 }
        let records = try parseRecords(text)
        guard let first = records.first, first == header else { throw LedgerCSVError.invalidHeader }
        let containerMap = Dictionary(
            containers.map { ($0.id.uuidString, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let categoryResolver = TaxonomyResolver(categories, name: \Category.name)
        let tagResolver = TaxonomyResolver(tags, name: \Tag.name)
        var fileFingerprints = Set<String>()
        var fileTransactionIDs = Set<UUID>()
        var previewRows: [LedgerImportPreviewRow] = []
        for (offset, fields) in records.dropFirst().enumerated() {
            let line = offset + 2
            do {
                guard fields.count == header.count else { throw LedgerCSVError.malformedCSV("row \(line) has \(fields.count) columns") }
                let dictionary = Dictionary(zip(header, fields), uniquingKeysWith: { existing, _ in existing })
                guard dictionary["schema_version"] == schemaVersion else { throw LedgerCSVError.unsupportedSchema(dictionary["schema_version"] ?? "") }
                let parsed = try importedEntry(
                    dictionary, containers: containerMap, categories: categoryResolver,
                    tags: tagResolver, rules: rules
                )
                let fingerprint = try semanticFingerprint(for: parsed.entry)
                let entry = try LedgerEntry(
                    id: parsed.entry.id, kind: parsed.entry.kind, civilDate: parsed.entry.civilDate,
                    recordedAt: parsed.entry.recordedAt, description: parsed.entry.description,
                    payee: parsed.entry.payee, category: parsed.entry.category, tags: parsed.entry.tags,
                    postings: parsed.entry.postings, note: parsed.entry.note,
                    importFingerprint: fingerprint
                )
                var duplicateReasons: [LedgerImportDuplicateReason] = []
                if existingFingerprints.contains(fingerprint) { duplicateReasons.append(.existingFingerprint) }
                if fileFingerprints.contains(fingerprint) { duplicateReasons.append(.fileFingerprint) }
                if existingTransactionIDs.contains(entry.id) { duplicateReasons.append(.existingTransactionID) }
                if fileTransactionIDs.contains(entry.id) { duplicateReasons.append(.fileTransactionID) }
                fileFingerprints.insert(fingerprint)
                fileTransactionIDs.insert(entry.id)
                previewRows.append(LedgerImportPreviewRow(
                    id: line,
                    entry: entry,
                    error: nil,
                    duplicateReasons: duplicateReasons,
                    ruleApplication: parsed.ruleApplication
                ))
            } catch {
                previewRows.append(LedgerImportPreviewRow(
                    id: line,
                    entry: nil,
                    error: String(describing: error),
                    duplicateReasons: [],
                    ruleApplication: nil
                ))
            }
        }
        return LedgerImportPreview(rows: previewRows)
    }

    private static func importedEntry(
        _ fields: [String: String],
        containers: [String: WealthContainer],
        categories: TaxonomyResolver<Category>,
        tags: TaxonomyResolver<Tag>,
        rules: [ClassificationRule]
    ) throws -> (entry: LedgerEntry, ruleApplication: LedgerImportRuleApplication?) {
        guard let id = UUID(uuidString: fields["transaction_id"] ?? ""),
              let kind = TransactionKind(rawValue: fields["kind"] ?? ""),
              let date = try? CivilDate(canonical: fields["civil_date"] ?? ""),
              let recordedAt = Int64(fields["recorded_at_ms"] ?? "") else { throw LedgerCSVError.invalidField("identity/date") }
        let source = try posting(prefix: "source", role: kind == .transfer ? .transferSource : .primary, fields: fields, containers: containers)
        var postings = [source]
        if kind == .transfer {
            postings.append(try posting(prefix: "target", role: .transferTarget, fields: fields, containers: containers))
        }
        var category: Category?
        let categoryText = unprotect(fields["category"] ?? "")
        if !categoryText.isEmpty {
            switch categories.resolve(categoryText) {
            case .unique(let match): category = match
            case .ambiguous: throw LedgerCSVError.ambiguousCategory(categoryText)
            case .missing: throw LedgerCSVError.unknownCategory(categoryText)
            }
        }
        var entryTags: [Tag] = []
        if let tagText = fields["tags"], !tagText.isEmpty {
            let names = try JSONDecoder().decode([String].self, from: Data(tagText.utf8)).map(unprotect)
            entryTags = try names.map { name in
                switch tags.resolve(name) {
                case .unique(let match): return match
                case .ambiguous: throw LedgerCSVError.ambiguousTag(name)
                case .missing: throw LedgerCSVError.unknownTag(name)
                }
            }
        }
        let description = unprotect(fields["description"] ?? "")
        let payee = unprotect(fields["payee"] ?? "")
        let result = DeterministicLedgerClassifier.classify(
            ClassificationInput(payee: payee.isEmpty ? nil : payee, description: description, kind: kind, sourceContainerID: source.containerID),
            rules: rules
        )
        let categorySource: LedgerImportValueSource = category == nil && result?.category != nil ? .rule : (category == nil ? .none : .csv)
        let tagsSource: LedgerImportValueSource = entryTags.isEmpty && !(result?.tags.isEmpty ?? true) ? .rule : (entryTags.isEmpty ? .none : .csv)
        if category == nil { category = result?.category }
        if entryTags.isEmpty { entryTags = result?.tags ?? [] }
        let appliedRule = result.flatMap { result in
            rules.first(where: { $0.id == result.ruleID }).map { rule in
                LedgerImportRuleApplication(
                    ruleID: result.ruleID,
                    ruleName: rule.name,
                    finalCategoryName: category?.name,
                    finalTagNames: entryTags.map(\.name),
                    categorySource: categorySource,
                    tagsSource: tagsSource
                )
            }
        }
        return (
            try LedgerEntry(
                id: id, kind: kind, civilDate: date,
                recordedAt: UTCInstant(millisecondsSince1970: recordedAt),
                description: description, payee: payee, category: category,
                tags: entryTags, postings: postings, note: unprotect(fields["note"] ?? "")
            ),
            appliedRule
        )
    }

    private static func posting(
        prefix: String,
        role: LedgerPostingRole,
        fields: [String: String],
        containers: [String: WealthContainer]
    ) throws -> LedgerPosting {
        let containerText = fields["\(prefix)_container_id"] ?? ""
        guard let container = containers[containerText] else { throw LedgerCSVError.unknownContainer(containerText) }
        guard let currency = CurrencyCode(rawValue: fields["\(prefix)_currency"] ?? ""),
              let amountDecimal = try? FixedPointMath.parseCanonical(fields["\(prefix)_amount"] ?? ""),
              let rateDecimal = try? FixedPointMath.parseCanonical(fields["\(prefix)_fx_rate"] ?? ""),
              let convertedDecimal = try? FixedPointMath.parseCanonical(fields["\(prefix)_converted_cny"] ?? ""),
              let referenceDate = try? CivilDate(canonical: fields["\(prefix)_fx_reference_date"] ?? ""),
              let fxRecorded = Int64(fields["\(prefix)_fx_recorded_at_ms"] ?? ""),
              let manual = parseBool(fields["\(prefix)_fx_manual"] ?? ""),
              let stale = parseBool(fields["\(prefix)_fx_stale"] ?? "") else { throw LedgerCSVError.invalidField(prefix) }
        let original = try Money(decimal: amountDecimal, currency: currency)
        let rate = try FXRate(decimal: rateDecimal, sourceCurrency: currency, targetCurrency: .cny)
        let valuation = try FXValuation(
            original: original, rate: rate, referenceDate: referenceDate,
            fetchedAt: UTCInstant(millisecondsSince1970: fxRecorded),
            providerIdentifier: unprotect(fields["\(prefix)_fx_source"] ?? ""),
            isManualOverride: manual, isStale: stale
        )
        guard valuation.convertedCNY == (try Money(decimal: convertedDecimal, currency: .cny)) else { throw LedgerCSVError.convertedValueMismatch }
        return try LedgerPosting(role: role, containerID: container.id, valuation: valuation)
    }

    private static func exportRecord(_ entry: LedgerEntry) -> [String] {
        let source = entry.kind == .transfer ? entry.transferSource! : entry.primaryPosting!
        let target = entry.transferTarget
        let tagData = try! JSONEncoder().encode(entry.tags.map { protect($0.name) })
        return [
            schemaVersion, entry.id.uuidString, entry.kind.rawValue, entry.civilDate.description,
            String(entry.recordedAt.millisecondsSince1970), protect(entry.description),
            protect(entry.payee ?? ""), protect(entry.category?.name ?? ""), String(decoding: tagData, as: UTF8.self),
            source.containerID.uuidString, source.valuation.original.currency.rawValue,
            decimal(source.valuation.original.decimal), decimal(source.valuation.rate.decimal),
            decimal(source.valuation.convertedCNY.decimal), protect(source.valuation.providerIdentifier),
            source.valuation.referenceDate.description, String(source.valuation.fetchedAt.millisecondsSince1970),
            bool(source.valuation.isManualOverride), bool(source.valuation.isStale),
            target?.containerID.uuidString ?? "", target?.valuation.original.currency.rawValue ?? "",
            target.map { decimal($0.valuation.original.decimal) } ?? "",
            target.map { decimal($0.valuation.rate.decimal) } ?? "",
            target.map { decimal($0.valuation.convertedCNY.decimal) } ?? "",
            protect(target?.valuation.providerIdentifier ?? ""), target?.valuation.referenceDate.description ?? "",
            target.map { String($0.valuation.fetchedAt.millisecondsSince1970) } ?? "",
            target.map { bool($0.valuation.isManualOverride) } ?? "",
            target.map { bool($0.valuation.isStale) } ?? "", protect(entry.note ?? "")
        ]
    }

    private static func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private static func bool(_ value: Bool) -> String { value ? "true" : "false" }
    private static func parseBool(_ value: String) -> Bool? {
        switch value { case "true": true; case "false": false; default: nil }
    }

    private static func protect(_ value: String) -> String {
        guard let first = value.first else { return value }
        if first == "'" { return "'" + value }
        return ["=", "+", "-", "@"].contains(first) ? "'" + value : value
    }

    private static func unprotect(_ value: String) -> String {
        if value.hasPrefix("''") { return String(value.dropFirst()) }
        if value.hasPrefix("'"), let next = value.dropFirst().first, ["=", "+", "-", "@"].contains(next) {
            return String(value.dropFirst())
        }
        return value
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private enum TaxonomyResolution<Value> {
        case unique(Value)
        case ambiguous
        case missing
    }

    private struct TaxonomyResolver<Value> {
        private let exact: [String: [Value]]
        private let normalized: [String: [Value]]

        init(_ values: [Value], name: KeyPath<Value, String>) {
            var exact: [String: [Value]] = [:]
            var normalized: [String: [Value]] = [:]
            for value in values {
                let displayName = value[keyPath: name]
                exact[displayName.precomposedStringWithCanonicalMapping, default: []].append(value)
                if let key = try? LedgerNameNormalization.key(displayName) {
                    normalized[key, default: []].append(value)
                }
            }
            self.exact = exact
            self.normalized = normalized
        }

        func resolve(_ raw: String) -> TaxonomyResolution<Value> {
            let exactMatches = exact[raw.precomposedStringWithCanonicalMapping] ?? []
            if exactMatches.count == 1 { return .unique(exactMatches[0]) }
            if exactMatches.count > 1 { return .ambiguous }
            guard let key = try? LedgerNameNormalization.key(raw) else { return .missing }
            let normalizedMatches = normalized[key] ?? []
            if normalizedMatches.count == 1 { return .unique(normalizedMatches[0]) }
            if normalizedMatches.count > 1 { return .ambiguous }
            return .missing
        }
    }

    static func semanticFingerprint(for entry: LedgerEntry) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let canonical = CanonicalLedgerEntry(entry)
        let data = try encoder.encode(canonical)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct CanonicalLedgerEntry: Encodable {
        let version = 1
        let kind: String
        let civilDate: String
        let recordedAtMS: Int64
        let description: String
        let payee: String?
        let categoryID: String?
        let tagIDs: [String]
        let postings: [CanonicalLedgerPosting]
        let note: String?

        init(_ entry: LedgerEntry) {
            kind = entry.kind.rawValue
            civilDate = entry.civilDate.description
            recordedAtMS = entry.recordedAt.millisecondsSince1970
            description = Self.text(entry.description)
            payee = entry.payee.map(Self.text)
            categoryID = entry.category?.id.uuidString.lowercased()
            tagIDs = Set(entry.tags.map { $0.id.uuidString.lowercased() }).sorted()
            postings = entry.postings
                .map(CanonicalLedgerPosting.init)
                .sorted { $0.roleOrder < $1.roleOrder }
            note = entry.note.map(Self.text)
        }

        private static func text(_ value: String) -> String {
            value.precomposedStringWithCanonicalMapping
        }
    }

    private struct CanonicalLedgerPosting: Encodable {
        let role: String
        let containerID: String
        let originalMinor: Int64
        let originalCurrency: String
        let convertedCNYMinor: Int64
        let fxCoefficient: Int64
        let fxSourceCurrency: String
        let fxTargetCurrency: String
        let fxSource: String
        let fxReferenceDate: String
        let fxRecordedAtMS: Int64
        let fxIsManual: Bool
        let fxIsStale: Bool

        fileprivate var roleOrder: Int {
            switch role {
            case LedgerPostingRole.primary.rawValue: 0
            case LedgerPostingRole.transferSource.rawValue: 1
            case LedgerPostingRole.transferTarget.rawValue: 2
            default: 3
            }
        }

        init(_ posting: LedgerPosting) {
            role = posting.role.rawValue
            containerID = posting.containerID.uuidString.lowercased()
            originalMinor = posting.valuation.original.minorUnits
            originalCurrency = posting.valuation.original.currency.rawValue
            convertedCNYMinor = posting.valuation.convertedCNY.minorUnits
            fxCoefficient = posting.valuation.rate.coefficient
            fxSourceCurrency = posting.valuation.rate.sourceCurrency.rawValue
            fxTargetCurrency = posting.valuation.rate.targetCurrency.rawValue
            fxSource = posting.valuation.providerIdentifier.precomposedStringWithCanonicalMapping
            fxReferenceDate = posting.valuation.referenceDate.description
            fxRecordedAtMS = posting.valuation.fetchedAt.millisecondsSince1970
            fxIsManual = posting.valuation.isManualOverride
            fxIsStale = posting.valuation.isStale
        }
    }

    static func parseRecords(_ text: String) throws -> [[String]] {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty: inQuotes = true
                case ",": record.append(field); field = ""
                case "\n":
                    if field.last == "\r" { field.removeLast() }
                    record.append(field); field = ""
                    if !(record.count == 1 && record[0].isEmpty) { records.append(record) }
                    record = []
                default: field.append(character)
                }
            }
            index = text.index(after: index)
        }
        guard !inQuotes else { throw LedgerCSVError.malformedCSV("unterminated quoted field") }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }
        return records
    }
}
