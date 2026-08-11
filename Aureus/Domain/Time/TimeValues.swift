import Foundation

enum TimeValueError: Error, Equatable, Sendable {
    case invalidCivilDate
    case invalidCanonicalDate
    case invalidTimeZone(String)
    case invalidMIC(String)
}

struct UTCInstant: Codable, Equatable, Comparable, Sendable {
    let millisecondsSince1970: Int64

    init(millisecondsSince1970: Int64) {
        self.millisecondsSince1970 = millisecondsSince1970
    }

    init(date: Date) {
        self.millisecondsSince1970 = Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1_000)
    }

    static func < (lhs: UTCInstant, rhs: UTCInstant) -> Bool {
        lhs.millisecondsSince1970 < rhs.millisecondsSince1970
    }
}

struct CivilDate: Codable, Equatable, Hashable, Comparable, CustomStringConvertible, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else {
            throw TimeValueError.invalidCivilDate
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw TimeValueError.invalidCivilDate
        }
        self.year = year
        self.month = month
        self.day = day
    }

    init(canonical: String) throws {
        let pieces = canonical.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0].count == 4,
              pieces[1].count == 2,
              pieces[2].count == 2,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            throw TimeValueError.invalidCanonicalDate
        }
        try self.init(year: year, month: month, day: day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func localDate(
        hour: Int,
        minute: Int,
        in timeZone: TimeZone,
        repeatedTimePolicy: Calendar.RepeatedTimePolicy = .first
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let startOfDay = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            return nil
        }
        let desired = DateComponents(hour: hour, minute: minute, second: 0)
        guard let match = calendar.nextDate(
            after: startOfDay.addingTimeInterval(-1),
            matching: desired,
            matchingPolicy: .strict,
            repeatedTimePolicy: repeatedTimePolicy,
            direction: .forward
        ) else {
            return nil
        }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: match)
        guard actual.year == year,
              actual.month == month,
              actual.day == day,
              actual.hour == hour,
              actual.minute == minute else {
            return nil
        }
        return match
    }

    static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

struct ExchangeSessionDate: Codable, Equatable, Sendable {
    let civilDate: CivilDate
    let mic: String
    let timeZoneIdentifier: String

    init(civilDate: CivilDate, mic: String, timeZoneIdentifier: String) throws {
        let normalizedMIC = mic.uppercased()
        guard normalizedMIC.count == 4,
              normalizedMIC.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw TimeValueError.invalidMIC(mic)
        }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw TimeValueError.invalidTimeZone(timeZoneIdentifier)
        }
        self.civilDate = civilDate
        self.mic = normalizedMIC
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

protocol Clock: Sendable {
    func now() -> UTCInstant
}

struct SystemClock: Clock {
    func now() -> UTCInstant {
        UTCInstant(date: Date())
    }
}

struct FixedClock: Clock {
    let instant: UTCInstant

    func now() -> UTCInstant {
        instant
    }
}
