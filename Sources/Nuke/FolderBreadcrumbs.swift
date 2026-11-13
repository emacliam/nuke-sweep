import SwiftUI

struct FolderBreadcrumbs: View {
    let root: URL
    let busy: Bool
    let navigate: (URL) -> Void
    private var ancestors: [URL] {
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        var result = [cursor]
        for component in root.standardizedFileURL.pathComponents.dropFirst() {
            cursor.appendPathComponent(component, isDirectory: true)
            result.append(cursor)
        }
        return result
    }
    var body: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(ancestors, id: \.path) { folder in
                    Button(folder.path) { navigate(folder) }
                }
            } label: { Image(systemName: "folder") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Folder hierarchy")
            ForEach(Array(ancestors.suffix(3)), id: \.path) { folder in
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Theme.secondary)
                Button(folder.path == "/" ? "Mac" : folder.lastPathComponent) { navigate(folder) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: folder.path == root.path ? .semibold : .regular))
                    .foregroundStyle(folder.path == root.path ? Theme.ink : Theme.secondary).lineLimit(1).truncationMode(.middle)
                    .help(folder.path).disabled(busy || folder.path == root.path)
            }
        }.disabled(busy).help(root.path)
    }
}
