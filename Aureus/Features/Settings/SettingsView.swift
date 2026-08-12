import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsFeatureModel
    @State private var showDisconnectConfirmation = false
    @State private var showDeleteCredentialConfirmation = false
    @State private var showResetConfirmation = false
    let mode: AppDataMode

    init(
        provider: any MarketDataProvider,
        credentialCoordinator: ProviderCredentialCoordinator,
        cache: MarketCacheStore,
        clock: any Clock,
        mode: AppDataMode
    ) {
        _model = State(initialValue: SettingsFeatureModel(
            provider: provider,
            credentialCoordinator: credentialCoordinator,
            cache: cache,
            clock: clock
        ))
        self.mode = mode
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsBanner
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providerSection
                    cacheSection
                    operationMessages
                    laterStageSection
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .task { await model.load() }
        .confirmationDialog(
            "Delete Twelve Data Key?",
            isPresented: $showDeleteCredentialConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Key and Provider Cache", role: .destructive) {
                Task { await model.deleteCredential() }
            }
            .accessibilityIdentifier("settings.provider.delete.confirm")
        } message: {
            Text("This deletes the Keychain credential, stops new requests, and removes only Twelve Data recoverable Market Cache entries.")
        }
        .confirmationDialog(
            "Disconnect Twelve Data?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect and Delete Provider Cache", role: .destructive) {
                Task { await model.disconnect() }
            }
            .accessibilityIdentifier("settings.provider.disconnect.confirm")
        } message: {
            Text("This stops new Twelve Data requests, removes the Keychain credential, and deletes only Twelve Data recoverable Market Cache entries. Permanent wealth data is not a deletion target.")
        }
        .confirmationDialog(
            "Reset Market Cache?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Market Cache", role: .destructive) {
                Task { await model.resetCache() }
            }
            .accessibilityIdentifier("settings.cache.reset.confirm")
        } message: {
            Text("This closes, deletes, recreates, and migrates only the Market Cache database and sidecars. It cannot access the Permanent Wealth Store.")
        }
        .accessibilityIdentifier("settings.content")
    }

    private var settingsBanner: some View {
        HStack {
            Image(systemName: mode == .syntheticDemo ? "testtube.2" : "gearshape.2")
            Text(mode == .syntheticDemo ? "Synthetic Demo Settings" : "Local Provider Settings")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("Stage 6 Infrastructure Candidate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityIdentifier("settings.mode")
    }

    private var providerSection: some View {
        GroupBox("Twelve Data — user-owned Key") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Aureus never bundles or shares a key. Production credentials are stored only in macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                SecureField("Twelve Data API Key", text: $model.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.provider.key")
                    .accessibilityLabel("Twelve Data API key secure entry")

                HStack {
                    Button(model.isConfigured ? "Update Key" : "Save Key") {
                        Task { await model.saveCredential() }
                    }
                    .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 || model.isWorking)
                    .accessibilityIdentifier("settings.provider.save")

                    Button("Validate") {
                        Task { await model.validateCredential() }
                    }
                    .disabled(!model.isConfigured || model.isWorking)
                    .accessibilityIdentifier("settings.provider.validate")

                    Button("Delete Key", role: .destructive) {
                        showDeleteCredentialConfirmation = true
                    }
                    .disabled(!model.isConfigured || model.isWorking)
                    .accessibilityIdentifier("settings.provider.delete")

                    Button("Disconnect", role: .destructive) {
                        showDisconnectConfirmation = true
                    }
                    .disabled(!model.isConfigured || model.isWorking)
                    .accessibilityIdentifier("settings.provider.disconnect")

                    if model.isWorking { ProgressView().controlSize(.small) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    providerStatusRow(
                        label: "Credential",
                        value: model.isConfigured ? "Configured in Keychain" : "Missing",
                        identifier: "settings.provider.credentialState"
                    )
                    providerStatusRow(
                        label: "Observed plan",
                        value: model.observedPlan,
                        identifier: "settings.provider.observedPlan"
                    )
                    providerStatusRow(
                        label: "Entitlement",
                        value: model.entitlement.rawValue,
                        identifier: "settings.provider.entitlement"
                    )
                    providerStatusRow(
                        label: "Last validation",
                        value: model.lastSuccessfulValidation.map { String($0.millisecondsSince1970) } ?? "Not verified",
                        identifier: "settings.provider.lastValidation"
                    )
                }

                Picker("Configured plan (display only)", selection: $model.declaredPlan) {
                    Text("Unknown").tag("Unknown")
                    Text("Basic").tag("Basic")
                    Text("Pro or higher").tag("Pro or higher")
                }
                .frame(width: 320)
                .accessibilityIdentifier("settings.provider.declaredPlan")
                Text("This label never grants entitlement. Only provider responses and successful endpoint access establish capabilities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                Text("Market entitlements")
                    .font(.headline)
                ForEach(["US", "XHKG", "XSHG", "XSHE", "XJPX"], id: \.self) { mic in
                    let capability = model.capability(for: mic)
                    HStack {
                        Text(mic).monospaced().frame(width: 70, alignment: .leading)
                        Text(capability?.observedEntitlement.rawValue ?? "unknown")
                        Text(capability?.freshness.rawValue ?? "unknown")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(capability?.evidenceStatus ?? "NOT VERIFIED")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("settings.provider.market.\(mic.lowercased())")
                }

                Text("Exchange catalog visibility is not entitlement proof. XHKG and XJPX EOD availability has conflicting official evidence and remains not verified until an entitled endpoint succeeds.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                ForEach(model.endpointCapabilities) { endpoint in
                    HStack {
                        Text(endpoint.endpoint.rawValue)
                            .frame(width: 150, alignment: .leading)
                        Text("\(endpoint.creditWeight) credits")
                        Text(endpoint.minimumPlanName)
                        Spacer()
                        Text(endpoint.catalogEvidence.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityIdentifier(
                        "settings.provider.endpoint.\(endpoint.endpoint.rawValue)"
                    )
                }
                Text("Persistent Twelve Data cache is disabled while public retention duration remains unverified. Frankfurter/ECB reference-rate cache uses a 24-hour TTL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("Source: Twelve Data", destination: URL(string: "https://twelvedata.com")!)
                    .accessibilityIdentifier("settings.provider.attribution")
            }
            .padding(10)
        }
        .accessibilityIdentifier("settings.provider")
    }

    private var cacheSection: some View {
        GroupBox("Bounded Market Cache") {
            VStack(alignment: .leading, spacing: 14) {
                if let statistics = model.cacheStatistics {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow { Text("Current usage"); Text(byteString(statistics.currentBytes)) }
                        GridRow { Text("Capacity"); Text(byteString(statistics.maximumBytes)) }
                        GridRow { Text("Usage"); Text("\(statistics.percentageBasisPoints / 100)%") }
                        GridRow { Text("Entries"); Text("\(statistics.entryCount)") }
                        GridRow { Text("Oldest entry"); Text(statistics.oldestEntry.map { String($0.millisecondsSince1970) } ?? "None") }
                        GridRow { Text("Last cleanup"); Text(statistics.lastCleanupResult ?? "Not run") }
                    }
                    .accessibilityIdentifier("settings.cache.summary")

                    ForEach(statistics.providerBreakdown) { provider in
                        Text("\(provider.providerIdentifier): \(provider.entryCount) entries, \(byteString(provider.bytes))")
                            .font(.caption)
                    }
                } else {
                    ContentUnavailableView("Cache status unavailable", systemImage: "externaldrive.badge.questionmark")
                }

                HStack {
                    Picker("Maximum", selection: $model.selectedMaximumMiB) {
                        ForEach([128, 256, 512, 1_024, 2_048, 4_096], id: \.self) { value in
                            Text(value >= 1_024 ? "\(value / 1_024) GiB" : "\(value) MiB").tag(value)
                        }
                    }
                    .frame(width: 210)
                    .accessibilityIdentifier("settings.cache.maximum")
                    Button("Apply Capacity") { Task { await model.applyMaximum() } }
                        .accessibilityIdentifier("settings.cache.apply")
                    Button("Remove Expired") { Task { await model.removeExpired() } }
                        .accessibilityIdentifier("settings.cache.removeExpired")
                    Button("Reset Market Cache", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .accessibilityIdentifier("settings.cache.reset")
                }

                Text("Defaults: 512 MiB, 90% high-water trigger, cleanup to 80%. Cleanup is restricted to recoverable Market Cache data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .accessibilityIdentifier("settings.cache")
    }

    private func providerStatusRow(label: String, value: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
                .frame(width: 96, alignment: .leading)
            Text(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private var laterStageSection: some View {
        GroupBox("Data lifecycle") {
            Text("Backup, Restore, export lifecycle, and broader privacy settings remain Stage 11 work. No capability is implied here.")
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }

    @ViewBuilder
    private var operationMessages: some View {
        if let status = model.statusMessage {
            Text(status)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.status")
        }
        if let error = model.errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.error")
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
