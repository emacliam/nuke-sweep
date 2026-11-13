import SwiftUI
import AppKit

struct AIAssistSettingsView: View {
    @Environment(AISettings.self) var ai
    @State private var keyDraft = ""
    @State private var showPreview = false
    @State private var testing = false
    @State private var testNote = ""
    @State private var detected: [String] = []
    @State private var confirmRemove = false

    private var active: AIProviderConfig { ai.activeProvider }
    private var activeHasKey: Bool { ai.hasKey(for: active) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(title: "Providers", detail: ai.enabled ? "Advisory only" : "Advisory only · off by default")
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable AI assist", isOn: Bindable(ai).enabled).font(.system(size: 13, weight: .medium))
                    if ai.enabled {
                        providerPicker
                        providerDetails
                    } else {
                        Text("AI is off. No provider is called and no network request is made.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Notice(text: active.isLocal
                   ? "AI suggestions are advisory. They never select, move or delete anything, and they cannot override Nuke's hard blocks. No file contents, source code, .env, receipt paths or absolute home paths are sent. This provider runs on this Mac."
                   : "AI suggestions are advisory. They never select, move or delete anything, and they cannot override Nuke's hard blocks. No file contents, source code, .env, receipt paths or absolute home paths are sent. \(active.name) receives relative names and evidence only.",
                   symbol: "hand.raised")
            Surface {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What AI receives").font(.system(size: 12, weight: .semibold))
                    Text("Folder or file name, relative path, size, kind, evidence label and rebuild hint, Git ignore state, and the scope label/policy. Nothing else.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Request log").font(.system(size: 12, weight: .semibold)).padding(.top, 6)
                    if ai.requestLog.isEmpty {
                        Text("No requests in this session.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    } else {
                        ForEach(ai.requestLog) { record in
                            HStack(spacing: 8) {
                                Text(record.date.formatted(date: .omitted, time: .standard)).font(.system(size: 9)).monospacedDigit()
                                Text(record.provider).font(.system(size: 9))
                                Text(record.item).font(.system(size: 9)).lineLimit(1)
                                Spacer()
                                Text(record.outcome).font(.system(size: 9)).foregroundStyle(record.outcome == "success" ? Theme.green : Theme.error)
                                Text("\(record.milliseconds) ms").font(.system(size: 9)).monospacedDigit().foregroundStyle(Theme.secondary)
                            }
                        }
                        Button("Clear request log") { ai.clearLog() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                    }
                }
            }
        }
        .sheet(isPresented: $showPreview) { AIPayloadPreview() }
        .onAppear {
            ai.refreshKeyStatus()
            detected = ai.discoveredModels[ai.activeProvider.id] ?? []
        }
        .onChange(of: ai.activeProviderID) { _, _ in
            detected = ai.discoveredModels[ai.activeProvider.id] ?? []; testNote = ""; keyDraft = ""
            if ai.offlineOnly && !ai.activeProvider.isLocal, let local = ai.providers.first(where: { $0.isLocal }) {
                ai.setActive(local.id)
            }
            ai.refreshKeyStatus()
        }
        .onChange(of: ai.offlineOnly) { _, blocked in
            guard blocked else { return }
            if !ai.providers.contains(where: { $0.isLocal }) { _ = ai.addProvider(.local) }
            if let local = ai.providers.first(where: { $0.isLocal }) { ai.setActive(local.id) }
        }
        .confirmationDialog("Remove \(active.name)?", isPresented: $confirmRemove) {
            Button("Remove provider and key", role: .destructive) { removeProvider() }
        } message: {
            Text("This removes the provider configuration and deletes its API key from the login Keychain.")
        }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Provider", selection: Binding(get: { ai.activeProviderID }, set: { ai.setActive($0) })) {
                    ForEach(ai.providers) { provider in Text(provider.name).tag(provider.id) }
                }.labelsHidden().frame(maxWidth: 260).accessibilityLabel("Active AI provider")
                Menu {
                    ForEach(AIProviderFlavor.allCases) { flavor in
                        Button("Add \(flavor.title)") { addProvider(flavor) }
                    }
                } label: { Label("Add", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Add AI provider")
                Spacer()
                Button("Remove") { confirmRemove = true }
                    .buttonStyle(QuietButton()).disabled(ai.providers.count <= 1)
            }
            HStack(spacing: 6) {
                Text(active.flavor.title).font(.system(size: 10, weight: .semibold))
                Text("·").foregroundStyle(Theme.secondary)
                Text(active.locality).font(.system(size: 10)).foregroundStyle(active.isLocal ? Theme.green : Theme.secondary)
                if activeHasKey { Label("Key stored", systemImage: "checkmark.shield").font(.system(size: 9)).foregroundStyle(Theme.green) }
                Spacer()
                Text(ai.providerStatus).font(.system(size: 10)).foregroundStyle(ai.providerReady ? Theme.green : Theme.secondary).lineLimit(2)
            }
            Text(active.flavor.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Plan provider").font(.system(size: 11))
                Picker("Plan provider", selection: Binding(get: { ai.planProviderID }, set: { ai.setPlanProvider($0) })) {
                    Text("Same as active").tag(UUID?.none)
                    ForEach(ai.providers) { provider in Text(provider.name).tag(Optional(provider.id)) }
                }.labelsHidden().frame(maxWidth: 260).accessibilityLabel("Plan AI provider")
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Explain uses the active provider. Plan can use a different provider or model; same metadata rules apply.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                if let planID = ai.planProviderID, planID != ai.activeProviderID {
                    Button("Edit plan provider") { ai.setActive(planID) }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                }
            }
            if !ai.providerReady(for: .plan) {
                Text("Plan provider: " + ai.providerStatus(for: .plan)).font(.system(size: 10)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Block all cloud AI requests", isOn: Bindable(ai).offlineOnly).font(.system(size: 12))
        }
    }

    private var providerDetails: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Name").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.secondary)
                TextField("Provider name", text: binding(\.name)).textFieldStyle(.roundedBorder).font(.system(size: 11))
            }
            if active.flavor == .deepSeek || active.flavor == .anthropic || active.flavor == .gemini {
                Text("Base URL: " + active.effectiveBaseURL).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Base URL").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.secondary)
                    TextField("Base URL", text: binding(\.baseURL)).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                }
                if !AISettings.isValidBaseURL(active.baseURL) {
                    Text("Use HTTPS, or HTTP only for 127.0.0.1, localhost or ::1. No query, fragment or credentials.")
                        .font(.system(size: 10)).foregroundStyle(Theme.error)
                } else if active.flavor == .local && !AISettings.isLoopbackEndpoint(active.baseURL) {
                    Text("A local provider must use a loopback base URL.").font(.system(size: 10)).foregroundStyle(Theme.error)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Model").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.secondary)
                HStack(spacing: 6) {
                    TextField("Model", text: binding(\.model)).textFieldStyle(.roundedBorder).font(.system(size: 11))
                    if !detected.isEmpty {
                        Menu("Detected") { ForEach(detected, id: \.self) { model in Button(model) { ai.updateActive { $0.model = model } } } }
                            .font(.system(size: 10)).fixedSize()
                    }
                }
            }
            if active.flavor != .local {
                if activeHasKey {
                    HStack {
                        Label("API key stored in the login Keychain", systemImage: "checkmark.shield").font(.system(size: 11)).foregroundStyle(Theme.green)
                        Spacer()
                        Button("Remove key") { Task { await ai.removeKey(for: active); keyDraft = "" } }.buttonStyle(QuietButton()).disabled(ai.keyBusy)
                    }
                } else {
                    HStack(spacing: 6) {
                        SecureField("API key", text: $keyDraft).textFieldStyle(.roundedBorder).font(.system(size: 11))
                        Button(ai.keyBusy ? "Saving…" : "Save key") { let draft = keyDraft; Task { if await ai.saveKey(draft, for: active) { keyDraft = "" } } }.buttonStyle(QuietButton()).disabled(ai.keyBusy || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                    }
                }
                if let error = ai.keyError { Text(error).font(.system(size: 10)).foregroundStyle(Theme.error) }
                Text("The key goes to the login Keychain, never to scan data, receipts or logs.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Ask before sending to a cloud provider", isOn: Bindable(ai).askBeforeCloud).font(.system(size: 12))
            }
            HStack(spacing: 8) {
                Button(testing ? "Testing…" : "Test connection") { testConnection() }
                    .buttonStyle(QuietButton()).disabled(testing || !ai.providerReady)
                Button("Preview what will be sent") { showPreview = true }.buttonStyle(QuietButton())
                Spacer()
            }
            if !testNote.isEmpty {
                Text(testNote).font(.system(size: 10)).foregroundStyle(testNote.localizedCaseInsensitiveContains("error") || testNote.localizedCaseInsensitiveContains("failed") || testNote.localizedCaseInsensitiveContains("HTTP") ? Theme.error : Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !detected.isEmpty {
                Text("Detected models: " + detected.prefix(8).joined(separator: ", ")).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AIProviderConfig, String>) -> Binding<String> {
        Binding(get: { ai.activeProvider[keyPath: keyPath] }, set: { value in ai.updateActive { $0[keyPath: keyPath] = value } })
    }

    private func addProvider(_ flavor: AIProviderFlavor) {
        _ = ai.addProvider(flavor)
        detected = []; testNote = ""; keyDraft = ""
        ai.refreshKeyStatus()
    }

    private func removeProvider() {
        ai.removeActiveProvider()
        detected = []; testNote = ""; keyDraft = ""
        ai.refreshKeyStatus()
    }

    private func testConnection() {
        guard !testing else { return }
        testing = true; testNote = "Testing connection…"; detected = []
        Task {
            do {
                let provider = try await ai.makeProvider()
                let check = try await provider.check()
                detected = check.models
                ai.setDiscoveredModels(check.models, for: ai.activeProvider)
                let names = check.models.prefix(5).joined(separator: ", ")
                testNote = "Connected in \(check.latencyMS) ms" + (names.isEmpty ? " · no model list returned" : " · " + names)
            } catch {
                testNote = error.localizedDescription
            }
            testing = false
        }
    }
}

struct AIExplainTarget: Identifiable {
    let id = UUID()
    let item: DiskItem
    let evidence: CleanupEvidence
    let scope: DeveloperScope?
}

struct AIExplainSheet: View {
    @Environment(AISettings.self) var ai
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let target: AIExplainTarget
    let previewBeforeSending: Bool

    @State private var context: AIContext
    @State private var phase = Phase.ready
    @State private var suggestion: AISuggestion?
    @State private var error = ""
    @State private var showPayload = false
    @State private var requestTask: Task<Void, Never>?
    @State private var confirmReplace = false

    private enum Phase { case ready, loading, done, failed }

    init(target: AIExplainTarget, previewBeforeSending: Bool = false) {
        self.target = target
        self.previewBeforeSending = previewBeforeSending
        _showPayload = State(initialValue: previewBeforeSending)
        _context = State(initialValue: AIContext.make(item: target.item, evidence: target.evidence, scope: target.scope))
    }

    private var canSend: Bool { ai.enabled && ai.providerReady }
    private var providerTitle: String { ai.activeProvider.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label("Explain with AI", systemImage: "sparkles").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(providerTitle).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(target.item.name).font(.system(size: 13, weight: .semibold))
                Text(context.relativePath).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            }

            Text("Local status: " + CandidateAssessment.make(target.item, evidence: target.evidence, scope: target.scope).state.rawValue)
                .font(.system(size: 12, weight: .semibold))
            DisclosureGroup("Evidence, consequences and unknowns") {
                AssessmentSummary(assessment: .make(target.item, evidence: target.evidence, scope: target.scope))
            }.font(.system(size: 11))
            switch phase {
            case .ready: readyView
            case .loading: loadingView
            case .done: resultView
            case .failed: failureView
            }
        }
        .padding(24)
        .frame(width: 640)
        .onAppear { ai.refreshKeyStatus() }
        .task {
            if !previewBeforeSending, phase == .ready, (ai.activeProvider.isLocal || !ai.askBeforeCloud), canSend { start() }
        }
        .onDisappear { requestTask?.cancel() }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Notice(text: ai.activeProvider.isLocal
                   ? "Only the metadata below is sent to your local model. It does not leave this Mac."
                   : "The metadata below will be sent to \(ai.activeProvider.name). File contents are never sent.",
                   symbol: "info.circle")
            DisclosureGroup("What will be sent", isExpanded: $showPayload) {
                ScrollView {
                    Text(context.jsonString).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 190)
            }.font(.system(size: 11))
            if !canSend {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ai.providerStatus).font(.system(size: 11)).foregroundStyle(Theme.warning)
                    Button("Open AI settings") { openSettings() }.buttonStyle(QuietButton())
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(ai.activeProvider.isLocal ? "Explain with local model" : "Send to \(ai.activeProvider.name)") { start() }
                    .buttonStyle(PrimaryButton()).disabled(!canSend)
            }
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Waiting for \(providerTitle)…").font(.system(size: 12)) }
            Text("The request contains metadata only. Nothing is selected or moved.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let suggestion {
                HStack(spacing: 8) {
                    Text("AI classification: " + suggestion.category.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    Text("AI interpretation").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("AI suggestion — not a safety guarantee").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                }
                Text(suggestion.explanation).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                if let rebuild = suggestion.rebuild {
                    Label("Rebuild: " + rebuild, systemImage: "arrow.clockwise").font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !suggestion.risks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Risks").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        ForEach(suggestion.risks, id: \.self) { risk in Text("• " + risk).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Text(target.evidence.label).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.secondary)
                    Text(target.evidence.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Nuke's evidence and review remain authoritative. Nothing was selected or moved.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                HStack {
                    Button("Copy explanation") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(suggestion.explanation + "\n\n" + (suggestion.rebuild ?? ""), forType: .string)
                    }.buttonStyle(QuietButton())
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(PrimaryButton())
                }
            }
        }
    }

    private var failureView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Notice.measured(error, symbol: "exclamationmark.triangle")
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Open AI settings") { openSettings() }.buttonStyle(QuietButton())
                Button("Retry") { start() }.buttonStyle(PrimaryButton()).disabled(!canSend)
            }
        }
    }

    private func start() {
        guard phase != .loading else { return }
        guard canSend else { error = ai.providerStatus(for: .plan); phase = .failed; return }
        phase = .loading
        requestTask?.cancel()
        let beginning = Date()
        requestTask = Task {
            do {
                let provider = try await ai.makeProvider()
                let result = try await provider.explain(context)
                guard !Task.isCancelled else { return }
                suggestion = result; phase = .done
                ai.record(provider: ai.activeProvider.name, item: target.item.name, outcome: "success", milliseconds: Int(Date().timeIntervalSince(beginning) * 1000))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; phase = .failed
                ai.record(provider: ai.activeProvider.name, item: target.item.name, outcome: "failed", milliseconds: Int(Date().timeIntervalSince(beginning) * 1000))
            }
        }
    }

    private func openSettings() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { model.page = .aiAssist }
    }
}

