import Foundation

/// A point-in-time metadata count, not connectivity, entitlement, or request coverage.
/// Session snapshots deliberately have no serialization conformance.
struct CacheFreshnessSnapshot: Equatable, Sendable {
    let observedAt: UTCInstant
    let freshCount: Int
    let expiredCount: Int
    let legacyCount: Int
    var classifiedCount: Int { freshCount + expiredCount }
    var totalCount: Int { classifiedCount + legacyCount }

    var state: String {
        if totalCount == 0 { return "Empty" }
        if classifiedCount == 0 { return "Legacy only" }
        if expiredCount == 0 { return "Within TTL" }
        if freshCount == 0 { return "Expired" }
        return "Mixed TTL"
    }
}

enum CacheFreshnessStatus: Equatable, Sendable {
    case notLoaded
    case available(CacheFreshnessSnapshot)
    case unavailable

    var snapshot: CacheFreshnessSnapshot? {
        guard case let .available(value) = self else { return nil }
        return value
    }

    func label(for title: String) -> String {
        switch self {
        case .notLoaded: return "\(title): Not loaded. Local cache status has not been read."
        case .unavailable: return "\(title): Unavailable. Local cache status could not be read."
        case let .available(value):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS 'UTC'"
            var text = "\(title): \(value.state). As of \(formatter.string(from: value.observedAt.date)). "
                + "\(value.totalCount) total entries; \(value.classifiedCount) TTL-classified; "
                + "\(value.freshCount) within TTL; \(value.expiredCount) expired; \(value.legacyCount) legacy. "
            text += value.totalCount == 0 ? "No entries are currently available."
                : "Offline coverage depends on the requested data and existing authorization."
            if value.expiredCount > 0 {
                text += " Expired entries require existing stale disclosure and fallback rules."
            }
            if value.legacyCount > 0 {
                text += " Legacy entries do not establish Twelve Data V1 offline availability."
            }
            return text + " TTL does not prove market real-time freshness or entitlement."
        }
    }
}
