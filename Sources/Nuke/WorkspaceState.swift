import Foundation

struct WorkspaceState: Codable {
    var page: String
    var root: URL
    var filters: [String: String]
    var focusedItem: String?
    var snapshot: ScanResult?
    var measured: Date?
    /// Last completed quick pass, so the Cleanup home can resume evidence instead of starting blank.
    var quick: QuickScanState?
}
struct RecoveryTask: Identifiable {
    enum Kind { case storage(URL), trash, findSpace }
    let id = UUID()
    let kind: Kind
    var title: String {
        switch kind { case .storage(let url): return url.path; case .trash: return "Trash"; case .findSpace: return "Find space" }
    }
}