struct AIPayloadPreview: View {
    @Environment(AISettings.self) var ai
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Payload preview", systemImage: "doc.text.magnifyingglass").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(ai.activeProvider.name).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Text("Endpoint: " + ai.activeProvider.baseURL + " · model: " + ai.activeProvider.model)
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
            ScrollView {
                Text(AISettings.sampleContext.jsonString).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 280).padding(10).background(Theme.rail.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            Notice(text: "Real requests replace the sample with the selected item's name, relative path, size, evidence and scope policy. File contents, source, credentials, receipt paths and absolute home paths are never included.", symbol: "hand.raised")
            HStack { Spacer(); Button("Close") { dismiss() }.buttonStyle(PrimaryButton()) }
        }.padding(24).frame(width: 620)
    }
}

struct AIPlanSheet: View {
    @Environment(AISettings.self) var ai
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let items: [DiskItem]
    let blocked: (DiskItem) -> Bool
    let scope: DeveloperScope?
    let evidence: (DiskItem) -> CleanupEvidence
    let currentSelection: [String: DiskItem]
    let onCreateScope: (([DiskItem]) -> Void)?
    let onApply: ([DiskItem], [DiskItem]) -> Void

    @State private var instruction = ""
    @State private var context: AIPlanContext
    @State private var contextReady = false
    @State private var phase = Phase.ready
    @State private var resolution: AIPlanResolution?
    @State private var error = ""
    @State private var showPayload = false
    @State private var requestTask: Task<Void, Never>?
    @State private var confirmReplace = false

