import Foundation

struct DuplicateReviewSelection {
    let items: [DiskItem]
    let proofs: [DuplicateProof]
}
enum DuplicateSelection {
    /// Keeper choice is explicit and preserved. A stale choice refuses the whole
    /// proposal instead of silently choosing a different file to retain.
    static func prepare(groups: [DuplicateGroup], selected: Set<String>, keepers: [String: String]) -> DuplicateReviewSelection? {
        var items: [DiskItem] = [], proofs: [DuplicateProof] = []
        for group in groups where selected.contains(group.id) {
            guard let first = group.files.first,
                  let keeper = group.files.first(where: { $0.id == (keepers[group.id] ?? first.id) }) else { return nil }
            for file in group.files where file.id != keeper.id {
                items.append(file); proofs.append(.init(keeper: keeper, duplicate: file))
            }
        }
        return .init(items: items, proofs: proofs)
    }
}
