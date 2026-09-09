import Foundation
import Observation

struct GeneralPreferencesSnapshot: Codable, Equatable, Sendable {
    let version: Int
    var newWealthCurrency: CurrencyCode
    var groupWealthAmounts: Bool

    static let defaults = Self(version: 1, newWealthCurrency: .cny, groupWealthAmounts: true)
}

enum GeneralPreferencesError: Error, Equatable { case invalidSuite }

/// Non-sensitive, graph-owned preferences. The default initializer never opens a domain.
@MainActor
@Observable
final class GeneralPreferencesStore {
    static let storageKey = "settings.general.preferences.v1"
    private(set) var snapshot: GeneralPreferencesSnapshot
    @ObservationIgnored private let defaults: UserDefaults?

    init() {
        defaults = nil
        snapshot = .defaults
    }

    private init(defaults: UserDefaults) {
        self.defaults = defaults
        snapshot = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    static func production() -> GeneralPreferencesStore {
        GeneralPreferencesStore(defaults: .standard)
    }

    convenience init(suiteName: String) throws {
        guard !suiteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let defaults = UserDefaults(suiteName: suiteName) else {
            throw GeneralPreferencesError.invalidSuite
        }
        self.init(defaults: defaults)
    }

    func load() -> GeneralPreferencesSnapshot { snapshot }

    func setNewWealthCurrency(_ currency: CurrencyCode) {
        snapshot.newWealthCurrency = currency
        save()
    }

    func setGroupWealthAmounts(_ enabled: Bool) {
        snapshot.groupWealthAmounts = enabled
        save()
    }

    private func save() {
        // All fields are finite primitives; no Provider or financial payload is accepted.
        if let defaults, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func decode(_ data: Data?) -> GeneralPreferencesSnapshot {
        struct Stored: Decodable {
            let version: Int
            let newWealthCurrency: String?
            let groupWealthAmounts: Bool?
        }
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == 1 else { return .defaults }
        return GeneralPreferencesSnapshot(
            version: 1,
            newWealthCurrency: stored.newWealthCurrency.flatMap(CurrencyCode.init(rawValue:)) ?? .cny,
            groupWealthAmounts: stored.groupWealthAmounts ?? true
        )
    }
}