    private enum Phase { case ready, loading, done, failed }

    init(items: [DiskItem], blocked: @escaping (DiskItem) -> Bool, scope: DeveloperScope?, evidence: @escaping (DiskItem) -> CleanupEvidence, currentSelection: [String: DiskItem], onCreateScope: (([DiskItem]) -> Void)?, onApply: @escaping ([DiskItem], [DiskItem]) -> Void) {
        self.items = items
        self.blocked = blocked
        self.scope = scope
        self.evidence = evidence
        self.currentSelection = currentSelection
        self.onCreateScope = onCreateScope
        self.onApply = onApply
        let candidates = items.prefix(80).map { item in
            let itemEvidence = evidence(item)
            let assessment = CandidateAssessment.make(item, evidence: itemEvidence.detail == "Checking folder context…" ? nil : itemEvidence, scope: scope, scopeBlocked: blocked(item))
            return AIPlanItem(name: item.name, sizeBytes: item.size, kind: item.directory ? "folder" : "file", evidence: itemEvidence.label, blocked: !assessment.canSelect, id: assessment.id, evidenceDetail: itemEvidence.detail, rebuild: itemEvidence.rebuild, assessment: assessment.state.rawValue + ": " + assessment.reason, unknowns: assessment.unknowns)
        }
        _context = State(initialValue: AIPlanContext(instruction: "", scopeLabel: scope?.displayName, scopePolicy: scope.map { $0.cleanupAllowed ? "cleanup_after_review" : "inspect_only" }, items: candidates))
    }

