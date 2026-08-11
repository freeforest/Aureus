import Foundation
import Observation

enum AppDestination: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case wealth
    case markets
    case portfolio
    case analytics
    case ledger
    case goals
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .wealth: "Wealth"
        case .markets: "Markets"
        case .portfolio: "Portfolio"
        case .analytics: "Analytics"
        case .ledger: "Ledger"
        case .goals: "Goals"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.3.group"
        case .wealth: "building.columns"
        case .markets: "chart.line.uptrend.xyaxis"
        case .portfolio: "briefcase"
        case .analytics: "waveform.path.ecg"
        case .ledger: "list.bullet.rectangle"
        case .goals: "target"
        case .settings: "gearshape"
        }
    }

    var implementationStage: String {
        switch self {
        case .dashboard: "Stage 5"
        case .wealth: "Stage 3"
        case .markets: "Stage 7"
        case .portfolio: "Stage 8"
        case .analytics: "Stage 9"
        case .ledger: "Stage 4"
        case .goals: "Stage 10"
        case .settings: "Stage 11"
        }
    }
}

enum AppStartupState: Equatable, Sendable {
    case starting
    case ready(AppDataMode)
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    var selection: AppDestination = .dashboard
    private(set) var startupState: AppStartupState = .starting

    @ObservationIgnored
    private(set) var dependencies: AppDependencies?

    @ObservationIgnored
    private let launchConfiguration: LaunchConfiguration

    init(launchConfiguration: LaunchConfiguration) {
        self.launchConfiguration = launchConfiguration
    }

    func start() async {
        guard case .starting = startupState, dependencies == nil else { return }
        do {
            let dependencies = try await AppDependencies.make(configuration: launchConfiguration)
            self.dependencies = dependencies
            startupState = .ready(launchConfiguration.dataMode)
        } catch {
            startupState = .failed(
                "Persistence initialization failed. No success state is available; existing data was not intentionally changed."
            )
        }
    }
}
