import Foundation

enum SyntheticGoalsSeeder {
    static let freedomGoalID = UUID(
        uuidString: "00000000-0000-4000-8000-000000010001"
    )!
    static let educationGoalID = UUID(
        uuidString: "00000000-0000-4000-8000-000000010002"
    )!

    static func seed(in store: WealthStore) async throws {
        let goals = [
            try Goal(
                id: freedomGoalID,
                name: "Synthetic Freedom Goal",
                target: Money(minorUnits: 50_000_000, currency: .cny),
                targetDate: CivilDate(year: 2035, month: 12, day: 31)
            ),
            try Goal(
                id: educationGoalID,
                name: "Synthetic USD Education Goal",
                target: Money(minorUnits: 10_000_000, currency: .usd),
                targetDate: CivilDate(year: 2040, month: 6, day: 30)
            )
        ]

        for goal in goals {
            if try await store.fetchGoal(id: goal.id) == nil {
                try await store.createGoal(goal)
            }
        }
    }
}