    private var payloadContext: AIPlanContext {
        AIPlanContext(instruction: String(instruction.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)), scopeLabel: context.scopeLabel, scopePolicy: context.scopePolicy, items: context.items)
    }

    private var planProvider: AIProviderConfig { ai.provider(for: .plan) }
    private var providerReady: Bool { ai.enabled && ai.providerReady(for: .plan) }
    private var hasInstruction: Bool { !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { providerReady && hasInstruction && contextReady && !context.items.isEmpty }

    private var selectedItems: [DiskItem] {
        guard let resolution else { return [] }
        return items.filter { item in
            let id = CandidateAssessment.make(item, evidence: nil).id
            return resolution.selectedIDs.contains(id) && context.items.contains { $0.id == id && !$0.blocked } && !blocked(item) && !item.incomplete
        }
    }

    private var proposedExcludedItems: [DiskItem] {
        guard let resolution else { return [] }
        return items.filter { resolution.excludedIDs.contains(CandidateAssessment.make($0, evidence: nil).id) }
    }

    private var excludedItems: [DiskItem] {
        scope == nil ? [] : proposedExcludedItems
    }

    private var selectionDiff: (added: [String], removed: [String]) {
        let current = Set(currentSelection.values.map(\.id))
        let selected = Set(selectedItems.map(\.id))
        let added = selected.subtracting(current).compactMap { id in items.first { $0.id == id }?.name }.sorted()
        let removed = current.subtracting(selected).compactMap { id in currentSelection[id]?.name }.sorted()
        return (added, removed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label("Draft a cleanup plan", systemImage: "sparkles").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(planProvider.name).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Text("Describe what to clean in the current folder. The model proposes top-level items to check; it cannot move or delete anything.").font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)

            switch phase {
            case .ready: readyView
            case .loading: loadingView
            case .done: resultView
            case .failed: failureView
            }
        }
        .padding(24)
        .frame(width: 680)
        .onAppear { ai.refreshKeyStatus() }
        .task {
            let token = ScanCancellation(), candidates = Array(items.prefix(80)), initial = context
            let explicitBlocks = candidates.map { blocked($0) }
            await withTaskCancellationHandler {
                let refreshed = await DiskWork.run("Assessing AI plan candidates", cancellation: token) { () -> [AIPlanItem] in
                    let deadline = Date().addingTimeInterval(5)
                    return candidates.enumerated().map { index, item in
                        guard !token.cancelled, Date() < deadline else { var pending = initial.items[index]; pending.blocked = true; return pending }
                        let local = CleanupEvidenceService.classify(item.url, sourceCheck: true)
                        let assessment = CandidateAssessment.make(item, evidence: local, scope: scope)
                        var candidate = initial.items[index]
                        candidate.evidence = local.label; candidate.evidenceDetail = local.detail; candidate.rebuild = local.rebuild
                        candidate.assessment = assessment.state.rawValue + ": " + assessment.reason; candidate.unknowns = assessment.unknowns
                        candidate.blocked = candidate.blocked || !assessment.canSelect
                        // Initial checking is temporary; explicit scope/measurement
                        // blocks and fresh local evidence remain authoritative.
                        if !item.incomplete, !explicitBlocks[index] { candidate.blocked = !assessment.canSelect }
                        return candidate
                    }
                }
                guard !Task.isCancelled else { return }
                context = AIPlanContext(instruction: initial.instruction, scopeLabel: initial.scopeLabel, scopePolicy: initial.scopePolicy, items: refreshed)
                contextReady = true
            } onCancel: { token.cancel() }
        }
        .onDisappear { requestTask?.cancel() }
        .confirmationDialog("Replace the current selection?", isPresented: $confirmReplace) {
            Button("Replace selection", role: .destructive) { apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plan will replace the current tree selection. The scope exclusions are added separately.")
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("e.g. Select build output and old caches, but keep node_modules and anything source-like.", text: $instruction, axis: .vertical)
                .textFieldStyle(.roundedBorder).font(.system(size: 12)).lineLimit(2...4)
            Text("The instruction is sent as written. Describe the goal, not file contents or secrets.")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            HStack {
                Text(verbatim: String(format: String(localized: "%@ at the top level of this folder"), Plural.items(context.items.count))).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                if items.count > 80 { Text("· first 80 sent").font(.system(size: 10)).foregroundStyle(Theme.warning) }
                Spacer()
                if !providerReady {
                    Text(ai.providerStatus(for: .plan)).font(.system(size: 10)).foregroundStyle(Theme.warning)
                } else if !hasInstruction {
                    Text("Describe what to clean to continue.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            DisclosureGroup("What will be sent", isExpanded: $showPayload) {
                ScrollView {
                    Text(payloadContext.jsonString).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 180)
            }.font(.system(size: 11))
            Notice(text: planProvider.isLocal
                   ? "The instruction and top-level item metadata go to your local model. Nothing leaves this Mac. No file contents are sent."
                   : "The instruction and top-level item metadata will be sent to \(planProvider.name). No file contents are sent.",
                   symbol: "info.circle")
            if !providerReady {
                Button("Open AI settings") { openSettings() }.buttonStyle(QuietButton())
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(planProvider.isLocal ? "Draft with local model" : "Draft with \(planProvider.name)") { start() }
                    .buttonStyle(PrimaryButton()).disabled(!canSend)
            }
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Drafting a plan with \(planProvider.name)…").font(.system(size: 12)) }
            Text("The model receives top-level names, sizes and evidence. It cannot select blocked items.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let resolution {
                HStack {
                    Text("Proposed plan").font(.system(size: 13, weight: .semibold))
                    Text("Review required").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("Nothing has been moved").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                }
                Text(resolution.reasoning).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                if resolution.selected.isEmpty {
                    Text("The model did not select any items. Adjust the instruction and try again.").font(.system(size: 11)).foregroundStyle(Theme.warning)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(selectedItems) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.green)
                                    Text(item.name).font(.system(size: 11))
                                    Spacer()
                                    Text(bytes(item.size)).font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: min(max(CGFloat(resolution.selected.count) * 26 + 8, 44), 200))
                }
                if !resolution.excluded.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scope == nil ? "Proposed exclusions (not applied in Files view)" : "Add as scope exclusions")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        ForEach(proposedExcludedItems) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "shield").font(.system(size: 10)).foregroundStyle(Theme.green)
                                Text(item.name).font(.system(size: 11))
                            }
                        }
                        if scope == nil {
                            Text("Exclusions are stored on saved scopes. Open this plan from a scope to apply them.").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                if !resolution.omitted.isEmpty {
                    Notice(text: "\(resolution.omitted.count) proposed name\(resolution.omitted.count == 1 ? " was" : "s were") blocked or not in this folder and excluded.", symbol: "exclamationmark.triangle")
                }
                if !resolution.risks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Risks").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        ForEach(resolution.risks, id: \.self) { risk in Text("• " + risk).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                if !currentSelection.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selection changes").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        Text(selectionDiff.added.isEmpty ? "No new boxes." : "Adds: " + selectionDiff.added.prefix(5).joined(separator: ", ")).font(.system(size: 10)).foregroundStyle(Theme.green)
                        Text(selectionDiff.removed.isEmpty ? "No boxes removed." : "Removes: " + selectionDiff.removed.prefix(5).joined(separator: ", ")).font(.system(size: 10)).foregroundStyle(Theme.warning)
                        Text(verbatim: String(format: String(localized: "This will replace the current selection of %@."), Plural.items(currentSelection.count))).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
                Text("Applying replaces the current tree selection with these boxes" + (scope == nil ? "." : " and adds the protected exclusions to this scope.") + " You still review and confirm cleanup; the existing safety rechecks run again.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Close") { dismiss() }
                    if scope == nil, let onCreateScope {
                        Button("Save as scope") { onCreateScope(proposedExcludedItems); dismiss() }.buttonStyle(QuietButton())
                            .help("Save this root as a reusable scope with the proposed exclusions")
                    }
                    Spacer()
                    Button("Apply plan") { requestApply() }.buttonStyle(PrimaryButton()).disabled(selectedItems.isEmpty && excludedItems.isEmpty)
                }
                if scope == nil, onCreateScope != nil {
                    Text("Save as scope keeps the proposed exclusions for future cleanups. It does not apply the selection.").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private var failureView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Notice.measured(error, symbol: "exclamationmark.triangle")
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Open AI settings") { openSettings() }.buttonStyle(QuietButton())
                Button("Retry") { start() }.buttonStyle(PrimaryButton()).disabled(!canSend)
            }
        }
    }

    private func start() {
        guard phase != .loading else { return }
        let payload = payloadContext
        guard canSend else { error = ai.providerStatus(for: .plan); phase = .failed; return }
        phase = .loading
        requestTask?.cancel()
        let beginning = Date()
        requestTask = Task {
            do {
                let provider = try await ai.makeProvider(for: .plan)
                let raw = try await provider.plan(payload)
                guard !Task.isCancelled else { return }
                resolution = raw.resolved(against: payload); phase = .done
                ai.record(provider: planProvider.name, item: "Cleanup plan · \(payload.items.count) items", outcome: "success", milliseconds: Int(Date().timeIntervalSince(beginning) * 1000))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; phase = .failed
                ai.record(provider: planProvider.name, item: "Cleanup plan", outcome: "failed", milliseconds: Int(Date().timeIntervalSince(beginning) * 1000))
            }
        }
    }

    private func requestApply() {
        if !currentSelection.isEmpty {
            confirmReplace = true
        } else {
            apply()
        }
    }

    private func apply() {
        onApply(selectedItems, excludedItems)
        dismiss()
    }

    private func openSettings() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { model.page = .aiAssist }
    }
}

