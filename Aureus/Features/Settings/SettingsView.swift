import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsFeatureModel
    @State private var dataLifecycleModel: SettingsDataLifecycleModel
    @State private var showDisconnectConfirmation = false
    @State private var showDeleteCredentialConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showRestoreConfirmation = false
    let mode: AppDataMode

    init(
        provider: any MarketDataProvider,
        marketDataService: MarketDataService,
        credentialCoordinator: ProviderCredentialCoordinator,
        cache: MarketCacheStore,
        sessionStore: TransientMarketSessionStore,
        wealthStore: WealthStore,
        internalBackupDirectoryURL: URL,
        appVersion: String,
        dataLifecycleGenerationID: @escaping @Sendable () -> UUID,
        clock: any Clock,
        mode: AppDataMode
    ) {
        _model = State(initialValue: SettingsFeatureModel(
            provider: provider,
            marketDataService: marketDataService,
            credentialCoordinator: credentialCoordinator,
            cache: cache,
            sessionStore: sessionStore,
            clock: clock
        ))
        _dataLifecycleModel = State(initialValue: SettingsDataLifecycleModel(
            store: wealthStore,
            backupRoot: internalBackupDirectoryURL,
            appVersion: appVersion,
            clock: clock,
            generationID: dataLifecycleGenerationID
        ))
        self.mode = mode
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsBanner
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dataLifecycleSection
                    providerSection
                    sessionSection
                    cacheSection
                    operationMessages
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .accessibilityIdentifier("settings.content")
        }
        .task {
            await model.load()
            await dataLifecycleModel.load()
        }
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
        .confirmationDialog(
            "Restore Selected Internal Backup?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Permanent Store", role: .destructive) {
                Task { await dataLifecycleModel.restoreSelected(confirmed: true) }
            }
            .accessibilityIdentifier("settings.dataLifecycle.restore.confirm")
        } message: {
            Text("Current Permanent records will be replaced. Aureus will create and validate a safety Backup before Restore. Backups contain private permanent financial records.")
        }
    }

    private var settingsBanner: some View {
        HStack {
            Image(systemName: mode == .syntheticDemo ? "testtube.2" : "gearshape.2")
            Text(mode == .syntheticDemo ? "Synthetic Demo Settings" : "Local Provider Settings")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("Stage 6MA Session Lifecycle Repair Candidate")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.mode")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
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
                    let minimum = capability?.minimumEntitlement.rawValue ?? "unknown"
                    let catalog = capability?.catalogEvidence.rawValue ?? "notVerified"
                    let live = capability?.liveObservation.rawValue ?? "notVerified"
                    let freshness = capability?.freshness.rawValue ?? "unknown"
                    let observedMICs = capability?.liveObservedMICs ?? []
                    HStack {
                        Text(mic).monospaced().frame(width: 70, alignment: .leading)
                        Text("Plan minimum: \(minimum)")
                        Text("Catalog: \(catalog)")
                        Text("Live: \(live)")
                        if !observedMICs.isEmpty {
                            Text(observedMICs.joined(separator: ", "))
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Freshness: \(freshness)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(mic). Plan minimum: \(minimum). Catalog: \(catalog). Live: \(live). "
                            + (observedMICs.isEmpty ? "" : "Observed MICs: \(observedMICs.joined(separator: ", ")). ")
                            + "Freshness: \(freshness)."
                    )
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
                        Text("Catalog: \(endpoint.catalogEvidence.rawValue)")
                        Text("Live: \(endpoint.liveObservation.rawValue)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(endpoint.endpoint.rawValue). \(endpoint.creditWeight) credits. "
                            + "Minimum plan: \(endpoint.minimumPlanName). "
                            + "Catalog: \(endpoint.catalogEvidence.rawValue). "
                            + "Live: \(endpoint.liveObservation.rawValue)."
                    )
                    .accessibilityIdentifier(
                        "settings.provider.endpoint.\(endpoint.endpoint.rawValue)"
                    )
                }
                Text("Twelve Data V1 persistent writes are disabled. Validated market responses use only the current App session. Frankfurter/ECB reference-rate cache remains independent with a 24-hour TTL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("Source: Twelve Data", destination: URL(string: "https://twelvedata.com")!)
                    .accessibilityIdentifier("settings.provider.attribution")
            }
            .padding(10)
        }
        .accessibilityIdentifier("settings.provider")
    }

    private var sessionSection: some View {
        GroupBox("Session Market Data") {
            VStack(alignment: .leading, spacing: 14) {
                if let statistics = model.sessionStatistics {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow { Text("Entries"); Text("\(statistics.entryCount)") }
                        GridRow { Text("Logical usage"); Text(byteString(statistics.accountedBytes)) }
                        GridRow { Text("Maximum"); Text("64 MiB") }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Session Market Data. \(statistics.entryCount) entries. "
                            + "Logical usage \(statistics.accountedBytes) bytes. Maximum 64 MiB."
                    )
                    .accessibilityIdentifier("settings.session.summary")
                }

                Text("Twelve Data values exist only in memory for this App session. They disappear on App exit, Disconnect, credential rotation, or Clear. Nothing in this section is written to SQLite, files, UserDefaults, Backup, or Export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.session.disclosure")

                Button("Clear Session Market Data", role: .destructive) {
                    Task { await model.clearSessionMarketData() }
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("settings.session.clear")
            }
            .padding(10)
        }
        .accessibilityIdentifier("settings.session")
    }

    private var cacheSection: some View {
        GroupBox("Authorized Persistent Market Cache") {
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Authorized Persistent Market Cache. Current usage \(byteString(statistics.currentBytes)). "
                            + "Capacity \(byteString(statistics.maximumBytes)). "
                            + "Usage \(statistics.percentageBasisPoints / 100) percent. "
                            + "Entries \(statistics.entryCount). "
                            + "Last cleanup \(statistics.lastCleanupResult ?? "Not run")."
                    )
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

                Text("Twelve Data V1 persistent writes are disabled. This isolated disk cache is only for data sources with separately confirmed storage rights, including the independent Frankfurter/ECB policy. Defaults: 512 MiB, 90% high-water trigger, cleanup to 80%.")
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

    private var dataLifecycleSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Data Lifecycle")
                    .font(.title3.weight(.semibold))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Settings data lifecycle")
                    .accessibilityIdentifier("settings.dataLifecycle.heading")

                Text(
                    "Data lifecycle: \(dataLifecycleModel.validGenerationCount) valid backups, "
                        + "\(dataLifecycleModel.ignoredEntryCount) ignored entries"
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Data lifecycle: \(dataLifecycleModel.validGenerationCount) valid backups, "
                        + "\(dataLifecycleModel.ignoredEntryCount) ignored entries"
                )
                .accessibilityIdentifier("settings.dataLifecycle.summary")

                if dataLifecycleModel.generations.isEmpty {
                    Text("No valid internal backups")
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("No valid internal backups")
                        .accessibilityIdentifier("settings.dataLifecycle.empty")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(dataLifecycleModel.generations) { generation in
                            Button {
                                dataLifecycleModel.selectGeneration(generation.id)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: dataLifecycleModel.selectedGenerationID == generation.id
                                          ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(generation.createdAt)
                                            .font(.body.monospacedDigit())
                                        Text(
                                            "App \(generation.appVersion) · Schema \(generation.schemaVersion) · "
                                                + byteString(generation.databaseByteCount)
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(dataLifecycleModel.isWorking || dataLifecycleModel.isRecoveryRequired)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "Internal Backup: \(generation.id), created \(generation.createdAt), "
                                    + "app \(generation.appVersion), schema \(generation.schemaVersion), "
                                    + "\(generation.databaseByteCount) bytes, "
                                    + (dataLifecycleModel.selectedGenerationID == generation.id
                                       ? "selected" : "not selected")
                            )
                            .accessibilityIdentifier(
                                "settings.dataLifecycle.generation.\(generation.id)"
                            )
                        }
                    }
                }

                HStack {
                    Button("Create Backup") {
                        Task { await dataLifecycleModel.createBackup() }
                    }
                    .disabled(!dataLifecycleModel.canCreateBackup)
                    .accessibilityIdentifier("settings.dataLifecycle.create")

                    Button("Restore Selected Backup", role: .destructive) {
                        showRestoreConfirmation = true
                    }
                    .disabled(!dataLifecycleModel.canRestore)
                    .accessibilityIdentifier("settings.dataLifecycle.restore")

                    if dataLifecycleModel.isWorking {
                        ProgressView().controlSize(.small)
                    }
                }

                Text(dataLifecycleModel.statusLabel)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dataLifecycleModel.statusLabel)
                    .accessibilityIdentifier("settings.dataLifecycle.status")

                if let error = dataLifecycleModel.errorLabel {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(error)
                        .accessibilityIdentifier("settings.dataLifecycle.error")
                }

                if let recovery = dataLifecycleModel.recoveryRequiredLabel {
                    Text(recovery)
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(recovery)
                        .accessibilityIdentifier("settings.dataLifecycle.recovery-required")
                }

                let disclosure = "Backup and Restore use Aureus’s private local Backup directory. Backups contain permanent financial records. Market Cache, Provider payloads, Credentials, Keychain data, and session-only planning assumptions are excluded. Aureus does not add application-layer encryption. Restore creates and validates a safety backup before replacing the Permanent Store."
                Text(disclosure)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(disclosure)
                    .accessibilityIdentifier("settings.dataLifecycle.disclosure")

                Text("External import/export, scheduling, cloud Backup, and user-selected file flows are not implemented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        } label: {
            Label("Internal Backup and Restore", systemImage: "externaldrive.badge.timemachine")
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
