import Foundation
import Security

struct AIRecord: Identifiable {
    let id = UUID()
    let date: Date
    let provider: String
    let item: String
    let outcome: String
    let milliseconds: Int
}

enum AIUseCase: String, CaseIterable, Sendable {
    case explain
    case plan
    case growth
}

enum AIProviderFlavor: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case deepSeek
    case openAICompatible
    case anthropic
    case gemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "Local model"
        case .deepSeek: return "DeepSeek"
        case .openAICompatible: return "OpenAI-compatible"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        }
    }

    var detail: String {
        switch self {
        case .local:
            return "Ollama or another OpenAI-compatible server on this Mac. No data leaves the machine."
        case .deepSeek:
            return "DeepSeek's cloud API. Metadata is sent; file contents are never sent."
        case .openAICompatible:
            return "OpenAI, OpenRouter, Groq, Mistral, Together, xAI, LM Studio, vLLM or another OpenAI-compatible endpoint."
        case .anthropic:
            return "Anthropic's Claude API. Metadata is sent; file contents are never sent."
        case .gemini:
            return "Google Gemini's API. Metadata is sent; file contents are never sent."
        }
    }

    var defaultName: String { title }

    var defaultBaseURL: String {
        switch self {
        case .local: return "http://127.0.0.1:11434/v1"
        case .deepSeek: return "https://api.deepseek.com"
        case .openAICompatible: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModel: String {
        switch self {
        case .local: return "llama3.2"
        case .deepSeek: return "deepseek-chat"
        case .openAICompatible: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-flash"
        }
    }
}

struct AIProviderConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var flavor: AIProviderFlavor
    var name: String
    var baseURL: String
    var model: String

    var keychainAccount: String { "provider-\(id.uuidString)" }

    var effectiveBaseURL: String {
        switch flavor {
        case .deepSeek: return "https://api.deepseek.com"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .local, .openAICompatible: return baseURL
        }
    }

    var isLocal: Bool {
        switch flavor {
        case .deepSeek, .anthropic, .gemini: return false
        case .local, .openAICompatible: return AISettings.isLoopbackEndpoint(baseURL)
        }
    }

    var requiresKey: Bool {
        switch flavor {
        case .local: return false
        case .deepSeek, .anthropic, .gemini: return true
        case .openAICompatible: return !isLocal
        }
    }
    var locality: String { isLocal ? "On this Mac" : "Cloud" }

    static func make(_ flavor: AIProviderFlavor, name: String? = nil) -> AIProviderConfig {
        AIProviderConfig(id: UUID(), flavor: flavor, name: name ?? flavor.defaultName, baseURL: flavor.defaultBaseURL, model: flavor.defaultModel)
    }
}

/// Keychain-backed keys. One account per provider; the key is never written to
/// UserDefaults, receipts, plans, logs or the bundle.
enum AIKeychain {
    private static var service: String { AppEnvironment.isDevelopment ? "local.nuke.ai.provider.development" : "local.nuke.ai.provider" }
    private static let legacyService = "local.nuke.ai.deepseek"
    private static let legacyAccount = "deepseek-api-key"