struct AIGrowthSheet: View {
    @Environment(AISettings.self) var ai
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let target: AIGrowthTarget

    @State private var phase = Phase.ready
    @State private var summary: AIGrowthSummary?
    @State private var error = ""
    @State private var showPayload = false
    @State private var requestTask: Task<Void, Never>?
    @State private var confirmReplace = false

    private enum Phase { case ready, loading, done, failed }

    private var growthProvider: AIProviderConfig { ai.provider(for: .growth) }
    private var providerReady: Bool { ai.enabled && ai.providerReady(for: .growth) }
    private var canSend: Bool { providerReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label("Explain storage growth", systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(growthProvider.name).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(target.context.rootName).font(.system(size: 13, weight: .semibold))
                Text("\(target.context.beforeDate) → \(target.context.afterDate) · \(target.context.deltaBytes >= 0 ? "+" : "−")\(bytes(abs(target.context.deltaBytes)))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            switch phase {
            case .ready: readyView
            case .loading: loadingView
            case .done: resultView
            case .failed: failureView
            }
        }
        .padding(24)
        .frame(width: 680)
        .onAppear { ai.refreshKeyStatus() }
        .onDisappear { requestTask?.cancel() }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Notice(text: growthProvider.isLocal
                   ? "The two-scan summary below goes to your local model. Nothing leaves this Mac. No file contents are sent."
                   : "The two-scan summary below will be sent to \(growthProvider.name). No file contents are sent.",
                   symbol: "info.circle")
            DisclosureGroup("What will be sent", isExpanded: $showPayload) {
                ScrollView {
                    Text(target.context.jsonString).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 190)
            }.font(.system(size: 11))
            if !providerReady {
                Text(ai.providerStatus(for: .growth)).font(.system(size: 11)).foregroundStyle(Theme.warning)
                Button("Open AI settings") { openSettings() }.buttonStyle(QuietButton())
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(growthProvider.isLocal ? "Explain with local model" : "Explain with \(growthProvider.name)") { start() }
                    .buttonStyle(PrimaryButton()).disabled(!canSend)
            }
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Comparing the saved scans with \(growthProvider.name)…").font(.system(size: 12)) }
            Text("The model receives only the stored totals, dates and changed item names. Nothing is scanned or moved.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary {
                HStack {
                    Text("Growth summary").font(.system(size: 13, weight: .semibold))
                    Text("Metadata-based interpretation").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("Advisory").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                }
                Text(summary.summary).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                if !summary.drivers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What changed").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        ForEach(summary.drivers, id: \.self) { driver in Text("• " + driver).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                if !summary.caveats.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Caveats").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        ForEach(summary.caveats, id: \.self) { caveat in Text("• " + caveat).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                Text("Based only on the two stored complete scans shown. File moves can appear as removal plus growth; this is not a cleanup recommendation.").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Copy summary") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary.summary, forType: .string)
                    }.buttonStyle(QuietButton())
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(PrimaryButton())
                }
            }
        }
    }

    private var failureView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Notice.measured(error, symbol: "exclamationmark.triangle")
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Open AI settings") { openSettings() }.buttonStyle(QuietButton())
                Button("Retry") { start() }.buttonStyle(PrimaryButton()).disabled(!canSend)
            }
        }
    }

    private func start() {
        guard phase != .loading else { return }
        guard canSend else { error = ai.providerStatus(for: .growth); phase = .failed; return }
        phase = .loading
        requestTask?.cancel()
        let beginning = Date()
        requestTask = Task {
            do {
                let provider = try await ai.makeProvider(for: .growth)
                let result = try await provider.explainGrowth(target.context)
                guard !Task.isCancelled else { return }
                summary = result; phase = .done
                ai.record(provider: growthProvider.name, item: "Growth · \(target.context.rootName)", outcome: "success", milliseconds: Int(Date().timeIntervalSince(beginning) * 1000))
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; phase = .failed
                ai.record(provider: growthProvider.name, item: "Growth · \(target.context.rootName)", outcome: "failed", milliseconds: Int(Date().timeIntervalSince(beginning) * 1000))
            }
        }
    }

    private func openSettings() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { model.page = .aiAssist }
    }
}
