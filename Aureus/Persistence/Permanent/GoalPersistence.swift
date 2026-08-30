import Foundation
import GRDB

enum GoalPersistenceError: Error, Equatable, Sendable {
    case goalNotFound
    case corruptRecord
}

private struct GoalPersistenceRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "goals"

    let id: String
    let name: String
    let targetMinor: Int64
    let currencyCode: String
    let targetDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case targetMinor = "target_minor"
        case currencyCode = "currency_code"
        case targetDate = "target_date"
    }

    init(goal: Goal) {
        id = goal.id.uuidString
        name = goal.name
        targetMinor = goal.target.minorUnits
        currencyCode = goal.target.currency.rawValue
        targetDate = goal.targetDate?.description
    }

    func domain() throws -> Goal {
        guard let id = UUID(uuidString: id),
              let currency = CurrencyCode(rawValue: currencyCode) else {
            throw GoalPersistenceError.corruptRecord
        }
        let date: CivilDate?
        if let targetDate {
            guard let decoded = try? CivilDate(canonical: targetDate) else {
                throw GoalPersistenceError.corruptRecord
            }
            date = decoded
        } else {
            date = nil
        }
        do {
            return try Goal(
                id: id,
                name: name,
                target: Money(minorUnits: targetMinor, currency: currency),
                targetDate: date
            )
        } catch {
            throw GoalPersistenceError.corruptRecord
        }
    }
}

extension WealthStore {
    func createGoal(_ goal: Goal) throws {
        let validated = try goal.validated()
        try queue.write { db in
            try GoalPersistenceRow(goal: validated).insert(db)
        }
    }

    func fetchGoals() throws -> [Goal] {
        try queue.read { db in
            try GoalPersistenceRow.fetchAll(
                db,
                sql: """
                    SELECT id, name, target_minor, currency_code, target_date
                    FROM goals
                    ORDER BY
                        CASE WHEN target_date IS NULL THEN 1 ELSE 0 END,
                        target_date,
                        name COLLATE NOCASE,
                        id
                    """
            ).map { try $0.domain() }
        }
    }

    func fetchGoal(id: UUID) throws -> Goal? {
        try queue.read { db in
            try GoalPersistenceRow.fetchOne(
                db,
                sql: """
                    SELECT id, name, target_minor, currency_code, target_date
                    FROM goals
                    WHERE id = ?
                    """,
                arguments: [id.uuidString]
            ).map { try $0.domain() }
        }
    }

    func updateGoal(_ goal: Goal) throws {
        let validated = try goal.validated()
        try queue.write { db in
            guard try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM goals WHERE id = ?",
                arguments: [validated.id.uuidString]
            ) == 1 else {
                throw GoalPersistenceError.goalNotFound
            }
            try db.execute(
                sql: """
                    UPDATE goals
                    SET name = ?, target_minor = ?, currency_code = ?, target_date = ?
                    WHERE id = ?
                    """,
                arguments: [
                    validated.name,
                    validated.target.minorUnits,
                    validated.target.currency.rawValue,
                    validated.targetDate?.description,
                    validated.id.uuidString
                ]
            )
            guard db.changesCount == 1 else { throw GoalPersistenceError.goalNotFound }
        }
    }

    func deleteGoal(id: UUID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM goals WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount == 1 else { throw GoalPersistenceError.goalNotFound }
        }
    }
}
