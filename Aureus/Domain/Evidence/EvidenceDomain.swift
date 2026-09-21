import Foundation

enum EvidenceError: String, Error, Equatable, Sendable {
    case disabled, invalidValue, unsafeRoot, ownerConflict, maintenanceUnavailable
    case targetMissing, operationConflict, materialUnavailable, relationshipChanged
    case inconsistentRegistration, recoveryRequired, legacyFormatUnsupported
}

enum EvidenceTarget: Equatable, Sendable {
    case ledger(UUID), container(UUID), portfolioActivity(UUID)

    var id: UUID {
        switch self { case .ledger(let id), .container(let id), .portfolioActivity(let id): id }
    }
    var column: String {
        switch self { case .ledger: "ledger_entry_id"; case .container: "container_id"; case .portfolioActivity: "portfolio_activity_id" }
    }
    var table: String {
        switch self { case .ledger: "ledger_transactions"; case .container: "asset_containers"; case .portfolioActivity: "portfolio_activities" }
    }
    var linkTable: String {
        switch self { case .ledger: "evidence_ledger_links"; case .container: "evidence_container_links"; case .portfolioActivity: "evidence_portfolio_activity_links" }
    }
}

struct EvidenceDocument: Equatable, Sendable {
    let file: ManagedEvidenceFile
    let registeredAt: Int64
    var id: UUID { file.id }
}

struct EvidenceRelation: Equatable, Sendable {
    let id: UUID
    let documentID: UUID
    let target: EvidenceTarget
    let createdAt: Int64
    let meaning: String
}

enum EvidenceImportState: String, Sendable, CaseIterable {
    case registered, stagingOwned, prepared, committed, cancelled, recoveryRequired
}

struct EvidenceImportOperation: Equatable, Sendable {
    let id: UUID
    let documentID: UUID
    let target: EvidenceTarget
    let meaning: String
    let originalFilename: String
    let registeredAt: Int64
    let state: EvidenceImportState
    let identity: ManagedEvidenceIdentity?
    let file: ManagedEvidenceFile?
    let lastError: EvidenceError?
}

struct EvidenceImportResult: Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available, needsSourceSelection, pendingReview, publishedPendingRecovery
        case materialUnavailable, targetRemoved, relationshipChanged, cancelled
    }
    let operation: EvidenceImportOperation
    let availability: Availability
}

enum EvidenceValue {
    static func uuid(_ text: String) throws -> UUID {
        guard let value = UUID(uuidString: text), value.uuidString == text else { throw EvidenceError.invalidValue }
        return value
    }
    static func text(_ value: String, nonempty: Bool = false) throws {
        guard !value.utf8.contains(0), !nonempty || !value.isEmpty else { throw EvidenceError.invalidValue }
    }
    static func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite, value >= Double(Int64.min), value < Double(Int64.max) else { throw EvidenceError.invalidValue }
        return Int64(value.rounded())
    }
    static func file(_ file: ManagedEvidenceFile) throws {
        try text(file.originalFilename, nonempty: true)
        guard file.relativeReference == file.id.uuidString.lowercased() + ".original",
              file.byteCount >= 0, file.sha256.utf8.count == 64,
              file.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw EvidenceError.invalidValue
        }
        _ = try milliseconds(file.copiedAt)
    }
}
