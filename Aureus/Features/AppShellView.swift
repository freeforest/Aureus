import SwiftUI

struct AppRootView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.startupState {
            case .starting:
                ProgressView("Preparing local stores…")
                    .accessibilityIdentifier("startup.progress")
            case let .failed(message):
                ContentUnavailableView(
                    "Aureus could not start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .accessibilityIdentifier("startup.error")
            case let .ready(mode):
                AppShellView(model: model, mode: mode)
            }
        }
        .task {
            await model.start()
        }
    }
}

struct AppShellView: View {
    @Bindable var model: AppModel
    let mode: AppDataMode

    var body: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: $model.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
                    .accessibilityLabel(destination.title)
                    .accessibilityIdentifier("sidebar.\(destination.rawValue)")
            }
            .navigationTitle("Aureus")
            .accessibilityLabel("Aureus primary navigation")
        } detail: {
            if model.selection == .wealth, let dependencies = model.dependencies {
                WealthView(
                    store: dependencies.wealthStore,
                    clock: dependencies.clock,
                    mode: mode
                )
            } else {
                VStack(spacing: 0) {
                    ModeBanner(mode: mode)
                    PlaceholderView(destination: model.selection)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ModeBanner: View {
    let mode: AppDataMode

    var body: some View {
        HStack {
            Image(systemName: mode == .syntheticDemo ? "testtube.2" : "tray")
            Text(mode == .syntheticDemo ? "Synthetic Demo Mode" : "Empty Local Store")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("Stage 3 Wealth Candidate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(mode == .syntheticDemo ? "mode.demo" : "mode.empty")
    }
}

private struct PlaceholderView: View {
    let destination: AppDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.systemImage)
        } description: {
            Text("\(destination.implementationStage) has not been implemented. This screen remains an honest placeholder with no financial data or completed business behavior.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("destination.\(destination.rawValue)")
    }
}
