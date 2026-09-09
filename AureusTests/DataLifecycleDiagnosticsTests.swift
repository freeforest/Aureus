import Foundation
import Testing
@testable import Aureus

final class RecordingDataLifecycleSink: DataLifecycleDiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DataLifecycleEvent] = []

    var events: [DataLifecycleEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var diagnostics: DataLifecycleDiagnostics { DataLifecycleDiagnostics(sink: self) }

    func record(_ event: DataLifecycleEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }
}

@Suite("Finite privacy-safe lifecycle diagnostics")
struct DataLifecycleDiagnosticsTests {
    @Test("Disabled backend has no sink; recording preserves only finite fields")
    func disabledAndRecording() {
        let sink = RecordingDataLifecycleSink()
        let event = DataLifecycleEvent(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none)
        #expect(!DataLifecycleDiagnostics.disabled.isEnabled)
        DataLifecycleDiagnostics.disabled.record(event)
        #expect(sink.events.isEmpty)
        sink.diagnostics.record(event)
        #expect(sink.events == [event])
    }

    @Test("Every terminal outcome has the required severity", arguments: DataLifecycleOutcome.allCases)
    func severity(outcome: DataLifecycleOutcome) {
        #expect(outcome.isError == (outcome != .succeeded))
        let sink = RecordingDataLifecycleSink()
        let event = DataLifecycleEvent(operation: .settingsInternalRestoreWorkflow, outcome: outcome, errorCategory: .restore)
        sink.diagnostics.record(event)
        #expect(sink.events == [event])
    }

    @Test("Adapter source has literal templates and private interpolation only")
    func privateTemplates() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Aureus/Diagnostics/DataLifecycleDiagnostics.swift"), encoding: .utf8)
        let calls = source.components(separatedBy: "\n").filter { $0.contains("logger.info(") || $0.contains("logger.error(") }
        #expect(calls.count == 2)
        for call in calls {
            #expect(call.components(separatedBy: "privacy: .private").count - 1 == 3)
            #expect(call.components(separatedBy: "\\(").count - 1 == 3)
        }
        #expect(!source.contains(".public"))
        #expect(!source.contains("String(describing:"))
        #expect(!source.contains("localizedDescription"))
        #expect(DataLifecycleOperation.allCases.count == 9)
    }

    @Test("OSLog smoke only exercises the finite call path, not delivery or retention")
    func osLogSmoke() {
        DataLifecycleDiagnostics.osLog.record(.init(operation: .settingsBackupWorkflow, outcome: .succeeded, errorCategory: .none))
    }
}
