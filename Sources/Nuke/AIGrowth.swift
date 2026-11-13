import Foundation

struct AIGrowthContext: Codable, Equatable {
    var task = "explain_growth"
    let rootName: String
    let beforeDate: String
    let afterDate: String
    let beforeBytes: Int64
    let afterBytes: Int64
    let deltaBytes: Int64
    let rows: [Row]

    struct Row: Codable, Equatable, Sendable {
        let name: String
        let beforeBytes: Int64
        let afterBytes: Int64
        let deltaBytes: Int64
    }

    init(before: StoredScan, after: StoredScan, rows: [GrowthRow], rootName: String) {
        let formatter = ISO8601DateFormatter()
        self.rootName = rootName
        self.beforeDate = formatter.string(from: before.date)
        self.afterDate = formatter.string(from: after.date)
        self.beforeBytes = before.total
        self.afterBytes = after.total
        self.deltaBytes = after.total - before.total
        self.rows = rows.prefix(12).map { Row(name: $0.name, beforeBytes: $0.before, afterBytes: $0.after, deltaBytes: $0.delta) }
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

struct AIGrowthSummary: Equatable, Sendable {
    let summary: String
    let drivers: [String]
    let caveats: [String]
    let confidence: Double

    static func parse(_ text: String) throws -> AIGrowthSummary {
        try AIOutputLimits.envelope(text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else {
            throw AIGrowthError.notJSON
        }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: Data(trimmed[start...end].utf8)) }
        catch { throw AIGrowthError.invalidJSON }
        guard payload.confidence.isFinite, (0...1).contains(payload.confidence) else { throw AIGrowthError.invalidConfidence }
        let summary = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw AIGrowthError.emptySummary }
        try AIOutputLimits.text(summary, maximum: 1_400)
        try AIOutputLimits.list(payload.drivers ?? [], count: 5, length: 300)
        try AIOutputLimits.list(payload.caveats ?? [], count: 5, length: 300)
        try AIOutputLimits.advice(summary)
        return AIGrowthSummary(
            summary: String(summary.prefix(1_400)),
            drivers: Array((payload.drivers ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(5)),
            caveats: Array((payload.caveats ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(5)),
            confidence: payload.confidence
        )
    }

    private struct Payload: Decodable {
        let summary: String
        let drivers: [String]?
        let caveats: [String]?
        let confidence: Double
    }
}

enum AIGrowthError: LocalizedError {
    case notJSON, invalidJSON, invalidConfidence, emptySummary
    var errorDescription: String? {
        switch self {
        case .notJSON, .invalidJSON: return "The AI growth response was not valid JSON."
        case .invalidConfidence: return "The AI growth response had an invalid confidence score."
        case .emptySummary: return "The AI growth response had no summary."
        }
    }
}

struct AIGrowthTarget: Identifiable {
    let id = UUID()
    let context: AIGrowthContext
}
