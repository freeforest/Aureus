import CryptoKit
import Foundation

enum LedgerCorrectionError: Error, Equatable, Sendable {
    case staleDraft, operationConflict, invalidRequest, invalidHistory, maintenanceUnavailable
}

struct LedgerEditToken: Codable, Equatable, Sendable {
    let targetID: UUID
    let stateDigest: String
    let latestHistoryID: UUID?
    let storeID: UUID
    let epoch: UUID
}

struct LedgerEditContext: Sendable {
    let entry: LedgerEntry
    let token: LedgerEditToken
}

struct LedgerCorrectionRequest: Sendable {
    let candidate: LedgerEntry
    let expected: LedgerEditToken
    let operationID: UUID
    let reason: String
    let occurredAt: UTCInstant
}

enum LedgerCorrectionCurrentState: String, Sendable {
    case unchanged, changed, deleted
}

enum LedgerCorrectionResult: Sendable {
    case applied(LedgerCorrectionHistory)
    case alreadyApplied(LedgerCorrectionHistory, LedgerCorrectionCurrentState)
    case noChange
    case minorUpdate
}

// Only the financial/identifying projection is retained in history. It is never a calculation input.
struct LedgerCorrectionProjection: Codable, Equatable, Sendable {
    struct Posting: Codable, Equatable, Sendable {
        let role: LedgerPostingRole
        let containerID: UUID
        let valuation: FXValuation
    }
    let id: UUID
    let kind: TransactionKind
    let civilDate: CivilDate
    let description: String
    let payee: String?
    let postings: [Posting]

    init(_ entry: LedgerEntry) {
        id = entry.id; kind = entry.kind; civilDate = entry.civilDate
        description = entry.description; payee = entry.payee
        postings = entry.postings.sorted { $0.role.rawValue < $1.role.rawValue }
            .map { Posting(role: $0.role, containerID: $0.containerID, valuation: $0.valuation) }
    }

    func hasSameImportantValues(as other: Self) -> Bool {
        guard id == other.id, kind == other.kind, civilDate == other.civilDate,
              description == other.description, payee == other.payee,
              postings.count == other.postings.count else { return false }
        return zip(postings, other.postings).allSatisfy { a, b in
            let x = a.valuation, y = b.valuation
            return a.role == b.role && a.containerID == b.containerID
                && x.original == y.original && x.rate == y.rate && x.convertedCNY == y.convertedCNY
                && x.referenceDate == y.referenceDate && x.providerIdentifier == y.providerIdentifier
                && x.isManualOverride == y.isManualOverride && x.isStale == y.isStale
        }
    }

    func validate() throws {
        guard !description.contains("\0"), !(payee?.contains("\0") ?? false),
              postings.map(\.role.rawValue) == postings.map(\.role.rawValue).sorted() else {
            throw LedgerCorrectionError.invalidHistory
        }
        _ = try CivilDate(canonical: civilDate.description)
        let checked = try postings.map { p -> LedgerPosting in
            let v = p.valuation
            _ = try CivilDate(canonical: v.referenceDate.description)
            guard !v.providerIdentifier.isEmpty, !v.providerIdentifier.contains("\0") else {
                throw LedgerCorrectionError.invalidHistory
            }
            let rate = try FXRate(coefficient: v.rate.coefficient, sourceCurrency: v.rate.sourceCurrency,
                                  targetCurrency: v.rate.targetCurrency)
            let rebuilt = try FXValuation(original: v.original, rate: rate, referenceDate: v.referenceDate,
                fetchedAt: v.fetchedAt, providerIdentifier: v.providerIdentifier,
                isManualOverride: v.isManualOverride, isStale: v.isStale)
            guard rebuilt == v else { throw LedgerCorrectionError.invalidHistory }
            return try LedgerPosting(role: p.role, containerID: p.containerID, valuation: v)
        }
        let entry = try LedgerEntry(id: id, kind: kind, civilDate: civilDate,
            recordedAt: UTCInstant(millisecondsSince1970: 0), description: description,
            payee: payee, postings: checked)
        guard entry.description == description, entry.payee == payee else { throw LedgerCorrectionError.invalidHistory }
    }
}

struct LedgerDeletionContext: Codable, Equatable, Sendable {
    struct Link: Codable, Equatable, Sendable {
        let documentID: UUID
        let linkID: UUID
        let createdAt: UTCInstant
        let meaning: String
    }
    let origin: String
    let links: [Link]
    let activityIDs: [UUID]
}

struct LedgerHistoryPayload: Codable, Equatable, Sendable {
    let version: Int
    let before: LedgerCorrectionProjection
    let after: LedgerCorrectionProjection?
    let deletion: LedgerDeletionContext?

    func validate(kind: String) throws {
        guard version == 1 else { throw LedgerCorrectionError.invalidHistory }
        try before.validate()
        switch kind {
        case "correction":
            guard let after, deletion == nil, after.id == before.id,
                  !before.hasSameImportantValues(as: after) else { throw LedgerCorrectionError.invalidHistory }
            try after.validate()
        case "deletionContext":
            guard after == nil, let deletion, deletion.origin == "existingDeleteAPI",
                  deletion.activityIDs.map(\.uuidString) == deletion.activityIDs.map(\.uuidString).sorted(),
                  Set(deletion.activityIDs).count == deletion.activityIDs.count,
                  deletion.links.map(\.linkID.uuidString) == deletion.links.map(\.linkID.uuidString).sorted(),
                  Set(deletion.links.map(\.linkID)).count == deletion.links.count,
                  deletion.links.allSatisfy({ !$0.meaning.contains("\0") }) else { throw LedgerCorrectionError.invalidHistory }
        default: throw LedgerCorrectionError.invalidHistory
        }
    }
}

struct LedgerCorrectionHistory: Equatable, Sendable {
    let sequence: Int64
    let id: UUID
    let operationID: UUID
    let targetID: UUID
    let kind: String
    let occurredAt: UTCInstant
    let reason: String?
    let payload: LedgerHistoryPayload
}

enum LedgerCorrectionEncoding {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func digest<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }
    static func reason(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= 500, !result.contains("\0") else { throw LedgerCorrectionError.invalidRequest }
        return result
    }
    struct Candidate: Codable {
        let id: UUID, kind: TransactionKind, date: CivilDate, recordedAt: UTCInstant
        let description: String, payee: String?, categoryID: UUID?, note: String?, fingerprint: String?
        let tags: [UUID], postings: [LedgerPosting]
        init(_ e: LedgerEntry) {
            id = e.id; kind = e.kind; date = e.civilDate; recordedAt = e.recordedAt
            description = e.description; payee = e.payee; categoryID = e.category?.id
            note = e.note; fingerprint = e.importFingerprint
            tags = e.tags.map(\.id).sorted { $0.uuidString < $1.uuidString }
            postings = e.postings.sorted { $0.role.rawValue < $1.role.rawValue }
        }
    }
    struct Request: Encodable {
        let candidate: Candidate
        let expected: LedgerEditToken
        let reason: String
        let occurredAt: UTCInstant
    }
}
