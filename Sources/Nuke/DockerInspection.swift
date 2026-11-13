import Foundation
import Darwin

struct DockerVolume: Identifiable, Codable, Equatable, Sendable {
    let name: String
    let driver: String
    let mountpoint: String
    let scope: String
    var id: String { name }
}

struct DockerReport: Sendable {
    let context: String
    let rows: [DockerUsage]
    let reachable: Bool
    let note: String?
    let volumes: [DockerVolume]
    let volumeError: String?
}
enum DockerInspection {
    static func inspect(run: ([String], TimeInterval) -> CommandResult = { CommandRunner.run("/usr/bin/env", ["docker"] + $0, timeout: $1) }) -> DockerReport {
        let context = run(["context", "show"], 5)
        guard context.status == 0, !context.output.isEmpty else { return .init(context: "", rows: [], reachable: false, note: "Docker CLI or its context configuration is unavailable. Install Docker Desktop or check its CLI setup, then retry. " + String(context.output.prefix(500)), volumes: [], volumeError: nil) }
        let result = run(["--context", context.output, "system", "df", "--format", "{{json .}}"], 12)
        guard result.status == 0 else {
            let denied = result.output.localizedCaseInsensitiveContains("permission denied")
            let message = denied ? "Access to this Docker engine was denied. Check the selected context and socket access; Full Disk Access does not grant Docker API access." : "The selected Docker engine is unavailable or did not answer. Docker Desktop may be stopped, or a remote engine may be disconnected."
            return .init(context: context.output, rows: [], reachable: false, note: message + " Current usage and cleanup are unavailable. No engine was started.\n" + String(result.output.prefix(700)), volumes: [], volumeError: nil)
        }
        let rows = parse(result.output)
        let volumeResult = run(["--context", context.output, "volume", "ls", "--format", "{{json .}}"], 10)
        let volumes = volumeResult.status == 0 ? parseVolumes(volumeResult.output) : []
        let volumeError = volumeResult.status == 0 ? nil : "Volume inventory unavailable. " + String(volumeResult.output.prefix(400))
        return .init(context: context.output, rows: rows, reachable: !rows.isEmpty, note: rows.isEmpty ? "Docker returned an unrecognized usage format. No cleanup is available." : nil, volumes: volumes, volumeError: volumeError)
    }
    static func parse(_ text: String) -> [DockerUsage] {
        text.split(separator: "\n").compactMap { line in
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let type = d["Type"] as? String else { return nil }
            func value(_ key: String) -> String { d[key].map { String(describing: $0) } ?? "—" }
            return DockerUsage(type: type, total: value("TotalCount"), active: value("Active"), size: value("Size"), reclaimable: value("Reclaimable"))
        }
    }
    static func parseVolumes(_ text: String) -> [DockerVolume] {
        text.split(separator: "\n").compactMap { line in
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let name = d["Name"] as? String, !name.isEmpty else { return nil }
            func value(_ key: String) -> String { d[key].map { String(describing: $0) } ?? "—" }
            return DockerVolume(name: name, driver: value("Driver"), mountpoint: value("Mountpoint"), scope: value("Scope"))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func localDisks(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [DiskItem] {
        let base = home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0")
        return ["data/Docker.raw", "data/Docker.qcow2", "Docker.raw", "Docker.qcow2"].compactMap { relative in
            let url = base.appendingPathComponent(relative)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return nil }
            return DiskItem(url: url, size: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512, directory: false, symlink: false, modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)), identity: .init(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)), incomplete: false)
        }
    }
}

struct DockerSavedUsage: Codable {
    let context: String
    let rows: [DockerUsage]
    let date: Date
    var volumes: [DockerVolume]?
}
