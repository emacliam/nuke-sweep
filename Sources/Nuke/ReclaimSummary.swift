import Foundation

/// What the app has actually measured, across every area that measures something.
///
/// The app previously never aggregated: a person had to visit six tabs and add up
/// the numbers themselves. The obvious fix — one big "reclaimable" total — would
/// be dishonest, because most areas are unmeasured until you scan them, and a
/// total that silently treats unscanned as zero understates the answer while
/// looking authoritative.
///
/// So this reports two things instead of one: what has been measured, and what
/// has not been looked at yet. An incomplete picture presented as incomplete is
/// more useful than a confident wrong number.
struct ReclaimSummary: Equatable, Sendable {
    struct Area: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let bytes: Int64
        let measured: Bool
        /// Where to send someone who wants to measure or review this area.
        let page: Page
    }

    let areas: [Area]

    var measuredAreas: [Area] { areas.filter(\.measured) }
    var unmeasuredAreas: [Area] { areas.filter { !$0.measured } }
    var measuredBytes: Int64 { measuredAreas.reduce(0) { $0 + $1.bytes } }
    var hasAnything: Bool { measuredBytes > 0 || !unmeasuredAreas.isEmpty }

    /// Ordered largest-first among measured areas, then the unmeasured ones, so
    /// the list reads as "here is what we found, here is what we have not looked
    /// at" rather than interleaving the two.
    var ordered: [Area] {
        measuredAreas.sorted { $0.bytes > $1.bytes } + unmeasuredAreas
    }

    static func make(
        quickBytes: Int64,
        quickMeasured: Bool,
        developerBytes: Int64,
        developerMeasured: Bool,
        projectBytes: Int64,
        projectsMeasured: Bool,
        trashBytes: Int64?,
        duplicateBytes: Int64,
        duplicatesMeasured: Bool
    ) -> ReclaimSummary {
        ReclaimSummary(areas: [
            .init(id: "quick", name: "Application caches", bytes: quickBytes, measured: quickMeasured, page: .findSpace),
            .init(id: "developer", name: "Developer caches", bytes: developerBytes, measured: developerMeasured, page: .developer),
            .init(id: "projects", name: "Project build output", bytes: projectBytes, measured: projectsMeasured, page: .projects),
            .init(id: "trash", name: "Trash", bytes: trashBytes ?? 0, measured: trashBytes != nil, page: .trash),
            .init(id: "duplicates", name: "Duplicate copies", bytes: duplicateBytes, measured: duplicatesMeasured, page: .duplicates)
        ])
    }
}
