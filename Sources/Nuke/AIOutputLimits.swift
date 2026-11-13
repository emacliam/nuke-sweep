import Foundation

/// Model token settings are not a trust boundary. Bound every decoded collection
/// and string before validation or display, even when a provider ignores its prompt.
enum AIOutputLimits {
    static func envelope(_ text: String) throws {
        guard text.utf8.count <= 131_072 else { throw Failure.limit }
    }
    static func text(_ text: String, maximum: Int) throws {
        guard text.count <= maximum else { throw Failure.limit }
    }
    static func list(_ items: [String], count: Int, length: Int) throws {
        guard items.count <= count else { throw Failure.limit }
        for item in items { try text(item, maximum: length) }
    }
    static func advice(_ text: String) throws {
        var lowered = text.lowercased()
        for caution in ["not safe to delete", "isn't safe to delete", "not completely safe"] { lowered = lowered.replacingOccurrences(of: caution, with: "caution") }
        if ["safe to delete", "100% safe", "completely safe", "guaranteed safe"].contains(where: { lowered.contains($0) }) { throw Failure.guarantee }
    }
    enum Failure: LocalizedError {
        case limit, guarantee
        var errorDescription: String? {
            switch self {
            case .limit: return "The AI response exceeded its field or item limits. Nothing was selected or moved."
            case .guarantee: return "The provider returned an unsupported safety guarantee. Local evidence and review are required; nothing was selected or moved."
            }
        }
    }
}
