import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var model: SettingsFeatureModel
    @State private var dataLifecycleModel: SettingsDataLifecycleModel
    @State private var showDisconnectConfirmation = false
    @State private var showDeleteCredentialConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showDataLifecycleDirectoryImporter = false
    @State private var directoryImporterPurpose: SettingsDataLifecycleDirectoryOperation?
    @State private var showExternalRestoreConfirmation = false
    @State private var externalRestoreLease: SettingsExternalRestoreSecurityLease?
    let mode: AppDataMode

    init(
        provider: any MarketDataProvider,
        marketDataService: MarketDataService,
        credentialCoordinator: ProviderCredentialCoordinator,
        cache: MarketCacheStore,
        sessionStore: TransientMarketSessionStore,
        wealthStore: WealthStore,
        internalBackupDirectoryURL: URL,
        permanentBackupExportConfiguration: PermanentBackupExportConfiguration,
        permanentExternalRestoreConfiguration: PermanentExternalRestoreConfiguration,
        appVersion: String,
        dataLifecycleGenerationID: @escaping @Sendable () -> UUID,
        clock: any Clock,
        mode: AppDataMode,
        generalPreferences: GeneralPreferencesStore = GeneralPreferencesStore(),
        diagnostics: DataLifecycleDiagnostics = .disabled
    ) {
        _model = State(initialValue: SettingsFeatureModel(
            provider: provider,
            marketDataService: marketDataService,
            credentialCoordinator: credentialCoordinator,
            cache: cache,
            sessionStore: sessionStore,
            clock: clock,
            generalPreferences: generalPreferences,
            diagnostics: diagnostics
        ))
        _dataLifecycleModel = State(initialValue: SettingsDataLifecycleModel(
            store: wealthStore,
            backupRoot: internalBackupDirectoryURL,
            appVersion: appVersion,
            clock: clock,
            generationID: dataLifecycleGenerationID,
            exportClient: .live(configuration: permanentBackupExportConfiguration),
            externalRestoreClient: .live(
                store: wealthStore,
                configuration: permanentExternalRestoreConfiguration
            ),
            diagnostics: diagnostics
        ))
        self.mode = mode
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsBanner
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalPreferencesSection
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
        .sheet(isPresented: $showRestoreConfirmation) {
            restoreConfirmationSheet
        }
        .sheet(
            isPresented: $showExternalRestoreConfirmation,
            onDismiss: releaseExternalRestoreSelectionIfIdle
        ) {
            externalRestoreConfirmationSheet
        }
        .fileImporter(
            isPresented: $showDataLifecycleDirectoryImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleDataLifecycleDirectorySelection
        )
        .onDisappear {
            releaseExternalRestoreSelectionIfIdle()
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

    private var generalPreferencesSection: some View {
        GroupBox("Wealth preferences") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Default currency for new Wealth containers", selection: $model.newWealthCurrency) {
                    Text("CNY").tag(CurrencyCode.cny)
                    Text("USD").tag(CurrencyCode.usd)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.general.currency")
                Picker("Group digits in Wealth amounts", selection: $model.groupWealthAmounts) {
                    Text("On").tag(true)
                    Text("Off").tag(false)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.general.grouping")
                Text("The default currency affects only new Wealth containers. Unified valuation remains CNY; existing records and open drafts are unchanged. USD still requires manual FX.")
                    .font(.caption)
                    .accessibilityIdentifier("settings.general.disclosure")
            }
            .padding(10)
        }
    }

    private func freshnessText(_ status: CacheFreshnessStatus, title: String, identifier: String) -> some View {
        let label = status.label(for: title)
        return Text(label)
            .font(.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }

    private var sessionSection: some View {
        GroupBox("Session Market Data") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Network connectivity: Not checked")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Network connectivity: Not checked")
                    .accessibilityIdentifier("settings.cache.connectivity")
                freshnessText(model.sessionFreshness, title: "Session Market Data",
                    identifier: "settings.session.freshness")
                Button("Refresh cache status") { Task { await model.refreshCacheStatus() } }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("settings.cache.refresh")
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
                freshnessText(model.persistentFreshness, title: "Authorized Persistent Market Cache",
                    identifier: "settings.cache.freshness")
                if let statistics = model.cacheStatistics {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow { Text("Current usage"); Text(byteString(statistics.currentBytes)) }
                        GridRow { Text("Capacity"); Text(byteString(statistics.maximumBytes)) }
                        GridRow { Text("Usage"); Text("\(statistics.percentageBasisPoints / 100)%") }
                        GridRow { Text("Entries"); Text("\(statistics.entryCount)") }
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

                    let oldestEntry = SettingsFeatureModel.oldestEntryLabel(for: statistics.oldestEntry)
                    Text(oldestEntry)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(oldestEntry)
                        .accessibilityIdentifier("settings.cache.oldestEntry")

                    let cleanupTime = SettingsFeatureModel.lastCleanupTimeLabel(for: statistics.lastCleanupAt)
                    Text(cleanupTime)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(cleanupTime)
                        .accessibilityIdentifier("settings.cache.lastCleanupAt")

                    if statistics.providerBreakdown.isEmpty {
                        Text("Provider breakdown: None")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Provider breakdown: None")
                            .accessibilityIdentifier("settings.cache.providers.empty")
                    }
                    ForEach(statistics.providerBreakdown) { provider in
                        let label = "\(provider.providerIdentifier): \(provider.entryCount) entries, \(byteString(provider.bytes))"
                        Text(label)
                            .font(.caption)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(label)
                            .accessibilityIdentifier("settings.cache.provider.\(provider.providerIdentifier)")
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

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("External Backup Export")
                        .font(.headline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("External Backup Export")
                        .accessibilityIdentifier("settings.dataLifecycle.externalExport.heading")

                    Text(externalExportWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(externalExportWarning)
                        .accessibilityIdentifier("settings.dataLifecycle.externalExport.warning")

                    Text("Aureus creates one two-file Backup generation folder in the selected directory. The destination is not remembered. Raw SQLite/general import, scheduling, cloud export, and external retention are not implemented.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Export Selected Backup…") {
                        directoryImporterPurpose = .externalExport
                        showDataLifecycleDirectoryImporter = true
                    }
                    .disabled(!dataLifecycleModel.canExport)
                    .accessibilityLabel("Export Selected Backup…")
                    .accessibilityIdentifier("settings.dataLifecycle.export")

                    if let result = dataLifecycleModel.externalExportResultLabel {
                        Text(result)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(result)
                            .accessibilityIdentifier("settings.dataLifecycle.externalExport.result")
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("External Backup Restore")
                        .font(.headline)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("External Backup Restore")
                        .accessibilityIdentifier("settings.dataLifecycle.externalRestore.heading")

                    Text(externalRestoreWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(externalRestoreWarning)
                        .accessibilityIdentifier("settings.dataLifecycle.externalRestore.warning")

                    Text("Choose a complete Aureus two-file Backup generation folder. The selection and access permission are used only for this explicit operation and are not remembered. Raw SQLite/general import, automatic or scheduled Restore, cloud Restore, and external retention are not implemented.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Restore External Backup…", role: .destructive) {
                        directoryImporterPurpose = .externalRestore
                        showDataLifecycleDirectoryImporter = true
                    }
                    .disabled(!dataLifecycleModel.canRestoreExternal)
                    .accessibilityLabel("Restore External Backup…")
                    .accessibilityIdentifier("settings.dataLifecycle.externalRestore")

                    if let result = dataLifecycleModel.externalRestoreResultLabel {
                        Text(result)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(result)
                            .accessibilityIdentifier("settings.dataLifecycle.externalRestore.result")
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

                Text("External Backup Export and validated External Backup Restore are explicit user-selected directory flows. Raw SQLite/general import, scheduling, cloud Backup/Restore, and external retention are not implemented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        } label: {
            Label("Internal Backup and Restore", systemImage: "externaldrive.badge.timemachine")
        }
    }

    private var restoreConfirmationSheet: some View {
        let title = "Restore Selected Internal Backup?"
        let warning = "Current Permanent records will be replaced. Aureus will create and validate a safety Backup before Restore. Backups contain private permanent financial records."
        return VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityIdentifier("settings.dataLifecycle.restore.dialog.heading")

            Text(warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(warning)
                .accessibilityIdentifier("settings.dataLifecycle.restore.dialog.warning")

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    showRestoreConfirmation = false
                }
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("settings.dataLifecycle.restore.cancel")

                Button("Restore Permanent Store", role: .destructive) {
                    showRestoreConfirmation = false
                    Task { await dataLifecycleModel.restoreSelected(confirmed: true) }
                }
                .disabled(!dataLifecycleModel.canRestore)
                .accessibilityLabel("Restore Permanent Store")
                .accessibilityIdentifier("settings.dataLifecycle.restore.confirm")
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var externalExportWarning: String {
        "External Backups contain private permanent financial records and are not encrypted by Aureus. Choose a private encrypted storage location you control. Do not choose a source-code repository or public/shared folder."
    }

    private var externalRestoreWarning: String {
        "External Restore will replace current Permanent records. Aureus will validate the selected two-file Backup and create and validate an internal safety Backup before replacement. External Backups contain private permanent financial records and are not encrypted by Aureus."
    }

    private var externalRestoreConfirmationSheet: some View {
        let title = "Restore Selected External Backup?"
        return VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityIdentifier("settings.dataLifecycle.externalRestore.dialog.heading")

            Text(externalRestoreWarning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(externalRestoreWarning)
                .accessibilityIdentifier("settings.dataLifecycle.externalRestore.dialog.warning")

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    showExternalRestoreConfirmation = false
                    releaseExternalRestoreSelectionIfIdle()
                }
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("settings.dataLifecycle.externalRestore.cancel")

                Button("Restore External Backup", role: .destructive) {
                    confirmExternalRestore()
                }
                .disabled(!dataLifecycleModel.canRestoreExternal)
                .accessibilityLabel("Restore External Backup")
                .accessibilityIdentifier("settings.dataLifecycle.externalRestore.confirm")
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func handleExternalExportSelection(_ selection: Result<[URL], Error>) {
        switch selection {
        case let .success(urls):
            guard let destination = urls.first else {
                dataLifecycleModel.externalDestinationSelectionFailed()
                return
            }
            Task {
                let isAccessing = destination.startAccessingSecurityScopedResource()
                defer {
                    if isAccessing {
                        destination.stopAccessingSecurityScopedResource()
                    }
                }
                await dataLifecycleModel.exportSelected(to: destination)
            }
        case let .failure(error):
            if error is CancellationError
                || (error as? CocoaError)?.code == .userCancelled {
                return
            }
            dataLifecycleModel.externalDestinationSelectionFailed()
        }
    }

    private func handleDataLifecycleDirectorySelection(_ selection: Result<[URL], Error>) {
        let purpose = directoryImporterPurpose
        directoryImporterPurpose = nil
        switch purpose {
        case .externalExport:
            handleExternalExportSelection(selection)
        case .externalRestore:
            handleExternalRestoreSelection(selection)
        case nil:
            return
        }
    }

    private func handleExternalRestoreSelection(_ selection: Result<[URL], Error>) {
        switch selection {
        case let .success(urls):
            guard dataLifecycleModel.canRestoreExternal,
                  let generationURL = urls.first else {
                dataLifecycleModel.externalSourceSelectionFailed()
                return
            }
            releaseExternalRestoreSelectionIfIdle()
            externalRestoreLease = SettingsExternalRestoreSecurityLease(url: generationURL)
            showExternalRestoreConfirmation = true
        case let .failure(error):
            if error is CancellationError
                || (error as? CocoaError)?.code == .userCancelled {
                return
            }
            dataLifecycleModel.externalSourceSelectionFailed()
        }
    }

    private func confirmExternalRestore() {
        guard dataLifecycleModel.canRestoreExternal,
              let lease = externalRestoreLease,
              lease.beginOperation() else { return }
        showExternalRestoreConfirmation = false
        Task {
            _ = await dataLifecycleModel.restoreExternal(from: lease.url)
            lease.finishOperation()
            if externalRestoreLease === lease {
                externalRestoreLease = nil
            }
        }
    }

    private func releaseExternalRestoreSelectionIfIdle() {
        externalRestoreLease?.releaseIfIdle()
        if externalRestoreLease?.isReleased == true {
            externalRestoreLease = nil
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

@MainActor
private final class SettingsExternalRestoreSecurityLease {
    let url: URL
    private let didStartAccess: Bool
    private(set) var isReleased = false
    private var operationIsInFlight = false

    init(url: URL) {
        self.url = url
        didStartAccess = url.startAccessingSecurityScopedResource()
    }

    func beginOperation() -> Bool {
        guard !isReleased, !operationIsInFlight else { return false }
        operationIsInFlight = true
        return true
    }

    func finishOperation() {
        operationIsInFlight = false
        release()
    }

    func releaseIfIdle() {
        guard !operationIsInFlight else { return }
        release()
    }

    private func release() {
        guard !isReleased else { return }
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
        isReleased = true
    }
}

private enum SettingsDataLifecycleDirectoryOperation {
    case externalExport
    case externalRestore
}
