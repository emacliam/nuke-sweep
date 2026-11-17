import SwiftUI

struct VolumeCheckView: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var volumes: [MountedVolume] = []
    @State private var loadingVolumes = false
    @State private var selected: MountedVolume?
    @State private var result: ScanResult?
    @State private var token: ScanCancellation?
    @State private var unavailable = false
    @State private var inspectedIdentity: FileIdentity?

    var body: some View {
        DisclosureGroup("Check an external or network volume", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Measure a mounted volume to find its largest folders. The check stays on that volume.")
                    .foregroundStyle(Theme.secondary)
                HStack {
                    Menu(selected?.name ?? "Choose volume") {
                        ForEach(volumes) { volume in
                            Button(volume.name + " · " + volume.detail) {
                                selected = volume
                                result = nil
                                unavailable = false
                            }
                        }
                        if volumes.isEmpty { Text("No external or network volumes found") }
                    }.disabled(token != nil || loadingVolumes)
                    Button("Refresh volumes") { loadVolumes() }.disabled(token != nil || loadingVolumes)
                    if let selected {
                        Button("Check volume") { inspect(selected) }.buttonStyle(PrimaryButton())
                            .disabled(token != nil || loadingVolumes)
                    }
                    if let token { Button("Stop") { token.cancel() } }
                }
                if loadingVolumes { ProgressView("Reading mounted volumes…") }
                if token != nil { ProgressView("Measuring the selected volume…") }
                if unavailable { Text("The volume disconnected or changed. Refresh volumes and try again.") }
                if let result, let selected {
                    Text("\(bytes(result.logical)) measured · \(result.visited) entries inspected")
                    if result.limited || result.skipped > 0 {
                        Text("Partial results. Some entries could not be read, or the scan stopped before it finished.")
                            .foregroundStyle(Theme.warning)
                    }
                    ForEach(result.items.prefix(8)) { item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text(bytes(item.size) + (item.incomplete ? "+" : "")).monospacedDigit()
                        }
                    }
                    Button("Browse this volume…") {
                        browse(selected)
                    }.buttonStyle(QuietButton()).disabled(token != nil || model.scanning)
                }
            }.font(.system(size: 12)).padding(.vertical, 8)
        }
        .onChange(of: expanded) { _, open in
            if open && token == nil { loadVolumes() }
        }
        .onDisappear { token?.cancel() }
    }

    private func loadVolumes() {
        guard !loadingVolumes else { return }
        loadingVolumes = true
        Task {
            volumes = await DiskWork.run("Reading mounted volumes") {
                MountedVolumeService.list().filter { !$0.isRoot && (!$0.internalVolume || $0.network) }
            }
            if let selected {
                self.selected = volumes.first { $0.id == selected.id }
                if self.selected == nil { result = nil }
            }
            loadingVolumes = false
        }
    }

    private func browse(_ volume: MountedVolume) {
        guard let inspectedIdentity else { return }
        let cancellation = ScanCancellation()
        token = cancellation
        Task {
            let connected = await DiskWork.run("Checking volume connection", cancellation: cancellation) {
                MountedVolumeService.connectedIdentity(volume.url) == inspectedIdentity
            }
            token = nil
            guard !cancellation.cancelled else { return }
            guard connected else {
                result = nil
                unavailable = true
                return
            }
            model.page = .storage
            model.scan(volume.url, force: true)
        }
    }

    private func inspect(_ volume: MountedVolume) {
        let cancellation = ScanCancellation()
        token = cancellation
        result = nil
        unavailable = false
        Task {
            let checked = await DiskWork.run("Checking " + volume.name, cancellation: cancellation) { () -> (ScanResult, FileIdentity)? in
                guard let identity = MountedVolumeService.connectedIdentity(volume.url) else { return nil }
                let result = DiskScanner.scan(volume.url, cancellation: cancellation)
                guard MountedVolumeService.connectedIdentity(volume.url) == identity else { return nil }
                return (result, identity)
            }
            result = checked?.0
            inspectedIdentity = checked?.1
            unavailable = checked == nil && !cancellation.cancelled
            token = nil
        }
    }
}
