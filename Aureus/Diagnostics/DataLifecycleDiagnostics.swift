import OSLog

enum DataLifecycleOperation: String, CaseIterable, Sendable {
    case settingsBackupWorkflow
    case settingsInternalRestoreWorkflow
    case settingsExportWorkflow
    case settingsExternalRestoreWorkflow
    case settingsRemoveExpiredWorkflow
    case settingsClearSessionWorkflow
    case settingsResetCacheWorkflow
    case settingsApplyMaximumWorkflow
    case permanentMigration
}

enum DataLifecycleOutcome: String, CaseIterable, Sendable {
    case succeeded
    case failed
    case rolledBack
    case recoveryRequired

    var isError: Bool { self != .succeeded }
}

enum DataLifecycleErrorCategory: String, CaseIterable, Sendable {
    case none
    case backup
    case restore
    case export
    case externalRestore
    case inventoryRefreshAfterCommit
    case cachePolicy
    case migrationPreflight
    case migrationBackup
    case migrationExecution
    case migrationPostValidation
    case unknown
}

/// Only finite classifications cross the diagnostics boundary; never business payloads.
struct DataLifecycleEvent: Equatable, Sendable {
    let operation: DataLifecycleOperation
    let outcome: DataLifecycleOutcome
    let errorCategory: DataLifecycleErrorCategory
}

protocol DataLifecycleDiagnosticSink: Sendable {
    func record(_ event: DataLifecycleEvent)
}

struct DataLifecycleDiagnostics: Sendable {
    private let sink: (any DataLifecycleDiagnosticSink)?

    static let disabled = DataLifecycleDiagnostics()
    static let osLog = DataLifecycleDiagnostics(sink: OSLogDataLifecycleSink())

    init(sink: (any DataLifecycleDiagnosticSink)? = nil) {
        self.sink = sink
    }

    var isEnabled: Bool { sink != nil }

    func record(_ event: DataLifecycleEvent) {
        sink?.record(event)
    }
}

private struct OSLogDataLifecycleSink: DataLifecycleDiagnosticSink {
    private let logger = Logger(subsystem: "com.aureus.wealthterminal", category: "data-lifecycle")

    func record(_ event: DataLifecycleEvent) {
        if event.outcome.isError {
            logger.error("operation=\(event.operation.rawValue, privacy: .private) outcome=\(event.outcome.rawValue, privacy: .private) errorCategory=\(event.errorCategory.rawValue, privacy: .private)")
        } else {
            logger.info("operation=\(event.operation.rawValue, privacy: .private) outcome=\(event.outcome.rawValue, privacy: .private) errorCategory=\(event.errorCategory.rawValue, privacy: .private)")
        }
    }
}
