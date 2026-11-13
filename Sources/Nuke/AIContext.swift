import Foundation

/// Metadata-only context. Add fields here deliberately; never add file contents,
/// environment values, receipt paths or absolute home paths.
struct AIContext: Codable, Equatable {
    var task = "explain_item"
    let name: String
    let kind: String
    let relativePath: String
    let sizeBytes: Int64
    let directory: Bool
    let symlink: Bool
    let incomplete: Bool
    let evidence: String
    let evidenceDetail: String
    let rebuild: String?
    let gitIgnored: Bool
    let scopeLabel: String?
    let scopePolicy: String?

    static func make(item: DiskItem, evidence: CleanupEvidence, scope: DeveloperScope?) -> AIContext {
        AIContext(
            name: item.name,
            kind: item.directory ? "folder" : item.symlink ? "symlink" : "file",
            relativePath: relativePath(item.url),
            sizeBytes: item.size,
            directory: item.directory,
            symlink: item.symlink,
            incomplete: item.incomplete,
            evidence: evidence.label,
            evidenceDetail: evidence.detail,
            rebuild: evidence.rebuild,
            gitIgnored: evidence.gitIgnored,
            scopeLabel: scope?.displayName,
            scopePolicy: scope.map { $0.cleanupAllowed ? "cleanup_after_review" : "inspect_only" }
        )
    }

    static func relativePath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        let parts = path.split(separator: "/")
        return parts.suffix(3).joined(separator: "/")
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

enum AICategory: String, Codable, CaseIterable, Sendable {
    case cache
    case buildOutput = "build_output"
    case dependencies
    case source
    case unknown

    var title: String {
        switch self {
        case .cache: return "Cache"
        case .buildOutput: return "Build output"
        case .dependencies: return "Dependencies"
        case .source: return "Source"
        case .unknown: return "Unknown"
        }
    }
    var isCaution: Bool { self == .source || self == .unknown }
}

struct AISuggestion: Codable, Equatable, Sendable {
    let category: AICategory
    let confidence: Double
    let explanation: String
    let rebuild: String?
    let risks: [String]

    static func parse(_ text: String) throws -> AISuggestion {
        try AIOutputLimits.envelope(text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = trimmed.firstIndex(of: "{")
        let end = trimmed.lastIndex(of: "}")
        guard let start, let end, start < end else { throw AISuggestionError.notJSON }
        let json = String(trimmed[start...end])
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: Data(json.utf8)) }
        catch { throw AISuggestionError.invalidJSON }

        guard let category = AICategory(rawValue: payload.category.lowercased()) else { throw AISuggestionError.unknownCategory }
        guard payload.confidence.isFinite, (0...1).contains(payload.confidence) else { throw AISuggestionError.invalidConfidence }
        let explanation = payload.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !explanation.isEmpty else { throw AISuggestionError.emptyExplanation }
        try AIOutputLimits.text(explanation, maximum: 1_200)
        try AIOutputLimits.text(payload.rebuild ?? "", maximum: 512)
        try AIOutputLimits.list(payload.risks ?? [], count: 5, length: 300)
        try AIOutputLimits.advice(explanation)
        try AIOutputLimits.advice(payload.rebuild ?? "")
        for risk in payload.risks ?? [] { try AIOutputLimits.advice(risk) }
        let risks = (payload.risks ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(5)
        return AISuggestion(
            category: category,
            confidence: payload.confidence,
            explanation: String(explanation.prefix(1_200)),
            rebuild: payload.rebuild.flatMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            },
            risks: Array(risks)
        )
    }

    private struct Payload: Decodable {
        let category: String
        let confidence: Double
        let explanation: String
        let rebuild: String?
        let risks: [String]?
    }
}

enum AISuggestionError: LocalizedError {
    case notJSON, invalidJSON, unknownCategory, invalidConfidence, emptyExplanation
    var errorDescription: String? {
        switch self {
        case .notJSON, .invalidJSON: return "The AI response was not valid JSON."
        case .unknownCategory: return "The AI response used an unknown category."
        case .invalidConfidence: return "The AI response had an invalid confidence score."
        case .emptyExplanation: return "The AI response had no explanation."
        }
    }
}

// MARK: - Cleanup plan proposals

