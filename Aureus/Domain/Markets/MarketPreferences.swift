import Foundation

enum MarketPreferenceError: Error, Equatable, Sendable {
    case invalidIdentifier
    case duplicate
    case maximumCountReached
    case missingItem
    case persistenceFailure
}

enum MarketRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case yearToDate = "YTD"
    case oneYear = "1Y"
    case fiveYears = "5Y"
    case maximum = "MAX"

    var id: String { rawValue }

    var outputSize: Int {
        switch self {
        case .oneDay: 1
        case .oneWeek: 7
        case .oneMonth: 31
        case .threeMonths: 93
        case .yearToDate, .oneYear: 366
        case .fiveYears: 1_830
        case .maximum: 5_000
        }
    }

    var dailyDisclosure: String {
        self == .oneDay ? "Latest Daily Bar" : "Daily bars"
    }
}

struct MarketWatchlistIdentity: Codable, Equatable, Hashable, Identifiable, Sendable {
    let symbol: String
    let mic: String

    var id: String { "\(symbol)|\(mic)" }

    init(symbol: String, mic: String) throws {
        let symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let mic = mic.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty,
              symbol.count <= 32,
              symbol.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-".contains($0)) }),
              mic.count == 4,
              mic.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw MarketPreferenceError.invalidIdentifier
        }
        self.symbol = symbol
        self.mic = mic
    }
}

struct MarketPreferencesSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    var watchlist: [MarketWatchlistIdentity]
    var selectedRange: MarketRange
    var enabledIndicators: Set<MarketIndicatorKind>
    var showsAccessibleTable: Bool

    static let empty = MarketPreferencesSnapshot(
        version: currentVersion,
        watchlist: [],
        selectedRange: .oneYear,
        enabledIndicators: [.sma20, .ema12],
        showsAccessibleTable: false
    )
}

actor MarketPreferencesStore {
    static let maximumWatchlistCount = 100
    static let storageKey = "markets.preferences.v1"

    private let defaults: UserDefaults?
    private var memorySnapshot: MarketPreferencesSnapshot?

    init(suiteName: String?, memoryOnly: Bool = false) {
        if memoryOnly {
            self.defaults = nil
            return
        }
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
    }

    func load() throws -> MarketPreferencesSnapshot {
        guard let defaults else { return memorySnapshot ?? .empty }
        guard let data = defaults.data(forKey: Self.storageKey) else { return .empty }
        do {
            let decoded = try JSONDecoder().decode(MarketPreferencesSnapshot.self, from: data)
            guard decoded.version == MarketPreferencesSnapshot.currentVersion,
                  decoded.watchlist.count <= Self.maximumWatchlistCount else {
                throw MarketPreferenceError.persistenceFailure
            }
            for identity in decoded.watchlist {
                _ = try MarketWatchlistIdentity(symbol: identity.symbol, mic: identity.mic)
            }
            guard Set(decoded.watchlist).count == decoded.watchlist.count else {
                throw MarketPreferenceError.persistenceFailure
            }
            return decoded
        } catch let error as MarketPreferenceError {
            throw error
        } catch {
            throw MarketPreferenceError.persistenceFailure
        }
    }

    func save(_ snapshot: MarketPreferencesSnapshot) throws {
        guard snapshot.version == MarketPreferencesSnapshot.currentVersion,
              snapshot.watchlist.count <= Self.maximumWatchlistCount,
              Set(snapshot.watchlist).count == snapshot.watchlist.count else {
            throw MarketPreferenceError.persistenceFailure
        }
        if defaults == nil {
            memorySnapshot = snapshot
            return
        }
        do {
            defaults?.set(try JSONEncoder().encode(snapshot), forKey: Self.storageKey)
        } catch {
            throw MarketPreferenceError.persistenceFailure
        }
    }

    func clearForTesting() {
        defaults?.removeObject(forKey: Self.storageKey)
        memorySnapshot = nil
    }
}
