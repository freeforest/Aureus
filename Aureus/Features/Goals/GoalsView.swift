import Charts
import SwiftUI

private enum GoalsReportSection: Int, CaseIterable {
    case overview
    case trajectory
    case fire
    case savingRate
    case calculationEvidence

    var title: String {
        switch self {
        case .overview: "Overview"
        case .trajectory: "Trajectory"
        case .fire: "FIRE"
        case .savingRate: "Saving Rate"
        case .calculationEvidence: "Calculation Evidence"
        }
    }
}

struct GoalsView: View {
    @State private var model: GoalsFeatureModel
    @State private var editor: GoalEditorPresentation?
    @State private var pendingDeletion: Goal?
    @State private var currentSection: GoalsReportSection = .overview
    let mode: AppDataMode

    init(store: WealthStore, clock: any Clock, mode: AppDataMode) {
        _model = State(initialValue: GoalsFeatureModel(store: store, clock: clock))
        self.mode = mode
    }

    var body: some View {
        @Bindable var bindable = model

        VStack(spacing: 0) {
            GoalsModeHeader(mode: mode)
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HSplitView {
                master(selection: $bindable.selectedGoalID, draft: $bindable.sessionDraft)
                    .frame(minWidth: 350, idealWidth: 380, maxWidth: 420)
                detail
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Goals")
        .sheet(item: $editor) { presentation in
            GoalEditorSheet(presentation: presentation) { goal in
                Task {
                    if presentation.existing == nil {
                        await model.createGoal(goal)
                    } else {
                        await model.updateGoal(goal)
                    }
                }
            }
        }
        .alert(
            "Delete Goal?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            if let goal = pendingDeletion {
                Button("Delete", role: .destructive) {
                    pendingDeletion = nil
                    Task { await model.deleteGoal(id: goal.id, confirmed: true) }
                }
                .accessibilityIdentifier("goals.delete.confirm")
            }
        } message: {
            if let goal = pendingDeletion {
                Text("Delete \"\(goal.name)\" from the local permanent Goals store?")
            }
        }
        .task {
            await model.load()
            currentSection = .overview
        }
        .onChange(of: model.selectedGoalID) { _, _ in currentSection = .overview }
        .onChange(of: model.sessionDraft) { _, _ in currentSection = .overview }
        .onChange(of: model.report) { _, _ in currentSection = .overview }
        .onChange(of: model.state) { _, state in
            if state == .failed { currentSection = .overview }
        }
    }

    private func master(
        selection: Binding<UUID?>,
        draft: Binding<GoalsSessionDraft>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(statusLabel)
                .font(.subheadline.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusLabel)
                .accessibilityIdentifier("goals.status")

            if model.state == .loading || model.state == .idle {
                ProgressView("Loading Goals…")
                    .accessibilityIdentifier("goals.loading")
            } else if model.goals.isEmpty {
                ContentUnavailableView(
                    "No Goals",
                    systemImage: "target",
                    description: Text("Create a local CNY or USD Goal. No planning assumptions are persisted.")
                )
                .frame(height: 120)
                .accessibilityIdentifier("goals.empty")
            } else {
                List(model.goals, selection: selection) { goal in
                    GoalRow(goal: goal)
                        .tag(goal.id)
                }
                .listStyle(.inset)
                .frame(minHeight: 105, idealHeight: 130, maxHeight: 150)
                .accessibilityIdentifier("goals.list")
            }

            HStack(spacing: 8) {
                Button("Add") { editor = GoalEditorPresentation(existing: nil) }
                    .accessibilityIdentifier("goals.add")
                Button("Edit") {
                    if let goal = model.selectedGoal { editor = GoalEditorPresentation(existing: goal) }
                }
                .disabled(model.selectedGoal == nil)
                .accessibilityIdentifier("goals.edit")
                Button("Delete", role: .destructive) { pendingDeletion = model.selectedGoal }
                    .disabled(model.selectedGoal == nil)
                    .accessibilityIdentifier("goals.delete")
            }

            Divider()
            Text("Session Planning Assumptions")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                inputRow(
                    "Monthly CNY",
                    text: draft.monthlyContribution,
                    identifier: "goals.input.monthly-contribution"
                )
                inputRow(
                    "Annual return %",
                    text: draft.expectedAnnualReturnPercent,
                    identifier: "goals.input.expected-return"
                )
                inputRow(
                    "Annual spending",
                    text: draft.annualSpending,
                    identifier: "goals.input.annual-spending"
                )
                inputRow(
                    "Withdrawal %",
                    text: draft.withdrawalRatePercent,
                    identifier: "goals.input.withdrawal-rate"
                )
                inputRow(
                    "Saving start",
                    text: draft.savingRateStartDate,
                    identifier: "goals.input.saving-start"
                )
                inputRow(
                    "Saving end",
                    text: draft.savingRateEndDate,
                    identifier: "goals.input.saving-end"
                )
                inputRow(
                    "As-of",
                    text: draft.asOfDate,
                    identifier: "goals.input.as-of"
                )
            }

            if let message = model.inputErrorMessage {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: message))
                    .accessibilityIdentifier("goals.input.error")
            }

            HStack(spacing: 8) {
                Button("Calculate") {
                    if model.applySessionDraft() { model.calculate() }
                }
                .disabled(model.selectedGoal == nil || model.state == .calculating)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityIdentifier("goals.calculate")
                Button("Cancel") {
                    model.cancelCalculation()
                    currentSection = .overview
                }
                .disabled(model.state != .calculating)
                .accessibilityIdentifier("goals.cancel")
            }

            if model.report == nil, model.state != .calculating {
                Text("Not Calculated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("goals.not-calculated")
            }

            Divider()
            reportNavigation
        }
        .padding(12)
    }

    private func inputRow(
        _ title: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        GridRow {
            Text(title).font(.caption)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 145)
                .accessibilityIdentifier(identifier)
        }
    }

    private var reportNavigation: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Goals report section: \(currentSection.title)")
                .font(.caption.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Goals report section: \(currentSection.title)")
                .accessibilityIdentifier("goals.navigation.current")
            HStack {
                Button("Previous") {
                    if let prior = GoalsReportSection(rawValue: currentSection.rawValue - 1) {
                        currentSection = prior
                    }
                }
                .disabled(model.report == nil || currentSection == .overview)
                .accessibilityIdentifier("goals.navigation.previous")
                Button("Next") {
                    if let next = GoalsReportSection(rawValue: currentSection.rawValue + 1) {
                        currentSection = next
                    }
                }
                .disabled(model.report == nil || currentSection == .calculationEvidence)
                .accessibilityIdentifier("goals.navigation.next")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goals.navigation.group")
    }

    @ViewBuilder
    private var detail: some View {
        if let report = model.report {
            ScrollView {
                reportSection(report)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            ContentUnavailableView(
                "Not Calculated",
                systemImage: "target",
                description: Text("Select a Goal, enter every session assumption, then calculate explicitly.")
            )
            .accessibilityIdentifier("goals.not-calculated.detail")
        }
    }

    @ViewBuilder
    private func reportSection(_ report: GoalsCalculationReport) -> some View {
        switch currentSection {
        case .overview:
            overview(report)
        case .trajectory:
            trajectory(report)
        case .fire:
            fire(report)
        case .savingRate:
            savingRate(report)
        case .calculationEvidence:
            calculationEvidence
        }
    }

    private func overview(_ report: GoalsCalculationReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            accessibleHeading(
                "Overview",
                label: "Goals report overview",
                identifier: "goals.overview.heading"
            )
            let goalLabel = "Goal: \(report.goal.name), target \(GoalsDisplay.money(report.goal.target)), target date \(report.goal.targetDate?.description ?? "not set")"
            accessibleText(goalLabel, identifier: "goals.overview.goal")
            accessibleText(
                "Current CNY net worth: \(GoalsDisplay.money(report.currentNetWorthCNY))",
                identifier: "goals.overview.net-worth"
            )
            switch report.progress {
            case let .available(progress):
                accessibleText(
                    "Goal progress: \(GoalsDisplay.percent(progress.progress)); remaining \(GoalsDisplay.money(progress.remainingCNY)); progress is not clamped.",
                    identifier: "goals.progress.summary"
                )
            case let .unavailable(reason):
                accessibleText(
                    "Goal progress unavailable: \(GoalsDisplay.unavailable(reason)).",
                    identifier: "goals.progress.unavailable"
                )
            }
        }
    }

    private func trajectory(_ report: GoalsCalculationReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            accessibleHeading(
                "Trajectory",
                label: "Goal trajectory section",
                identifier: "goals.trajectory.heading"
            )
            switch report.trajectory {
            case let .available(available):
                VStack(alignment: .leading, spacing: 6) {
                    Chart(report.presentationTrajectory) { point in
                        LineMark(
                            x: .value("Month", point.monthIndex),
                            y: .value("Projected CNY", GoalsDisplay.chartValue(point.projectedValueCNY))
                        )
                        .foregroundStyle(.blue)
                    }
                    .frame(height: 190)
                    .accessibilityHidden(true)
                    Text("Visual assumption-based CNY trajectory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Goal trajectory chart"))
                .accessibilityIdentifier("goals.chart.trajectory")

                let summary = "Trajectory summary: \(report.presentationTrajectory.count) points, as-of \(report.asOfDate), target month \(available.targetDate), initial/current value \(GoalsDisplay.money(report.currentNetWorthCNY)), target-date scenario value \(GoalsDisplay.money(available.targetDateScenario.futureValueCNY))."
                accessibleText(summary, identifier: "goals.trajectory.summary")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trajectory table: \(report.presentationTrajectory.count) rows")
                        .font(.caption.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(report.presentationTrajectory) { point in
                                let label = "Month \(point.monthIndex): projected \(GoalsDisplay.money(point.projectedValueCNY))"
                                accessibleText(
                                    label,
                                    identifier: "goals.trajectory.row.\(point.monthIndex)"
                                )
                                .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .frame(height: 170)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Trajectory table: \(report.presentationTrajectory.count) rows")
                .accessibilityIdentifier("goals.trajectory.table")

            case let .unavailable(reason):
                accessibleText(
                    "Trajectory unavailable: \(GoalsDisplay.unavailable(reason)).",
                    identifier: "goals.trajectory.unavailable"
                )
            }
            accessibleText(
                CompoundPlanningResult.disclosure,
                identifier: "goals.trajectory.disclosure"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func fire(_ report: GoalsCalculationReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            accessibleHeading(
                "FIRE",
                label: "FIRE arithmetic scenario section",
                identifier: "goals.fire.heading"
            )
            let scenario = report.fireScenario
            accessibleText(
                "FIRE arithmetic summary: annual spending \(GoalsDisplay.money(scenario.annualSpendingCNY)), user-supplied withdrawal rate \(GoalsDisplay.percent(scenario.withdrawalRate)), FIRE Number \(GoalsDisplay.money(scenario.fireNumberCNY)), current progress \(GoalsDisplay.percent(scenario.progress)).",
                identifier: "goals.fire.summary"
            )
            accessibleText(
                "Estimated reach: \(GoalsDisplay.reach(scenario.estimatedReach)).",
                identifier: "goals.fire.reach"
            )
            accessibleText(FIREScenario.disclosure, identifier: "goals.fire.disclosure")
                .foregroundStyle(.secondary)
        }
    }

    private func savingRate(_ report: GoalsCalculationReport) -> some View {
        let saving = report.savingRate
        return VStack(alignment: .leading, spacing: 12) {
            accessibleHeading(
                "Saving Rate",
                label: "Saving Rate section",
                identifier: "goals.saving-rate.heading"
            )
            VStack(alignment: .leading, spacing: 6) {
                Chart(saving.observedMonths, id: \.period) { month in
                    BarMark(
                        x: .value("Month", GoalsDisplay.month(month.period)),
                        y: .value("Savings CNY", GoalsDisplay.chartValue(month.ordinarySavingsCNY))
                    )
                    .foregroundStyle(.green)
                }
                .frame(height: 190)
                .accessibilityHidden(true)
                Text("Visual observed ordinary Saving Rate amounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Observed Saving Rate chart"))
            .accessibilityIdentifier("goals.chart.saving-rate")

            let summary = "Saving Rate summary: range \(saving.range.start) through \(saving.range.end), ordinary income \(GoalsDisplay.money(saving.ordinaryIncomeCNY)), ordinary expense \(GoalsDisplay.money(saving.ordinaryExpenseCNY)), savings \(GoalsDisplay.money(saving.ordinarySavingsCNY)), aggregate rate \(GoalsDisplay.savingRate(saving.aggregateRate)), \(saving.includedEntryCount) included entries, \(saving.observedMonths.count) observed months."
            accessibleText(summary, identifier: "goals.saving-rate.summary")

            VStack(alignment: .leading, spacing: 4) {
                Text("Saving Rate table: \(saving.observedMonths.count) rows")
                    .font(.caption.weight(.semibold))
                ForEach(saving.observedMonths, id: \.period) { month in
                    let period = GoalsDisplay.month(month.period)
                    let label = "\(period): income \(GoalsDisplay.money(month.ordinaryIncomeCNY)), expense \(GoalsDisplay.money(month.ordinaryExpenseCNY)), savings \(GoalsDisplay.money(month.ordinarySavingsCNY)), rate \(GoalsDisplay.savingRate(month.savingRate))."
                    accessibleText(
                        label,
                        identifier: "goals.saving-rate.row.\(period)"
                    )
                    .font(.caption.monospacedDigit())
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Saving Rate table: \(saving.observedMonths.count) rows")
            .accessibilityIdentifier("goals.saving-rate.table")

            accessibleText(
                SavingRateReport.disclosure,
                identifier: "goals.saving-rate.disclosure"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var calculationEvidence: some View {
        VStack(alignment: .leading, spacing: 12) {
            accessibleHeading(
                "Calculation Evidence",
                label: "Goals calculation evidence section",
                identifier: "goals.evidence.heading"
            )
            accessibleText(
                "Calculation evidence: local permanent Goals, Wealth, and Ledger records only. Planning assumptions are session-only. No Provider request was made. No Market Cache, Credential, or Keychain data was read. No automatic FX conversion was performed. Planning assumptions were not persisted. Scenarios are not predictions, guarantees, or recommendations.",
                identifier: "goals.evidence"
            )
        }
    }

    private func accessibleHeading(
        _ text: String,
        label: String,
        identifier: String
    ) -> some View {
        Text(text)
            .font(.title2.weight(.semibold))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityIdentifier(identifier)
    }

    private func accessibleText(_ text: String, identifier: String) -> some View {
        Text(verbatim: text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityIdentifier(identifier)
    }

    private var statusLabel: String {
        let value: String
        switch model.state {
        case .idle, .loading: value = "Loading"
        case .calculating: value = "Calculating"
        case .failed: value = "Failed"
        case .ready: value = model.report == nil ? "Ready" : "Calculated"
        }
        return "Goals status: \(value)"
    }
}

private struct GoalsModeHeader: View {
    let mode: AppDataMode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Goals")
                .font(.subheadline.weight(.semibold))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Goals page"))
                .accessibilityIdentifier("goals.page")

            if mode == .syntheticDemo {
                Text("Synthetic Demo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "Goals mode: Synthetic Demo"))
                    .accessibilityIdentifier("goals.mode.synthetic")
            } else {
                Text("Production Local")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "Goals mode: Production Local"))
                    .accessibilityIdentifier("goals.mode.production")
            }

            Text(verbatim: GoalsFeatureModel.localOnlyDisclosure)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: GoalsFeatureModel.localOnlyDisclosure))
                .accessibilityIdentifier("goals.disclosure.local-only")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct GoalRow: View {
    let goal: Goal

    var body: some View {
        let label = "Goal: \(goal.name), target \(GoalsDisplay.money(goal.target)), target date \(goal.targetDate?.description ?? "not set")"
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: goal.name).font(.body.weight(.medium))
            Text("\(GoalsDisplay.money(goal.target)) · \(goal.targetDate?.description ?? "No target date")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityIdentifier("goals.goal.\(goal.id.uuidString.lowercased())")
    }
}

private struct GoalEditorPresentation: Identifiable {
    let existing: Goal?
    let id: String

    init(existing: Goal?) {
        self.existing = existing
        id = existing?.id.uuidString ?? "new-goal"
    }
}

private struct GoalEditorDraft {
    var name = ""
    var target = ""
    var currency: CurrencyCode = .cny
    var hasTargetDate = false
    var targetDate = ""

    init(existing: Goal?) {
        guard let existing else { return }
        name = existing.name
        target = NSDecimalNumber(decimal: existing.target.decimal).stringValue
        currency = existing.target.currency
        hasTargetDate = existing.targetDate != nil
        targetDate = existing.targetDate?.description ?? ""
    }

    func goal(id: UUID) throws -> Goal {
        let amount = try Money(
            decimal: FixedPointMath.parseCanonical(target.trimmingCharacters(in: .whitespacesAndNewlines)),
            currency: currency
        )
        let date = hasTargetDate ? try CivilDate(canonical: targetDate) : nil
        return try Goal(id: id, name: name, target: amount, targetDate: date)
    }
}

private struct GoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let presentation: GoalEditorPresentation
    let onSave: (Goal) -> Void
    @State private var draft: GoalEditorDraft
    @State private var errorMessage: String?

    init(presentation: GoalEditorPresentation, onSave: @escaping (Goal) -> Void) {
        self.presentation = presentation
        self.onSave = onSave
        _draft = State(initialValue: GoalEditorDraft(existing: presentation.existing))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(presentation.existing == nil ? "Add Goal" : "Edit Goal")
                .font(.title2.weight(.semibold))
                .padding(18)
            Divider()
            Form {
                TextField("Name", text: $draft.name)
                    .accessibilityIdentifier("goals.editor.name")
                TextField("Target amount", text: $draft.target)
                    .accessibilityIdentifier("goals.editor.target")
                Picker("Currency", selection: $draft.currency) {
                    Text("CNY").tag(CurrencyCode.cny)
                    Text("USD").tag(CurrencyCode.usd)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("goals.editor.currency")
                Toggle("Has target date", isOn: $draft.hasTargetDate)
                    .accessibilityIdentifier("goals.editor.has-target-date")
                TextField("Target date (YYYY-MM-DD)", text: $draft.targetDate)
                    .disabled(!draft.hasTargetDate)
                    .accessibilityIdentifier("goals.editor.target-date")
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("goals.editor.error")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 500, minHeight: 330)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("goals.editor.cancel")
                Button("Save") {
                    do {
                        let id = presentation.existing?.id ?? UUID()
                        onSave(try draft.goal(id: id))
                        dismiss()
                    } catch {
                        errorMessage = "Enter a non-empty name, a positive canonical target, and an optional canonical target date."
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("goals.editor.save")
            }
            .padding(14)
        }
    }
}

private enum GoalsDisplay {
    static func money(_ value: Money) -> String {
        "\(value.currency.rawValue) \(number(value.decimal, minimum: 2, maximum: 2))"
    }

    static func percent(_ value: Ratio) -> String {
        "\(number(value.decimal * Decimal(100), minimum: 0, maximum: 2))%"
    }

    static func savingRate(_ value: SavingRateValue) -> String {
        switch value {
        case let .available(rate): percent(rate)
        case let .unavailable(reason): "unavailable (\(unavailable(reason)))"
        }
    }

    static func unavailable(_ reason: GoalPlanningUnavailableReason) -> String {
        switch reason {
        case .targetCurrencyUnsupportedForCNYProgress:
            "target currency unsupported for CNY progress"
        case .missingTargetDate:
            "missing target date"
        case .targetDateNotFuture:
            "target date month is not future"
        case .alreadyReached:
            "already reached"
        case .notReachedWithinMaximumMonths:
            "not reached within maximum 1200 months"
        case .nonPositiveIncome:
            "non-positive ordinary income"
        }
    }

    static func reach(_ reach: GoalReachEstimate) -> String {
        switch reach {
        case .alreadyReached:
            "already reached"
        case let .reached(months, value):
            "reached in \(months) months at \(money(value))"
        case let .unavailable(reason):
            "unavailable (\(unavailable(reason)))"
        }
    }

    static func month(_ value: GoalPlanningMonth) -> String {
        String(format: "%04d-%02d", value.year, value.month)
    }

    static func chartValue(_ value: Money) -> Double {
        NSDecimalNumber(decimal: value.decimal).doubleValue
    }

    private static func number(
        _ value: Decimal,
        minimum: Int,
        maximum: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = minimum
        formatter.maximumFractionDigits = maximum
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
}