struct AIPlanItem: Codable, Equatable, Sendable {
    let name: String
    let sizeBytes: Int64
    let kind: String
    var evidence: String
    var blocked: Bool
    var id: String? = nil
    var evidenceDetail: String? = nil
    var rebuild: String? = nil
    var assessment: String? = nil
    var unknowns: [String] = []
}

struct AIPlanContext: Codable, Equatable {
    var task = "draft_cleanup_plan"
    let instruction: String
    let scopeLabel: String?
    let scopePolicy: String?
    let items: [AIPlanItem]

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

struct AIPlanSuggestion: Equatable, Sendable {
    let select: [String]
    let keep: [String]
    let exclude: [String]
    let reasoning: String
    let risks: [String]
    let confidence: Double

    static func parse(_ text: String) throws -> AIPlanSuggestion {
        try AIOutputLimits.envelope(text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else {
            throw AIPlanError.notJSON
        }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: Data(trimmed[start...end].utf8)) }
        catch { throw AIPlanError.invalidJSON }
        guard payload.confidence.isFinite, (0...1).contains(payload.confidence) else { throw AIPlanError.invalidConfidence }
        let reasoning = payload.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reasoning.isEmpty else { throw AIPlanError.emptyReasoning }
        try AIOutputLimits.text(reasoning, maximum: 1_200)
        try AIOutputLimits.list(payload.select ?? [], count: 80, length: 1_024)
        try AIOutputLimits.list(payload.keep ?? [], count: 80, length: 1_024)
        try AIOutputLimits.list(payload.exclude ?? [], count: 80, length: 1_024)
        try AIOutputLimits.list(payload.risks ?? [], count: 5, length: 300)
        try AIOutputLimits.advice(reasoning)
        return AIPlanSuggestion(
            select: (payload.select ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            keep: (payload.keep ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            exclude: (payload.exclude ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            reasoning: String(reasoning.prefix(1_200)),
            risks: Array((payload.risks ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(5)),
            confidence: payload.confidence
        )
    }

    func resolved(against context: AIPlanContext) -> AIPlanResolution {
        let usesIDs = context.items.contains { $0.id != nil }
        let grouped = Dictionary(grouping: context.items, by: { usesIDs ? ($0.id ?? "") : $0.name })
        let valid = grouped.filter { !$0.key.isEmpty && $0.value.count == 1 }
        let keys = Set(valid.keys)
        let kept = Array(Set(keep.prefix(80).filter { keys.contains($0) })).sorted()
        let excluded = Array(Set(exclude.prefix(80).filter { keys.contains($0) })).sorted()
        let protected = Set(kept).union(excluded)
        var seen = Set<String>(), selected: [String] = [], omitted: [String] = []
        for key in select.prefix(80) where seen.insert(key).inserted {
            guard let item = valid[key]?.first, !item.blocked else { omitted.append(key); continue }
            if !protected.contains(key) { selected.append(key) }
        }
        func names(_ keys: [String]) -> [String] { keys.compactMap { valid[$0]?.first?.name } }
        return AIPlanResolution(selected: names(selected), kept: names(kept), excluded: names(excluded), omitted: omitted, reasoning: reasoning, risks: risks, confidence: confidence, selectedIDs: usesIDs ? selected : [], excludedIDs: usesIDs ? excluded : [])
    }

    private struct Payload: Decodable {
        let select: [String]?
        let keep: [String]?
        let exclude: [String]?
        let reasoning: String
        let risks: [String]?
        let confidence: Double
    }
}

struct AIPlanResolution: Equatable, Sendable {
    let selected: [String]
    let kept: [String]
    let excluded: [String]
    let omitted: [String]
    let reasoning: String
    let risks: [String]
    let confidence: Double
    var selectedIDs: [String] = []
    var excludedIDs: [String] = []
}

enum AIPlanError: LocalizedError {
    case notJSON, invalidJSON, invalidConfidence, emptyReasoning
    var errorDescription: String? {
        switch self {
        case .notJSON, .invalidJSON: return "The AI plan response was not valid JSON."
        case .invalidConfidence: return "The AI plan response had an invalid confidence score."
        case .emptyReasoning: return "The AI plan response had no reasoning."
        }
    }
}
