import Foundation
import GRDB

enum DatabaseQueueFactory {
    static func open(at url: URL) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }
}