    private static func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func load(service: String, account: String) -> String? {
        var query = query(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    private static func save(_ key: String, service: String, account: String) -> Bool {
        let data = Data(key.utf8)
        let base = query(service: service, account: account)
        if SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess { return true }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Whether an item exists, without reading it.
    ///
    /// Asking for the data decrypts the secret, which is what makes macOS raise
    /// its Keychain access prompt and block the caller until it is answered.
    /// Existence only needs the attributes, so this neither decrypts nor prompts.
    static func hasKey(account: String) -> Bool { exists(service: service, account: account) }
    private static func exists(service: String, account: String) -> Bool {
        var query = query(service: service, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    static func load(account: String) -> String? { load(service: service, account: account) }

    @discardableResult
    static func save(_ key: String, account: String) -> Bool { save(key, service: service, account: account) }

    static func delete(account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }

    /// Earlier builds stored the DeepSeek key in a dedicated item. Move it once.
    static func migrateLegacyDeepSeek(to account: String) {
        guard !AppEnvironment.isDevelopment else { return }
        // Existence checks first: the legacy secret is only decrypted when there
        // is genuinely something to move.
        guard !exists(service: service, account: account),
              exists(service: legacyService, account: legacyAccount),
              let legacy = load(service: legacyService, account: legacyAccount) else { return }
        if save(legacy, service: service, account: account) {
            SecItemDelete(query(service: legacyService, account: legacyAccount) as CFDictionary)
        }
    }
}

@Observable @MainActor final class AISettings {
    private enum Key {
        static let enabled = "nuke.ai.enabled"
        static let providers = "nuke.ai.providers"
        static let activeProvider = "nuke.ai.activeProvider"
        static let planProvider = "nuke.ai.planProvider"
        static let models = "nuke.ai.models"
        static let askBeforeCloud = "nuke.ai.askBeforeCloud"
        static let offlineOnly = "nuke.ai.offlineOnly"
    }
    private let defaults = UserDefaults.standard
    private var demoMode = false

    var enabled: Bool { didSet { if !demoMode { defaults.set(enabled, forKey: Key.enabled) } } }
    var providers: [AIProviderConfig] { didSet { if !demoMode { persistProviders() } } }
    var activeProviderID: UUID { didSet { if !demoMode { defaults.set(activeProviderID.uuidString, forKey: Key.activeProvider) } } }
    var planProviderID: UUID? { didSet { if !demoMode { defaults.set(planProviderID?.uuidString, forKey: Key.planProvider) } } }
    var askBeforeCloud: Bool { didSet { if !demoMode { defaults.set(askBeforeCloud, forKey: Key.askBeforeCloud) } } }
    var offlineOnly: Bool { didSet { if !demoMode { defaults.set(offlineOnly, forKey: Key.offlineOnly) } } }
    private(set) var keyStatus: [UUID: Bool] = [:]
    private(set) var discoveredModels: [UUID: [String]] = [:]
    private(set) var requestLog: [AIRecord] = []
    var keyError: String?
    private(set) var keySavedAt: Date?

    init() {
        enabled = defaults.bool(forKey: Key.enabled)
        askBeforeCloud = defaults.object(forKey: Key.askBeforeCloud) as? Bool ?? true
        offlineOnly = defaults.bool(forKey: Key.offlineOnly)
        let loaded = Self.loadProviders(defaults)
        let resolvedProviders = loaded.isEmpty ? Self.defaultProviders(defaults) : loaded
        let resolvedActive = defaults.string(forKey: Key.activeProvider).flatMap(UUID.init) ?? resolvedProviders[0].id
        providers = resolvedProviders
        activeProviderID = resolvedProviders.contains(where: { $0.id == resolvedActive }) ? resolvedActive : resolvedProviders[0].id
        planProviderID = nil
        persistProviders()
        defaults.set(activeProviderID.uuidString, forKey: Key.activeProvider)
        if let raw = defaults.string(forKey: Key.planProvider), let id = UUID(uuidString: raw), providers.contains(where: { $0.id == id }) {
            planProviderID = id
        }
        if let data = defaults.data(forKey: Key.models), let decoded = try? JSONDecoder().decode([UUID: [String]].self, from: data) {
            discoveredModels = decoded
        }
    }

    /// Deterministic, non-persisting provider state for screenshot/QA runs.
    func applyDemoConfiguration() {
        demoMode = true
        enabled = true
        offlineOnly = true
        let demo = AIProviderConfig.make(.local, name: "Demo local model")
        providers = [demo]
        activeProviderID = demo.id
        planProviderID = nil
        askBeforeCloud = false
    }

    var activeProvider: AIProviderConfig {
        providers.first(where: { $0.id == activeProviderID }) ?? providers[0]
    }

    var planProvider: AIProviderConfig { provider(for: .plan) }

    func provider(for useCase: AIUseCase) -> AIProviderConfig {
        switch useCase {
        case .explain, .growth:
            return activeProvider
        case .plan:
            if let id = planProviderID, let provider = providers.first(where: { $0.id == id }) { return provider }
            return activeProvider
        }
    }

    func setPlanProvider(_ id: UUID?) {
        if let id, providers.contains(where: { $0.id == id }) { planProviderID = id }
        else { planProviderID = nil }
    }

    func providerName(for useCase: AIUseCase) -> String { provider(for: useCase).name }

    var localEndpointIsValid: Bool { Self.isLoopbackEndpoint(activeProvider.baseURL) }

    nonisolated static func isLoopbackEndpoint(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host),
              components.user == nil, components.password == nil,
              !components.path.isEmpty else { return false }
        return true
    }

    var providerReady: Bool { providerReady(for: .explain) }

    func providerReady(for useCase: AIUseCase) -> Bool {
        guard enabled else { return false }
        let provider = provider(for: useCase)
        guard !offlineOnly || provider.isLocal else { return false }
        guard !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard Self.isValidBaseURL(provider.effectiveBaseURL) else { return false }
        if provider.flavor == .local && !Self.isLoopbackEndpoint(provider.baseURL) { return false }
        if provider.requiresKey && !hasKey(for: provider) { return false }
        return true
    }

    var providerStatus: String { providerStatus(for: .explain) }

    func providerStatus(for useCase: AIUseCase) -> String {
        if !enabled { return "AI assist is off." }
        let provider = provider(for: useCase)
        if offlineOnly && !provider.isLocal { return "Cloud AI is blocked. Choose a local provider." }
        if provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No model name is configured." }
        if provider.flavor == .local && !Self.isLoopbackEndpoint(provider.baseURL) { return "Local base URL must be http://127.0.0.1, localhost or ::1." }
        if !Self.isValidBaseURL(provider.effectiveBaseURL) { return "Use an https URL, or http only for a loopback host." }
        if provider.requiresKey && !hasKey(for: provider) { return "No API key is stored for \(provider.name)." }
        return "Ready: \(provider.name) · \(provider.model)"
    }

    nonisolated static func isValidBaseURL(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return false }
        if scheme == "http" { return ["127.0.0.1", "localhost", "::1"].contains(host) }
        return true
    }

    /// Refreshes which providers have a stored key.
    ///
    /// Keychain calls are synchronous IPC to securityd and can block for as long
    /// as a system prompt stays on screen. This ran on the main actor every time
    /// an AI view appeared, so a slow or prompting Keychain froze the whole
    /// window. The work now happens off the main actor and publishes when done.
    func refreshKeyStatus() {
        let snapshot = providers
        let generation = UUID(); keyStatusGeneration = generation
        Task {
            let next = await Task.detached(priority: .userInitiated) { () -> [UUID: Bool] in
                var next: [UUID: Bool] = [:]
                for provider in snapshot {
                    if provider.flavor == .deepSeek { AIKeychain.migrateLegacyDeepSeek(to: provider.keychainAccount) }
                    next[provider.id] = provider.flavor == .local ? false : AIKeychain.hasKey(account: provider.keychainAccount)
                }
                return next
            }.value
            // A newer refresh, or a save/remove in the meantime, wins.
            guard keyStatusGeneration == generation else { return }
            keyStatus = next
        }
    }
    private var keyStatusGeneration = UUID()

    func hasKey(for provider: AIProviderConfig) -> Bool {
        provider.flavor == .local ? false : (keyStatus[provider.id] ?? false)
    }

    /// True while a save or remove is waiting on the Keychain, so the buttons
    /// can refuse a second press instead of queueing one behind a system prompt.
    private(set) var keyBusy = false

    @discardableResult
    func saveDeepSeekKey(_ raw: String) async -> Bool { await saveKey(raw, for: activeProvider) }

    /// Writing to the Keychain is synchronous IPC to securityd and can wait on a
    /// system prompt, the same as reading. It runs off the main actor so the
    /// window keeps responding while it does.
    @discardableResult
    func saveKey(_ raw: String, for provider: AIProviderConfig) async -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 8 else { keyError = String(localized: "That key is too short."); return false }
        guard !keyBusy else { return false }
        keyBusy = true; defer { keyBusy = false }
        let account = provider.keychainAccount
        let stored = await Task.detached(priority: .userInitiated) { AIKeychain.save(key, account: account) }.value
        guard stored else { keyError = String(localized: "Could not store the key in the login Keychain."); return false }
        // The provider may have been removed while the Keychain was busy.
        guard providers.contains(where: { $0.id == provider.id }) else {
            Task.detached(priority: .utility) { AIKeychain.delete(account: account) }
            return false
        }
        keyError = nil; keyStatusGeneration = UUID(); keyStatus[provider.id] = true; keySavedAt = Date()
        return true
    }

    func removeKey(for provider: AIProviderConfig) async {
        guard !keyBusy else { return }
        keyBusy = true; defer { keyBusy = false }
        let account = provider.keychainAccount
        await Task.detached(priority: .userInitiated) { AIKeychain.delete(account: account) }.value
        keyStatusGeneration = UUID(); keyStatus[provider.id] = false; keySavedAt = nil; keyError = nil
    }

    func makeProvider() async throws -> any AIExplainingProvider { try await makeProvider(for: .explain) }

    /// Async because reading the key is a Keychain call that may wait on a
    /// system prompt; it must not hold the main actor while it does.
    func makeProvider(for useCase: AIUseCase) async throws -> any AIExplainingProvider {
        guard enabled else { throw AIProviderError.disabled }
        let provider = provider(for: useCase)
        guard !offlineOnly || provider.isLocal else { throw AIProviderError.cloudBlocked }
        if provider.flavor == .local && !Self.isLoopbackEndpoint(provider.baseURL) { throw AIProviderError.invalidLocalEndpoint }
        let key: String? = provider.flavor == .local ? nil : await Task.detached(priority: .userInitiated) {
            if provider.flavor == .deepSeek { AIKeychain.migrateLegacyDeepSeek(to: provider.keychainAccount) }
            return AIKeychain.load(account: provider.keychainAccount)
        }.value
        if provider.requiresKey, (key ?? "").isEmpty { throw AIProviderError.missingKey }
        switch provider.flavor {
        case .anthropic:
            return AnthropicProvider(name: provider.name, key: key ?? "", model: provider.model)
        case .gemini:
            return GeminiProvider(name: provider.name, key: key ?? "", model: provider.model)
        case .local, .deepSeek, .openAICompatible:
            return try OpenAICompatibleProvider(name: provider.name, baseURL: provider.effectiveBaseURL, model: provider.model, key: key)
        }
    }

    func addProvider(_ flavor: AIProviderFlavor) -> UUID {
        var name = flavor.defaultName
        let existing = Set(providers.map(\.name))
        if existing.contains(name) {
            var index = 2
            while existing.contains("\(flavor.defaultName) \(index)") { index += 1 }
            name = "\(flavor.defaultName) \(index)"
        }
        var provider = AIProviderConfig.make(flavor, name: name)
        provider.baseURL = flavor.defaultBaseURL
        provider.model = flavor.defaultModel
        providers.append(provider)
        activeProviderID = provider.id
        refreshKeyStatus()
        return provider.id
    }

    func removeActiveProvider() {
        guard providers.count > 1 else { return }
        let provider = activeProvider
        // Nothing waits on this: the provider is gone from the list either way,
        // and the Keychain must not hold the main actor while it answers.
        let account = provider.keychainAccount
        Task.detached(priority: .utility) { AIKeychain.delete(account: account) }
        providers.removeAll { $0.id == provider.id }
        keyStatus[provider.id] = nil
        discoveredModels[provider.id] = nil
        persistModels()
        if planProviderID == provider.id { planProviderID = nil }
        activeProviderID = providers[0].id
        refreshKeyStatus()
    }

    func updateActive(_ mutate: (inout AIProviderConfig) -> Void) {
        guard let index = providers.firstIndex(where: { $0.id == activeProviderID }) else { return }
        var copy = providers[index]
        mutate(&copy)
        providers[index] = copy
        persistProviders()
    }

    func setActive(_ id: UUID) {
        guard providers.contains(where: { $0.id == id }) else { return }
        activeProviderID = id
    }

    func record(provider: String, item: String, outcome: String, milliseconds: Int) {
        requestLog.insert(AIRecord(date: Date(), provider: provider, item: String(item.prefix(80)), outcome: outcome, milliseconds: milliseconds), at: 0)
        if requestLog.count > 20 { requestLog = Array(requestLog.prefix(20)) }
    }

    func setDiscoveredModels(_ models: [String], for provider: AIProviderConfig) {
        discoveredModels[provider.id] = Array(Set(models.filter { !$0.isEmpty })).sorted()
        persistModels()
    }

    func clearLog() { requestLog = [] }

    private func persistModels() {
        guard let data = try? JSONEncoder().encode(discoveredModels) else { return }
        defaults.set(data, forKey: Key.models)
    }

    private func persistProviders() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        defaults.set(data, forKey: Key.providers)
    }

    private static func loadProviders(_ defaults: UserDefaults) -> [AIProviderConfig] {
        guard let data = defaults.data(forKey: Key.providers),
              let decoded = try? JSONDecoder().decode([AIProviderConfig].self, from: data) else { return [] }
        return decoded
    }

    private static func defaultProviders(_ defaults: UserDefaults) -> [AIProviderConfig] {
        var local = AIProviderConfig.make(.local)
        if let old = defaults.string(forKey: "nuke.ai.localEndpoint"), !old.isEmpty {
            local.baseURL = old.hasSuffix("/chat/completions") ? String(old.dropLast("/chat/completions".count)) : old
        }
        if let old = defaults.string(forKey: "nuke.ai.localModel"), !old.isEmpty { local.model = old }
        var deepSeek = AIProviderConfig.make(.deepSeek)
        if let old = defaults.string(forKey: "nuke.ai.deepSeekModel"), !old.isEmpty { deepSeek.model = old }
        let oldProvider = defaults.string(forKey: "nuke.ai.provider") ?? "local"
        let active = oldProvider == "deepSeek" ? deepSeek.id : local.id
        defaults.set(active.uuidString, forKey: Key.activeProvider)
        return [local, deepSeek]
    }

    static var sampleContext: AIContext {
        AIContext(
            name: "dist",
            kind: "folder",
            relativePath: "~/code/example/dist",
            sizeBytes: 84_200_000,
            directory: true,
            symlink: false,
            incomplete: false,
            evidence: "Build output",
            evidenceDetail: "Generated build output. A copied manifest inside does not make it source.",
            rebuild: "Rebuild from source.",
            gitIgnored: true,
            scopeLabel: "Example project",
            scopePolicy: "cleanup_after_review"
        )
    }
}
