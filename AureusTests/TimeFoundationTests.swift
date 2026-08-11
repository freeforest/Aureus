import Foundation
import Testing
@testable import Aureus

@Suite("Time foundations")
struct TimeFoundationTests {
    @Test("UTC epoch milliseconds round-trip")
    func utcRoundTrip() {
        let original = UTCInstant(millisecondsSince1970: 1_768_435_200_123)
        #expect(UTCInstant(date: original.date) == original)
    }

    @Test("Civil dates validate leap day and reject invalid dates")
    func civilDateValidation() throws {
        #expect(try CivilDate(canonical: "2024-02-29").description == "2024-02-29")
        var invalidRejected = false
        do {
            _ = try CivilDate(canonical: "2023-02-29")
        } catch {
            invalidRejected = true
        }
        #expect(invalidRejected)
    }

    @Test("Civil dates preserve year boundaries")
    func yearBoundary() throws {
        let end = try CivilDate(canonical: "2025-12-31")
        let start = try CivilDate(canonical: "2026-01-01")
        #expect(end < start)
    }

    @Test("Shanghai and Tokyo session zones are explicit")
    func asianZones() throws {
        let date = try CivilDate(canonical: "2026-08-11")
        let shanghai = try ExchangeSessionDate(
            civilDate: date,
            mic: "XSHG",
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let tokyo = try ExchangeSessionDate(
            civilDate: date,
            mic: "XJPX",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        #expect(shanghai.timeZoneIdentifier == "Asia/Shanghai")
        #expect(tokyo.timeZoneIdentifier == "Asia/Tokyo")
    }

    @Test("New York DST gap is invalid and fold is distinguishable")
    func newYorkDSTGapAndFold() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let gap = try CivilDate(canonical: "2024-03-10")
        #expect(gap.localDate(hour: 2, minute: 30, in: zone) == nil)

        let fold = try CivilDate(canonical: "2024-11-03")
        let first = fold.localDate(
            hour: 1,
            minute: 30,
            in: zone,
            repeatedTimePolicy: .first
        )
        let last = fold.localDate(
            hour: 1,
            minute: 30,
            in: zone,
            repeatedTimePolicy: .last
        )
        #expect(first != nil)
        #expect(last != nil)
        #expect(last!.timeIntervalSince(first!) == 3_600)
    }

    @Test("Weekend session date remains a date, not a fabricated trading calendar")
    func weekendSessionDistinction() throws {
        let saturday = try CivilDate(canonical: "2026-08-15")
        let session = try ExchangeSessionDate(
            civilDate: saturday,
            mic: "XSYN",
            timeZoneIdentifier: "Asia/Shanghai"
        )
        #expect(session.civilDate == saturday)
        #expect(session.mic == "XSYN")
    }

    @Test("Injected clock is deterministic")
    func injectedClock() {
        let instant = UTCInstant(millisecondsSince1970: 42)
        let clock: any Clock = FixedClock(instant: instant)
        #expect(clock.now() == instant)
    }
}
